import SwiftUI
import AppKit
import AuditCore

struct DeveloperLinksView: View {
    @Bindable var model: AuditModel
    let app: InstalledApp
    @Environment(\.dismiss) private var dismiss
    @State private var draft = DeveloperLinks()
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Developer links · " + app.name).font(.title2.bold()); Spacer(); Button("Cancel") { dismiss() } }
            Text("Manual addresses apply to " + DeveloperLinks.key(app)).font(.caption).textSelection(.enabled)
            TextField("Website — https://vendor.example", text: $draft.website)
            TextField("Support — https://vendor.example/support", text: $draft.support)
            TextField("Release notes — https://vendor.example/releases", text: $draft.releaseNotes)
            Text("Paste complete HTTPS addresses. Leave a field empty to use the catalog fallback where available. Manual links are user supplied; they do not verify a publisher or change update checks.").font(.callout).foregroundStyle(.secondary)
            ForEach(draft.entries, id: \.0) { label, address in
                if let url = DeveloperLinks.url(address) { Text(label + " → " + (url.host ?? "")).font(.caption).textSelection(.enabled) }
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack { Button("Clear manual links") { draft = DeveloperLinks() }; Spacer(); Button("Save links") {
                do {
                    let value = try draft.validated(); var settings = model.settings
                    var links = settings.developerLinks ?? [:]
                    if value.entries.isEmpty { links.removeValue(forKey: DeveloperLinks.key(app)) } else { links[DeveloperLinks.key(app)] = value }
                    settings.developerLinks = links; model.saveSettings(settings)
                    if model.error == nil { dismiss() }
                } catch { self.error = error.localizedDescription }
            }.keyboardShortcut(.defaultAction) }
        }.textFieldStyle(.roundedBorder).padding(24).frame(width: 700)
        .onAppear { draft = model.settings.developerLinks?[DeveloperLinks.key(app)] ?? DeveloperLinks() }
    }
}
struct DuplicatesView: View {
    @Bindable var model: AuditModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Duplicate installations").font(.title2.bold()); Spacer(); Button("Done") { dismiss() } }
            Text("Exact known bundle IDs at multiple paths. Copies may be intentional; no apps are removed. Symlink aliases or restored copies can appear separately.").font(.callout).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(DuplicateDetector.groups(model.apps)) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.bundleID).font(.headline)
                            ForEach(group.apps) { app in
                                HStack { VStack(alignment: .leading) { Text(app.name + " · " + app.version + " (" + app.build + ")"); Text(app.path).font(.caption).textSelection(.enabled) }; Spacer(); Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)]) } }
                            }
                        }
                        Divider()
                    }
                    if DuplicateDetector.groups(model.apps).isEmpty { Text("No duplicate bundle identities found in this scan.") }
                }
            }
        }.padding(24).frame(width: 850, height: 600)
    }
}
