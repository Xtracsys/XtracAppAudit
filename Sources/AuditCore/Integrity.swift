import Foundation
import CryptoKit

public struct IntegrityEvidence: Codable, Sendable {
    public let checked: Date
    public let hashes: [String: String]
    public let errors: [String: String]
    public var revision: String? = nil
    public init(hashes: [String: String], errors: [String: String]) { checked = Date(); self.hashes = hashes; self.errors = errors }
    public static func digest(_ url: URL, limit: UInt64 = 2_147_483_648) throws -> String {
        let before = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = before[.size] as? NSNumber, size.uint64Value <= limit else { throw AuditFileError.invalid("File exceeds hashing limit (2 GB by default).") }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hasher = SHA256(); var total: UInt64 = 0
        let deadline = Date().addingTimeInterval(30)
        while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty {
            guard Date() < deadline, !Task.isCancelled else { throw AuditFileError.invalid("Hashing timed out or was cancelled.") }
            total += UInt64(bytes.count)
            guard total <= limit else { throw AuditFileError.invalid("File grew beyond hashing limit.") }
            hasher.update(data: bytes)
        }
        let after = try FileManager.default.attributesOfItem(atPath: url.path)
        guard total == size.uint64Value,
              (before[.size] as? NSNumber) == (after[.size] as? NSNumber),
              (before[.modificationDate] as? Date) == (after[.modificationDate] as? Date),
              (before[.systemFileNumber] as? NSNumber) == (after[.systemFileNumber] as? NSNumber) else { throw AuditFileError.invalid("File changed during hashing; no stable digest recorded.") }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public static func collect(_ app: InstalledApp) -> Self {
        let before = AppRevision.read(app)
        if let scanned = app.revision, scanned != before { return Self(hashes: [:], errors: ["Inventory": "App files changed since scanning. Rescan before collecting hashes."]) }
        let paths = ["Executable": app.executablePath, "Info.plist": app.path + "/Contents/Info.plist", "CodeResources": app.path + "/Contents/_CodeSignature/CodeResources"]
        var hashes: [String: String] = [:]; var errors: [String: String] = [:]
        for key in paths.keys.sorted() {
            guard let path = paths[key] ?? nil else { errors[key] = "No executable path available"; continue }
            do { hashes[key] = try digest(URL(fileURLWithPath: path)) } catch { errors[key] = error.localizedDescription }
        }
        var value = Self(hashes: hashes, errors: errors)
        value.revision = before == AppRevision.read(app) ? before : nil
        return value
    }
    public static func fingerprint(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
}
