import SwiftUI
import AppKit
import AuditCore

@MainActor enum ConfigurationFiles {
    static func read() throws -> Data? {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) < 8_000_000 else { throw AuditFileError.invalid("Configuration exceeds 8 MB.") }
        return try Data(contentsOf: url)
    }
    static func write<T: Encodable>(_ value: T, name: String) throws {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = name
        if panel.runModal() == .OK, let url = panel.url { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(value).write(to: url, options: .atomic) }
    }
    static func teams(_ value: String) -> [String] { value.split { $0.isWhitespace || $0 == "," || $0 == ";" }.map(String.init) }
}
struct PolicyView: View {
    @Bindable var model: AuditModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = AuditPolicy()
    @State private var trusted = ""
    @State private var bundle = ""
    @State private var minimum = ""
    @State private var teams = ""
    @State private var allowed = true
    @State private var selection: String?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Approved-app policy").font(.title2.bold()); Spacer(); Button("Cancel") { dismiss() }; Button("Save policy") { save() }.keyboardShortcut(.defaultAction) }
            Toggle("Enable policy findings", isOn: $draft.enabled)
            Toggle("Allow only apps explicitly listed below", isOn: $draft.allowOnlyListed)
            TextField("Global trusted team IDs (optional, comma separated)", text: $trusted).textFieldStyle(.roundedBorder)
            Text("A per-app team list overrides the global list. Uncollected or invalid signing evidence stays Unknown. App Audit reports policy exceptions; it does not block or uninstall apps.").font(.caption).foregroundStyle(.secondary)
            Table(draft.rules, selection: $selection) {
                TableColumn("Bundle ID", value: \.bundleID)
                TableColumn("Decision") { Text($0.allowed ? "Allowed" : "Blocked") }.width(90)
                TableColumn("Minimum") { Text($0.minimumVersion ?? "None") }.width(90)
                TableColumn("Teams") { Text($0.teams.joined(separator: ", ")) }
            }
            HStack { TextField("Bundle ID", text: $bundle); TextField("Min version", text: $minimum).frame(width: 100); TextField("Team IDs", text: $teams); Toggle("Allowed", isOn: $allowed).frame(width: 95) }.textFieldStyle(.roundedBorder)
            HStack {
                Button("Add / replace rule") {
                    var value = draft; value.trustedTeams = ConfigurationFiles.teams(trusted)
                    value.rules.removeAll { $0.bundleID == bundle }
                    value.rules.append(AppPolicyRule(bundleID: bundle, allowed: allowed, minimumVersion: minimum.isEmpty ? nil : minimum, teams: ConfigurationFiles.teams(teams)))
                    do { draft = try value.validated(); error = nil } catch { self.error = error.localizedDescription }
                }
                Button("Edit selected") { if let rule = draft.rules.first(where: { $0.bundleID == selection }) { bundle = rule.bundleID; minimum = rule.minimumVersion ?? ""; teams = rule.teams.joined(separator: ", "); allowed = rule.allowed } }.disabled(selection == nil)
                Button("Remove selected") { draft.rules.removeAll { $0.bundleID == selection }; selection = nil }.disabled(selection == nil)
                Spacer()
                Button("Import…") { do { if let data = try ConfigurationFiles.read() { draft = try AuditPolicy.decode(data); trusted = draft.trustedTeams.joined(separator: ", "); error = nil } } catch { self.error = error.localizedDescription } }
                Button("Export…") { do { var value = draft; value.trustedTeams = ConfigurationFiles.teams(trusted); try ConfigurationFiles.write(try value.validated(), name: "App-Audit-Policy.json") } catch { self.error = error.localizedDescription } }
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            Text("Imported changes are drafts until Save policy. Existing monitor settings keep their saved policy until options are saved/applied again.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 1000, height: 620).onAppear { draft = model.settings.policy; trusted = draft.trustedTeams.joined(separator: ", ") }
    }
    private func save() {
        do { draft.trustedTeams = ConfigurationFiles.teams(trusted); _ = try draft.validated(); var settings = model.settings; settings.policy = draft; model.saveSettings(settings); if model.error == nil { dismiss() } }
        catch { self.error = error.localizedDescription }
    }
}
struct RegistryView: View {
    @Bindable var model: AuditModel
    @Environment(\.dismiss) private var dismiss
    @State private var custom: [PublisherRule] = []
    @State private var bundle = ""
    @State private var team = ""
    @State private var cask = ""
    @State private var source = ""
    @State private var selection: String?
    @State private var error: String?
    private var all: [PublisherRule] { (PublisherRule.known + custom).sorted { $0.bundleID < $1.bundleID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Publisher registry").font(.title2.bold()); Spacer(); Button("Cancel") { dismiss() }; Button("Save rules") { save() }.keyboardShortcut(.defaultAction) }
            Text("\(PublisherRule.known.count) built-in rules · \(custom.count) custom. Matching still requires a valid Apple-anchored signature, signed bundle ID and expected team. Built-ins cannot be overridden by imports.").font(.callout).foregroundStyle(.secondary)
            Table(all, selection: $selection) {
                TableColumn("Bundle ID", value: \.bundleID)
                TableColumn("Apple team", value: \.teamID).width(115)
                TableColumn("Cask", value: \.cask).width(160)
                TableColumn("Provenance") { Text($0.provenance ?? "Built-in publisher rule") }
            }
            HStack { TextField("Bundle ID", text: $bundle); TextField("Apple team ID", text: $team).frame(width: 140); TextField("Cask token", text: $cask).frame(width: 180) }.textFieldStyle(.roundedBorder)
            TextField("Provenance / vendor confirmation (recommended)", text: $source).textFieldStyle(.roundedBorder)
            HStack {
                Button("Add / replace custom rule") {
                    var rules = custom.filter { $0.bundleID != bundle }; rules.append(PublisherRule(bundleID: bundle, teamID: team, cask: cask, provenance: source.isEmpty ? nil : source))
                    do { _ = try PublisherRegistry.combined(custom: rules); custom = rules; error = nil } catch { self.error = error.localizedDescription }
                }
                Button("Edit custom") { if let rule = custom.first(where: { $0.bundleID == selection }) { bundle = rule.bundleID; team = rule.teamID; cask = rule.cask; source = rule.provenance ?? "" } }.disabled(!custom.contains { $0.bundleID == selection })
                Button("Remove custom") { custom.removeAll { $0.bundleID == selection }; selection = nil }.disabled(!custom.contains { $0.bundleID == selection })
                Spacer()
                Button("Import…") { do { if let data = try ConfigurationFiles.read() { custom = try PublisherRegistry.decode(data).rules; error = nil } } catch { self.error = error.localizedDescription } }
                Button("Export custom…") { do { try ConfigurationFiles.write(PublisherRegistry(rules: custom), name: "App-Audit-Publishers.json") } catch { self.error = error.localizedDescription } }
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            Text("Review imported trust decisions before saving. Do not approve a team just because the installed app claims a familiar name. Provenance should identify an independently trusted vendor source.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 1100, height: 600).onAppear { custom = model.settings.customRules }
    }
    private func save() {
        do { _ = try PublisherRegistry.combined(custom: custom); var settings = model.settings; settings.customRules = custom; model.saveSettings(settings); if model.error == nil { dismiss() } }
        catch { self.error = error.localizedDescription }
    }
}
