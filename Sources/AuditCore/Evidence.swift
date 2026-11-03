import Foundation
import Security

public struct SigningIdentity: Sendable, Codable {
    public let identifier: String
    public let team: String
    public let publisher: String
    public let valid: Bool
    public let status: String
    public let diagnostics: String
    public static func inspect(_ path: String) -> Self {
        var code: SecStaticCode?
        let create = SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code)
        guard create == errSecSuccess, let code else {
            return Self(identifier: "", team: "", publisher: "Unknown", valid: false, status: "Unavailable", diagnostics: "Unable to read signing metadata (\(create)).")
        }
        var raw: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &raw)
        let info = raw as? [String: Any] ?? [:]
        let identifier = info[kSecCodeInfoIdentifier as String] as? String ?? ""
        let team = info[kSecCodeInfoTeamIdentifier as String] as? String ?? ""
        let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
        let publisher = certificates.first.flatMap { SecCertificateCopySubjectSummary($0) as String? } ?? (team.isEmpty ? "Unsigned / ad-hoc / unknown" : team)
        let check = ProcessRunner.run("/usr/bin/codesign", ["--verify", "--strict", "--all-architectures", "-R=anchor apple generic", path], timeout: 15)
        let valid = infoStatus == errSecSuccess && check.status == 0 && !check.timedOut && !team.isEmpty
        let status = check.timedOut ? "Timed out" : check.status == 0 ? (team.isEmpty ? "Valid Apple signature (no team)" : "Valid") : "Invalid / unsigned / untrusted"
        return Self(identifier: identifier, team: team, publisher: publisher, valid: valid, status: status, diagnostics: check.output)
    }
}
public struct PublisherRule: Codable, Sendable, Identifiable {
    public var id: String { bundleID }
    public let bundleID: String
    public let teamID: String
    public let cask: String
    public var provenance: String? = nil
    public init(bundleID: String, teamID: String, cask: String, provenance: String? = nil) { self.bundleID = bundleID; self.teamID = teamID; self.cask = cask; self.provenance = provenance }
    public func matches(bundleID: String, signedID: String, teamID: String, valid: Bool) -> Bool {
        valid && self.bundleID == bundleID && self.bundleID == signedID && self.teamID == teamID
    }
    // Limited, explicit rules. Filename-only candidates never acquire a verified verdict.
    public static let known: [Self] = [
        .init(bundleID: "com.google.Chrome", teamID: "EQHXZ8M8AV", cask: "google-chrome"),
        .init(bundleID: "com.microsoft.VSCode", teamID: "UBF8T346G9", cask: "visual-studio-code"),
        .init(bundleID: "org.mozilla.firefox", teamID: "43AQ936H96", cask: "firefox"),
        .init(bundleID: "com.microsoft.edgemac", teamID: "UBF8T346G9", cask: "microsoft-edge", provenance: "Apple-anchored installed Microsoft Edge signature verified 2026-10-22"),
        .init(bundleID: "com.microsoft.teams2", teamID: "UBF8T346G9", cask: "microsoft-teams", provenance: "Apple-anchored installed Microsoft Teams signature verified 2026-10-22"),
        .init(bundleID: "com.github.GitHubClient", teamID: "VEKTX9H2N7", cask: "github", provenance: "Apple-anchored installed GitHub Desktop signature verified 2026-10-22"),
        .init(bundleID: "ru.keepcoder.Telegram", teamID: "6N38VWS5BX", cask: "telegram", provenance: "Apple-anchored installed Telegram signature verified 2026-10-22"),
        .init(bundleID: "com.electron.ollama", teamID: "3MU9H2V9Y9", cask: "ollama-app", provenance: "Apple-anchored installed Ollama signature verified 2026-10-22"),
        .init(bundleID: "com.todesktop.230313mzl4w4u92", teamID: "VDXQ22DGB9", cask: "cursor", provenance: "Apple-anchored installed Cursor signature verified 2026-10-22")
    ]
}
public struct ReceiptEvidence: Codable, Sendable {
    public let packageID: String
    public let date: Date
    public let version: String
    public static func parse(_ data: Data) -> Self? {
        guard let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let id = dict["pkgid"] as? String, !id.isEmpty,
              let time = dict["install-time"] as? NSNumber, time.doubleValue > 0,
              time.doubleValue <= Date().addingTimeInterval(86400).timeIntervalSince1970 else { return nil }
        return Self(packageID: id, date: Date(timeIntervalSince1970: time.doubleValue), version: dict["pkg-version"] as? String ?? "Unknown")
    }
    public static func merge(_ primary: [Self], _ fallback: [Self]) -> [Self] {
        let byID = Dictionary((primary + fallback).map { ($0.packageID, $0) }, uniquingKeysWith: { $0.date >= $1.date ? $0 : $1 })
        return byID.values.sorted { $0.date == $1.date ? $0.packageID < $1.packageID : $0.date > $1.date }
    }
    public static func matchedRecord(_ data: Data, appPath: String, files: String) -> Self? {
        guard let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let prefix = dict["InstallPrefixPath"] as? String,
              let id = dict["PackageIdentifier"] as? String, !id.hasPrefix("-"), id.count <= 512,
              let date = dict["InstallDate"] as? Date, date.timeIntervalSince1970 > 0, date <= Date().addingTimeInterval(86400) else { return nil }
        let base = URL(fileURLWithPath: "/" + prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).standardizedFileURL.path
        let prefixPath = base == "/" ? "/" : base + "/"
        guard appPath.hasPrefix(prefixPath) else { return nil }
        let relative = String(appPath.dropFirst(prefixPath.count))
        let entries = Set(files.split(whereSeparator: \.isNewline).map { String($0).hasPrefix("./") ? String($0.dropFirst(2)) : String($0) })
        guard entries.contains(relative) || entries.contains(relative + "/Contents/Info.plist") else { return nil }
        return Self(packageID: id, date: date, version: dict["PackageVersion"] as? String ?? "Unknown")
    }
    public static func lookup(app: InstalledApp) -> ReceiptLookup {
        var issues: [String] = []
        var ids = Set<String>()
        let paths = [app.path, app.executablePath].compactMap { $0 }
        for path in paths {
            let result = ProcessRunner.run("/usr/sbin/pkgutil", ["--file-info-plist", path], timeout: 4)
            guard result.status == 0, !result.timedOut else { issues.append("File ownership lookup \(result.timedOut ? "timed out" : "failed") for \(path): \(result.output)"); continue }
            // pkgutil may emit one plist per owning package; collect only receipt IDs from plist dictionaries.
            let text = result.output
            let pieces = text.components(separatedBy: "</plist>")
            for piece in pieces where piece.contains("<plist") {
                guard let start = piece.range(of: "<?xml")?.lowerBound ?? piece.range(of: "<plist")?.lowerBound else { continue }
                let data = Data((String(piece[start...]) + "</plist>").utf8)
                guard let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { issues.append("Unparseable file ownership result for \(path)"); continue }
                func collect(_ value: Any) {
                    if let d = value as? [String: Any] {
                        if let id = d["pkgid"] as? String, !id.hasPrefix("-"), id.count <= 512, !id.contains("\0") { ids.insert(id) }
                        for (key, child) in d where key != "pkgid" { collect(child) }
                    } else if let array = value as? [Any] { array.forEach(collect) }
                }
                collect(dict)
            }
        }
        if ids.count > 8 { issues.append("Receipt lookup limited to first eight owning packages.") }
        var receipts: [Self] = ids.sorted().prefix(8).compactMap { id in
            let info = ProcessRunner.run("/usr/sbin/pkgutil", ["--pkg-info-plist", id], timeout: 4)
            guard info.status == 0, !info.timedOut else { issues.append("Receipt \(id) lookup \(info.timedOut ? "timed out" : "failed"): \(info.output)"); return nil }
            guard let receipt = parse(Data(info.output.utf8)) else { issues.append("Receipt \(id) contained no valid install event."); return nil }
            return receipt
        }.sorted { $0.date > $1.date }
        do {
            let directory = URL(fileURLWithPath: "/var/db/receipts")
            do {
                let records = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "plist" }.sorted { $0.path < $1.path }
                var candidates = 0
                for record in records {
                    guard let data = try? Data(contentsOf: record),
                          let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                          let rawPrefix = dict["InstallPrefixPath"] as? String, !rawPrefix.isEmpty,
                          rawPrefix != "/", let id = dict["PackageIdentifier"] as? String, !id.hasPrefix("-"), id.count <= 512 else { continue }
                    let prefix = URL(fileURLWithPath: "/" + rawPrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).standardizedFileURL.path
                    guard prefix != "/", app.path.hasPrefix(prefix + "/") else { continue }
                    candidates += 1
                    if candidates > 16 { issues.append("Payload fallback limited to sixteen candidate receipts."); break }
                    let payload = ProcessRunner.run("/usr/sbin/pkgutil", ["--files", id], timeout: 4)
                    if payload.timedOut || payload.status != 0 { issues.append("Receipt payload lookup failed or timed out: \(id)"); continue }
                    if let receipt = matchedRecord(data, appPath: app.path, files: payload.output) { receipts.append(receipt) }
                }
            } catch { issues.append("Receipt index unavailable: \(error.localizedDescription)") }
        }
        receipts = merge(receipts, [])
        let status = issues.isEmpty ? (receipts.isEmpty ? "No matched receipts returned" : "Matched installer receipts") : (receipts.isEmpty ? "Lookup unavailable / incomplete" : "Matched receipts; lookup incomplete")
        return ReceiptLookup(receipts: receipts, status: status, diagnostics: issues.joined(separator: "\n"))
    }
}
public struct ReceiptLookup: Sendable {
    public let receipts: [ReceiptEvidence]
    public let status: String
    public let diagnostics: String
}
public struct SecurityEvidence: Codable, Sendable {
    public let checked: Date
    public let signature: String
    public let publisher: String
    public let teamID: String
    public let signedID: String
    public let architecture: String
    public let gatekeeper: String
    public let notarization: String
    public let diagnostics: String
    public let receipts: [ReceiptEvidence]
    public var receiptStatus: String? = nil
    public var revision: String? = nil
    public var installDate: Date? { receipts.first?.date }
    public var installSource: String { receipts.isEmpty ? "Bundle filesystem creation estimate; " + (receiptStatus ?? "receipt lookup status unknown") : "Installer receipt event (not original installation proof)" }
    /// Distribution context is reported only from an accepted Gatekeeper assessment.
    /// A path, bundle identifier or receipt alone never establishes trust.
    public static func notarizationStatus(status: Int32, timedOut: Bool, output: String) -> String {
        guard !timedOut else { return "Not established — assessment timed out" }
        guard status == 0 else { return "Not established — assessment unsuccessful" }
        let source = output.split(whereSeparator: \.isNewline).map(String.init).first { $0.hasPrefix("source=") }
        switch source {
        case "source=Notarized Developer ID": return "Confirmed notarized"
        case "source=Apple System": return "Apple system distribution"
        case "source=Mac App Store": return "App Store distribution"
        default: return "Not established — no explicit notarization evidence"
        }
    }
    public static func inspect(_ app: InstalledApp, allowNetwork: Bool = true) -> Self {
        guard allowNetwork else { return Self(checked: Date(), signature: "Skipped (offline)", publisher: "Not collected", teamID: "", signedID: "", architecture: app.architecture ?? "Unknown", gatekeeper: "Skipped (offline)", notarization: "Not checked", diagnostics: "Offline mode skips signing/trust and Gatekeeper commands that may contact Apple services.", receipts: []) }
        let before = AppRevision.read(app)
        if let scanned = app.revision, scanned != before { return Self(checked: Date(), signature: "Unavailable", publisher: "Not collected", teamID: "", signedID: "", architecture: "Unknown", gatekeeper: "Unavailable", notarization: "Not checked", diagnostics: "App files changed since scanning. Rescan before inspecting.", receipts: []) }
        let identity = SigningIdentity.inspect(app.path)
        let assessment = ProcessRunner.run("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=4", app.path], timeout: 20)
        let gatekeeper = assessment.timedOut ? "Timed out" : assessment.status == 0 ? "Accepted" : assessment.status == -1 ? "Unavailable" : "Rejected / assessment failed"
        let notarization = Self.notarizationStatus(status: assessment.status, timedOut: assessment.timedOut, output: assessment.output)
        let receiptLookup = ReceiptEvidence.lookup(app: app)
        var evidence = Self(checked: Date(), signature: identity.status, publisher: identity.publisher, teamID: identity.team, signedID: identity.identifier,
                    architecture: app.architecture ?? "Unknown", gatekeeper: gatekeeper, notarization: notarization,
                    diagnostics: "SIGNATURE\n" + identity.diagnostics + "\nGATEKEEPER\n" + assessment.output + "\nRECEIPTS\n" + receiptLookup.diagnostics,
                    receipts: receiptLookup.receipts)
        evidence.receiptStatus = receiptLookup.status
        evidence.revision = before == AppRevision.read(app) ? before : nil
        return evidence
    }
}
public enum MachArchitecture {
    public static func read(_ data: Data) -> String {
        let bytes = Array(data.prefix(4096))
        func number(_ offset: Int, little: Bool = false) -> UInt32? {
            guard offset >= 0, offset + 4 <= bytes.count else { return nil }
            let values = little ? Array(bytes[offset..<offset+4].reversed()) : Array(bytes[offset..<offset+4])
            return values.reduce(0) { ($0 << 8) | UInt32($1) }
        }
        func name(_ cpu: UInt32) -> String {
            switch cpu { case 0x0100000c: return "arm64"; case 0x01000007: return "x86_64"; case 7: return "i386"; case 12: return "arm"; default: return "cpu-\(cpu)" }
        }
        guard let magic = number(0) else { return "Unknown" }
        if [UInt32(0xfeedface), 0xfeedfacf, 0xcefaedfe, 0xcffaedfe].contains(magic), let cpu = number(4, little: magic == 0xcefaedfe || magic == 0xcffaedfe) { return name(cpu) }
        guard [UInt32(0xcafebabe), 0xcafebabf, 0xbebafeca, 0xbfbafeca].contains(magic) else { return "Unknown" }
        let little = magic == 0xbebafeca || magic == 0xbfbafeca
        let stride = magic == 0xcafebabf || magic == 0xbfbafeca ? 32 : 20
        guard let count = number(4, little: little), count > 0, count <= 32 else { return "Unknown" }
        let cpus = (0..<Int(count)).compactMap { number(8 + $0 * stride, little: little) }
        guard cpus.count == Int(count) else { return "Unknown" }
        return Set(cpus.map(name)).sorted().joined(separator: ", ")
    }
    public static func at(_ path: String?) -> String {
        guard let path, let data = InventoryFile.read(path, limit: 4096, prefixOnly: true) else { return "Unknown" }
        return read(data)
    }
}
