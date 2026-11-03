import XCTest
@testable import AuditCore

final class RoutingTests: XCTestCase {
    func app(_ path: String, id: String = "com.apple.Test", store: Bool = false, feed: String? = nil) -> InstalledApp {
        InstalledApp(name: "Test", path: path, bundleID: id, version: "1", build: "1", created: nil, lastUsed: nil, feed: feed, appStore: store)
    }
    func testClassificationHasBoundaryChecksAndNoNamespaceTrustShortcut() {
        XCTAssertEqual(app("/System/Applications/Notes.app").classification.category, .apple)
        XCTAssertTrue(app("/System/Library/CoreServices/Batteries.app").classification.managedByMacOS)
        XCTAssertEqual(app("/System/Library/CoreServices/Batteries.app").classification.category, .system)
        XCTAssertFalse(app("/System/ApplicationsFake/Evil.app").classification.managedByMacOS)
        XCTAssertFalse(app("/Users/Test/Notes.app").classification.managedByMacOS)
        XCTAssertFalse(app("/Applications/Notes.app").classification.managedByMacOS)
        XCTAssertEqual(app("/Applications/Other.app", id: "org.example.other").classification.category, .thirdParty)
        XCTAssertTrue(app("/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app").classification.managedByMacOS)
    }
    func testManagedAppsNeverUseDeclaredFeedOrCatalogEvenOnline() async {
        let system = app("/System/Library/CoreServices/Batteries.app", feed: "https://example.org/should-not-fetch")
        let result = await UpdateChecker().check(system)
        XCTAssertEqual(result.status, "Managed by macOS")
        XCTAssertTrue(result.detail.contains("not confirmation")); XCTAssertFalse(result.source.contains("brew"))
        let offline = await UpdateChecker().check(system, allowNetwork: false)
        XCTAssertEqual(offline.status, "Managed by macOS")
        let store = await UpdateChecker().check(app("/Applications/Store.app", store: true, feed: "https://example.org/no-fetch"), allowNetwork: false)
        XCTAssertEqual(store.status, "App Store")
    }
    func testLegacyCatalogMatchesIgnoredWithoutSuppressingSecurityOrPolicy() {
        let a = app("/System/Library/CoreServices/Console.app")
        let security = SecurityEvidence(checked: Date(), signature: "Invalid / unsigned / untrusted", publisher: "Unknown", teamID: "", signedID: a.bundleID, architecture: "arm64", gatekeeper: "Rejected / assessment failed", notarization: "Not confirmed", diagnostics: "Fixture", receipts: [])
        let snapshot = AuditSnapshot(apps: [a], roots: ["/System"], warnings: [], updates: [a.id: UpdateResult(status: "Possible update", latest: "99")], evidence: [a.id: security])
        let policy = AuditPolicy(enabled: true, allowOnlyListed: true)
        let findings = FindingEngine.evaluate(snapshot, baseline: nil, policy: policy)
        XCTAssertFalse(findings.contains { $0.title == "Update source identity needs review" })
        XCTAssertTrue(findings.contains { $0.title == "Signing or Gatekeeper needs investigation" && $0.severity == .action })
        XCTAssertTrue(findings.contains { $0.title == "App is outside approved policy" })
        XCTAssertEqual(UpdateRouting.result(a, recorded: snapshot.updates[a.id])?.status, "Managed by macOS")
        var changedApp = a; changedApp.revision = "old"
        var changed = AuditSnapshot(apps: [changedApp], roots: ["/System"], warnings: [], updates: [:], evidence: [:]); changed.revisions = [a.id: "new"]
        XCTAssertTrue(FindingEngine.evaluate(changed, baseline: nil, policy: AuditPolicy()).contains { $0.title.contains("predates") })
    }
    func testRoutineManualCoverageGroupedButRealFailuresRemainSeparate() {
        let a = app("/Applications/One.app", id: "org.example.one"), b = app("/Applications/Two.app", id: "org.example.two"), c = app("/Applications/Three.app", id: "org.example.three")
        let system = app("/System/Applications/Notes.app")
        let snapshot = AuditSnapshot(apps: [a,b,c,system], roots: ["/"], warnings: [], updates: [a.id: UpdateResult(status: "Unsupported"), b.id: UpdateResult(status: "Manual check needed"), c.id: UpdateResult(status: "Check failed", detail: "Network timeout"), system.id: UpdateResult(status: "Unsupported")], evidence: [:])
        let findings = FindingEngine.evaluate(snapshot, baseline: nil, policy: AuditPolicy())
        XCTAssertEqual(findings.filter { $0.title == "Some apps need manual update checks" }.count, 1)
        XCTAssertEqual(findings.filter { $0.title == "Update status is inconclusive" }.count, 1)
        XCTAssertTrue(UpdateRouting.coverage(snapshot).contains("macOS-managed: 1"))
        XCTAssertTrue(UpdateRouting.coverage(snapshot).contains("manual source checks: 2"))
        let legacy = snapshot.updates[a.id]!
        XCTAssertEqual(UpdateRouting.result(a, recorded: legacy)?.status, "Manual check needed")
        XCTAssertEqual(UpdateRouting.result(a, recorded: legacy)?.checked, legacy.checked)
    }
    func testCategoryPreferenceAndRedactedClassificationSurviveRoundTrip() throws {
        var prefs = AuditPreferences(); prefs.category = AppCategory.system.rawValue
        XCTAssertEqual(try JSONDecoder().decode(AuditPreferences.self, from: JSONEncoder().encode(prefs)).category, AppCategory.system.rawValue)
        prefs.category = "bad"; XCTAssertNil(prefs.validated().category)
        var safari = app("/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app")
        safari.recordedClassification = safari.classification
        let snapshot = AuditSnapshot(apps: [safari], roots: ["/System/Volumes/Preboot"], warnings: [], updates: [:], evidence: [:])
        let redacted = try ShareExport([snapshot]).snapshot(snapshot)
        XCTAssertTrue(redacted.apps[0].classification.managedByMacOS)
        XCTAssertTrue(redacted.workflowEvidence(redacted.apps[0]).contains("OS-maintained"))
    }
}
