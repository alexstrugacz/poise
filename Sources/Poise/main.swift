import AppKit
import UserNotifications

// Read-only check of the bundled executable and notification service.
if CommandLine.arguments.contains("--diagnostics") {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
        var payload: [String: Any] = [
            "app": Bundle.main.bundleIdentifier ?? "missing",
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "missing",
            "menuBarOnly": Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool ?? false,
            "notificationAuthorization": settings.authorizationStatus.rawValue,
            "notificationAlerts": settings.alertSetting.rawValue,
            "appIconExists": Bundle.main.url(forResource: "Poise", withExtension: "icns") != nil
        ]
        payload["lastLaunch"] = LaunchDiagnostics.read() ?? [:]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) { print(text) }
        exit(0)
    }
    RunLoop.main.run(until: Date().addingTimeInterval(10))
    fputs("Notification service did not respond within 10 seconds.\n", stderr)
    exit(1)
}

LaunchDiagnostics.record("processStarted")
MainActor.assumeIsolated {
    let application = NSApplication.shared
    LaunchDiagnostics.record("applicationCreated")
    let controller = AppController()
    application.delegate = controller
    application.setActivationPolicy(.accessory)
    withExtendedLifetime(controller) { application.run() }
}
