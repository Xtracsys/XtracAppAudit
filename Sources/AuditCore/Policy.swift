import Foundation

public struct AppPolicyRule: Codable, Equatable, Sendable, Identifiable {
    public var id: String { bundleID }
    public var bundleID: String
    public var allowed: Bool
    public var minimumVersion: String?
    public var teams: [String]
    public init(bundleID: String, allowed: Bool = true, minimumVersion: String? = nil, teams: [String] = []) {
        self.bundleID = bundleID; self.allowed = allowed; self.minimumVersion = minimumVersion; self.teams = teams
    }
}
public struct AuditPolicy: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var enabled: Bool
    public var allowOnlyListed: Bool
    public var trustedTeams: [String]
    public var rules: [AppPolicyRule]
    public init(enabled: Bool = false, allowOnlyListed: Bool = false, trustedTeams: [String] = [], rules: [AppPolicyRule] = []) { self.enabled = enabled; self.allowOnlyListed = allowOnlyListed; self.trustedTeams = trustedTeams; self.rules = rules }
    public func validated() throws -> Self {
        guard schemaVersion == 1, rules.count <= 10000, Set(rules.map(\.bundleID)).count == rules.count else { throw AuditFileError.invalid("Policy has an unsupported schema, too many rules or duplicate bundle IDs.") }
        for rule in rules {
            guard PublisherRegistry.validBundleID(rule.bundleID), rule.teams.allSatisfy(PublisherRegistry.validTeam), rule.minimumVersion.map({ Version.compare($0, $0) != nil }) ?? true else { throw AuditFileError.invalid("Invalid policy rule for \(rule.bundleID). Use numeric minimum versions and ten-character Apple team IDs.") }
        }
        guard trustedTeams.allSatisfy(PublisherRegistry.validTeam) else { throw AuditFileError.invalid("Trusted teams must be ten-character Apple team IDs.") }
        return self
    }
    public static func decode(_ data: Data) throws -> Self { try JSONDecoder().decode(Self.self, from: data).validated() }
}
public struct PublisherRegistry: Codable, Sendable {
    public var schemaVersion = 1
    public var rules: [PublisherRule]
    public init(rules: [PublisherRule] = []) { self.rules = rules }
    public static func validTeam(_ value: String) -> Bool { value.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil }
    public static func validBundleID(_ value: String) -> Bool { value.count <= 255 && value.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]+$", options: .regularExpression) != nil }
    public static func combined(custom: [PublisherRule]) throws -> [PublisherRule] {
        let all = PublisherRule.known + custom
        guard custom.count <= 10000, Set(all.map(\.bundleID)).count == all.count else { throw AuditFileError.invalid("Duplicate publisher rule or attempted override of a built-in rule.") }
        for rule in custom {
            guard validBundleID(rule.bundleID), validTeam(rule.teamID), rule.cask.range(of: "^[a-z0-9][a-z0-9+@._-]{0,127}$", options: .regularExpression) != nil else { throw AuditFileError.invalid("Invalid publisher rule. Use a bundle ID, ten-character team ID and a Homebrew cask token.") }
        }
        return all
    }
    public static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schemaVersion == 1 else { throw AuditFileError.invalid("Unsupported registry schema.") }
        _ = try combined(custom: value.rules)
        return value
    }
}
public struct AuditSettings: Codable, Sendable {
    public var policy = AuditPolicy()
    public var customRules: [PublisherRule] = []
    public var developerLinks: [String: DeveloperLinks]? = nil
    public var exceptions: [String: FindingException]? = nil
    public var context: AuditContext? = nil
    public var offlineMode: Bool? = nil
    public init() {}
    public func validated() throws -> Self {
        _ = try policy.validated(); _ = try PublisherRegistry.combined(custom: customRules)
        guard (developerLinks?.count ?? 0) <= 10000 else { throw AuditFileError.invalid("Too many developer link entries.") }
        for (_, links) in developerLinks ?? [:] { _ = try links.validated() }
        _ = try context?.validated()
        guard (exceptions?.count ?? 0) <= 10000 else { throw AuditFileError.invalid("Too many exceptions.") }
        for (_, value) in exceptions ?? [:] { _ = try value.validated() }
        return self
    }
}
public enum AuditStorage {
    public static var directory: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("App Audit", isDirectory: true) }
    public static func loadSettings(at directory: URL = directory) throws -> AuditSettings {
        let url = directory.appendingPathComponent("settings.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return AuditSettings() }
        return try JSONDecoder().decode(AuditSettings.self, from: Data(contentsOf: url)).validated()
    }
    public static func saveSettings(_ settings: AuditSettings, at directory: URL = directory) throws {
        _ = try settings.validated()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(settings).write(to: directory.appendingPathComponent("settings.json"), options: .atomic)
    }
}
