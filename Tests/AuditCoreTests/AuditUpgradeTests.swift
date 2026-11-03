import XCTest
@testable import AuditCore

final class AuditUpgradeTests: XCTestCase {
    func app(_ path: String, id: String = "test.app", version: String = "1", build: String = "1") -> InstalledApp {
        InstalledApp(name: "Test", path: path, bundleID: id, version: version, build: build, created: nil, lastUsed: nil, feed: nil, appStore: false)
    }
    func testSnapshotRoundTripAndUnsupportedSchema() throws {
        let snapshot = AuditSnapshot(apps: [app("/Applications/Test.app")], roots: ["/Applications"], warnings: ["Unreadable app"], updates: [:], evidence: [:])
        let data = try snapshot.encoded()
        let decoded = try AuditSnapshot.decode(data)
        XCTAssertEqual(decoded.apps[0].path, "/Applications/Test.app")
        XCTAssertEqual(decoded.warnings, ["Unreadable app"])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["schemaVersion"] = 999
        XCTAssertThrowsError(try AuditSnapshot.decode(JSONSerialization.data(withJSONObject: json)))
    }
    func testComparisonReportsUpdatesMovesAdditionsAndRemovals() {
        let before = [app("/Applications/A.app", id: "a"), app("/Applications/B.app", id: "b"), app("/Applications/Gone.app", id: "gone")]
        let after = [app("/Applications/A.app", id: "a", version: "2"), app("/Users/test/Applications/B.app", id: "b"), app("/Applications/New.app", id: "new")]
        let changes = AuditComparison.changes(before: before, after: after)
        XCTAssertEqual(Set(changes.map(\.kind)), Set(["Updated", "Relocated", "Added", "Removed"]))
        XCTAssertEqual(changes.first { $0.kind == "Updated" }?.before?.version, "1")
        XCTAssertEqual(changes.first { $0.kind == "Relocated" }?.after?.path, "/Users/test/Applications/B.app")
    }
    func testDuplicateBundleIDsAreNotGuessedAsMoves() {
        let before = [app("/a.app"), app("/b.app")]
        let after = [app("/c.app")]
        let changes = AuditComparison.changes(before: before, after: after)
        XCTAssertEqual(changes.filter { $0.kind == "Removed" }.count, 2)
        XCTAssertEqual(changes.filter { $0.kind == "Added" }.count, 1)
        XCTAssertFalse(changes.contains { $0.kind == "Relocated" })
    }
    func testChangedIdentityAtSamePathIsReplacement() {
        let changes = AuditComparison.changes(before: [app("/Test.app", id: "old")], after: [app("/Test.app", id: "new")])
        XCTAssertEqual(changes.first?.kind, "Replaced")
    }
    func testPreferencesRoundTripAndCorruptionFallback() throws {
        let suite = "AppAuditTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PreferenceStore(defaults: defaults)
        var settings = AuditPreferences()
        settings.folders = ["/Applications", "/custom"]
        settings.filter = "Updates"; settings.search = "Chrome"; settings.sort = "version"; settings.ascending = false; settings.showSecurity = true
        try store.save(settings)
        XCTAssertEqual(store.load().folders, settings.folders)
        XCTAssertEqual(store.load().sort, "version")
        XCTAssertFalse(store.load().ascending)
        defaults.set(Data("invalid".utf8), forKey: PreferenceStore.key)
        XCTAssertEqual(store.load().filter, "All apps")
    }
    func testPublisherIdentityRequiresBundleTeamAndValidSignature() {
        let rule = PublisherRule(bundleID: "com.example.app", teamID: "TEAM123", cask: "example")
        XCTAssertTrue(rule.matches(bundleID: "com.example.app", signedID: "com.example.app", teamID: "TEAM123", valid: true))
        XCTAssertFalse(rule.matches(bundleID: "com.example.app", signedID: "fake", teamID: "TEAM123", valid: true))
        XCTAssertFalse(rule.matches(bundleID: "com.example.app", signedID: "com.example.app", teamID: "BAD", valid: true))
        XCTAssertFalse(rule.matches(bundleID: "com.example.app", signedID: "com.example.app", teamID: "TEAM123", valid: false))
    }
    func testReceiptParsingUsesReceiptTimeAndIdentifier() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["pkgid": "com.example.pkg", "install-time": 1_700_000_000, "pkg-version": "2.0"], format: .xml, options: 0)
        let receipt = try XCTUnwrap(ReceiptEvidence.parse(data))
        XCTAssertEqual(receipt.packageID, "com.example.pkg")
        XCTAssertEqual(receipt.date.timeIntervalSince1970, 1_700_000_000)
        XCTAssertNil(ReceiptEvidence.parse(Data("bad".utf8)))
    }
    func testArchitectureReadsThinAndUniversalMachO() {
        let thin = Data([0xcf,0xfa,0xed,0xfe, 0x0c,0,0,1] + Array(repeating: UInt8(0), count: 24))
        XCTAssertEqual(MachArchitecture.read(thin), "arm64")
        let fat = Data([0xca,0xfe,0xba,0xbe, 0,0,0,2, 1,0,0,7] + Array(repeating: UInt8(0), count: 16) + [1,0,0,12] + Array(repeating: UInt8(0), count: 16))
        XCTAssertEqual(MachArchitecture.read(fat), "arm64, x86_64")
        XCTAssertEqual(MachArchitecture.read(Data([1,2,3])), "Unknown")
    }
    func testSnapshotRejectsDuplicatePathsAndScopeChangesAreFlagged() throws {
        let a = app("/Test.app")
        let invalid = AuditSnapshot(apps: [a, a], roots: ["/"], warnings: [], updates: [:], evidence: [:])
        XCTAssertThrowsError(try AuditSnapshot.decode(invalid.encoded()))
        let baseline = AuditSnapshot(apps: [a], roots: ["/Applications"], warnings: ["Unreadable"], updates: [:], evidence: [:])
        XCTAssertEqual(AuditComparison.scopeNotes(baseline: baseline, roots: ["/custom"], warnings: []).count, 2)
    }
    func testProcessRunnerDrainsOutputAndTimesOut() {
        let output = ProcessRunner.run("/usr/bin/printf", ["hello"], timeout: 2)
        XCTAssertEqual(output.output, "hello")
        XCTAssertEqual(output.status, 0)
        let slow = ProcessRunner.run("/bin/sleep", ["5"], timeout: 0.05)
        XCTAssertTrue(slow.timedOut)
    }
    func testSnapshotRetainsSecurityAndReceiptEvidence() throws {
        let receipt = ReceiptEvidence(packageID: "test.pkg", date: Date(timeIntervalSince1970: 1700000000), version: "2")
        let evidence = SecurityEvidence(checked: Date(timeIntervalSince1970: 1700000000), signature: "Valid", publisher: "Example", teamID: "TEAM", signedID: "test.app", architecture: "arm64", gatekeeper: "Accepted", notarization: "Confirmed by Gatekeeper", diagnostics: "example", receipts: [receipt])
        let a = app("/Test.app")
        let snapshot = AuditSnapshot(apps: [a], roots: ["/"], warnings: [], updates: [:], evidence: [a.id: evidence])
        let decoded = try AuditSnapshot.decode(snapshot.encoded())
        XCTAssertEqual(decoded.evidence[a.id]?.receipts.first?.packageID, "test.pkg")
        let csv = CSV.export([a], updates: [:], evidence: decoded.evidence)
        XCTAssertTrue(csv.contains("Example")); XCTAssertTrue(csv.contains("test.pkg")); XCTAssertTrue(csv.contains("Confirmed by Gatekeeper"))
        XCTAssertEqual(decoded.evidence[a.id]?.installDate, receipt.date)
    }

    func testMissingScanFolderProducesWarning() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let result = Scanner.scan(roots: [path])
        XCTAssertTrue(result.apps.isEmpty)
        XCTAssertTrue(result.warnings.contains { $0.contains(path.path) })
    }

    func testReceiptPayloadFallbackRequiresExactPath() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["PackageIdentifier": "com.example.pkg", "PackageVersion": "2", "InstallDate": Date(timeIntervalSince1970: 1700000000), "InstallPrefixPath": "Applications"], format: .xml, options: 0)
        let files = "Example.app\nExample.app/Contents/Info.plist\n"
        XCTAssertEqual(ReceiptEvidence.matchedRecord(data, appPath: "/Applications/Example.app", files: files)?.packageID, "com.example.pkg")
        XCTAssertNil(ReceiptEvidence.matchedRecord(data, appPath: "/Applications/Other.app", files: files))
        XCTAssertNil(ReceiptEvidence.matchedRecord(data, appPath: "/Users/test/Example.app", files: files))
    }

    func testReceiptMergeKeepsLatestEventAcrossLookupSources() {
        let old = ReceiptEvidence(packageID: "same.pkg", date: Date(timeIntervalSince1970: 100), version: "1")
        let new = ReceiptEvidence(packageID: "same.pkg", date: Date(timeIntervalSince1970: 200), version: "2")
        let other = ReceiptEvidence(packageID: "other.pkg", date: Date(timeIntervalSince1970: 150), version: "1")
        let merged = ReceiptEvidence.merge([old], [new, other])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first?.version, "2")
        XCTAssertEqual(merged.first?.date.timeIntervalSince1970, 200)
    }

}
