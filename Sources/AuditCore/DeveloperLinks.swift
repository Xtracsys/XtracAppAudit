import Foundation

public struct DeveloperLinks: Codable, Sendable, Equatable {
    public var website: String
    public var support: String
    public var releaseNotes: String
    public init(website: String = "", support: String = "", releaseNotes: String = "") { self.website = website; self.support = support; self.releaseNotes = releaseNotes }
    public static func url(_ text: String) -> URL? {
        guard text.count <= 2048, !text.contains(where: { $0.isWhitespace || $0.isNewline }),
              let value = URLComponents(string: text), value.scheme?.lowercased() == "https",
              value.user == nil, value.password == nil, let host = value.host, !host.isEmpty,
              host.contains("."), host != "localhost", value.port == nil || value.port == 443 else { return nil }
        return value.url
    }
    public func validated() throws -> Self {
        for text in [website, support, releaseNotes] where !text.isEmpty {
            guard Self.url(text) != nil else { throw AuditFileError.invalid("Use a complete HTTPS address without spaces, credentials or a custom port.") }
        }
        return self
    }
    public static func key(_ app: InstalledApp) -> String { PublisherRegistry.validBundleID(app.bundleID) && app.bundleID != "Unknown" ? "bundle:" + app.bundleID : "path:" + app.path }
    public var entries: [(String, String)] { [("Developer website", website), ("Support", support), ("Release notes", releaseNotes)].filter { !$0.1.isEmpty } }
}
public struct DuplicateGroup: Identifiable, Sendable {
    public var id: String { bundleID }
    public let bundleID: String
    public let apps: [InstalledApp]
}
public enum DuplicateDetector {
    public static func groups(_ apps: [InstalledApp]) -> [DuplicateGroup] {
        Dictionary(grouping: apps.filter { $0.bundleID != "Unknown" && PublisherRegistry.validBundleID($0.bundleID) }, by: \.bundleID)
            .filter { Set($0.value.map(\.path)).count > 1 }
            .map { DuplicateGroup(bundleID: $0.key, apps: $0.value.sorted { $0.path < $1.path }) }.sorted { $0.bundleID < $1.bundleID }
    }
}
