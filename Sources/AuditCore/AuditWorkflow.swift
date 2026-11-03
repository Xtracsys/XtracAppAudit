import Foundation

public enum UpdateAge: String, Codable, CaseIterable, Sendable {
    case recent = "0–30 days", middle = "31–60 days", aging = "61–90 days", older = "Over 90 days", unknown = "Unknown"
    public static func band(date: Date?, now: Date = Date()) -> Self {
        guard let date, date <= now else { return .unknown }
        let days = Int(now.timeIntervalSince(date) / 86400)
        return days <= 30 ? .recent : days <= 60 ? .middle : days <= 90 ? .aging : .older
    }
    public static func evidence(_ app: InstalledApp, security: SecurityEvidence?) -> (date: Date?, source: String) {
        if app.classification.managedByMacOS { return (security?.installDate ?? app.modified, "OS-maintained component: use Software Update; receipt/file dates do not establish individual patch compliance") }
        if let date = security?.installDate { return (date, "Installer receipt event; may be an install or update") }
        return (app.modified, "Filesystem modification estimate; copying or maintenance can change it")
    }
}
public struct AuditContext: Codable, Equatable, Sendable {
    public var client = "", site = "", auditor = "", notes = ""
    public init() {}
    public var summary: String { "Client: \(client) · Site: \(site) · Auditor: \(auditor)\nNotes: \(notes)" }
    public func validated() throws -> Self {
        guard [client, site, auditor].allSatisfy({ $0.count <= 300 }), notes.count <= 8000 else { throw AuditFileError.invalid("Context fields are limited to 300 characters; notes to 8,000.") }
        return self
    }
}
public struct FindingException: Codable, Equatable, Sendable {
    public var fingerprint: String
    public let reason: String
    public let reviewer: String
    public let recorded: Date
    public let expires: Date?
    public var revoked: Date?
    public init(finding: AuditFinding, reason: String, reviewer: String, expires: Date?, now: Date = Date()) {
        fingerprint = finding.fingerprint; self.reason = reason.trimmingCharacters(in: .whitespacesAndNewlines); self.reviewer = reviewer.trimmingCharacters(in: .whitespacesAndNewlines); recorded = now; self.expires = expires
    }
    public func validated() throws -> Self {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reason.count <= 4000, !reviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reviewer.count <= 300, fingerprint.count == 64,
              expires.map({ $0 > recorded }) ?? true else { throw AuditFileError.invalid("An exception needs a reason (up to 4,000 characters) and a reviewer. If set, expiry must follow its recorded time.") }
        return self
    }
    public func status(for finding: AuditFinding, now: Date = Date()) -> String {
        if revoked != nil { return "Revoked" }
        if fingerprint != finding.fingerprint { return "Evidence changed — review again" }
        if let expires, expires <= now { return "Expired" }
        return "Active exception"
    }
    public func active(for finding: AuditFinding, now: Date = Date()) -> Bool { status(for: finding, now: now) == "Active exception" }
    public var description: String { "Reason: \(reason)\nReviewer: \(reviewer.isEmpty ? "Not recorded" : reviewer)\nRecorded: \(recorded.formatted()) · Expires: \(expires?.formatted() ?? "No expiry")" }
}
/// Current review queue; absent findings are retained without implying resolution.
public enum ExceptionReviewBucket: String, CaseIterable, Sendable {
    case overdue = "Overdue", changed = "Evidence changed", soon = "Expiring within 30 days"
    case active = "Active / no expiry", absent = "Finding absent", revoked = "Revoked"
    public static func classify(_ decision: FindingException, finding: AuditFinding?, now: Date = Date()) -> Self {
        if decision.revoked != nil { return .revoked }
        if let expiry = decision.expires, expiry <= now { return .overdue }
        guard let finding else { return .absent }
        if decision.fingerprint != finding.fingerprint { return .changed }
        if let expiry = decision.expires, expiry <= now.addingTimeInterval(30 * 86400) { return .soon }
        return .active
    }
}
public enum AppRevision {
    /// Cheap change indicator for selected files, not a cryptographic bundle verification.
    public static func read(_ app: InstalledApp) -> String? {
        let paths = [app.path, app.path + "/Contents/Info.plist", app.path + "/Contents/_CodeSignature/CodeResources"] + (app.executablePath.map { [$0] } ?? [])
        var values = [app.version, app.build]
        for path in paths {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else {
                if path == app.path || path.hasSuffix("Info.plist") { return nil }
                values.append("missing"); continue
            }
            values += [String((attrs[.size] as? NSNumber)?.uint64Value ?? 0), String((attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0), String((attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0)]
        }
        return IntegrityEvidence.fingerprint(values.joined(separator: "|"))
    }
    public static func status(observed: String?, current: String?) -> String {
        guard let observed, let current else { return "Freshness unknown" }
        return observed == current ? "No observed file change" : "Stale — app files changed; rescan and recheck"
    }
}

extension AuditSnapshot {
    public var workflowSummary: String {
        let bands = UpdateAge.allCases.map { band in
            band.rawValue + ": " + String(apps.filter { !$0.classification.managedByMacOS && UpdateAge.band(date: UpdateAge.evidence($0, security: evidence[$0.id]).date, now: captured) == band }.count)
        }.joined(separator: " · ")
        let decisions = (findings ?? FindingEngine.evaluate(self, baseline: nil, policy: policy ?? AuditPolicy())).filter { $0.exception?.active(for: $0, now: captured) == true }.count
        return "Active exceptions at capture: \(decisions)\n" + (context?.summary ?? "Audit context not recorded") + "\nNetwork mode at capture: " + (offlineMode == true ? "Offline" : "Online permitted / legacy unknown") + "\n" + UpdateRouting.coverage(self) + "\nUpdate-age evidence (excluding OS-maintained components): " + bands + "\nAge is receipt/modification evidence, not proof of a vendor update or a vulnerability verdict."
    }
    public func workflowEvidence(_ app: InstalledApp) -> String {
        let age = UpdateAge.evidence(app, security: evidence[app.id])
        let revision = revisions?[app.id] ?? app.revision
        let updateFreshness = UpdateRouting.localResult(app) == nil ? AppRevision.status(observed: updates[app.id]?.revision, current: revision) : "Availability not checked; update channel only"
        return "Category: " + app.classification.category.rawValue + "\nUpdate age: " + (app.classification.managedByMacOS ? "OS-maintained" : UpdateAge.band(date: age.date, now: captured).rawValue) + " · " + (age.date?.formatted() ?? "Unknown") + "\n" + age.source + "\nUpdate freshness: " + updateFreshness + "\nSecurity freshness: " + AppRevision.status(observed: evidence[app.id]?.revision, current: revision) + "\nIntegrity freshness: " + AppRevision.status(observed: integrity?[app.id]?.revision, current: revision)
    }
}
