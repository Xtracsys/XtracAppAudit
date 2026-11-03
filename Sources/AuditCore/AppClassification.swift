import Foundation

public enum AppCategory: String, Codable, CaseIterable, Sendable {
    case thirdParty = "Third-party apps", apple = "Apple apps", system = "System components"
}
public struct AppClassification: Codable, Sendable {
    public let category: AppCategory
    public let managedByMacOS: Bool
    public let basis: String
    public static func classify(path: String, bundleID: String) -> Self {
        let path = URL(fileURLWithPath: path).standardizedFileURL.path
        if path.hasPrefix("/System/Library/CoreServices/") {
            return Self(category: .system, managedByMacOS: true, basis: "macOS CoreServices install location; this is not signature verification")
        }
        let roots = ["/System/Applications/", "/System/Cryptexes/App/System/Applications/", "/System/Volumes/Preboot/Cryptexes/App/System/Applications/"]
        if roots.contains(where: { path.hasPrefix($0) }) {
            return Self(category: .apple, managedByMacOS: true, basis: "macOS application install location; this is not signature verification")
        }
        if bundleID.hasPrefix("com.apple.") {
            return Self(category: .apple, managedByMacOS: false, basis: "Claimed Apple bundle identifier (metadata only); signing is checked separately")
        }
        return Self(category: .thirdParty, managedByMacOS: false, basis: "Outside known macOS locations with no claimed Apple namespace; includes unclassified apps")
    }
}
public enum UpdateRouting {
    public static func localResult(_ app: InstalledApp, checked: Date = Date()) -> UpdateResult? {
        if app.classification.managedByMacOS {
            return UpdateResult(status: "Managed by macOS", source: "https://support.apple.com/en-us/108382", detail: "Use System Settings → General → Software Update. This is an update channel, not confirmation that macOS or this app is current. Third-party catalog matching is excluded. " + app.classification.basis, identity: "macOS install-location classification; publisher verification is separate", checked: checked)
        }
        if app.appStore { return UpdateResult(status: "App Store", detail: "Check App Store updates. Store availability was not queried; this is not a current-version verdict.", checked: checked) }
        return nil
    }
    public static func result(_ app: InstalledApp, recorded: UpdateResult?, at date: Date = Date()) -> UpdateResult? {
        if let local = localResult(app, checked: recorded?.checked ?? date) { return local }
        if let recorded, recorded.status == "Unsupported" {
            var value = UpdateResult(status: "Manual check needed", latest: recorded.latest, source: recorded.source, detail: "Legacy Unsupported meant no automatic source match, not vendor end of support. " + recorded.detail, identity: recorded.identity ?? "Not verified", checked: recorded.checked)
            value.revision = recorded.revision; value.homepage = recorded.homepage; return value
        }
        return recorded
    }
    public static func coverage(_ snapshot: AuditSnapshot) -> String {
        let macOS = snapshot.apps.filter { $0.classification.managedByMacOS }.count
        let store = snapshot.apps.filter { !$0.classification.managedByMacOS && $0.appStore }.count
        let manual = snapshot.apps.filter { !$0.classification.managedByMacOS && !$0.appStore && ["Unsupported", "Manual check needed"].contains(snapshot.updates[$0.id]?.status ?? "") }.count
        return "macOS-managed: \(macOS) · App Store: \(store) · manual source checks: \(manual). Software Update/App Store availability has not been checked. Managed channels are coverage information, not per-app update failures."
    }
}
extension InstalledApp {
    public var classification: AppClassification { recordedClassification ?? AppClassification.classify(path: path, bundleID: bundleID) }
    public var ageLabel: String { classification.managedByMacOS ? "OS-maintained" : "" }
}
