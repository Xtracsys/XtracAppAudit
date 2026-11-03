import XCTest
@testable import AuditCore

final class CommunityTests: XCTestCase {
    func app(_ path: String, id: String = "com.example.app", version: String = "1") -> InstalledApp {
        InstalledApp(name: "Example", path: path, bundleID: id, version: version, build: version, created: nil, lastUsed: nil, feed: "https://example.com/feed?private=secret", appStore: false)
    }
    func testManualLinksValidateAndOldSettingsLoad() throws {
        XCTAssertNotNil(DeveloperLinks.url("https://example.com/support"))
        for address in ["javascript:alert(1)", "file:///tmp/app", "http://example.com", "https://user:pass@example.com", "https://example.com:8443", "https://exa mple.com", "https://localhost"] { XCTAssertNil(DeveloperLinks.url(address), address) }
        let old = try AuditSettings().validated()
        let data = try JSONEncoder().encode(old)
        XCTAssertNil(try JSONDecoder().decode(AuditSettings.self, from: data).developerLinks)
        var settings = old
        settings.developerLinks = ["bundle:com.example.app": DeveloperLinks(website: "https://example.com", support: "https://example.com/help", releaseNotes: "https://example.com/releases")]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try AuditStorage.saveSettings(settings, at: directory)
        XCTAssertEqual(try AuditStorage.loadSettings(at: directory).developerLinks, settings.developerLinks)
        XCTAssertEqual(DeveloperLinks.key(app("/one.app")), DeveloperLinks.key(app("/two.app")))
        XCTAssertNotEqual(DeveloperLinks.key(app("/one.app", id: "Unknown")), DeveloperLinks.key(app("/two.app", id: "Unknown")))
    }
    func testDuplicatesGroupKnownIdentityWithoutNameGuessing() {
        let apps = [app("/one.app"), app("/two.app", version: "2"), app("/three.app", id: "Unknown"), app("/four.app", id: "Unknown"), app("/five.app", id: "com.other.app")]
        let groups = DuplicateDetector.groups(apps)
        XCTAssertEqual(groups.count, 1); XCTAssertEqual(groups[0].apps.count, 2)
        let snapshot = AuditSnapshot(apps: apps, roots: ["/"], warnings: [], updates: [:], evidence: [:])
        XCTAssertEqual(FindingEngine.evaluate(snapshot, baseline: nil, policy: AuditPolicy()).filter { $0.title.hasPrefix("Multiple installations") }.count, 1)
    }
    func testRedactionPreservesEvidenceKeysAndComparisonIdentity() throws {
        let old = app("/Users/alice/Private Apps/Example.app")
        var before = AuditSnapshot(apps: [old], roots: ["/Users/alice/Private Apps"], warnings: ["Failure /Users/alice/Other Secret/report.txt"], updates: [:], evidence: [:])
        before.integrity = [old.id: IntegrityEvidence(hashes: ["Executable": "abc"], errors: ["test": "/Users/alice/Secret/file"])]
        before.developerLinks = [DeveloperLinks.key(old): DeveloperLinks(website: "HTTPS://example.com/?token=secret#private")]
        var after = AuditSnapshot(apps: [app(old.path, version: "2"), app("/Users/alice/Private Apps/Extra.app", id: "com.extra.app")], roots: before.roots, warnings: [], updates: [:], evidence: [:])
        after.integrity = before.integrity
        let redactor = ShareExport([before, after]); let first = try redactor.snapshot(before); let second = try redactor.snapshot(after)
        let text = String(decoding: try first.encoded(), as: UTF8.self)
        XCTAssertFalse(text.contains("alice")); XCTAssertFalse(text.contains("Private Apps")); XCTAssertFalse(text.contains("token=")); XCTAssertFalse(text.contains("report.txt"))
        XCTAssertEqual(first.integrity?[first.apps[0].id]?.hashes["Executable"], "abc")
        XCTAssertEqual(first.redacted, true)
        XCTAssertEqual(AuditComparison.changes(baseline: first, current: second).filter { $0.kind == "Updated" }.count, 1)
        XCTAssertEqual(before.apps[0].path, old.path)
        XCTAssertTrue(HTMLReport.render(first, baseline: nil, policy: AuditPolicy()).contains("REDACTED EXPORT"))
    }
    func testRootScanAndMixedCaseURLsCannotBypassRedaction() throws {
        let snapshot = AuditSnapshot(apps: [app("/Users/alice/Example.app")], roots: ["/"], warnings: ["Failure /Users/alice/Secret/report.txt", "HTTPS://example.com/?token=private#secret", "https://example.com/?token=lowercase"], updates: [:], evidence: [:])
        let output = String(decoding: try ShareExport([snapshot]).snapshot(snapshot).encoded(), as: UTF8.self)
        for secret in ["alice", "report.txt", "token=", "lowercase", "private#"] { XCTAssertFalse(output.contains(secret), secret) }
    }
    func testCaskHomepageIsOptionalMetadata() throws {
        let old = try JSONDecoder().decode(Cask.self, from: Data(#"{"token":"example","version":"1"}"#.utf8))
        XCTAssertNil(old.homepage)
        let new = try JSONDecoder().decode(Cask.self, from: Data(#"{"token":"example","version":"1","homepage":"https://example.com"}"#.utf8))
        XCTAssertEqual(new.homepage, "https://example.com")
    }
}
