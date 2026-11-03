import XCTest
import CoreGraphics
@testable import AuditCore

final class MonitoringTests: XCTestCase {
    func app(version: String = "1") -> InstalledApp {
        InstalledApp(name: "Example", path: "/Applications/Example.app", bundleID: "com.example.app", version: version, build: version, created: nil, lastUsed: nil, feed: nil, appStore: false)
    }
    func testStreamingHashAndFileLimit() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        try Data("hello".utf8).write(to: path)
        XCTAssertEqual(try IntegrityEvidence.digest(path), "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        XCTAssertThrowsError(try IntegrityEvidence.digest(path, limit: 2))
    }
    func testSameVersionIntegrityChangeIsCompared() {
        let a = app()
        var before = AuditSnapshot(apps: [a], roots: ["/Applications"], warnings: [], updates: [:], evidence: [:])
        var after = before
        before.integrity = [a.id: IntegrityEvidence(hashes: ["Executable": "aaa"], errors: [:])]
        after.integrity = [a.id: IntegrityEvidence(hashes: ["Executable": "bbb"], errors: [:])]
        let changes = AuditComparison.changes(baseline: before, current: after)
        XCTAssertTrue(changes.contains { $0.kind == "Integrity changed" })
        let findings = FindingEngine.evaluate(after, baseline: before, policy: AuditPolicy())
        XCTAssertTrue(findings.contains { $0.title.contains("without a version change") && $0.severity == .action })
    }
    func testPolicyViolationsAndUnknownVersions() throws {
        let policy = AuditPolicy(enabled: true, allowOnlyListed: true, rules: [AppPolicyRule(bundleID: "com.example.app", minimumVersion: "2", teams: [])])
        let current = AuditSnapshot(apps: [app()], roots: [], warnings: [], updates: [:], evidence: [:])
        XCTAssertTrue(FindingEngine.evaluate(current, baseline: nil, policy: policy).contains { $0.title == "Below minimum version" && $0.severity == .action })
        let unknown = AuditSnapshot(apps: [app(version: "beta")], roots: [], warnings: [], updates: [:], evidence: [:])
        XCTAssertTrue(FindingEngine.evaluate(unknown, baseline: nil, policy: policy).contains { $0.title == "Minimum version cannot be checked" && $0.severity == .unknown })
        XCTAssertThrowsError(try AuditPolicy(enabled: true, rules: [AppPolicyRule(bundleID: "com.example.app"), AppPolicyRule(bundleID: "com.example.app")]).validated())
    }
    func testCustomRegistryRejectsConflictsAndBadTeams() throws {
        XCTAssertThrowsError(try PublisherRegistry.combined(custom: [.init(bundleID: "com.google.Chrome", teamID: "EQHXZ8M8AV", cask: "fake")]))
        XCTAssertThrowsError(try PublisherRegistry.combined(custom: [.init(bundleID: "com.example.app", teamID: "bad", cask: "example")]))
        let rules = try PublisherRegistry.combined(custom: [.init(bundleID: "com.example.app", teamID: "ABCDEFGHIJ", cask: "example")])
        XCTAssertGreaterThan(rules.count, 3)
    }
    func testAlertDedupAndIncompleteScope() {
        let base = AuditSnapshot(apps: [], roots: ["/Applications"], warnings: [], updates: [:], evidence: [:])
        let current = AuditSnapshot(apps: [app()], roots: ["/Applications"], warnings: [], updates: [:], evidence: [:])
        let events = MonitorAlerts.events(current: current, baseline: base, findings: [])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(MonitorAlerts.newEvents(events, previous: Set(events.map(\.fingerprint))).count, 0)
        let partial = AuditSnapshot(apps: [], roots: ["/Applications"], warnings: ["Missing root"], updates: [:], evidence: [:])
        XCTAssertTrue(MonitorAlerts.events(current: partial, baseline: current, findings: []).isEmpty)
        XCTAssertTrue(MonitorAlerts.events(current: current, baseline: nil, findings: []).isEmpty)
    }
    func testLaunchAgentUsesSeparateArgumentsAndDailyTime() throws {
        let config = MonitorConfiguration(roots: ["/Applications"], hour: 9, minute: 30)
        let data = try config.launchAgent(executable: "/Apps/App Audit.app/Contents/MacOS/AppAudit", configurationPath: "/Users/Test/monitor.json", logDirectory: "/Users/Test/Logs")
        let value = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(value["ProgramArguments"] as? [String], ["/Apps/App Audit.app/Contents/MacOS/AppAudit", "--scheduled-audit", "/Users/Test/monitor.json"])
        XCTAssertEqual((value["StartCalendarInterval"] as? [String: Int])?["Minute"], 30)
        XCTAssertEqual(value["RunAtLoad"] as? Bool, false)
    }
    func testScheduleInstallFailureReportsWhetherPreviousScheduleWasRestored() {
        let ordinary = MonitorRecovery.enableFailureMessage(primary: "new schedule rejected", restorationFailures: [])
        XCTAssertEqual(ordinary, "Cannot enable scheduled audit: new schedule rejected")

        let recovered = MonitorRecovery.enableFailureMessage(primary: "new schedule rejected", restorationFailures: ["previous plist restore failed"])
        XCTAssertTrue(recovered.contains("new schedule rejected"))
        XCTAssertTrue(recovered.contains("previous plist restore failed"))
    }
    func testReportEscapesUntrustedText() {
        let a = InstalledApp(name: "<script>alert(1)</script>", path: "/Applications/Bad.app", bundleID: "bad", version: "1", build: "1", created: nil, lastUsed: nil, feed: nil, appStore: false)
        let snapshot = AuditSnapshot(apps: [a], roots: ["/Applications"], warnings: [], updates: [:], evidence: [:])
        let html = HTMLReport.render(snapshot, baseline: nil, policy: AuditPolicy())
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertTrue(html.contains("Content-Security-Policy"))
        XCTAssertTrue(html.contains("Suggested next step"))
    }
    func testVersionOneSnapshotStillLoads() throws {
        let snap = AuditSnapshot(apps: [app()], roots: [], warnings: [], updates: [:], evidence: [:])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: snap.encoded()) as? [String: Any])
        json["schemaVersion"] = 1; json.removeValue(forKey: "integrity")
        XCTAssertEqual(try AuditSnapshot.decode(JSONSerialization.data(withJSONObject: json)).apps.count, 1)
    }
    func testMonitorQuietBaselineDedupAndFailurePreservesHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let apps = root.appendingPathComponent("Apps")
        let contents = apps.appendingPathComponent("Example.app/Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("_CodeSignature"), withIntermediateDirectories: true)
        let executable = contents.appendingPathComponent("MacOS/Example")
        try Data("first".utf8).write(to: executable)
        try Data("resources".utf8).write(to: contents.appendingPathComponent("_CodeSignature/CodeResources"))
        let info = ["CFBundleIdentifier":"com.example.app", "CFBundleName":"Example", "CFBundleVersion":"1", "CFBundleShortVersionString":"1", "CFBundleExecutable":"Example"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let monitor = root.appendingPathComponent("Monitor")
        try FileManager.default.createDirectory(at: monitor, withIntermediateDirectories: true)
        let url = monitor.appendingPathComponent("monitor.json")
        var config = MonitorConfiguration(roots: [apps.path]); config.inspectSecurity = false; config.checkUpdates = false; config.notifications = false
        config.policy = AuditPolicy(enabled: true, rules: [AppPolicyRule(bundleID: "com.example.app", minimumVersion: "2")])
        try JSONEncoder().encode(config).write(to: url)
        let first = try await MonitorRunner.run(configurationURL: url)
        XCTAssertTrue(first.events.isEmpty)
        let second = try await MonitorRunner.run(configurationURL: url)
        XCTAssertTrue(second.events.isEmpty, "Existing first-run policy findings should not alert on an unchanged second audit")
        try Data("changed".utf8).write(to: executable)
        let changed = try await MonitorRunner.run(configurationURL: url)
        XCTAssertTrue(changed.events.contains { $0.title.contains("Integrity changed") })
        let unchanged = try await MonitorRunner.run(configurationURL: url)
        XCTAssertTrue(unchanged.events.isEmpty)
        let pointer = unchanged.status.latestFile
        try Data("bad config".utf8).write(to: url)
        do { _ = try await MonitorRunner.run(configurationURL: url); XCTFail("Invalid config must fail") } catch {}
        XCTAssertEqual(MonitorRunner.status(directory: monitor, includeFailure: false)?.latestFile, pointer)
        XCTAssertNotNil(MonitorRunner.status(directory: monitor)?.error)
    }

    func testAlertIdentityDistinguishesSameNamedApps() {
        let a = AuditFinding(id: "rule/one", severity: .action, app: "Example", path: "/one.app", title: "Below minimum version", evidence: "1 < 2", nextStep: "Update")
        let b = AuditFinding(id: "rule/two", severity: .action, app: "Example", path: "/two.app", title: "Below minimum version", evidence: "1 < 2", nextStep: "Update")
        let first = MonitorAlerts.actionEvents([a])[0]
        let second = MonitorAlerts.actionEvents([b])[0]
        XCTAssertNotEqual(first.fingerprint, second.fingerprint)
        XCTAssertEqual(MonitorAlerts.newEvents([second], previous: [first.fingerprint]).count, 1)
    }
    func testPartialAuditRetainsCompleteHashesAndKnownViolations() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let apps = root.appendingPathComponent("Apps")
        let hidden = root.appendingPathComponent("Disconnected")
        let contents = apps.appendingPathComponent("Example.app/Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("_CodeSignature"), withIntermediateDirectories: true)
        try Data("first".utf8).write(to: contents.appendingPathComponent("MacOS/Example"))
        try Data("resources".utf8).write(to: contents.appendingPathComponent("_CodeSignature/CodeResources"))
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier":"com.example.app", "CFBundleName":"Example", "CFBundleVersion":"1", "CFBundleShortVersionString":"1", "CFBundleExecutable":"Example"], format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let monitor = root.appendingPathComponent("Monitor")
        try FileManager.default.createDirectory(at: monitor, withIntermediateDirectories: true)
        let configURL = monitor.appendingPathComponent("monitor.json")
        var config = MonitorConfiguration(roots: [apps.path]); config.inspectSecurity = false; config.checkUpdates = false; config.notifications = false
        config.policy = AuditPolicy(enabled: true, rules: [AppPolicyRule(bundleID: "com.example.app", minimumVersion: "2")])
        try JSONEncoder().encode(config).write(to: configURL)
        let complete = try await MonitorRunner.run(configurationURL: configURL)
        try FileManager.default.moveItem(at: apps, to: hidden)
        let partial = try await MonitorRunner.run(configurationURL: configURL)
        XCTAssertEqual(partial.status.completeFile, complete.status.completeFile)
        try FileManager.default.moveItem(at: hidden, to: apps)
        let restored = try await MonitorRunner.run(configurationURL: configURL)
        XCTAssertTrue(restored.events.isEmpty, "Restoring unchanged scope must not re-alert known violations or apps")
        try FileManager.default.moveItem(at: apps, to: hidden)
        _ = try await MonitorRunner.run(configurationURL: configURL)
        try Data("modified".utf8).write(to: hidden.appendingPathComponent("Example.app/Contents/MacOS/Example"))
        try FileManager.default.moveItem(at: hidden, to: apps)
        let changed = try await MonitorRunner.run(configurationURL: configURL)
        XCTAssertTrue(changed.events.contains { $0.title.contains("Integrity changed") }, "Compare against last complete hash evidence across missing scope")
    }

    func testNativePDFHasFiniteReadablePages() throws {
        let snapshot = AuditSnapshot(apps: [app()], roots: ["/Applications"], warnings: [], updates: [:], evidence: [:])
        let data = try PDFReport.data(snapshot, baseline: nil, policy: AuditPolicy())
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        XCTAssertGreaterThan(document.numberOfPages, 0)
        XCTAssertLessThan(document.numberOfPages, 10)
        XCTAssertEqual(document.page(at: 1)?.getBoxRect(.mediaBox).width, 595)
    }

    func testPDFSplitsOversizedBlocksAcrossPageBoundaries() throws {
        let apps = (0..<32).map { index in
            InstalledApp(name: "Example \(index)", path: "/Applications/" + String(repeating: "long imported path segment /", count: 120 + index) + "Example.app", bundleID: "com.example.\(index)", version: "1", build: "1", created: nil, lastUsed: nil, feed: nil, appStore: false)
        }
        let snapshot = AuditSnapshot(apps: apps, roots: ["/Applications"], warnings: [], updates: [:], evidence: [:])
        let data = try PDFReport.data(snapshot, baseline: nil, policy: AuditPolicy())
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        XCTAssertGreaterThan(document.numberOfPages, 32)
        XCTAssertLessThan(document.numberOfPages, 150)
    }

}
