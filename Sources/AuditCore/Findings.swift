import Foundation

public enum FindingSeverity: String, Codable, CaseIterable, Sendable { case action = "Action needed", review = "Review", unknown = "Unknown"; public var rank: Int { self == .action ? 0 : self == .review ? 1 : 2 } }
public struct AuditFinding: Identifiable, Codable, Sendable {
    public let id: String
    public let severity: FindingSeverity
    public let app: String
    public let path: String
    public let title: String
    public let evidence: String
    public let nextStep: String
    public var exception: FindingException? = nil
    public var fingerprint: String { IntegrityEvidence.fingerprint([id, severity.rawValue, title, evidence].joined(separator: "\n")) }
    public init(id: String, severity: FindingSeverity, app: String = "Audit coverage", path: String = "", title: String, evidence: String, nextStep: String) {
        self.id = id; self.severity = severity; self.app = app; self.path = path; self.title = title; self.evidence = evidence; self.nextStep = nextStep
    }
}
public enum FindingEngine {
    public static func evaluate(_ snapshot: AuditSnapshot, baseline: AuditSnapshot?, policy: AuditPolicy) -> [AuditFinding] {
        var findings: [AuditFinding] = []
        func add(_ id: String, _ severity: FindingSeverity, _ app: InstalledApp?, _ title: String, _ evidence: String, _ next: String) {
            findings.append(AuditFinding(id: id + (app?.path ?? ""), severity: severity, app: app?.name ?? "Audit coverage", path: app?.path ?? "", title: title, evidence: evidence, nextStep: next))
        }
        for group in DuplicateDetector.groups(snapshot.apps) {
            add("duplicate/" + group.bundleID, .review, nil, "Multiple installations: " + group.apps[0].name,
                group.bundleID + "\n" + group.apps.map { $0.version + " · " + $0.path }.joined(separator: "\n"),
                "Review the versions and locations. Copies can be intentional; reveal each in Finder before deciding which to keep. App Audit does not remove them.")
        }
        if !snapshot.warnings.isEmpty { add("scan-warnings", .unknown, nil, "Inventory coverage is incomplete", snapshot.warnings.joined(separator: "\n"), "Reconnect missing scan folders or resolve access warnings, then rescan before treating missing apps as removals.") }
        let missingSecurity = snapshot.apps.filter { snapshot.evidence[$0.id] == nil }.count
        if missingSecurity > 0 { add("security-coverage", .unknown, nil, "Security evidence has not been collected", "\(missingSecurity) of \(snapshot.apps.count) apps have no collected security evidence.", "Run Inspect security for the apps you need to audit. Unknown does not mean unsafe.") }
        let missingIntegrity = snapshot.apps.filter { snapshot.integrity?[$0.id] == nil }.count
        if missingIntegrity > 0 { add("hash-coverage", .unknown, nil, "Integrity baseline is incomplete", "\(missingIntegrity) apps have no recorded hashes.", "Collect integrity hashes, save an audit and compare it with a later audit.") }
        let manualApps = snapshot.apps.filter { !$0.classification.managedByMacOS && !$0.appStore && ["Unsupported", "Manual check needed"].contains(snapshot.updates[$0.id]?.status ?? "") }
        if !manualApps.isEmpty {
            add("manual-update-coverage", .unknown, nil, "Some apps need manual update checks", "\(manualApps.count) apps have no automatic source match:\n" + manualApps.map { $0.name + " · " + $0.path }.sorted().joined(separator: "\n"), "Use their developer links to check manually. Missing automatic coverage does not mean an app is unsupported by its vendor.")
        }
        for app in snapshot.apps {
            let current = snapshot.revisions?[app.id] ?? app.revision
            let observed = [app.revision, snapshot.updates[app.id]?.revision, snapshot.evidence[app.id]?.revision, snapshot.integrity?[app.id]?.revision].compactMap { $0 }
            if let current, observed.contains(where: { $0 != current }) {
                add("stale", .review, app, "Evidence predates an observed app file change", "A previous scan/check's file revision differs from the latest local metadata observation.", "Rescan to refresh app metadata, then repeat relevant update, signing and integrity checks. Revision metadata is not a full bundle verification.")
            }
            if let security = snapshot.evidence[app.id] {
                let signatureValid = security.signature.hasPrefix("Valid")
                if !signatureValid && security.gatekeeper == "Accepted" {
                    add("contradiction", .review, app, "Strict validation and Gatekeeper differ", "Strict signature: \(security.signature). Gatekeeper accepted this app. \(security.diagnostics.prefix(3000))", "Review the diagnostic. Finder metadata or resource changes can fail strict validation even when Gatekeeper accepts an app; verify the vendor copy before concluding it is malicious.")
                } else if security.signature == "Invalid / unsigned / untrusted" || security.gatekeeper == "Rejected / assessment failed" {
                    add("security-failure", .action, app, "Signing or Gatekeeper needs investigation", "Signature: \(security.signature). Gatekeeper: \(security.gatekeeper). \(security.diagnostics.prefix(3000))", "Confirm the vendor and inspect the diagnostic. Reinstall from a trusted source if the bundle is unexpectedly modified; this result alone is not a malware verdict.")
                } else if !signatureValid || ["Timed out", "Unavailable"].contains(security.gatekeeper) {
                    add("security-unknown", .unknown, app, "Security check is inconclusive", "Signature: \(security.signature). Gatekeeper: \(security.gatekeeper).", "Retry the check and review access/network conditions. Do not treat unavailable evidence as a clean verdict.")
                }
            }
            if let integrity = snapshot.integrity?[app.id], !integrity.errors.isEmpty { add("hash-unavailable", .unknown, app, "Some integrity hashes are unavailable", integrity.errors.keys.sorted().map { "\($0): \(integrity.errors[$0] ?? "")" }.joined(separator: "\n"), "Check file access or repeat collection after the app finishes updating. Only files with stable recorded hashes are compared.") }
            if let update = snapshot.updates[app.id], !app.classification.managedByMacOS, !app.appStore {
                if update.status == "Update available" && !(update.revision != nil && current != nil && update.revision != current) { add("update", .action, app, "Verified update available", "Installed \(app.version); source \(update.latest). \(update.source). \(update.identity ?? "")", "Review the verified source and update through the vendor's supported mechanism. App Audit does not install it.") }
                else if ["Possible update", "Unverified candidate"].contains(update.status) { add("update-candidate", .review, app, "Update source identity needs review", "Latest candidate \(update.latest). \(update.identity ?? "Not verified"). \(update.source)", "Confirm the bundle ID and publisher against the vendor, or add a carefully reviewed custom publisher rule. A filename match is not identity proof.") }
                else if ["Unknown", "Check failed"].contains(update.status) { add("update-unknown", .unknown, app, "Update status is inconclusive", update.detail, "Use the vendor or App Store to check manually. No supported match is not proof that the app is current.") }
            }
            if policy.enabled {
                let rule = policy.rules.first { $0.bundleID == app.bundleID }
                if rule?.allowed == false || (policy.allowOnlyListed && rule == nil) { add("policy-allow", .action, app, "App is outside approved policy", "Bundle ID \(app.bundleID) is blocked or is not on the allow-only list.", "Confirm the business need and remove the app or amend the approved policy through your normal review process.") }
                if let minimum = rule?.minimumVersion {
                    if let comparison = Version.compare(app.version, minimum) {
                        if comparison == .orderedAscending { add("policy-version", .action, app, "Below minimum version", "Installed \(app.version); policy minimum \(minimum).", "Update from the approved source or review the policy exception.") }
                    } else { add("policy-version-unknown", .unknown, app, "Minimum version cannot be checked", "Installed \(app.version); minimum \(minimum). Versions are not comparable.", "Confirm the version manually; this app has not been shown compliant with the minimum.") }
                }
                let teams = rule?.teams.isEmpty == false ? rule!.teams : policy.trustedTeams
                if !teams.isEmpty {
                    if let security = snapshot.evidence[app.id], security.signature == "Valid", security.signedID == app.bundleID {
                        if !teams.contains(security.teamID) { add("policy-team", .action, app, "Publisher is outside approved policy", "Observed team \(security.teamID); approved teams \(teams.joined(separator: ", ")).", "Validate the publisher change against the vendor before granting an exception.") }
                    } else { add("policy-team-unknown", .unknown, app, "Approved publisher cannot be verified", "A matching signed identifier and valid signature are required to check the allowed teams.", "Collect or resolve signing evidence before marking publisher policy compliant.") }
                }
            }
        }
        if let baseline {
            for change in AuditComparison.changes(baseline: baseline, current: snapshot) {
                let app = change.after ?? change.before
                if change.kind == "Integrity changed" {
                    let sameVersion = change.before?.version == change.after?.version && change.before?.build == change.after?.build
                    add("integrity-change", sameVersion ? .action : .review, app, sameVersion ? "Integrity changed without a version change" : "Integrity changed with an app update", change.summary, "Compare the vendor release and signature evidence. Hash changes alone do not prove tampering; these hashes cover the main executable and signing metadata, not every bundle file.")
                } else if ["Signing team changed", "Signature changed"].contains(change.kind) { add("signing-change-" + change.kind, .review, app, change.kind, change.summary, "Confirm the publisher or signing change through a trusted vendor source before accepting the new baseline.") }
            }
        }
        return findings.map { item in var value = item; value.exception = snapshot.exceptions?[item.id]; return value }.sorted { $0.severity.rank == $1.severity.rank ? ($0.app, $0.title, $0.id) < ($1.app, $1.title, $1.id) : $0.severity.rank < $1.severity.rank }
    }
}
