import AppKit
import UserNotifications
import ServiceManagement
import PoiseCore

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let preferencesKey = "poise.preferences.v1"
    private var preferences = Preferences()
    private var authorization: UNAuthorizationStatus = .notDetermined
    private var alerts: UNNotificationSetting = .notSupported
    private var nextReminder: Date?
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var headerItem: NSMenuItem?
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var suspensionReasons = Set<String>()
    private var lastTick = Date()
    private var lastAuthorizationCheck = Date.distantPast
    private var menuIsOpen = false
    private var permissionRequestInFlight = false
    private var lastError: String?
    private var lastErrorDetail: String?
    private var lastSuccess: String?
    private var didInitialize = false

    private var canNotify: Bool { authorization == .authorized || authorization == .provisional }
    private var isPaused: Bool { (preferences.pausedUntil ?? .distantPast) > Date() }
    private var canRun: Bool { canNotify && preferences.remindersEnabled && !isPaused && suspensionReasons.isEmpty }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchDiagnostics.record("applicationDidFinishLaunching")
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier).contains(where: {
               $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
           }) {
            LaunchDiagnostics.record("duplicateInstanceDetected")
            NSApp.terminate(nil)
            return
        }
        loadPreferences()
        center.delegate = self
        let done = UNNotificationAction(identifier: "poise.done", title: "Done", options: [])
        let snooze = UNNotificationAction(identifier: "poise.snooze", title: "Remind in 5 min", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "poise.checkin", actions: [done, snooze], intentIdentifiers: []),
            UNNotificationCategory(identifier: "poise.test", actions: [done], intentIdentifiers: [])
        ])
        center.removeAllPendingNotificationRequests()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true
        statusItem.button?.title = " Poise"
        statusItem.button?.image = NSImage(systemSymbolName: "figure.stand", accessibilityDescription: "Poise posture reminders")
        statusItem.button?.image?.size = NSSize(width: 18, height: 18)
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.setAccessibilityLabel("Poise posture reminders")
        statusItem.menu = menu
        menu.autoenablesItems = false
        menu.delegate = self
        observeEnvironment()
        rebuildMenu()
        let tickTimer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tickTimer.tolerance = 1
        RunLoop.main.add(tickTimer, forMode: .common)
        timer = tickTimer
        didInitialize = true
        LaunchDiagnostics.record("menuReady")
        // Opening the menu must not depend on an asynchronous notification-service query.
        DispatchQueue.main.async { [weak self] in self?.showMenu() }
        Task { await refreshAuthorization() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        LaunchDiagnostics.record("reopenRequested")
        DispatchQueue.main.async { [weak self] in self?.showMenu() }
        return false
    }

    private func showMenu() {
        guard didInitialize, !menuIsOpen, let button = statusItem?.button else { return }
        statusItem.isVisible = true
        updateStatus()
        NSApp.activate(ignoringOtherApps: true)
        button.performClick(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard didInitialize else { return }
        LaunchDiagnostics.record("terminated")
        timer?.invalidate()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        for (source, token) in observers { source.removeObserver(token) }
    }

    private func loadPreferences() {
        if let data = defaults.data(forKey: preferencesKey),
           let saved = try? JSONDecoder().decode(Preferences.self, from: data), saved.isValid { preferences = saved }
        if let pause = preferences.pausedUntil, pause <= Date() { preferences.pausedUntil = nil }
    }

    private func savePreferences() {
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: preferencesKey) }
    }

    private func resetSchedule() {
        nextReminder = canRun ? preferences.nextReminder(after: Date()) : nil
        updateStatus()
    }

    private func didChangePreferences() {
        lastError = nil
        lastErrorDetail = nil
        lastSuccess = nil
        savePreferences()
        resetSchedule()
        if !menuIsOpen { rebuildMenu() }
    }

    private func tick() {
        let now = Date()
        let gap = now.timeIntervalSince(lastTick)
        lastTick = now
        if let pause = preferences.pausedUntil, pause <= now {
            preferences.pausedUntil = nil
            savePreferences()
            resetSchedule()
        }
        // A long suspension or a clock adjustment starts a fresh interval.
        if gap > 90 || gap < 0 { resetSchedule() }
        if canRun {
            if let due = nextReminder, due <= now {
                if preferences.schedule.contains(now) { sendNotification(isTest: false) }
                nextReminder = preferences.nextReminder(after: now)
            } else if nextReminder == nil { resetSchedule() }
        } else { nextReminder = nil }
        updateStatus()
        if now.timeIntervalSince(lastAuthorizationCheck) > 30 {
            Task { await refreshAuthorization() }
        }
    }

    private func refreshAuthorization() async {
        lastAuthorizationCheck = Date()
        let settings = await center.notificationSettings()
        let changed = authorization != settings.authorizationStatus || alerts != settings.alertSetting
        authorization = settings.authorizationStatus
        alerts = settings.alertSetting
        if changed {
            resetSchedule()
            if !canNotify { center.removeAllDeliveredNotifications() }
            if !menuIsOpen { rebuildMenu() }
        }
    }

    private func sendNotification(isTest: Bool) {
        guard canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = "Time for a posture check"
        content.body = "Take a moment to notice how you're sitting."
        content.categoryIdentifier = isTest ? "poise.test" : "poise.checkin"
        if preferences.soundEnabled { content.sound = .default }
        let identifier = isTest ? "poise.test" : "poise.reminder"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        Task {
            do {
                try await center.add(request)
                lastError = nil
                lastErrorDetail = nil
                if isTest { lastSuccess = "Test reminder sent" }
            } catch {
                lastError = "Couldn't send reminder"
                lastErrorDetail = error.localizedDescription
            }
            if !menuIsOpen { rebuildMenu() }
        }
    }

    private func observeEnvironment() {
        let workspace = NSWorkspace.shared.notificationCenter
        let pairs: [(Notification.Name, Notification.Name, String)] = [
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, "sleep"),
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, "screen"),
            (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, "session")
        ]
        for (begin, end, reason) in pairs {
            observe(begin, source: workspace) { [weak self] in
                self?.suspensionReasons.insert(reason)
                self?.resetSchedule()
                self?.center.removeAllDeliveredNotifications()
            }
            observe(end, source: workspace) { [weak self] in
                self?.suspensionReasons.remove(reason)
                self?.lastTick = Date()
                self?.resetSchedule()
            }
        }
        observe(.NSSystemTimeZoneDidChange, source: .default) { [weak self] in self?.resetSchedule() }
        observe(NSApplication.didBecomeActiveNotification, source: .default) { [weak self] in
            Task { await self?.refreshAuthorization() }
        }
    }

    private func observe(_ name: Notification.Name, source: NotificationCenter, action: @escaping @MainActor () -> Void) {
        let token = source.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { action() }
        }
        observers.append((source, token))
    }

    private func statusText() -> String {
        if permissionRequestInFlight { return "Waiting for notification permission…" }
        if !canNotify { return authorization == .notDetermined ? "Enable notifications to get started" : "Notifications are off" }
        if !preferences.remindersEnabled { return "Reminders are off" }
        if let pause = preferences.pausedUntil, pause > Date() { return "Paused until \(time(pause))" }
        if !suspensionReasons.isEmpty { return "Paused while your Mac is away" }
        guard let nextReminder else { return "Preparing your next reminder…" }
        if !preferences.schedule.contains(Date()) {
            let formatter = DateFormatter()
            formatter.doesRelativeDateFormatting = true
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return "Next reminder: \(formatter.string(from: nextReminder))"
        }
        let minutes = max(1, Int(ceil(nextReminder.timeIntervalSinceNow / 60)))
        return "Next reminder in \(minutes) min · \(time(nextReminder))"
    }

    private func updateStatus() {
        guard statusItem != nil else { return }
        let text = statusText()
        headerItem?.title = text
        statusItem.button?.toolTip = "Poise — \(text)"
        // The menu remains available while reminders or notification access are off.
        statusItem.button?.appearsDisabled = false
        var label = " Poise"
        if preferences.showCountdown {
            if !canNotify || !preferences.remindersEnabled { label = " Off" }
            else if isPaused { label = " Ⅱ" }
            else if let nextReminder {
                let minutes = max(1, Int(ceil(nextReminder.timeIntervalSinceNow / 60)))
                label = minutes > 60 ? " \(Int(ceil(Double(minutes) / 60)))h" : " \(minutes)m"
            }
        }
        statusItem.button?.title = label
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
        menuIsOpen = true
        LaunchDiagnostics.record("menuOpened")
        Task { await refreshAuthorization() }
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        LaunchDiagnostics.record("menuClosed")
        // Rebuild after tracking and action dispatch have finished.
        DispatchQueue.main.async { [weak self] in self?.rebuildMenu() }
    }

    @discardableResult
    private func item(_ title: String, action: Selector? = nil, in parent: NSMenu? = nil, checked: Bool? = nil, enabled: Bool = true, tag: Int = 0) -> NSMenuItem {
        let result = NSMenuItem(title: title, action: action, keyEquivalent: "")
        result.target = self
        result.isEnabled = enabled && action != nil
        result.tag = tag
        if let checked { result.state = checked ? .on : .off }
        (parent ?? menu).addItem(result)
        return result
    }

    private func submenu(_ title: String, in parent: NSMenu? = nil) -> NSMenu {
        let child = NSMenu(title: title)
        child.autoenablesItems = false
        let row = item(title, in: parent)
        row.isEnabled = true
        row.submenu = child
        return child
    }

    private func rebuildMenu() {
        guard statusItem != nil else { return }
        menu.removeAllItems()
        item("Poise", enabled: false)
        headerItem = item(statusText(), enabled: false)
        if !canNotify {
            if authorization == .notDetermined {
                item(permissionRequestInFlight ? "Waiting for Permission…" : "Enable Notifications…", action: #selector(enableNotifications), enabled: !permissionRequestInFlight)
            } else { item("Open Notification Settings…", action: #selector(openNotificationSettings)) }
            menu.addItem(.separator())
        } else if alerts == .disabled {
            item("Banners Are Off — Notification Settings…", action: #selector(openNotificationSettings))
            menu.addItem(.separator())
        }
        item("Reminders Enabled", action: #selector(toggleReminders), checked: preferences.remindersEnabled)
        item(isPaused ? "Resume Reminders" : "Pause for 30 Minutes", action: #selector(togglePause), enabled: preferences.remindersEnabled)
        menu.addItem(.separator())
        let intervals = submenu("Remind Every: \(preferences.intervalMinutes) Minutes")
        for minutes in [15, 30, 45, 60] {
            item("\(minutes) minutes", action: #selector(changeInterval(_:)), in: intervals, checked: preferences.intervalMinutes == minutes, tag: minutes)
        }
        buildScheduleMenu()
        item("Reminder Sound", action: #selector(toggleSound), checked: preferences.soundEnabled)
        item("Show Time in Menu Bar", action: #selector(toggleCountdown), checked: preferences.showCountdown)
        let loginStatus = SMAppService.mainApp.status
        item("Launch at Login", action: #selector(toggleLogin), checked: loginStatus == .enabled || loginStatus == .requiresApproval)
        if loginStatus == .requiresApproval { item("Finish Login Setup…", action: #selector(openLoginSettings)) }
        menu.addItem(.separator())
        item("Send Test Reminder", action: #selector(sendTest), enabled: canNotify)
        if canNotify && alerts != .disabled { item("Notification Settings…", action: #selector(openNotificationSettings)) }
        if let lastError {
            let errorItem = item(lastError, enabled: false)
            errorItem.toolTip = lastErrorDetail
        } else if let lastSuccess { item(lastSuccess, enabled: false) }
        menu.addItem(.separator())
        let quit = item("Quit Poise", action: #selector(quit))
        quit.keyEquivalent = "q"
        updateStatus()
    }

    private func buildScheduleMenu() {
        let schedule = preferences.schedule
        let days: String
        if schedule.weekdays == Set(2...6) { days = "Weekdays" }
        else if schedule.weekdays.count == 7 { days = "Every Day" }
        else if schedule.weekdays == [1, 7] { days = "Weekends" }
        else { days = "\(schedule.weekdays.count) Days" }
        let settings = submenu("Schedule: \(days), \(clockMinute(schedule.startMinute))–\(clockMinute(schedule.endMinute))")
        let weekdays = Calendar.current.weekdaySymbols
        for day in [2, 3, 4, 5, 6, 7, 1] {
            let selected = schedule.weekdays.contains(day)
            item(weekdays[day - 1], action: #selector(toggleDay(_:)), in: settings, checked: selected,
                 enabled: !(selected && schedule.weekdays.count == 1), tag: day)
        }
        settings.addItem(.separator())
        let start = submenu("From: \(clockMinute(schedule.startMinute))", in: settings)
        for minute in stride(from: 0, to: 1440, by: 60) {
            item(clockMinute(minute), action: #selector(changeStart(_:)), in: start,
                 checked: schedule.startMinute == minute, enabled: minute < schedule.endMinute, tag: minute)
        }
        let end = submenu("Until: \(clockMinute(schedule.endMinute))", in: settings)
        for minute in stride(from: 60, through: 1440, by: 60) {
            item(clockMinute(minute), action: #selector(changeEnd(_:)), in: end,
                 checked: schedule.endMinute == minute, enabled: minute > schedule.startMinute, tag: minute)
        }
        settings.addItem(.separator())
        item("Uses Your Mac’s Local Time", in: settings, enabled: false)
    }

    private func time(_ date: Date) -> String { DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short) }

    private func clockMinute(_ minute: Int) -> String {
        if minute == 1440 { return "Midnight" }
        let date = Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: minute / 60, minute: minute % 60))!
        return time(date)
    }

    @objc private func enableNotifications() {
        guard !permissionRequestInFlight else { return }
        permissionRequestInFlight = true
        updateStatus()
        Task {
            do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
            catch { lastError = "Couldn't request notifications"; lastErrorDetail = error.localizedDescription }
            permissionRequestInFlight = false
            await refreshAuthorization()
            if !menuIsOpen { rebuildMenu() }
        }
    }

    @objc private func toggleReminders() {
        preferences.remindersEnabled.toggle()
        preferences.pausedUntil = nil
        if !preferences.remindersEnabled { center.removeAllDeliveredNotifications() }
        didChangePreferences()
    }

    @objc private func togglePause() {
        preferences.pausedUntil = isPaused ? nil : Date().addingTimeInterval(30 * 60)
        center.removeAllDeliveredNotifications()
        didChangePreferences()
    }

    @objc private func changeInterval(_ sender: NSMenuItem) {
        preferences.intervalMinutes = sender.tag
        didChangePreferences()
    }

    @objc private func toggleDay(_ sender: NSMenuItem) {
        if preferences.schedule.weekdays.contains(sender.tag) {
            guard preferences.schedule.weekdays.count > 1 else { return }
            preferences.schedule.weekdays.remove(sender.tag)
        } else { preferences.schedule.weekdays.insert(sender.tag) }
        didChangePreferences()
    }

    @objc private func changeStart(_ sender: NSMenuItem) {
        guard sender.tag < preferences.schedule.endMinute else { return }
        preferences.schedule.startMinute = sender.tag
        didChangePreferences()
    }

    @objc private func changeEnd(_ sender: NSMenuItem) {
        guard sender.tag > preferences.schedule.startMinute else { return }
        preferences.schedule.endMinute = sender.tag
        didChangePreferences()
    }

    @objc private func toggleSound() { preferences.soundEnabled.toggle(); didChangePreferences() }
    @objc private func toggleCountdown() { preferences.showCountdown.toggle(); savePreferences(); updateStatus() }
    @objc private func sendTest() { sendNotification(isTest: true) }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleLogin() {
        Task {
            do {
                let status = SMAppService.mainApp.status
                if status == .enabled || status == .requiresApproval { try await SMAppService.mainApp.unregister() }
                else { try SMAppService.mainApp.register() }
                lastError = nil
                lastErrorDetail = nil
            } catch {
                lastError = "Couldn't change launch at login"
                lastErrorDetail = error.localizedDescription
            }
            if !menuIsOpen { rebuildMenu() }
        }
    }

    @objc private func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }

    @objc private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            let identifier = response.notification.request.identifier
            if response.actionIdentifier == "poise.snooze", identifier == "poise.reminder", self.canRun {
                self.nextReminder = self.preferences.schedule.nextAllowedDate(onOrAfter: Date().addingTimeInterval(5 * 60))
                self.updateStatus()
            }
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
            completionHandler()
        }
    }
}
