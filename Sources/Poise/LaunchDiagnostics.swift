import Foundation

enum LaunchDiagnostics {
    static var stateURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Poise", isDirectory: true)
            .appendingPathComponent("launch-state.json")
    }

    static func record(_ phase: String) {
        let payload: [String: Any] = [
            "phase": phase,
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "time": ISO8601DateFormatter().string(from: Date())
        ]
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: stateURL, options: .atomic)
        } catch {
            fputs("Poise launch state: \(error.localizedDescription)\n", stderr)
        }
    }

    static func read() -> [String: Any]? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
