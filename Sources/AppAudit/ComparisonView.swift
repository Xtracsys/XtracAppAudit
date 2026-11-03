import SwiftUI
import AuditCore

struct ComparisonView: View {
    @Bindable var model: AuditModel
    @State private var tab = "Changes"
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Audit changes").font(.title2.bold()); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            if let baseline = model.baseline {
                Text("Baseline: \(model.baselineName) · \(baseline.captured.formatted())").foregroundStyle(.secondary)
                Picker("View", selection: $tab) { Text("Changes").tag("Changes"); Text("Saved audit evidence").tag("Saved") }.pickerStyle(.segmented)
                if tab == "Saved" { SavedAuditView(snapshot: baseline, export: { model.exportBaseline() }) }
                else {
                ForEach(model.comparisonNotes, id: \.self) { note in Label(note, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                Text("\(model.changes.count) inventory changes. Security and update evidence remain attached to each saved audit; this view compares app identity, version/build, location, recorded hashes and signing results.").font(.caption).foregroundStyle(.secondary)
                Table(model.changes) {
                    TableColumn("Change", value: \.kind).width(min: 100, ideal: 140)
                    TableColumn("Application", value: \.name).width(min: 130, ideal: 180)
                    TableColumn("Before / after", value: \.summary).width(min: 350, ideal: 550)
                }
                HStack {
                    if model.changes.isEmpty { Label("No inventory differences found", systemImage: "checkmark.circle") }
                    Spacer(); Button("Export changes CSV…") { model.exportChanges() }
                }
                }
            } else {
                ContentUnavailableView("Choose a baseline", systemImage: "clock.arrow.circlepath", description: Text("Open a saved audit snapshot or use the current scan as a baseline."))
                Button("Open snapshot…") { model.loadBaseline() }
            }
        }.padding(24).frame(width: 1000, height: 600)
    }
}
