import Foundation

public struct AuditPreferences: Codable, Equatable, Sendable {
    public var folders = Scanner.defaultRoots.map(\.path)
    public var filter = "All apps"
    public var search = ""
    public var sort = "name"
    public var ascending = true
    public var showSecurity = false
    public var showDates = true
    public var showLocation = true
    public var showNotarization: Bool? = nil
    public var discoveryVersion: Int? = 2
    public var category: String? = nil
    public init() {}
    public func validated() -> Self {
        var result = self
        let oldDefaults = Set(["/Applications", NSHomeDirectory() + "/Applications", "/System/Applications", "/System/Library/CoreServices"])
        if discoveryVersion == nil && Set(folders) == oldDefaults { result.folders = ["/"] }
        result.discoveryVersion = 2
        result.folders = Array(Set(result.folders.filter { $0.hasPrefix("/") && !$0.contains("\0") })).sorted()
        // An intentionally empty folder list is retained.
        if !["All apps", "Updates", "Unknown last use", "Needs review"].contains(filter) { result.filter = "All apps" }
        if !["name", "version", "installed", "used", "path", "architecture", "signature", "publisher", "gatekeeper", "notarization"].contains(sort) { result.sort = "name" }
        if let category = result.category, category != "All" && !AppCategory.allCases.map(\.rawValue).contains(category) { result.category = nil }
        result.search = String(search.prefix(1000))
        return result
    }
}
public final class PreferenceStore {
    public static let key = "AppAudit.preferences.v1"
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> AuditPreferences {
        guard let data = defaults.data(forKey: Self.key), let settings = try? JSONDecoder().decode(AuditPreferences.self, from: data) else { return AuditPreferences() }
        return settings.validated()
    }
    public func save(_ value: AuditPreferences) throws { defaults.set(try JSONEncoder().encode(value.validated()), forKey: Self.key) }
}
