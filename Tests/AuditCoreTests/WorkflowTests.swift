import XCTest
@testable import AuditCore

final class WorkflowTests: XCTestCase {
    func testExceptionQueueBoundariesAndPrecedence() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let item = finding()
        func decision(_ seconds: Double?) -> FindingException {
            FindingException(finding: item, reason: "Controlled fixture", reviewer: "Auditor", expires: seconds.map { now.addingTimeInterval($0) }, now: now.addingTimeInterval(-100))
        }
        XCTAssertEqual(ExceptionReviewBucket.classify(decision(0), finding: item, now: now), .overdue)
        XCTAssertEqual(ExceptionReviewBucket.classify(decision(-1), finding: nil, now: now), .overdue)
        XCTAssertEqual(ExceptionReviewBucket.classify(decision(30 * 86400), finding: item, now: now), .soon)
        XCTAssertEqual(ExceptionReviewBucket.classify(decision(30 * 86400 + 1), finding: item, now: now), .active)
        XCTAssertEqual(ExceptionReviewBucket.classify(decision(nil), finding: item, now: now), .active)
        XCTAssertEqual(ExceptionReviewBucket.classify(decision(60), finding: finding("changed"), now: now), .changed)
        XCTAssertEqual(ExceptionReviewBucket.classify(decision(60), finding: nil, now: now), .absent)
        var revoked = decision(-1); revoked.revoked = now
        XCTAssertEqual(ExceptionReviewBucket.classify(revoked, finding: item, now: now), .revoked)
    }
    func testAgeBoundariesAndUnknownFuture() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        for (days, expected) in [(0, UpdateAge.recent), (30, .recent), (31, .middle), (60, .middle), (61, .aging), (90, .aging), (91, .older)] {
            XCTAssertEqual(UpdateAge.band(date: now.addingTimeInterval(-Double(days) * 86400), now: now), expected)
        }
        XCTAssertEqual(UpdateAge.band(date: nil, now: now), .unknown)
        XCTAssertEqual(UpdateAge.band(date: now.addingTimeInterval(1), now: now), .unknown)
    }
    func finding(_ evidence: String = "one") -> AuditFinding { AuditFinding(id: "test", severity: .action, title: "Test", evidence: evidence, nextStep: "Review") }
    func testExceptionRequiresReasonAndBindsEvidenceExpiryAndRevocation() throws {
        let now = Date(); let item = finding()
        XCTAssertThrowsError(try FindingException(finding: item, reason: "  ", reviewer: "", expires: nil).validated())
        XCTAssertThrowsError(try FindingException(finding: item, reason: "Reason", reviewer: "  ", expires: nil).validated())
        var decision = try FindingException(finding: item, reason: "Controlled fixture", reviewer: "Auditor", expires: now.addingTimeInterval(60), now: now).validated()
        XCTAssertTrue(decision.active(for: item, now: now))
        XCTAssertFalse(decision.active(for: finding("two"), now: now))
        XCTAssertFalse(decision.active(for: item, now: now.addingTimeInterval(61)))
        var accepted = item; accepted.exception = decision
        XCTAssertTrue(MonitorAlerts.actionEvents([accepted]).isEmpty)
        decision.revoked = now; XCTAssertFalse(decision.active(for: item, now: now))
        accepted.exception = decision; XCTAssertEqual(MonitorAlerts.actionEvents([accepted]).count, 1)
    }
    func testOfflineCheckDoesNotFetchOrInspectMissingApp() async {
        let app = InstalledApp(name: "Missing", path: "/not-present.app", bundleID: "org.example.app", version: "1", build: "1", created: nil, lastUsed: nil, feed: "https://example.org/feed", appStore: false)
        let result = await UpdateChecker().check(app, allowNetwork: false)
        XCTAssertEqual(result.status, "Offline — not checked")
        let security = SecurityEvidence.inspect(app, allowNetwork: false)
        XCTAssertEqual(security.signature, "Skipped (offline)"); XCTAssertEqual(security.gatekeeper, "Skipped (offline)")
    }
    func testReceiptAgePrecedesModificationEstimateAndStaleUpdatesAreNotActionable() {
        var app = InstalledApp(name: "Test", path: "/Example.app", bundleID: "org.example.app", version: "1", build: "1", created: nil, lastUsed: nil, feed: nil, appStore: false)
        app.modified = Date(timeIntervalSince1970: 100)
        let receipt = ReceiptEvidence(packageID: "org.example.pkg", date: Date(timeIntervalSince1970: 200), version: "1")
        let security = SecurityEvidence(checked: Date(), signature: "Valid", publisher: "Example", teamID: "ABCDEFGHIJ", signedID: app.bundleID, architecture: "arm64", gatekeeper: "Accepted", notarization: "Not confirmed", diagnostics: "", receipts: [receipt])
        XCTAssertEqual(UpdateAge.evidence(app, security: nil).date, app.modified)
        XCTAssertEqual(UpdateAge.evidence(app, security: security).date, receipt.date)
        var update = UpdateResult(status: "Update available", latest: "2"); update.revision = "old"
        var snapshot = AuditSnapshot(apps: [app], roots: ["/"], warnings: [], updates: [app.id: update], evidence: [:]); snapshot.revisions = [app.id: "new"]
        let findings = FindingEngine.evaluate(snapshot, baseline: nil, policy: AuditPolicy())
        XCTAssertTrue(findings.contains { $0.title.contains("predates") })
        XCTAssertFalse(findings.contains { $0.title == "Verified update available" })
    }
    func testOfflineMonitorSkipsConfiguredOnlineAndTrustChecks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let apps = root.appendingPathComponent("Apps"); let contents = apps.appendingPathComponent("Example.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = ["CFBundleName": "Example", "CFBundleIdentifier": "org.example.app", "CFBundleVersion": "1", "CFBundleShortVersionString": "1", "SUFeedURL": "https://example.org/feed"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let configURL = root.appendingPathComponent("monitor.json")
        var config = MonitorConfiguration(roots: [apps.path]); config.offlineMode = true; config.notifications = false
        try JSONEncoder().encode(config).write(to: configURL)
        let run = try await MonitorRunner.run(configurationURL: configURL)
        XCTAssertEqual(run.snapshot.apps.count, 1); XCTAssertEqual(run.snapshot.offlineMode, true)
        XCTAssertTrue(run.snapshot.updates.isEmpty); XCTAssertTrue(run.snapshot.evidence.isEmpty)
        XCTAssertEqual(run.snapshot.integrity?.count, 1)
    }
    func testWorkflowSettingsSnapshotAndRedactedNotes() throws {
        var settings = AuditSettings(); var context = AuditContext(); context.client = "Private Customer"; context.auditor = "Private Person"; context.notes = "Sensitive note"
        settings.context = context; settings.offlineMode = true
        let app = InstalledApp(name: "Test", path: "/Users/alice/Test.app", bundleID: "org.example.app", version: "1", build: "1", created: nil, lastUsed: nil, feed: nil, appStore: false)
        var item = finding("Evidence /Users/alice/Test.app"); let decision = FindingException(finding: item, reason: "Private Customer exception", reviewer: "Private Person", expires: nil)
        item.exception = decision; settings.exceptions = [item.id: decision]
        _ = try settings.validated()
        let decoded = try JSONDecoder().decode(AuditSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.context, context); XCTAssertEqual(decoded.offlineMode, true)
        var snapshot = AuditSnapshot(apps: [app], roots: ["/Users/alice"], warnings: [], updates: [:], evidence: [:])
        snapshot.context = context; snapshot.exceptions = settings.exceptions; snapshot.findings = [item]
        let copy = try AuditSnapshot.decode(snapshot.encoded()); XCTAssertEqual(copy.context, context)
        let redacted = try ShareExport([snapshot]).snapshot(snapshot)
        let text = String(decoding: try redacted.encoded(), as: UTF8.self)
        XCTAssertFalse(text.contains("Private Customer")); XCTAssertFalse(text.contains("Private Person")); XCTAssertFalse(text.contains("Sensitive note"))
        XCTAssertTrue(redacted.findings![0].exception!.active(for: redacted.findings![0]))
    }
    func testRecheckRejectsInventoryChangedSinceScan() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let info = root.appendingPathComponent("Contents/Info.plist"); try Data("version one".utf8).write(to: info)
        var app = InstalledApp(name: "Test", path: root.path, bundleID: "org.example.app", version: "1", build: "1", created: nil, lastUsed: nil, feed: "https://example.org/feed", appStore: false)
        app.revision = try XCTUnwrap(AppRevision.read(app)); try Data("version two changed".utf8).write(to: info)
        let update = await UpdateChecker().check(app)
        XCTAssertEqual(update.status, "Unknown"); XCTAssertNil(update.revision); XCTAssertTrue(update.detail.contains("Rescan"))
        XCTAssertTrue(IntegrityEvidence.collect(app).hashes.isEmpty)
        XCTAssertTrue(SecurityEvidence.inspect(app).diagnostics.contains("Rescan"))
    }
    func testRevisionDetectsFileChangesAndLegacyIsUnknown() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let info = root.appendingPathComponent("Contents/Info.plist"); try Data("before".utf8).write(to: info)
        let app = InstalledApp(name: "Test", path: root.path, bundleID: "org.example.app", version: "1", build: "1", created: nil, lastUsed: nil, feed: nil, appStore: false)
        let before = try XCTUnwrap(AppRevision.read(app)); try Data("after larger".utf8).write(to: info)
        XCTAssertNotEqual(before, AppRevision.read(app))
        XCTAssertTrue(AppRevision.status(observed: before, current: AppRevision.read(app)).hasPrefix("Stale"))
        XCTAssertEqual(AppRevision.status(observed: nil, current: before), "Freshness unknown")
    }
}
