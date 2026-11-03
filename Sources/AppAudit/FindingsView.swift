import SwiftUI
import AuditCore

struct FindingsView: View {
    @Bindable var model: AuditModel
    @Environment(\.dismiss) private var dismiss
    @State private var filter = "All"
    @State private var selection: String?
    @State private var editing: AuditFinding?
    private var findings: [AuditFinding] { model.findings.filter { filter == "All" || $0.severity.rawValue == filter } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Audit findings").font(.title2.bold()); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            HStack {
                Text("\(model.findings.filter { $0.severity == .action }.count) action needed · \(model.findings.filter { $0.severity == .review }.count) review · \(model.findings.filter { $0.severity == .unknown }.count) unknown")
                Spacer(); Picker("Show", selection: $filter) { Text("All").tag("All"); ForEach(FindingSeverity.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) } }.frame(width: 210)
            }
            Text(UpdateRouting.coverage(model.rawSnapshot())).font(.caption).foregroundStyle(.secondary)
            HSplitView {
                Table(findings, selection: $selection) {
                    TableColumn("Priority") { item in Text(item.severity.rawValue).foregroundStyle(item.severity == .action ? .red : item.severity == .review ? .orange : .secondary) }.width(110)
                    TableColumn("Decision") { Text($0.exception?.status(for: $0) ?? "Unreviewed") }.width(145)
                    TableColumn("Application", value: \.app).width(min: 120, ideal: 170)
                    TableColumn("Finding", value: \.title).width(min: 210, ideal: 280)
                }.frame(minWidth: 520)
                ScrollView {
                    if let item = findings.first(where: { $0.id == selection }) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(item.title).font(.headline); Text(item.severity.rawValue).bold(); Text(item.app); Text(item.path).font(.caption)
                            Text("Evidence").font(.headline); Text(item.evidence).font(.callout)
                            Text("Suggested next step").font(.headline); Text(item.nextStep).font(.callout)
                            Divider()
                            if let decision = item.exception { Text(decision.status(for: item)).font(.headline); Text(decision.description) }
                            Button("Document / edit exception…") { editing = item }
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    } else { ContentUnavailableView("Select a finding", systemImage: "list.bullet.clipboard", description: Text("Findings explain the evidence and a suggested next step. Unknown does not mean unsafe.")) }
                }.frame(minWidth: 300)
            }
            HStack { Text("Policy: \(model.settings.policy.enabled ? "enabled" : "disabled") · \(model.integrity.count) integrity records · \(model.findings.filter { $0.exception?.active(for: $0) == true }.count) active exceptions").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Export HTML…") { model.exportReport(pdf: false) }; Button("Export PDF…") { model.exportReport(pdf: true) } }.disabled(model.working)
        }.padding(24).frame(width: 1200, height: 700)
        .sheet(item: $editing) { ExceptionEditor(model: model, finding: $0) }
    }
}
