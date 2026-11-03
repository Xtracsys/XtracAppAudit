import Foundation
import AppKit
import UserNotifications
import AuditCore

@MainActor enum NativeMonitor {
    static let label = "com.xtracsys.appaudit.daily"
    static var directory: URL { AuditStorage.directory.appendingPathComponent("Monitor", isDirectory: true) }
    static var configurationURL: URL { directory.appendingPathComponent("monitor.json") }
    static var agentURL: URL { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/LaunchAgents/" + label + ".plist") }
    static var enabled: Bool { FileManager.default.fileExists(atPath: agentURL.path) }
    static func loadConfiguration() -> MonitorConfiguration {
        guard let data = try? Data(contentsOf: configurationURL), let value = try? JSONDecoder().decode(MonitorConfiguration.self, from: data).validated() else { return MonitorConfiguration() }
        return value
    }
    static func saveConfiguration(_ config: MonitorConfiguration) throws {
        _ = try config.validated()
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("Logs"), withIntermediateDirectories: true)
        try JSONEncoder().encode(config).write(to: configurationURL, options: .atomic)
    }
    static func enable(_ config: MonitorConfiguration) async throws -> String {
        try saveConfiguration(config)
        guard let executable = Bundle.main.executableURL?.path, executable.contains(".app/Contents/MacOS/") else { throw AuditFileError.invalid("Open the packaged .app to enable background audits.") }
        var permission = "Notifications disabled in monitor settings."
        if config.notifications {
            do { permission = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) ? "Notification permission granted." : "Notification permission declined; saved findings remain available." }
            catch { permission = "Notifications unavailable: \(error.localizedDescription)" }
        }
        let plist = try config.launchAgent(executable: executable, configurationPath: configurationURL.path, logDirectory: directory.appendingPathComponent("Logs").path)
        let old = try? Data(contentsOf: agentURL)
        try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let domain = "gui/\(getuid())"
        let service = label; let path = agentURL.path
        _ = await Task.detached { ProcessRunner.run("/bin/launchctl", ["bootout", domain + "/" + service], timeout: 8) }.value
        try plist.write(to: agentURL, options: .atomic)
        let result = await Task.detached { ProcessRunner.run("/bin/launchctl", ["bootstrap", domain, path], timeout: 8) }.value
        guard result.status == 0, !result.timedOut else {
            var restorationFailures: [String] = []
            if let old {
                do {
                    try old.write(to: agentURL, options: .atomic)
                    let restored = await Task.detached { ProcessRunner.run("/bin/launchctl", ["bootstrap", domain, path], timeout: 8) }.value
                    if restored.status != 0 || restored.timedOut {
                        restorationFailures.append(restored.output.isEmpty ? "launchctl could not reload the previous schedule." : restored.output)
                    }
                } catch {
                    restorationFailures.append("could not restore the previous schedule file: " + error.localizedDescription)
                }
            } else {
                do { try FileManager.default.removeItem(at: agentURL) }
                catch { restorationFailures.append("could not remove the failed schedule file: " + error.localizedDescription) }
            }
            throw AuditFileError.invalid(MonitorRecovery.enableFailureMessage(primary: result.output, restorationFailures: restorationFailures))
        }
        return "Daily audit enabled at \(String(format: "%02d:%02d", config.hour, config.minute)) local time. " + permission
    }
    static func disable() async throws {
        let target = "gui/\(getuid())/" + label
        let check = await Task.detached { ProcessRunner.run("/bin/launchctl", ["print", target], timeout: 8) }.value
        if check.timedOut || (check.status != 0 && !check.output.contains("Could not find service") && !check.output.contains("could not find service") && check.status != 113) { throw AuditFileError.invalid("Cannot establish scheduler status: " + check.output) }
        if check.status == 0 {
            let result = await Task.detached { ProcessRunner.run("/bin/launchctl", ["bootout", target], timeout: 8) }.value
            guard result.status == 0, !result.timedOut else { throw AuditFileError.invalid("Cannot disable loaded schedule: " + result.output) }
        }
        if FileManager.default.fileExists(atPath: agentURL.path) { try FileManager.default.removeItem(at: agentURL) }
    }
}
enum MonitorNotifications {
    static func deliver(_ run: MonitorRun, enabled: Bool) async -> String {
        guard enabled else { return "Notifications disabled." }
        guard !run.events.isEmpty else { return "No new meaningful changes; no notification sent." }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional].contains(settings.authorizationStatus) else { return "Notification permission not granted; review saved findings in Monitor." }
        let content = UNMutableNotificationContent()
        content.title = "App Audit: \(run.events.count) new findings or changes"
        content.body = run.events.prefix(3).map(\.title).joined(separator: "; ")
        content.sound = .default
        do { try await center.add(UNNotificationRequest(identifier: "app-audit-" + UUID().uuidString, content: content, trigger: nil)); return "Notification submitted." }
        catch { return "Notification delivery failed: " + error.localizedDescription }
    }
}
