import Foundation

/// Consistent path replacement across live/baseline export. Review output before sharing.
public struct ShareExport {
    private let appReplacements: [(String, String)]
    private let rootReplacements: [(String, String)]
    public init(_ snapshots: [AuditSnapshot]) {
        let standard = ["/Applications", "/System/Applications", "/System/Library/CoreServices", "/Library"]
        let apps = Set(snapshots.flatMap(\.apps).map(\.path)).sorted()
        var pairs: [(String, String)] = []
        for (index, path) in apps.enumerated() where !standard.contains(where: { path.hasPrefix($0 + "/") }) {
            pairs.append((path, "/Redacted/Apps/\(index + 1)/" + URL(fileURLWithPath: path).lastPathComponent))
        }
        appReplacements = pairs.sorted { $0.0.count > $1.0.count }; pairs = []
        for (index, root) in Set(snapshots.flatMap(\.roots)).sorted().enumerated() where root != "/" && !standard.contains(root) {
            pairs.append((root, "/Redacted/ScanFolder\(index + 1)"))
        }
        rootReplacements = pairs.sorted { $0.0.count > $1.0.count }
    }
    public func text(_ value: String) -> String {
        // Strip URLs before path rewriting can change their separators.
        var result = value.replacingOccurrences(of: "(?i)https?://[^\\s<>\"']+", with: "[web address removed for sharing]", options: .regularExpression)
        for (from, to) in appReplacements { result = result.replacingOccurrences(of: from, with: to) }
        // Diagnostics can contain paths beyond inventoried bundles. Prefer over-redaction.
        for prefix in ["/Users/", "/Volumes/"] {
            result = result.replacingOccurrences(of: prefix + "[^\\r\\n\\t\"<>]*", with: prefix + "REDACTED", options: .regularExpression)
        }
        for (from, to) in rootReplacements { result = result.replacingOccurrences(of: from, with: to) }
        return result
    }
    public func snapshot(_ value: AuditSnapshot) throws -> AuditSnapshot {
        func scrub(_ value: Any) -> Any {
            if let string = value as? String { return text(string) }
            if let array = value as? [Any] { return array.map(scrub) }
            if let dict = value as? [String: Any] {
                return Dictionary(dict.filter { $0.key != "context" }.map { key, value in
                    (text(key), ["reason", "reviewer"].contains(key) ? "[Free text omitted for sharing]" : scrub(value))
                }, uniquingKeysWith: { first, _ in first })
            }
            return value
        }
        let object = try JSONSerialization.jsonObject(with: value.encoded())
        var result = try AuditSnapshot.decode(JSONSerialization.data(withJSONObject: scrub(object)))
        if let originals = value.findings, var findings = result.findings {
            for index in findings.indices where index < originals.count {
                if var decision = findings[index].exception, originals[index].exception?.fingerprint == originals[index].fingerprint {
                    decision.fingerprint = findings[index].fingerprint; findings[index].exception = decision
                    result.exceptions?[findings[index].id] = decision
                }
            }
            result.findings = findings
        }
        result.redacted = true
        return result
    }
}
