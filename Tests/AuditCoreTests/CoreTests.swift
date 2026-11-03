import XCTest
import Darwin
@testable import AuditCore

final class CoreTests: XCTestCase {
    func testVersionsAreNumericAndConservative() {
        XCTAssertEqual(Version.compare("1.9", "1.10"), .orderedAscending)
        XCTAssertEqual(Version.compare("2.0.0", "2.0"), .orderedSame)
        XCTAssertNil(Version.compare("latest", "3.0"))
        XCTAssertNil(Version.compare("1.0-beta", "1.0"))
    }
    func testScannerReadsBundleAndReportsMalformedNestedHelpers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("Example.app/Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Helpers/Inner.app"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleName": "Example", "CFBundleIdentifier": "test.example", "CFBundleShortVersionString": "1.2", "CFBundleVersion": "12"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let result = Scanner.scan(roots: [root, root])
        XCTAssertEqual(result.apps.count, 1)
        XCTAssertTrue(result.warnings.contains { $0.contains("Inner.app") })
        XCTAssertEqual(result.apps.first?.version, "1.2")
        XCTAssertEqual(result.apps.first?.bundleID, "test.example")
    }
    func testDeepDiscoveryIncludesHiddenNestedAndLinkedAppsWithoutCycles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        for path in [".hidden/Hidden.app", "Outer.app", "Outer.app/Contents/Helpers/Nested.app", "Plugin.bundle/Embedded.app"] {
            let contents = root.appendingPathComponent(path + "/Contents")
            try fm.createDirectory(at: contents, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleName": path, "CFBundleIdentifier": "test." + path, "CFBundleVersion": "1"], format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        }
        try fm.createSymbolicLink(at: root.appendingPathComponent("alias"), withDestinationURL: root.appendingPathComponent(".hidden"))
        try fm.createSymbolicLink(at: root.appendingPathComponent(".hidden/cycle"), withDestinationURL: root)
        let result = Scanner.scan(roots: [root, root.appendingPathComponent("Outer.app")])
        XCTAssertEqual(result.apps.count, 4)
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertEqual(Set(result.apps.map(\.path)).count, 4)
    }
    func testDiscoveryRejectsSpecialFilesAndOversizedMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let pipe = root.appendingPathComponent("metadata")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        XCTAssertNil(InventoryFile.read(pipe.path, limit: 100))
        XCTAssertEqual(MachArchitecture.at(pipe.path), "Unknown")
        let file = root.appendingPathComponent("large")
        try Data(repeating: 1, count: 101).write(to: file)
        XCTAssertNil(InventoryFile.read(file.path, limit: 100))
        XCTAssertEqual(InventoryFile.read(file.path, limit: 10, prefixOnly: true)?.count, 10)
    }
    func testLateCancellationStillMarksPartialAndAppSymlinkIsDiscovered() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("AAA/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleName": "Linked app", "CFBundleIdentifier": "test.link"], format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("ZAlias.app"), withDestinationURL: root.appendingPathComponent("AAA"))
        XCTAssertEqual(Scanner.scan(roots: [root]).apps.first?.bundleID, "test.link")
        let flag = ScanCancellationFlag()
        let result = Scanner.scan(roots: [root], cancelled: { flag.cancelled }, progress: { _, _ in flag.cancel() })
        XCTAssertTrue(result.warnings.contains { $0.contains("partial") })
    }
    func testCancelledDiscoveryExplicitlyMarksPartialCoverage() {
        let result = Scanner.scan(roots: [URL(fileURLWithPath: "/")], cancelled: { true })
        XCTAssertTrue(result.apps.isEmpty)
        XCTAssertTrue(result.warnings.contains { $0.contains("partial") })
    }
    func testDefaultScopeIsFilesystemAndLegacyPreferencesMigrate() throws {
        XCTAssertEqual(Scanner.defaultRoots.map(\.path), ["/"])
        var old = AuditPreferences()
        old.folders = ["/Applications", NSHomeDirectory() + "/Applications", "/System/Applications", "/System/Library/CoreServices"]
        old.discoveryVersion = nil
        XCTAssertEqual(old.validated().folders, ["/"])
        old.folders = ["/custom"]
        XCTAssertEqual(old.validated().folders, ["/custom"])
    }
    func testCSVQuotesAndNeutralizesFormulas() {
        XCTAssertEqual(CSV.field("a,\"b\n"), "\"a,\"\"b\n\"")
        XCTAssertEqual(CSV.field("=SUM(1)"), "\"'=SUM(1)\"")
        XCTAssertEqual(CSV.field("  +cmd"), "\"'  +cmd\"")
    }
    func testAppcastUsesBuildAndRejectsIncompatibleRelease() throws {
        let xml = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><sparkle:minimumSystemVersion>99.0</sparkle:minimumSystemVersion><enclosure sparkle:version="999" sparkle:shortVersionString="9.0" /></item>
        <item><enclosure sparkle:version="120" sparkle:shortVersionString="1.2" /></item>
        </channel></rss>
        """
        let release = try Appcast.latest(Data(xml.utf8), os: "14.0")
        XCTAssertEqual(release?.build, "120")
        XCTAssertEqual(release?.version, "1.2")
        XCTAssertThrowsError(try Appcast.latest(Data("<rss>".utf8), os: "14.0"))
    }
    func testCaskMatchingRequiresUnambiguousArtifact() throws {
        let json = Data("""
        [{"token":"foo","version":"2.0","artifacts":[["Foo.app",{"target":"Foo.app"}]]},
         {"token":"foo-beta","version":"3.0","artifacts":[["Foo.app",{"target":"Foo.app"}]]}]
        """.utf8)
        let casks = try JSONDecoder().decode([Cask].self, from: json)
        XCTAssertNil(Cask.match(filename: "Foo.app", casks: casks))
        XCTAssertNotNil(Cask.match(filename: "Foo.app", casks: [casks[0]]))
        XCTAssertNil(Cask.match(filename: "Fooo.app", casks: casks))
    }
    func testRealHomebrewObjectArtifacts() throws {
        let data = Data(#"[{"token":"firefox","version":"2.0","artifacts":[{"app":["Firefox.app"],"target":"/Applications/Firefox.app"}]}]"#.utf8)
        let casks = try JSONDecoder().decode([Cask].self, from: data)
        XCTAssertEqual(Cask.match(filename: "Firefox.app", casks: casks)?.token, "firefox")
    }
    func testUnsafeUpdateURLsRejected() {
        for url in ["http://example.com/feed", "https://127.0.0.1/feed", "https://192.168.1.1/feed", "https://host.local/feed", "https://user:pass@example.com/feed", "file:///tmp/feed"] {
            XCTAssertNil(UpdateChecker.allowedURL(url), url)
        }
        XCTAssertNotNil(UpdateChecker.allowedURL("https://updates.example.com/feed.xml"))
    }

    func testItemLevelSparkleVersionsSurvivePlainEnclosure() throws {
        let xml = Data(#"<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>42</sparkle:version><sparkle:shortVersionString>2.1</sparkle:shortVersionString><enclosure url="https://example.com/app.zip"/></item></channel></rss>"#.utf8)
        XCTAssertEqual(try Appcast.latest(xml, os: "14.0")?.build, "42")
        XCTAssertEqual(try Appcast.latest(xml, os: "14.0")?.version, "2.1")
    }
    func testMissingMarketingVersionRemainsUnknown() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("OnlyBuild.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleVersion": "999"], format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        XCTAssertEqual(Scanner.scan(roots: [root]).apps.first?.version, "Unknown")
    }

    func testCaskRejectsIncompatibleOSAndResolvesVariant() throws {
        let data = Data(#"[{"token":"foo","version":"9.0","artifacts":[],"depends_on":{"macos":{">=":["15.0"]}},"variations":{"arm64_sonoma":{"version":"7.0","depends_on":{"macos":{">=":["14.0"]}}}}}]"#.utf8)
        let cask = try JSONDecoder().decode([Cask].self, from: data)[0]
        XCTAssertNil(cask.compatibleVersion(os: "13.0", architecture: "arm64"))
        XCTAssertEqual(cask.compatibleVersion(os: "14.0", architecture: "arm64"), "7.0")
        XCTAssertEqual(cask.compatibleVersion(os: "15.0", architecture: "arm64"), "9.0")
    }

    func testRenamedCaskMatchesInstalledTargetOnly() throws {
        for artifacts in [#"[{"app":["Original.app",{"target":"Renamed.app"}]}]"#, #"[{"app":["Original.app"],"target":"/Applications/Renamed.app"}]"#] {
            let data = Data((#"[{"token":"rename","version":"1.0","artifacts":_ADDITIONAL_}]"#.replacingOccurrences(of: "_ADDITIONAL_", with: artifacts)).utf8)
            let casks = try JSONDecoder().decode([Cask].self, from: data)
            XCTAssertNotNil(Cask.match(filename: "Renamed.app", casks: casks))
            XCTAssertNil(Cask.match(filename: "Original.app", casks: casks))
        }
    }

    func testResolutionCancellationBeforeInstallCompletesOnce() async {
        let gate = ResolutionGate()
        gate.finish(false)
        let result = await withCheckedContinuation { gate.install($0) }
        gate.finish(true)
        XCTAssertFalse(result)
    }
    func testResolutionTimeoutAfterInstallCompletesOnce() async {
        let gate = ResolutionGate()
        let result = await withCheckedContinuation { continuation in
            gate.install(continuation)
            gate.finish(false)
            gate.finish(true)
        }
        XCTAssertFalse(result)
    }

}

private final class ScanCancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func cancel() { lock.lock(); value = true; lock.unlock() }
}
