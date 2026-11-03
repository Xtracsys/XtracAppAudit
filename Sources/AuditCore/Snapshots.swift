import Foundation

public struct AuditSnapshot: Codable, Sendable {
    public let schemaVersion: Int
    public let captured: Date
    public let roots: [String]
    public let warnings: [String]
    public let apps: [InstalledApp]
    public var updates: [String: UpdateResult]
    public let evidence: [String: SecurityEvidence]
    public var integrity: [String: IntegrityEvidence]? = nil
    public var policy: AuditPolicy? = nil
    public var findings: [AuditFinding]? = nil
    public var developerLinks: [String: DeveloperLinks]? = nil
    public var redacted: Bool? = nil
    public var exceptions: [String: FindingException]? = nil
    public var context: AuditContext? = nil
    public var revisions: [String: String]? = nil
    public var offlineMode: Bool? = nil
    public init(apps: [InstalledApp], roots: [String], warnings: [String], updates: [String: UpdateResult], evidence: [String: SecurityEvidence]) {
        schemaVersion = 2; captured = Date(); self.apps = apps; self.roots = roots; self.warnings = warnings; self.updates = updates; self.evidence = evidence
    }
    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
    public static func decode(_ data: Data) throws -> AuditSnapshot {
        guard data.count <= 64_000_000 else { throw AuditFileError.invalid("Snapshot exceeds 64 MB.") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(Self.self, from: data)
        guard [1, 2].contains(snapshot.schemaVersion) else { throw AuditFileError.invalid("Unsupported snapshot schema \(snapshot.schemaVersion).") }
        guard snapshot.apps.count <= 100_000, Set(snapshot.apps.map(\.path)).count == snapshot.apps.count,
              snapshot.apps.allSatisfy({ $0.path.hasPrefix("/") }) else { throw AuditFileError.invalid("Invalid or duplicate application paths.") }
        return snapshot
    }
}
public enum AuditFileError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}
public struct AuditChange: Identifiable, Sendable {
    public var id: String { kind + (before?.path ?? "") + "→" + (after?.path ?? "") }
    public let kind: String
    public let before: InstalledApp?
    public let after: InstalledApp?
    public var name: String { after?.name ?? before?.name ?? "Unknown" }
    public var detail: String? = nil
    public var summary: String {
        if let detail { return detail }
        switch kind {
        case "Updated": return "\(before?.version ?? "") (\(before?.build ?? "")) → \(after?.version ?? "") (\(after?.build ?? ""))"
        case "Relocated", "Relocated & updated": return "\(before?.path ?? "") → \(after?.path ?? "")"
        case "Replaced": return "\(before?.bundleID ?? "") → \(after?.bundleID ?? "")"
        default: return after?.path ?? before?.path ?? ""
        }
    }
}
public enum AuditComparison {
    public static func changes(before: [InstalledApp], after: [InstalledApp]) -> [AuditChange] {
        var old = Dictionary(before.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var new = Dictionary(after.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var changes: [AuditChange] = []
        func updated(_ a: InstalledApp, _ b: InstalledApp) -> Bool { a.version != b.version || a.build != b.build }
        for path in Set(old.keys).intersection(new.keys).sorted() {
            guard let a = old.removeValue(forKey: path), let b = new.removeValue(forKey: path) else { continue }
            if a.bundleID != b.bundleID { changes.append(AuditChange(kind: "Replaced", before: a, after: b)) }
            else if updated(a, b) { changes.append(AuditChange(kind: "Updated", before: a, after: b)) }
        }
        // Uniqueness must hold across the entire inventory, not just unmatched paths.
        let oldIDs = Dictionary(grouping: before, by: \.bundleID)
        let newIDs = Dictionary(grouping: after, by: \.bundleID)
        for path in old.keys.sorted() {
            guard let a = old[path], a.bundleID != "Unknown", !a.bundleID.isEmpty,
                  oldIDs[a.bundleID]?.count == 1, newIDs[a.bundleID]?.count == 1,
                  let b = newIDs[a.bundleID]?.first, new[b.path] != nil else { continue }
            changes.append(AuditChange(kind: updated(a, b) ? "Relocated & updated" : "Relocated", before: a, after: b))
            old.removeValue(forKey: path); new.removeValue(forKey: b.path)
        }
        changes += old.values.map { AuditChange(kind: "Removed", before: $0, after: nil) }
        changes += new.values.map { AuditChange(kind: "Added", before: nil, after: $0) }
        return changes.sorted { ($0.kind, $0.name, $0.id) < ($1.kind, $1.name, $1.id) }
    }
    public static func changes(baseline: AuditSnapshot, current: AuditSnapshot) -> [AuditChange] {
        var changes = self.changes(before: baseline.apps, after: current.apps)
        let oldPaths = Dictionary(baseline.apps.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let oldIDs = Dictionary(grouping: baseline.apps, by: \.bundleID)
        let newIDs = Dictionary(grouping: current.apps, by: \.bundleID)
        for app in current.apps {
            let before = oldPaths[app.path] ?? (app.bundleID != "Unknown" && oldIDs[app.bundleID]?.count == 1 && newIDs[app.bundleID]?.count == 1 ? oldIDs[app.bundleID]?.first : nil)
            guard let before, before.bundleID == app.bundleID else { continue }
            func append(_ kind: String, _ detail: String) { var item = AuditChange(kind: kind, before: before, after: app); item.detail = detail; changes.append(item) }
            if let old = baseline.integrity?[before.id], let new = current.integrity?[app.id] {
                let keys = Set(old.hashes.keys).intersection(new.hashes.keys).sorted().filter { old.hashes[$0] != new.hashes[$0] }
                if !keys.isEmpty { append("Integrity changed", keys.map { "\($0): \(old.hashes[$0] ?? "") → \(new.hashes[$0] ?? "")" }.joined(separator: "\n")) }
            }
            if let old = baseline.evidence[before.id], let new = current.evidence[app.id] {
                if !old.teamID.isEmpty && !new.teamID.isEmpty && old.teamID != new.teamID { append("Signing team changed", "\(old.teamID) → \(new.teamID)") }
                let stable = { (value: String) in value.hasPrefix("Valid") || value == "Invalid / unsigned / untrusted" }
                if stable(old.signature) && stable(new.signature) && old.signature != new.signature { append("Signature changed", "\(old.signature) → \(new.signature)") }
            }
        }
        return changes.sorted { ($0.kind, $0.name, $0.id) < ($1.kind, $1.name, $1.id) }
    }
    public static func scopeNotes(baseline: AuditSnapshot, roots: [String], warnings: [String]) -> [String] {
        var notes: [String] = []
        if baseline.redacted == true { notes.append("Baseline was redacted for sharing. Paths cannot reliably match a live audit; use original local snapshots for comparisons.") }
        if Set(baseline.roots) != Set(roots) { notes.append("Scan folders differ. Added/removed entries may reflect a scope change.") }
        if !baseline.warnings.isEmpty || !warnings.isEmpty { notes.append("One or both audits have scan warnings. Missing entries may be unreadable rather than removed.") }
        return notes
    }
    public static func csv(_ changes: [AuditChange]) -> String {
        let rows = [["Change", "Name", "Bundle ID before", "Bundle ID after", "Path before", "Path after", "Version before", "Version after", "Build before", "Build after", "Change evidence"]] + changes.map {
            [$0.kind, $0.name, $0.before?.bundleID ?? "", $0.after?.bundleID ?? "", $0.before?.path ?? "", $0.after?.path ?? "", $0.before?.version ?? "", $0.after?.version ?? "", $0.before?.build ?? "", $0.after?.build ?? "", $0.detail ?? ""]
        }
        return rows.map { $0.map(CSV.field).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
}
