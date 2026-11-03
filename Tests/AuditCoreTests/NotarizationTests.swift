import XCTest
@testable import AuditCore

final class NotarizationTests: XCTestCase {
    func testAcceptedSourcesAreDistinct() {
        XCTAssertEqual(SecurityEvidence.notarizationStatus(status: 0, timedOut: false, output: "accepted\nsource=Notarized Developer ID\norigin=Example"), "Confirmed notarized")
        XCTAssertEqual(SecurityEvidence.notarizationStatus(status: 0, timedOut: false, output: "source=Apple System"), "Apple system distribution")
        XCTAssertEqual(SecurityEvidence.notarizationStatus(status: 0, timedOut: false, output: "source=Mac App Store"), "App Store distribution")
    }
    func testFailureAndUnrecognizedSourcesNeverConfirmTrust() {
        for source in ["source=Notarized Developer ID", "source=Apple System", "source=Mac App Store"] {
            XCTAssertTrue(SecurityEvidence.notarizationStatus(status: 1, timedOut: false, output: source).hasPrefix("Not established"))
            XCTAssertTrue(SecurityEvidence.notarizationStatus(status: 0, timedOut: true, output: source).contains("timed out"))
        }
        for output in ["", "source=Developer ID", "diagnostic: source=Notarized Developer ID", "source=Notarized Developer ID extra"] {
            XCTAssertTrue(SecurityEvidence.notarizationStatus(status: 0, timedOut: false, output: output).hasPrefix("Not established"))
        }
    }
    func testColumnDefaultsHiddenAndLegacyPreferencesLoad() throws {
        XCTAssertNil(AuditPreferences().showNotarization)
        let data = try JSONEncoder().encode(AuditPreferences())
        XCTAssertNil(try JSONDecoder().decode(AuditPreferences.self, from: data).showNotarization)
    }
}
