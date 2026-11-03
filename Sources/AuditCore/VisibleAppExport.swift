import Foundation

public struct VisibleAppExport: Codable, Sendable {
    public struct Record: Codable, Sendable {
        public let app: InstalledApp
        public let update: UpdateResult?
        public let security: SecurityEvidence?
        public let integrity: IntegrityEvidence?
        public let developerLinks: DeveloperLinks?
        public let revision: String?
        public let findings: [AuditFinding]

        fileprivate init(app: InstalledApp, snapshot: AuditSnapshot) {
            self.app = app
            update = UpdateRouting.result(app, recorded: snapshot.updates[app.id], at: snapshot.captured)
            security = snapshot.evidence[app.id]
            integrity = snapshot.integrity?[app.id]
            developerLinks = snapshot.developerLinks?[DeveloperLinks.key(app)]
            revision = snapshot.revisions?[app.id] ?? app.revision
            findings = (snapshot.findings ?? []).filter { $0.path == app.path || $0.path.isEmpty }
        }
    }

    public static let formatIdentifier = "com.xtracsys.appaudit.visible-apps"
    public static let currentSchemaVersion = 1

    public let format: String
    public let schemaVersion: Int
    public let captured: Date
    public let roots: [String]
    public let warnings: [String]
    public let context: AuditContext?
    public let redacted: Bool
    public let apps: [Record]

    public init(snapshot: AuditSnapshot) {
        format = Self.formatIdentifier
        schemaVersion = Self.currentSchemaVersion
        captured = snapshot.captured
        roots = snapshot.roots
        warnings = snapshot.warnings
        context = snapshot.context
        redacted = snapshot.redacted == true
        apps = snapshot.apps.map { Record(app: $0, snapshot: snapshot) }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
