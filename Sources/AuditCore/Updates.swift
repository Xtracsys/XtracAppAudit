import Foundation
import Darwin

public struct UpdateResult: Sendable, Codable {
    public let status: String
    public let latest: String
    public let source: String
    public let checked: Date
    public let detail: String
    public var homepage: String? = nil
    public var revision: String? = nil
    public let identity: String?
    public init(status: String, latest: String = "", source: String = "", detail: String = "", identity: String = "Not verified", checked: Date = Date()) {
        self.status = status; self.latest = latest; self.source = source; self.checked = checked; self.detail = detail; self.identity = identity
    }
}
public struct Cask: Decodable, Sendable {
    public let token: String
    public let version: String
    public let artifacts: [JSONValue]?
    public let url: String?
    public let homepage: String?
    public let depends_on: [String: JSONValue]?
    public let variations: [String: JSONValue]?
    public func compatibleVersion(os: String, architecture: String) -> String? {
        let major = Int(os.split(separator: ".").first ?? "") ?? 0
        let names = [11: "big_sur", 12: "monterey", 13: "ventura", 14: "sonoma", 15: "sequoia", 26: "tahoe"]
        var selectedVersion = version
        var requirements = depends_on
        if let name = names[major] {
            for key in [architecture + "_" + name, name, architecture] {
                if case .object(let variant) = variations?[key] {
                    if case .string(let v) = variant["version"] { selectedVersion = v }
                    if case .object(let deps) = variant["depends_on"] { requirements = deps }
                    break
                }
            }
        } else if !(variations?.isEmpty ?? true) { return nil }
        if let macos = requirements?["macos"] {
            guard case .object(let constraints) = macos else { return nil }
            for (op, value) in constraints {
                guard case .array(let versions) = value else { return nil }
                let accepted = versions.contains { entry in
                    guard case .string(let required) = entry, let order = Version.compare(os, required) else { return false }
                    switch op {
                    case ">=": return order != .orderedAscending
                    case ">": return order == .orderedDescending
                    case "<=": return order != .orderedDescending
                    case "<": return order == .orderedAscending
                    case "==", "=": return order == .orderedSame
                    default: return false
                    }
                }
                if !accepted { return nil }
            }
        }
        if let arch = requirements?["arch"] {
            guard case .array(let entries) = arch else { return nil }
            let supported = entries.contains { entry in
                if case .string(let value) = entry { return value == architecture }
                if case .object(let values) = entry, case .string(let type) = values["type"] {
                    return type == (architecture == "arm64" ? "arm" : "intel")
                }
                return false
            }
            if !supported { return nil }
        }
        return selectedVersion
    }
    public static func match(filename: String, casks: [Cask]) -> Cask? {
        let matches = casks.filter { cask in
            (cask.artifacts ?? []).contains { artifact in
                let values: [JSONValue]
                var target: String?
                switch artifact {
                case .object(let object):
                    if case .string(let path) = object["target"] { target = path }
                    guard case .array(let appValues) = object["app"] else { return false }; values = appValues
                case .array(let array): values = array
                default: return false
                }
                guard let first = values.first,
                      case .string(let path) = first else { return false }
                if target == nil {
                    for value in values.dropFirst() {
                        if case .object(let options) = value, case .string(let renamed) = options["target"] { target = renamed }
                    }
                }
                let installed = target ?? path
                return URL(fileURLWithPath: installed).lastPathComponent == filename && installed.hasSuffix(".app")
            }
        }
        return matches.count == 1 ? matches[0] : nil
    }
}
public enum JSONValue: Decodable, Sendable {
    case string(String), array([JSONValue]), object([String: JSONValue]), other
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else { self = .other }
    }
}
public struct Release: Sendable {
    public var version = ""
    public var build = ""
    var minimum = ""
    var maximum = ""
    var channel = ""
    var os = ""
}
public enum Appcast {
    public static func latest(_ data: Data, os: String) throws -> Release? {
        let delegate = FeedParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? URLError(.cannotParseResponse) }
        let candidates = delegate.releases.filter { release in
            !release.build.isEmpty && release.channel.isEmpty && (release.os.isEmpty || release.os == "macos") &&
            (release.minimum.isEmpty || Version.compare(os, release.minimum).map { $0 != .orderedAscending } == true) &&
            (release.maximum.isEmpty || Version.compare(os, release.maximum).map { $0 != .orderedDescending } == true)
        }
        // Feed order is not trusted. Unorderable builds cannot establish latest.
        guard candidates.allSatisfy({ Version.compare($0.build, $0.build) != nil }) else { return nil }
        return candidates.max { Version.compare($0.build, $1.build) == .orderedAscending }
    }
}
private final class FeedParser: NSObject, XMLParserDelegate {
    var releases: [Release] = []
    var current: Release?
    var element = ""
    var buffer = ""
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        element = name; buffer = ""
        if name == "item" { current = Release() }
        if name == "enclosure", current != nil {
            if let build = attributes["sparkle:version"] { current?.build = build }
            if let version = attributes["sparkle:shortVersionString"] { current?.version = version }
            current?.os = attributes["sparkle:os"] ?? ""
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { buffer += string }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "sparkle:minimumSystemVersion": current?.minimum = text
        case "sparkle:maximumSystemVersion": current?.maximum = text
        case "sparkle:channel": current?.channel = text
        case "sparkle:version": if !text.isEmpty { current?.build = text }
        case "sparkle:shortVersionString": if !text.isEmpty { current?.version = text }
        case "item": if let release = current { releases.append(release) }; current = nil
        default: break
        }
        buffer = ""
    }
}
public actor UpdateChecker {
    private var catalog: [Cask]?
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        config.httpMaximumConnectionsPerHost = 3
        session = URLSession(configuration: config, delegate: SafeRedirects(), delegateQueue: nil)
    }
    public static func allowedURL(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              let host = url.host?.lowercased(), host.contains("."), !host.hasSuffix(".local"),
              host != "localhost", !host.contains(":"),
              host.range(of: "^[0-9.]+$", options: .regularExpression) == nil else { return nil }
        return url
    }
    private static func resolveHost(_ host: String) -> Bool {
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, nil, &result) == 0, let first = result else { return false }
        defer { freeaddrinfo(first) }
        var pointer: UnsafeMutablePointer<addrinfo>? = first
        while let info = pointer {
            let address = info.pointee
            if address.ai_family == AF_INET {
                let ip = address.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
                let a = ip >> 24, b = (ip >> 16) & 255
                if a == 0 || a == 10 || a == 127 || a >= 224 || (a == 169 && b == 254) || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168) || (a == 100 && (64...127).contains(b)) { return false }
            } else if address.ai_family == AF_INET6 {
                let raw = address.ai_addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
                let octets = withUnsafeBytes(of: raw) { Array($0) }
                // Accept only global unicast; excludes loopback, local, mapped IPv4.
                if octets[0] & 0xe0 != 0x20 { return false }
            } else { return false }
            pointer = address.ai_next
        }
        return true
    }
    static func publicHost(_ host: String) async -> Bool {
        let gate = ResolutionGate()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                gate.install(continuation)
                DispatchQueue.global(qos: .utility).async { gate.finish(resolveHost(host)) }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) { gate.finish(false) }
            }
        } onCancel: { gate.finish(false) }
    }
    private func fetch(_ text: String, limit: Int) async throws -> Data {
        guard let url = Self.allowedURL(text), await Self.publicHost(url.host ?? "") else { throw URLError(.unsupportedURL) }
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let finalURL = response.url, Self.allowedURL(finalURL.absoluteString) != nil, response.expectedContentLength <= Int64(limit) else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }
    public func loadCatalog() async throws {
        if catalog == nil {
            catalog = try JSONDecoder().decode([Cask].self, from: await fetch("https://formulae.brew.sh/api/cask.json", limit: 40_000_000))
        }
    }
    public func check(_ app: InstalledApp, rules: [PublisherRule] = PublisherRule.known, allowNetwork: Bool = true) async -> UpdateResult {
        let before = AppRevision.read(app)
        if let scanned = app.revision, scanned != before { return UpdateResult(status: "Unknown", detail: "App files changed since inventory was scanned. Rescan before checking its version or feed.") }
        if var local = UpdateRouting.localResult(app) { local.revision = before; return local }
        guard allowNetwork else { return UpdateResult(status: "Offline — not checked", detail: "Network checks are disabled.") }
        var value = await performCheck(app, rules: rules)
        if let before, before == AppRevision.read(app) { value.revision = before }
        else { value = UpdateResult(status: "Unknown", detail: "App files changed or were unreadable during this check. Rescan and retry.") }
        return value
    }
    private func performCheck(_ app: InstalledApp, rules: [PublisherRule]) async -> UpdateResult {
        if let feed = app.feed {
            let signing = await Task.detached { SigningIdentity.inspect(app.path) }.value
            let verified = signing.valid && signing.identifier == app.bundleID
            do {
                let os = ProcessInfo.processInfo.operatingSystemVersion
                let release = try Appcast.latest(await fetch(feed, limit: 5_000_000), os: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
                guard let release else { return UpdateResult(status: "Unknown", source: feed, detail: "No comparable stable release compatible with this macOS.") }
                return result(installed: app.build, remote: release.build, display: release.version.isEmpty ? release.build : release.version, source: feed, detail: "Sparkle bundle build comparison; latest build \(release.build). Feed URL supplied by installed app.", identity: verified ? "Signed app feed · \(signing.publisher) · \(signing.team)" : "Unverified app/feed identity", verified: verified)
            } catch { return UpdateResult(status: "Check failed", source: feed, detail: error.localizedDescription) }
        }
        if app.appStore { return UpdateResult(status: "App Store", detail: "Check updates in the App Store.") }
        do { try await loadCatalog() }
        catch { return UpdateResult(status: "Check failed", source: "https://formulae.brew.sh/api/cask.json", detail: error.localizedDescription) }
        let rule = rules.first { $0.bundleID == app.bundleID }
        let caskByID = rule.flatMap { rule in catalog?.first { $0.token == rule.cask } }
        guard let cask = caskByID ?? Cask.match(filename: URL(fileURLWithPath: app.path).lastPathComponent, casks: catalog ?? []) else {
            return UpdateResult(status: "Manual check needed", detail: "No automatic source match. Use the developer website, support or release notes to check manually; this does not mean the vendor stopped supporting the app.")
        }
        var verified = false
        var identity = "Filename candidate only; publisher not verified"
        if let rule, rule.cask == cask.token {
            let signing = await Task.detached { SigningIdentity.inspect(app.path) }.value
            verified = rule.matches(bundleID: app.bundleID, signedID: signing.identifier, teamID: signing.team, valid: signing.valid)
            identity = verified ? "Bundle ID + valid signing team \(signing.team)" : "Publisher rule not satisfied: signature \(signing.status), signed ID \(signing.identifier), team \(signing.team)"
        }
        // Some casks publish marketing,build; compare marketing version only.
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "intel"
        #endif
        guard let candidate = cask.compatibleVersion(os: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)", architecture: arch) else {
            var value = UpdateResult(status: "Unknown", latest: cask.version, source: "https://formulae.brew.sh/cask/\(cask.token)", detail: "Catalog compatibility is unsupported or excludes this OS/architecture. Review the source manually.", identity: identity)
            value.homepage = DeveloperLinks.url(cask.homepage ?? "")?.absoluteString; return value
        }
        let remote = String(candidate.split(separator: ",").first ?? "")
        var value = result(installed: app.version, remote: remote, display: candidate,
                      source: "https://formulae.brew.sh/cask/\(cask.token)", detail: "Applied catalog OS/architecture requirements where supplied. Confirm vendor eligibility on source page.", identity: identity, verified: verified)
        value.homepage = DeveloperLinks.url(cask.homepage ?? "")?.absoluteString; return value
    }
    private func result(installed: String, remote: String, display: String, source: String, detail: String, identity: String, verified: Bool) -> UpdateResult {
        guard let order = Version.compare(installed, remote) else { return UpdateResult(status: "Unknown", latest: display, source: source, detail: "Versions cannot be compared reliably. " + detail, identity: identity) }
        let status = !verified ? (order == .orderedAscending ? "Possible update" : "Unverified candidate") : order == .orderedAscending ? "Update available" : order == .orderedSame ? "Current at source" : "Newer than source"
        return UpdateResult(status: status, latest: display, source: source, detail: detail, identity: identity)
    }
}

private final class SafeRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        Task {
            guard let url = request.url, UpdateChecker.allowedURL(url.absoluteString) != nil, await UpdateChecker.publicHost(url.host ?? "") else { completionHandler(nil); return }
            completionHandler(request)
        }
    }
}

// Resolves cancellation/timeout/result races once; a timed-out libc lookup can finish in the background.
final class ResolutionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Bool?
    private var continuation: CheckedContinuation<Bool, Never>?
    func install(_ value: CheckedContinuation<Bool, Never>) {
        lock.lock()
        if let result { lock.unlock(); value.resume(returning: result) }
        else { continuation = value; lock.unlock() }
    }
    func finish(_ value: Bool) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = value
        let pending = continuation; continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
