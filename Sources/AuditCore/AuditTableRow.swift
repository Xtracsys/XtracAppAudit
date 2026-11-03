import Foundation

/// Live presentation values keep table sorting aligned with the displayed evidence.
public struct AuditTableRow: Identifiable {
    public let app: InstalledApp
    public let update: String
    public let signature: String
    public let publisher: String
    public let gatekeeper: String
    public let notarization: String
    public let installSort: Date
    public let ageSort: Date
    public var id: String { app.id }
    public var name: String { app.name }
    public var version: String { app.version }
    public var path: String { app.path }
    public var architecture: String { app.architecture ?? "Unknown" }
    public var usedSort: Date { app.usedSort }
    public var usedText: String { app.usedText }

    public init(app: InstalledApp, update: String, security: SecurityEvidence?) {
        self.app = app; self.update = update
        signature = security?.signature ?? "Not checked"
        publisher = security?.publisher ?? "Not checked"
        gatekeeper = security?.gatekeeper ?? "Not checked"
        notarization = security?.notarization ?? "Not checked"
        installSort = security?.installDate ?? app.installSort
        ageSort = app.classification.managedByMacOS ? .distantFuture : UpdateAge.evidence(app, security: security).date ?? .distantPast
    }
}
