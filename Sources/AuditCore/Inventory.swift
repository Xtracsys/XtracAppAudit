import Foundation
import CoreServices
import Darwin

public struct InstalledApp: Identifiable, Sendable, Codable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let bundleID: String
    public let version: String
    public let build: String
    public let created: Date?
    public let lastUsed: Date?
    public let feed: String?
    public let appStore: Bool
    public let executablePath: String?
    public let architecture: String?
    public var modified: Date? = nil
    public var revision: String? = nil
    public var recordedClassification: AppClassification? = nil
    public init(name: String, path: String, bundleID: String, version: String, build: String, created: Date?, lastUsed: Date?, feed: String?, appStore: Bool, executablePath: String? = nil, architecture: String? = nil) {
        self.name = name; self.path = path; self.bundleID = bundleID; self.version = version; self.build = build; self.created = created; self.lastUsed = lastUsed; self.feed = feed; self.appStore = appStore; self.executablePath = executablePath; self.architecture = architecture
    }
    public var installedText: String { created.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Unknown" }
    public var installSort: Date { created ?? .distantPast }
    public var usedSort: Date { lastUsed ?? .distantPast }
    public var usedText: String { lastUsed.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Unknown" }
}
public struct ScanResult: Sendable {
    public let apps: [InstalledApp]
    public let warnings: [String]
}
public enum Scanner {
    public static var defaultRoots: [URL] {
        [URL(fileURLWithPath: "/")]
    }
    public static func scan(roots: [URL], cancelled: @Sendable () -> Bool = { false }, progress: @Sendable (Int, String) -> Void = { _, _ in }) -> ScanResult {
        let fm = FileManager.default
        var apps: [String: InstalledApp] = [:]
        var warnings: [String] = []
        func read(_ url: URL) {
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard apps[path] == nil else { return }
            let infoURL = url.appendingPathComponent("Contents/Info.plist")
            guard let data = InventoryFile.read(infoURL.path, limit: 4 * 1024 * 1024),
                  let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else {
                warnings.append("Cannot read bundle metadata: \(url.path)"); return
            }
            let values = try? url.resourceValues(forKeys: [.creationDateKey])
            let item = MDItemCreate(nil, path as CFString)
            let lastUsed = item.flatMap { MDItemCopyAttribute($0, kMDItemLastUsedDate) as? Date }
            let executable = (info["CFBundleExecutable"] as? String).flatMap { name -> String? in
                guard !name.isEmpty, name == URL(fileURLWithPath: name).lastPathComponent else { return nil }
                let resolved = url.appendingPathComponent("Contents/MacOS").appendingPathComponent(name).resolvingSymlinksInPath().path
                return resolved.hasPrefix(path + "/") ? resolved : nil
            }
            func label(_ value: Any?) -> String? {
                guard let text = value as? String else { return nil }
                let stripped = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters).union(CharacterSet(charactersIn: "\u{200e}\u{200f}\u{200b}\u{feff}")))
                return stripped.isEmpty ? nil : stripped
            }
            var app = InstalledApp(name: label(info["CFBundleDisplayName"]) ?? label(info["CFBundleName"]) ?? url.deletingPathExtension().lastPathComponent,
                path: path, bundleID: info["CFBundleIdentifier"] as? String ?? "Unknown",
                version: label(info["CFBundleShortVersionString"]) ?? "Unknown",
                build: info["CFBundleVersion"] as? String ?? "Unknown", created: values?.creationDate,
                lastUsed: lastUsed, feed: info["SUFeedURL"] as? String,
                appStore: fm.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path), executablePath: executable, architecture: MachArchitecture.at(executable))
            app.modified = ([url.path, infoURL.path] + (executable.map { [$0] } ?? [])).compactMap { (try? fm.attributesOfItem(atPath: $0)[.modificationDate]) as? Date }.max()
            app.recordedClassification = AppClassification.classify(path: path, bundleID: app.bundleID)
            app.revision = AppRevision.read(app)
            apps[path] = app
        }
        // Follow directory links, but visit each filesystem directory identity once.
        // This handles cycles and macOS firmlink aliases without excluding hidden paths.
        var pending = roots.reversed().map { $0 }
        var visited = Set<String>()
        var visitedPaths = Set<String>()
        var count = 0
        var lastProgress = Date.distantPast
        while let candidate = pending.popLast() {
            if cancelled() { warnings.append("Scan interrupted by user; inventory is partial."); break }
            let url = candidate.standardizedFileURL.resolvingSymlinksInPath()
            let path = url.path
            // Device nodes are not application storage; do not descend into devfs.
            if path == "/dev" { warnings.append("Coverage exclusion: /dev device filesystem (not application storage)."); continue }
            do {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true else { continue }
                if candidate.pathExtension.lowercased() == "app" || url.pathExtension.lowercased() == "app" { read(url) }
                guard visitedPaths.insert(path).inserted else { continue }
                let attributes = try fm.attributesOfItem(atPath: path)
                if let device = attributes[.systemNumber] as? NSNumber, let inode = attributes[.systemFileNumber] as? NSNumber {
                    guard visited.insert("\(device):\(inode)").inserted else { continue }
                }
                count += 1
                if Date().timeIntervalSince(lastProgress) >= 0.5 { progress(count, path); lastProgress = Date() }
                // Continue inside bundles: embedded helper apps are inventory evidence too.
                let children = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [])
                // Prefer logical macOS paths before their Data-volume mirrors so
                // identity deduplication keeps stable, user-facing app locations.
                let ordered = children.sorted { left, right in
                    func rank(_ url: URL) -> Int {
                        if url.path == "/System" || url.path == "/System/Volumes" { return 1 }
                        return 0
                    }
                    if rank(left) != rank(right) { return rank(left) < rank(right) }
                    return left.path < right.path
                }
                for child in ordered.reversed() {
                    if cancelled() { break }
                    do {
                        let properties = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                        if properties.isDirectory == true || properties.isSymbolicLink == true { pending.append(child) }
                    } catch { warnings.append("Cannot inspect path: \(child.path): \(error.localizedDescription)") }
                }
            } catch { warnings.append("Cannot scan path: \(path): \(error.localizedDescription)") }
        }
        if cancelled() && !warnings.contains(where: { $0.contains("Scan interrupted by user") }) {
            warnings.append("Scan interrupted by user; inventory is partial.")
        }
        progress(count, "Scan finished")
        return ScanResult(apps: apps.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, warnings: warnings)
    }
}
/// Only regular files are read; nonblocking open prevents FIFO/device traps in untrusted bundles.
enum InventoryFile {
    static func read(_ path: String, limit: Int, prefixOnly: Bool = false) -> Data? {
        let descriptor = Darwin.open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size >= 0, prefixOnly || info.st_size <= limit else { return nil }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: min(limit + 1, 65536))
        while result.count < limit + (prefixOnly ? 0 : 1) {
            let wanted = min(buffer.count, limit + (prefixOnly ? 0 : 1) - result.count)
            let count = Darwin.read(descriptor, &buffer, wanted)
            if count == 0 { break }
            if count < 0 { if errno == EINTR { continue }; return nil }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result.count <= limit ? result : nil
    }
}
public enum Version {
    // Unknown formats intentionally do not produce an up-to-date verdict.
    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult? {
        func parts(_ value: String) -> [Int]? {
            var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasPrefix("v") { text.removeFirst() }
            guard !text.isEmpty, text.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) else { return nil }
            let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
            let numbers = pieces.compactMap { Int($0) }
            return numbers.count == pieces.count ? numbers : nil
        }
        guard let a = parts(lhs), let b = parts(rhs) else { return nil }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
public enum CSV {
    public static func field(_ value: String) -> String {
        let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first
        let safe = first.map { "=+-@".contains($0) } == true || value.hasPrefix("\t") || value.hasPrefix("\r") ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    public static func export(_ apps: [InstalledApp], updates: [String: UpdateResult], evidence: [String: SecurityEvidence] = [:], integrity: [String: IntegrityEvidence] = [:], developerLinks: [String: DeveloperLinks] = [:], revisions: [String: String] = [:], findings: [AuditFinding] = [], context: AuditContext? = nil, asOf: Date = Date()) -> String {
        let iso = ISO8601DateFormatter()
        let header = ["Name", "Bundle ID", "Installed version", "Build", "Path", "Install date evidence", "Install date source", "Last used", "Last used source", "Update status", "Latest version", "Update source", "Checked at", "Identity basis", "Architecture", "Signature", "Publisher", "Team ID", "Signed ID", "Gatekeeper", "Notarization", "Security checked at", "Receipt IDs", "Receipt event date", "Receipt lookup", "Executable SHA256", "Info.plist SHA256", "CodeResources SHA256", "Integrity checked at", "Integrity errors", "Manual developer website", "Manual support", "Manual release notes", "Catalog homepage", "Update age band", "Update date evidence", "Update date source", "Update freshness", "Security freshness", "Integrity freshness", "Audit context", "Exception decisions", "App category", "Update channel"]
        let rows = apps.map { app -> [String] in
            let update = UpdateRouting.result(app, recorded: updates[app.id], at: asOf)
            let security = evidence[app.id]
            let links = developerLinks[DeveloperLinks.key(app)] ?? DeveloperLinks()
            let row: [String] = [app.name, app.bundleID, app.version, app.build, app.path,
                    (security?.installDate ?? app.created).map { iso.string(from: $0) } ?? "", security?.installSource ?? "Bundle filesystem creation (estimate; receipts not checked)",
                    app.lastUsed.map { iso.string(from: $0) } ?? "", "Spotlight (best effort)",
                    update?.status ?? "Not checked", update?.latest ?? "", update?.source ?? "", (app.classification.managedByMacOS || app.appStore) ? "" : update.map { iso.string(from: $0.checked) } ?? "", update?.identity ?? "Not verified", app.architecture ?? "Unknown", security?.signature ?? "Not checked", security?.publisher ?? "Not checked", security?.teamID ?? "", security?.signedID ?? "", security?.gatekeeper ?? "Not checked", security?.notarization ?? "Not checked", security.map { iso.string(from: $0.checked) } ?? "", security?.receipts.map(\.packageID).joined(separator: "; ") ?? "", security?.installDate.map { iso.string(from: $0) } ?? "", security?.receiptStatus ?? (security == nil ? "Not checked" : "Unknown (legacy snapshot)"), integrity[app.id]?.hashes["Executable"] ?? "", integrity[app.id]?.hashes["Info.plist"] ?? "", integrity[app.id]?.hashes["CodeResources"] ?? "", integrity[app.id].map { iso.string(from: $0.checked) } ?? "", integrity[app.id]?.errors.keys.sorted().map { "\($0): \(integrity[app.id]?.errors[$0] ?? "")" }.joined(separator: "; ") ?? ""]
            let age = UpdateAge.evidence(app, security: security)
            let revision = revisions[app.id] ?? app.revision
            let decisions = findings.filter { $0.path == app.path || $0.path.isEmpty }.compactMap { item -> String? in
                guard let decision = item.exception else { return nil }
                return item.title + " · " + decision.status(for: item, now: asOf) + " · " + decision.description
            }.joined(separator: "\n")
            return row + [links.website, links.support, links.releaseNotes, update?.homepage ?? "", app.classification.managedByMacOS ? "OS-maintained" : UpdateAge.band(date: age.date, now: asOf).rawValue, age.date.map { iso.string(from: $0) } ?? "", age.source,
                          (app.classification.managedByMacOS || app.appStore) ? "Availability not checked; update channel only" : AppRevision.status(observed: update?.revision, current: revision), AppRevision.status(observed: security?.revision, current: revision), AppRevision.status(observed: integrity[app.id]?.revision, current: revision), context?.summary ?? "", decisions, app.classification.category.rawValue, app.classification.managedByMacOS ? "macOS Software Update" : app.appStore ? "App Store" : "Developer / automatic source or manual check"]
        }
        return ([header] + rows).map { $0.map(field).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
}
