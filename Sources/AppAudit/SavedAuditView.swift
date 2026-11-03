import SwiftUI
import AuditCore

struct SavedAuditView: View {
    let snapshot: AuditSnapshot
    let export: () -> Void
    @State private var selection: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Read-only saved evidence · \(snapshot.apps.count) apps").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Export saved evidence CSV…", action: export) }
            DisclosureGroup("Audit context and age evidence") { Text(snapshot.workflowSummary).font(.caption).textSelection(.enabled) }
            HSplitView {
                Table(snapshot.apps, selection: $selection) {
                    TableColumn("Application", value: \.name)
                    TableColumn("Version", value: \.version).width(80)
                }.frame(minWidth: 300)
                ScrollView {
                    if let app = snapshot.apps.first(where: { $0.id == selection }) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(app.name).font(.title3.bold())
                            Text("\(app.bundleID)\n\(app.version) / \(app.build)\n\(app.path)")
                            Text("Architecture: \(app.architecture ?? "Unknown")")
                            Text(snapshot.workflowEvidence(app)).font(.callout)
                            ForEach((snapshot.findings ?? []).filter { $0.path == app.path && $0.exception != nil }) { finding in
                                if let decision = finding.exception { Text(finding.title + " · " + decision.status(for: finding, now: snapshot.captured)).bold(); Text(decision.description) }
                            }
                            Text("Last used: \(app.lastUsed?.formatted() ?? "Unknown")")
                            if let security = snapshot.evidence[app.id] {
                                Text("Install evidence: \((security.installDate ?? app.created)?.formatted() ?? "Unknown")\n\(security.installSource)")
                                Text("Signature: \(security.signature)\nPublisher: \(security.publisher)\nTeam: \(security.teamID)\nSigned ID: \(security.signedID)\nGatekeeper: \(security.gatekeeper)\nNotarization: \(security.notarization)\nChecked: \(security.checked.formatted())")
                                ForEach(security.receipts, id: \.packageID) { receipt in Text("Receipt: \(receipt.packageID) · \(receipt.version) · \(receipt.date.formatted())") }
                                DisclosureGroup("Saved diagnostics") { Text(security.diagnostics).font(.system(.caption, design: .monospaced)) }
                            } else { Text("Security and receipts were not checked in this snapshot. Install estimate: \(app.created?.formatted() ?? "Unknown")") }
                            if let integrity = snapshot.integrity?[app.id] {
                                Text("Integrity collected: \(integrity.checked.formatted())")
                                ForEach(integrity.hashes.keys.sorted(), id: \.self) { key in Text("SHA-256 \(key): \(integrity.hashes[key] ?? "")").font(.system(.caption, design: .monospaced)) }
                                ForEach(integrity.errors.keys.sorted(), id: \.self) { key in Text("Unavailable \(key): \(integrity.errors[key] ?? "")") }
                            }
                            if let update = snapshot.updates[app.id] {
                                Text("Update: \(update.status)\nLatest: \(update.latest)\nSource: \(update.source)\nIdentity: \(update.identity ?? "Unknown")\nChecked: \(update.checked.formatted())\n\(update.detail)")
                            } else { Text("Updates were not checked in this snapshot.") }
                        }.font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    } else { ContentUnavailableView("Select a saved app", systemImage: "archivebox", description: Text("Review its historical evidence. Imported evidence is a saved observation, not a new verification.")) }
                }.frame(minWidth: 400)
            }
            if !snapshot.warnings.isEmpty { Text("Saved scan warnings: \(snapshot.warnings.joined(separator: "; "))").font(.caption).foregroundStyle(.orange).lineLimit(3) }
        }
    }
}
