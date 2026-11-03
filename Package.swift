// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "AppAudit", platforms: [.macOS("14.4")], products: [.executable(name: "AppAudit", targets: ["AppAudit"])], targets: [.target(name: "AuditCore", resources: [.copy("Resources/XtracsysLogo.png")]), .executableTarget(name: "AppAudit", dependencies: ["AuditCore"]), .testTarget(name: "AuditCoreTests", dependencies: ["AuditCore"])])
