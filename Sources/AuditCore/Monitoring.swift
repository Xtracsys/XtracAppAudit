import Foundation
import Darwin

public struct MonitorConfiguration: Codable, Sendable {
    public var schemaVersion = 1
    public var roots: [String]
    public var hour: Int
    public var minute: Int
    public var checkUpdates = true
    public var inspectSecurity = true
    public var notifications = true
    public var policy = AuditPolicy()
    public var customRules: [PublisherRule] = []
    public var offlineMode: Bool? = nil
    public var exceptions: [String: FindingException]? = nil
    public var context: AuditContext? = nil
    public init(roots: [String] = Scanner.defaultRoots.map(\.path), hour: Int = 9, minute: Int = 0) { self.roots = roots; self.hour = hour; self.minute = minute }
    public func validated() throws -> Self {
        guard schemaVersion == 1, (0...23).contains(hour), (0...59).contains(minute), !roots.isEmpty, roots.count <= 100,
              roots.allSatisfy({ $0.hasPrefix("/") && !$0.contains("\0") }) else { throw AuditFileError.invalid("Monitor needs absolute scan folders and a valid daily time.") }
        _ = try policy.validated(); _ = try PublisherRegistry.combined(custom: customRules)
        _ = try context?.validated(); for (_, value) in exceptions ?? [:] { _ = try value.validated() }
        return self
    }
    public func launchAgent(executable: String, configurationPath: String, logDirectory: String) throws -> Data {
        _ = try validated()
        return try PropertyListSerialization.data(fromPropertyList: [
            "Label": "com.xtracsys.appaudit.daily",
            "ProgramArguments": [executable, "--scheduled-audit", configurationPath],
            "StartCalendarInterval": ["Hour": hour, "Minute": minute], "RunAtLoad": false,
            "ProcessType": "Background", "ThrottleInterval": 60,
            "StandardOutPath": logDirectory + "/monitor.log", "StandardErrorPath": logDirectory + "/monitor-error.log"
        ], format: .xml, options: 0)
    }
}
public enum MonitorRecovery {
    public static func enableFailureMessage(primary: String, restorationFailures: [String]) -> String {
        let reason = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = "Cannot enable scheduled audit: " + (reason.isEmpty ? "the launch service rejected the schedule." : reason)
        guard !restorationFailures.isEmpty else { return message }
        return message + " Recovery also failed: " + restorationFailures.joined(separator: "; ")
    }
}
public struct MonitorEvent: Codable, Sendable {
    public var identity: String? = nil
    public let title: String
    public let detail: String
    public var fingerprint: String { IntegrityEvidence.fingerprint((identity ?? "") + "\n" + title + "\n" + detail) }
}
public enum MonitorAlerts {
    public static func actionEvents(_ findings: [AuditFinding]) -> [MonitorEvent] { findings.filter { $0.severity == .action && $0.exception?.active(for: $0) != true }.map { MonitorEvent(identity: $0.id, title: $0.title + ": " + $0.app, detail: $0.evidence) } }
    public static func events(current: AuditSnapshot, baseline: AuditSnapshot?, findings: [AuditFinding]) -> [MonitorEvent] {
        guard let baseline else { return [] }
        let completeScope = Set(current.roots) == Set(baseline.roots) && current.warnings.isEmpty && baseline.warnings.isEmpty
        let changes = AuditComparison.changes(baseline: baseline, current: current)
        let sameRoots = Set(current.roots) == Set(baseline.roots)
        var result = changes.filter {
            completeScope || ["Integrity changed", "Signing team changed", "Signature changed", "Updated", "Replaced"].contains($0.kind) || (sameRoots && $0.kind == "Added")
        }.map { MonitorEvent(identity: $0.id, title: ($0.kind == "Added" ? "Newly observed app" : $0.kind) + ": " + $0.name, detail: $0.summary) }
        result += actionEvents(findings)
        return Dictionary(result.map { ($0.fingerprint, $0) }, uniquingKeysWith: { first, _ in first }).values.sorted { $0.fingerprint < $1.fingerprint }
    }
    public static func newEvents(_ events: [MonitorEvent], previous: Set<String>) -> [MonitorEvent] { events.filter { !previous.contains($0.fingerprint) } }
}
public struct MonitorStatus: Codable, Sendable {
    public var completed: Date
    public var appCount: Int
    public var findingCount: Int
    public var newEventCount: Int
    public var message: String
    public var alertFingerprints: [String]
    public var latestFile: String? = nil
    public var completeFile: String? = nil
    public var notification: String?
    public var error: String?
}
public struct MonitorRun: Sendable {
    public let snapshot: AuditSnapshot
    public let status: MonitorStatus
    public let events: [MonitorEvent]
}
public enum MonitorRunner {
    private static func decoder() -> JSONDecoder { let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; return value }
    private static func encoder() -> JSONEncoder { let value = JSONEncoder(); value.dateEncodingStrategy = .iso8601; value.outputFormatting = [.prettyPrinted, .sortedKeys]; return value }
    public static func status(directory: URL, includeFailure: Bool = true) -> MonitorStatus? {
        let good = (try? Data(contentsOf: directory.appendingPathComponent("status.json"))).flatMap { try? decoder().decode(MonitorStatus.self, from: $0) }
        let bad = includeFailure ? (try? Data(contentsOf: directory.appendingPathComponent("last-error.json"))).flatMap { try? decoder().decode(MonitorStatus.self, from: $0) } : nil
        if let bad, good == nil || bad.completed >= good!.completed { return bad }
        return good
    }
    public static func historyURL(directory: URL, name: String) throws -> URL {
        guard name.range(of: "^audit-[0-9]+-[A-Fa-f0-9-]+\\.json$", options: .regularExpression) != nil else { throw AuditFileError.invalid("Invalid history reference.") }
        return directory.appendingPathComponent("History", isDirectory: true).appendingPathComponent(name)
    }
    public static func latest(directory: URL) throws -> AuditSnapshot? {
        guard let name = status(directory: directory, includeFailure: false)?.latestFile else { return nil }
        return try AuditSnapshot.decode(Data(contentsOf: historyURL(directory: directory, name: name)))
    }
    public static func recordNotification(directory: URL, latestFile: String?, message: String) {
        let descriptor = open(directory.appendingPathComponent("monitor.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return }
        defer { _ = flock(descriptor, LOCK_UN) }
        guard var value = status(directory: directory, includeFailure: false), value.latestFile == latestFile else { return }
        value.notification = message
        try? encoder().encode(value).write(to: directory.appendingPathComponent("status.json"), options: .atomic)
    }
    public static func run(configurationURL: URL) async throws -> MonitorRun {
        let directory = configurationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.appendingPathComponent("monitor.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw AuditFileError.invalid("Cannot open monitor lock.") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { close(descriptor); throw AuditFileError.invalid("An audit is already running.") }
        defer { _ = flock(descriptor, LOCK_UN); close(descriptor) }
        let statusURL = directory.appendingPathComponent("status.json")
        var prior: MonitorStatus?
        do {
            if FileManager.default.fileExists(atPath: statusURL.path) { prior = try decoder().decode(MonitorStatus.self, from: Data(contentsOf: statusURL)) }
            let config = try decoder().decode(MonitorConfiguration.self, from: Data(contentsOf: configurationURL)).validated()
            let globalSettings = try AuditStorage.loadSettings()
            let offline = config.offlineMode == true || globalSettings.offlineMode == true
            let observed = try latest(directory: directory)
            let complete: AuditSnapshot?
            if let name = prior?.completeFile { complete = try AuditSnapshot.decode(Data(contentsOf: historyURL(directory: directory, name: name))) } else { complete = nil }
            let baseline = complete ?? observed
            let scan = Scanner.scan(roots: config.roots.map { URL(fileURLWithPath: $0) })
            var evidence: [String: SecurityEvidence] = [:]; var integrity: [String: IntegrityEvidence] = [:]; var updates: [String: UpdateResult] = [:]
            let rules = try PublisherRegistry.combined(custom: config.customRules)
            let checker = UpdateChecker()
            var anyOffline = offline
            for app in scan.apps {
                try Task.checkCancellation()
                let globalOfflineNow = try AuditStorage.loadSettings().offlineMode == true
                let offlineNow = config.offlineMode == true || globalOfflineNow
                anyOffline = anyOffline || offlineNow
                integrity[app.id] = IntegrityEvidence.collect(app)
                if config.inspectSecurity && !offlineNow { evidence[app.id] = SecurityEvidence.inspect(app) }
                let globalOfflineBeforeUpdate = try AuditStorage.loadSettings().offlineMode == true
                anyOffline = anyOffline || globalOfflineBeforeUpdate
                if config.checkUpdates && !offlineNow && !globalOfflineBeforeUpdate { updates[app.id] = await checker.check(app, rules: rules) }
            }
            try Task.checkCancellation()
            var snapshot = AuditSnapshot(apps: scan.apps, roots: config.roots, warnings: scan.warnings, updates: updates, evidence: evidence)
            snapshot.integrity = integrity; snapshot.policy = config.policy
            snapshot.exceptions = globalSettings.exceptions ?? config.exceptions; snapshot.context = config.context; snapshot.offlineMode = anyOffline
            snapshot.revisions = Dictionary(scan.apps.compactMap { app in AppRevision.read(app).map { (app.id, $0) } }, uniquingKeysWith: { first, _ in first })
            let findings = FindingEngine.evaluate(snapshot, baseline: baseline, policy: config.policy)
            snapshot.findings = findings
            let events = MonitorAlerts.events(current: snapshot, baseline: baseline, findings: findings)
            let fresh = MonitorAlerts.newEvents(events, previous: Set(prior?.alertFingerprints ?? []))
            let history = directory.appendingPathComponent("History", isDirectory: true)
            try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
            let data = try snapshot.encoded()
            guard data.count <= 64_000_000 else { throw AuditFileError.invalid("Audit exceeds snapshot size limit; prior baseline retained.") }
            let stamp = String(Int(Date().timeIntervalSince1970)) + "-" + UUID().uuidString
            let name = "audit-" + stamp + ".json"
            let snapshotURL = history.appendingPathComponent(name)
            try data.write(to: snapshotURL, options: .atomic)
            try HTMLReport.render(snapshot, baseline: baseline, policy: config.policy).write(to: snapshotURL.deletingPathExtension().appendingPathExtension("html"), atomically: true, encoding: .utf8)
            let partial = !scan.warnings.isEmpty
            var status = MonitorStatus(completed: Date(), appCount: scan.apps.count, findingCount: findings.count, newEventCount: fresh.count,
                message: partial ? "Partial audit saved; last complete baseline retained. Missing-app alerts suppressed." : baseline == nil ? "Initial audit saved; alerts begin with subsequent meaningful changes." : "Audit completed.",
                alertFingerprints: Array(Set((events + MonitorAlerts.actionEvents(findings)).map(\.fingerprint))).sorted(), notification: nil, error: nil)
            if partial { status.alertFingerprints = Array(Set(status.alertFingerprints + (prior?.alertFingerprints ?? []))).sorted() }
            status.latestFile = name; status.completeFile = partial ? prior?.completeFile : name
            // One atomic pointer/status commit. Failed preparation never replaces the last successful audit.
            try encoder().encode(status).write(to: statusURL, options: .atomic)
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("last-error.json"))
            let files = (try? FileManager.default.contentsOfDirectory(at: history, includingPropertiesForKeys: nil)) ?? []
            let audits = files.filter { $0.lastPathComponent.hasPrefix("audit-") && $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
            let protected = Set([status.latestFile, status.completeFile].compactMap { $0 })
            let keep = max(0, 30 - protected.count)
            for old in audits.filter({ !protected.contains($0.lastPathComponent) }).dropFirst(keep) {
                try? FileManager.default.removeItem(at: old)
                try? FileManager.default.removeItem(at: old.deletingPathExtension().appendingPathExtension("html"))
            }
            return MonitorRun(snapshot: snapshot, status: status, events: fresh)
        } catch {
            var failure = MonitorStatus(completed: Date(), appCount: 0, findingCount: 0, newEventCount: 0, message: "Audit failed; prior audits and complete baseline retained.", alertFingerprints: prior?.alertFingerprints ?? [], notification: nil, error: error.localizedDescription)
            failure.latestFile = prior?.latestFile; failure.completeFile = prior?.completeFile
            try? encoder().encode(failure).write(to: directory.appendingPathComponent("last-error.json"), options: .atomic)
            throw error
        }
    }
}
