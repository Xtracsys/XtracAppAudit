import XCTest
@testable import AuditCore

final class TableRowTests: XCTestCase {
    func testEvidenceColumnsSortInBothDirections() {
        let app = InstalledApp(name: "Test", path: "/Test.app", bundleID: "test", version: "1", build: "1", created: nil, lastUsed: nil, feed: nil, appStore: false)
        let a = AuditTableRow(app: app, update: "Available", security: nil)
        let b = AuditTableRow(app: app, update: "Unknown", security: SecurityEvidence(checked: Date(), signature: "Valid", publisher: "Vendor", teamID: "T", signedID: "test", architecture: "arm64", gatekeeper: "Accepted", notarization: "Confirmed", diagnostics: "", receipts: []))
        for key in [\AuditTableRow.update, \.signature, \.publisher, \.gatekeeper, \.notarization] {
            let forward = [b, a].sorted(using: KeyPathComparator(key)).map { $0[keyPath: key] }
            let reverse = [b, a].sorted(using: KeyPathComparator(key, order: .reverse)).map { $0[keyPath: key] }
            XCTAssertNotEqual(forward[0], forward[1])
            XCTAssertEqual(forward, reverse.reversed())
        }
        XCTAssertEqual(a.architecture, "Unknown")
        XCTAssertEqual(b.installSort, app.installSort)
    }
    func testAgeUsesDatesAndArchitectureUsesDisplayedValue() {
        var old = InstalledApp(name: "Old", path: "/Old.app", bundleID: "old", version: "1", build: "1", created: Date(timeIntervalSince1970: 100), lastUsed: nil, feed: nil, appStore: false, architecture: "x86_64")
        var new = InstalledApp(name: "New", path: "/New.app", bundleID: "new", version: "1", build: "1", created: Date(timeIntervalSince1970: 200), lastUsed: nil, feed: nil, appStore: false, architecture: "arm64")
        old.modified = old.created; new.modified = new.created
        let rows = [AuditTableRow(app: new, update: "Not checked", security: nil), AuditTableRow(app: old, update: "Not checked", security: nil)]
        XCTAssertEqual(rows.sorted(using: KeyPathComparator(\.ageSort)).map(\.name), ["Old", "New"])
        XCTAssertEqual(rows.sorted(using: KeyPathComparator(\.ageSort, order: .reverse)).map(\.name), ["New", "Old"])
        XCTAssertEqual(rows.sorted(using: KeyPathComparator(\.architecture)).map(\.name), ["New", "Old"])
        XCTAssertEqual(rows.sorted(using: KeyPathComparator(\.architecture, order: .reverse)).map(\.name), ["Old", "New"])
    }

}
