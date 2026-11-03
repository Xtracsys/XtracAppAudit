import SwiftUI
import AppKit
import AuditCore

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AuditModel()
    @State private var selection: String?
    @State private var sortOrder = [KeyPathComparator(\AuditTableRow.name)]
    @State private var showFolders = false
    @State private var showComparison = false
    @State private var showFindings = false
    @State private var showPolicy = false
    @State private var showRegistry = false
    @State private var showMonitor = false
    @State private var editingLinks: InstalledApp?
    @State private var showDuplicates = false
    @State private var showContext = false
    @State private var showExceptions = false
    @State private var showNetworkDevices = false
    private var visible: [InstalledApp] { rows.map(\.app) }
    private var rows: [AuditTableRow] {
        let filtered = model.apps.filter { app in
            let age = UpdateAge.band(date: UpdateAge.evidence(app, security: model.evidence[app.id]).date)
            return (model.preferences.category == nil || model.preferences.category == "All" || model.preferences.category == app.classification.category.rawValue) &&
            (model.ageFilter == "All ages" || (model.ageFilter == "OS-maintained" && app.classification.managedByMacOS) || (!app.classification.managedByMacOS && age.rawValue == model.ageFilter)) &&
            (model.preferences.search.isEmpty || [app.name, app.bundleID, app.version, app.path].contains { $0.localizedCaseInsensitiveContains(model.preferences.search) }) &&
            (model.preferences.filter == "All apps" ||
             (model.preferences.filter == "Updates" && ["Update available", "Possible update"].contains(model.updates[app.id]?.status ?? "")) ||
             (model.preferences.filter == "Unknown last use" && app.lastUsed == nil) ||
             (model.preferences.filter == "Needs review" && (model.evidence[app.id]?.signature.hasPrefix("Valid") != true || model.evidence[app.id]?.gatekeeper != "Accepted")))
        }
        return filtered.map { AuditTableRow(app: $0, update: model.updateDisplay($0), security: model.evidence[$0.id]) }
            .sorted(using: sortOrder + [KeyPathComparator(\AuditTableRow.path)])
    }

    private var selected: InstalledApp? { model.apps.first { $0.id == selection } }
    var body: some View {
        VStack(spacing: 0) {
            header
            scanningOptions
            HStack(spacing: 18) {
                metric("Inventoried", value: model.apps.count, icon: "square.grid.2x2")
                metric("Verified updates", value: model.verifiedUpdates, icon: "arrow.down.circle")
                metric("Unknown last use", value: model.apps.filter { $0.lastUsed == nil }.count, icon: "clock.badge.questionmark")
                Spacer()
                Picker("Filter", selection: $model.preferences.filter) { Text("All apps").tag("All apps"); Text("Updates").tag("Updates"); Text("Unknown last use").tag("Unknown last use"); Text("Needs review").tag("Needs review") }.frame(width: 230)
                TextField("Search apps, versions, paths…", text: $model.preferences.search).textFieldStyle(.roundedBorder).frame(width: 280)
            }.padding(18).background(.quaternary.opacity(0.3))
            HStack {
                Label("\(model.findings.filter { $0.severity == .action }.count) action needed · \(model.findings.filter { $0.severity == .review }.count) review · \(model.findings.filter { $0.severity == .unknown }.count) unknown", systemImage: "list.bullet.clipboard")
                Text("Policy \(model.settings.policy.enabled ? "on" : "off")").foregroundStyle(.secondary)
                Text("\(model.findings.filter { $0.exception?.active(for: $0) == true }.count) active exceptions").foregroundStyle(.secondary)
                if model.offline { Label("Offline — online/trust checks and browser links disabled", systemImage: "wifi.slash").foregroundStyle(.secondary) }
                if model.redactExports { Label("Export redaction on", systemImage: "eye.slash").foregroundStyle(.secondary).help("Explicit exports redact personal paths and web addresses. Review files before sharing; other app details remain. Local monitor history stays complete.") }
                Spacer(); Button("Review findings") { showFindings = true }
            }.font(.caption).padding(.horizontal, 18).padding(.vertical, 7)
            if model.baseline != nil {
                HStack {
                    Label("Baseline: \(model.baselineName)", systemImage: "clock.arrow.circlepath").lineLimit(1)
                    Text("\(model.changes.count) changes").bold()
                    if !model.comparisonNotes.isEmpty { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).help(model.comparisonNotes.joined(separator: "\n")) }
                    Spacer(); Button("Review changes") { showComparison = true }
                    Button("Clear baseline") { model.baseline = nil }
                }.font(.caption).padding(.horizontal, 18).padding(.vertical, 8)
            }
            HStack(spacing: 14) {
                Text("Update age evidence").font(.caption.bold())
                Button("All (\(model.apps.count))") { model.ageFilter = "All ages" }
                Button("OS-maintained · \(model.apps.filter { $0.classification.managedByMacOS }.count)") { model.ageFilter = "OS-maintained" }
                ForEach(UpdateAge.allCases, id: \.self) { band in
                    Button { model.ageFilter = band.rawValue } label: {
                        Text(band.rawValue + " · " + String(model.apps.filter { !$0.classification.managedByMacOS && UpdateAge.band(date: UpdateAge.evidence($0, security: model.evidence[$0.id]).date) == band }.count))
                            .font(.caption).foregroundStyle(ageColor(band))
                    }.accessibilityLabel("Filter update age: " + band.rawValue)
                }
                Spacer(); Text(model.ageFilter).font(.caption).foregroundStyle(.secondary)
            }.buttonStyle(.borderless).padding(.horizontal, 18).padding(.vertical, 9)
            HStack {
                Picker("Category", selection: Binding(get: { model.preferences.category ?? "All" }, set: { model.preferences.category = $0; model.savePreferences() })) {
                    Text("All apps").tag("All")
                    ForEach(AppCategory.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
                }.frame(width: 255).help("Categories use install locations or claimed bundle metadata, not publisher verification. Third-party includes unclassified apps.")
                Text(UpdateRouting.coverage(model.rawSnapshot())).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }.padding(.horizontal, 18).padding(.bottom, 8)
            HSplitView {
                Table(rows, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Application", value: \.name) { app in
                        HStack { Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 24, height: 24); Text(app.name).lineLimit(1) }
                    }.width(min: 170, ideal: 230)
                    TableColumn("Version", value: \.version).width(min: 75, ideal: 90)
                    TableColumn("Update", value: \.update) { app in
                        Text(app.update).foregroundStyle(model.updates[app.id]?.status == "Update available" ? Color.orange : Color.secondary)
                    }.width(min: 110, ideal: 130)
                    if model.preferences.showDates {
                        TableColumn("Update age", value: \.ageSort) { row in
                            let app = row.app
                            let age = UpdateAge.band(date: UpdateAge.evidence(app, security: model.evidence[app.id]).date)
                            Text(app.classification.managedByMacOS ? "OS-maintained" : age.rawValue).foregroundStyle(app.classification.managedByMacOS ? Color.secondary : ageColor(age)).help(UpdateAge.evidence(app, security: model.evidence[app.id]).source)
                        }.width(min: 92, ideal: 110)
                        TableColumn("Install evidence", value: \.installSort) { app in Text((model.evidence[app.id]?.installDate ?? app.app.created)?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown") }.width(min: 100, ideal: 115)
                        TableColumn("Last used", value: \.usedSort) { Text($0.usedText) }.width(min: 90, ideal: 110)
                    }
                    TableColumn("Architecture", value: \.architecture).width(min: 85, ideal: 100)
                    if model.preferences.showSecurity {
                        TableColumn("Signature", value: \.signature).width(min: 100, ideal: 140)
                        TableColumn("Publisher", value: \.publisher).width(min: 120, ideal: 180)
                        TableColumn("Gatekeeper", value: \.gatekeeper).width(min: 100, ideal: 120)
                    }
                    if model.preferences.showNotarization == true {
                        TableColumn("Notarization", value: \.notarization).width(min: 100, ideal: 150)
                    }
                    if model.preferences.showLocation {
                        TableColumn("Location", value: \.path) { Text($0.path).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }.width(min: 150, ideal: 250)
                    }
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    if let id = ids.first, let app = model.apps.first(where: { $0.id == id }) {
                        Button("Reveal in Finder") { reveal(app) }
                        Button("Check for update") { model.check([app]) }.disabled(model.working || model.offline)
                        Button("Copy path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(app.path, forType: .string) }
                    }
                } primaryAction: { ids in if let id = ids.first, let app = model.apps.first(where: { $0.id == id }) { reveal(app) } }
                .frame(minWidth: 670)
                ScrollView {
                    if let app = selected { details(app) }
                    else { ContentUnavailableView("Select an application", systemImage: "app.badge.checkmark", description: Text("Review its metadata, update source and signature.")) }
                }.frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
            }
            HStack {
                if model.working { ProgressView().controlSize(.small) }
                Text(model.progress).lineLimit(1)
                Spacer()
                if !model.warnings.isEmpty { Text("\(model.warnings.count) scan warnings").foregroundStyle(.orange).help(model.warnings.joined(separator: "\n")) }
                Text("\(visible.count) shown · dates are best effort").foregroundStyle(.secondary)
            }.font(.caption).padding(12)
        }
        .task {
            restoreSort(); model.scan()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if !Task.isCancelled && !model.working { await model.refreshRevisions() }
            }
        }
        .onChange(of: model.preferences) { model.savePreferences() }
        .onChange(of: sortOrder) { persistSort() }
        .alert("App Audit", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
        .sheet(isPresented: $showFolders) { folders }
        .sheet(isPresented: $showComparison) { ComparisonView(model: model) }
        .sheet(isPresented: $showFindings) { FindingsView(model: model) }
        .sheet(isPresented: $showPolicy) { PolicyView(model: model) }
        .sheet(isPresented: $showRegistry) { RegistryView(model: model) }
        .sheet(isPresented: $showMonitor) { MonitorView(model: model) }
        .sheet(item: $editingLinks) { DeveloperLinksView(model: model, app: $0) }
        .sheet(isPresented: $showDuplicates) { DuplicatesView(model: model) }
        .sheet(isPresented: $showContext) { AuditContextView(model: model) }
        .sheet(isPresented: $showExceptions) { ExceptionRegister(model: model) }
        .sheet(isPresented: $showNetworkDevices) { NetworkDevicesView(discovery: model.networkDiscovery) }
        .onAppear { model.setNetworkDiscoveryForeground(scenePhase == .active) }
        .onChange(of: scenePhase) { model.setNetworkDiscoveryForeground(scenePhase == .active) }
        .onDisappear { model.setNetworkDiscoveryEnabled(false) }
    }
    private var header: some View {
        HStack {
            if let data = Brand.logoData, let logo = NSImage(data: data) {
                Image(nsImage: logo).resizable().scaledToFit().frame(width: 46, height: 46)
                    .padding(4).background(.white, in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityLabel("Xtracsys logo")
            }
            VStack(alignment: .leading, spacing: 3) { Text("App Audit").font(.title2.bold()); Text("XTRACSYS · Application inventory & version review").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Menu {
                Button("Audit context & notes…") { showContext = true }
                Button("Exception review queue…") { showExceptions = true }
                Button("Refresh evidence freshness") { Task { await model.refreshRevisions() } }.disabled(model.working)
                Button("Duplicate installations…") { showDuplicates = true }
                Toggle("Redact personal paths & web addresses in exports", isOn: $model.redactExports)
                Button("Findings dashboard") { showFindings = true }
                Button("Collect integrity hashes") { model.collectIntegrity(visible) }.disabled(model.working)
                Button("Approved-app policy…") { showPolicy = true }
                Button("Publisher registry…") { showRegistry = true }
                Button("Monitor & schedule…") { showMonitor = true }
                Divider()
                Button("Export HTML report…") { model.exportReport(pdf: false) }.disabled(model.working)
                Button("Export PDF report…") { model.exportReport(pdf: true) }.disabled(model.working)
                Button("Saved audit HTML report…") { model.exportReport(pdf: false, saved: true) }.disabled(model.baseline == nil || model.working)
                Button("Saved audit PDF report…") { model.exportReport(pdf: true, saved: true) }.disabled(model.baseline == nil || model.working)
            } label: { Label("Audit tools", systemImage: "shield.lefthalf.filled") }
            Menu {
                Button("Save full audit snapshot…") { model.saveSnapshot() }.disabled(model.working || model.apps.isEmpty)
                Button("Open snapshot as baseline…") { model.loadBaseline() }
                Button("Use current audit as baseline") { model.useCurrentAsBaseline() }.disabled(model.working || model.apps.isEmpty)
                Button("Review changes") { showComparison = true }.disabled(model.baseline == nil)
            } label: { Label("Snapshots", systemImage: "clock.arrow.circlepath") }
            Menu {
                Toggle("Dates", isOn: $model.preferences.showDates)
                Toggle("Security evidence", isOn: $model.preferences.showSecurity)
                Toggle("Notarization / distribution", isOn: Binding(get: { model.preferences.showNotarization == true }, set: { model.preferences.showNotarization = $0 }))
                Toggle("Location", isOn: $model.preferences.showLocation)
            } label: { Label("Columns", systemImage: "tablecells") }
            Button { model.inspect(visible) } label: { Label("Inspect security", systemImage: "checkmark.shield") }.disabled(model.working || visible.isEmpty || model.offline)
            Button { showFolders = true } label: { Label("Folders", systemImage: "folder") }
            Button { model.scan() } label: { Label("Rescan", systemImage: "arrow.clockwise") }.disabled(model.working)
            if model.canStop { Button("Stop") { model.cancel() } }
            else { Button { model.check(visible) } label: { Label("Check updates", systemImage: "network") }.disabled(model.working || visible.isEmpty || model.offline) }
            Button { model.export(visible) } label: { Label("Export CSV", systemImage: "square.and.arrow.up") }.disabled(visible.isEmpty)
            Button { model.exportJSON(visible) } label: { Label("Export JSON", systemImage: "curlybraces") }.disabled(visible.isEmpty)
        }.buttonStyle(.bordered).padding(20)
    }
    private var scanningOptions: some View {
        HStack(spacing: 26) {
            Toggle(isOn: Binding(get: { !model.offline }, set: { model.setOffline(!$0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Online and trust checks").font(.subheadline.weight(.medium))
                    Text(model.offline ? "Off" : "On").font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .disabled(model.working)
            .help("Allows update catalog checks, signing and Gatekeeper checks, and opening developer links. This setting is saved.")

            Toggle(isOn: Binding(get: { model.networkDiscoveryEnabled }, set: { enabled in
                model.setNetworkDiscoveryEnabled(enabled)
                if enabled { showNetworkDevices = true }
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Find network devices").font(.subheadline.weight(.medium))
                    Text(model.networkDiscoveryEnabled ? "On · Bonjour" : "Off").font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .help("When on, looks for devices advertising supported Bonjour services on the local network. Results stay on this Mac and clear when turned off.")

            if model.networkDiscoveryEnabled {
                Button { showNetworkDevices = true } label: {
                    Label("View services · \(model.networkDiscovery.services.count)", systemImage: "dot.radiowaves.left.and.right")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.18))
    }
    private func metric(_ title: String, value: Int, icon: String) -> some View {
        HStack { Image(systemName: icon).foregroundStyle(Color.accentColor); VStack(alignment: .leading) { Text("\(value)").font(.title2.monospacedDigit().bold()); Text(title).font(.caption).foregroundStyle(.secondary) } }
    }
    private func details(_ app: InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 48, height: 48); Text(app.name).font(.title2.bold()) }
            item("Bundle ID", app.bundleID); item("Installed version / build", "\(app.version) / \(app.build)")
            item("Location", app.path)
            Button("Reveal in Finder", systemImage: "folder") { reveal(app) }
            Divider()
            item("Executable architecture", app.architecture ?? "Unknown")
            item("Install date evidence", (model.evidence[app.id]?.installDate ?? app.created)?.formatted() ?? "Unknown")
            item("Date source", model.evidence[app.id]?.installSource ?? "Filesystem creation estimate; receipts not checked")
            if let security = model.evidence[app.id], !security.receipts.isEmpty {
                ForEach(security.receipts, id: \.packageID) { receipt in
                    item("Receipt \(receipt.packageID)", "\(receipt.version) · \(receipt.date.formatted())")
                }
            }
            Text("Receipt dates record installer events, often the latest update. Filesystem dates are estimates affected by copying/restoring. Neither proves original installation. Inspect security to look up matching receipts.").font(.caption).foregroundStyle(.secondary)
            item("Category", app.classification.category.rawValue)
            Text(app.classification.basis).font(.caption).foregroundStyle(.secondary)
            let age = UpdateAge.evidence(app, security: model.evidence[app.id])
            item("Update age evidence", (app.classification.managedByMacOS ? "OS-maintained" : UpdateAge.band(date: age.date).rawValue) + " · " + (age.date?.formatted() ?? "Unknown"))
            Text(age.source + ". This is not proof of a vendor update or a vulnerability rating.").font(.caption).foregroundStyle(.secondary)
            item("Last used", app.lastUsed?.formatted() ?? "Unknown")
            Text("Spotlight metadata, when available. Unknown does not mean never used.").font(.caption).foregroundStyle(.secondary)
            Divider()
            if let result = UpdateRouting.result(app, recorded: model.updates[app.id]) {
                item("Update status", result.status)
                if !result.latest.isEmpty { item("Latest at source", result.latest) }
                item("Update identity basis", result.identity ?? "Not verified")
                if app.classification.managedByMacOS || app.appStore { Text("Update availability has not been checked; this label identifies the update channel.").font(.caption).foregroundStyle(.secondary) }
                else { item("Evidence freshness", AppRevision.status(observed: result.revision, current: model.revisions[app.id])) }
                Text(result.detail).font(.caption).foregroundStyle(.secondary)
                if let url = URL(string: result.source), UpdateChecker.allowedURL(result.source) != nil { Link("Open update source", destination: url).disabled(model.offline) }
                if !app.classification.managedByMacOS && !app.appStore { item("Checked", result.checked.formatted()) }
            } else { Text("Updates have not been checked.").foregroundStyle(.secondary) }
            Divider()
            Text("DEVELOPER LINKS").font(.caption2.bold()).foregroundStyle(.secondary)
            let manual = model.settings.developerLinks?[DeveloperLinks.key(app)] ?? DeveloperLinks()
            ForEach(manual.entries, id: \.0) { label, address in
                if let url = DeveloperLinks.url(address) {
                    Link(label + " · " + (url.host ?? ""), destination: url).disabled(model.offline)
                    Text("User supplied · " + address).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if manual.website.isEmpty, let address = model.updates[app.id]?.homepage, let url = DeveloperLinks.url(address) {
                Link("Developer website · " + (url.host ?? ""), destination: url).disabled(model.offline)
                Text("Homebrew catalog supplied · publisher identity is shown separately above").font(.caption2).foregroundStyle(.secondary)
            }
            if manual.entries.isEmpty && model.updates[app.id]?.homepage == nil { Text("No developer link collected. Check for updates to look up catalog data, or enter an address manually.").font(.caption).foregroundStyle(.secondary) }
            Button("Edit developer links…", systemImage: "link") { editingLinks = app }
            Button("Check this app", systemImage: "arrow.down.circle") { model.check([app]) }.disabled(model.working || model.offline)
            if app.appStore { Link("Open App Store updates", destination: URL(string: "macappstore://showUpdatesPage")!).disabled(model.offline) }
            Divider()
            Button("Inspect security & receipts", systemImage: "signature") { model.inspect([app]) }.disabled(model.working || model.offline)
            if let security = model.evidence[app.id] {
                item("Signature", security.signature); item("Publisher", security.publisher)
                item("Signing team / identifier", "\(security.teamID) / \(security.signedID)")
                item("Gatekeeper", security.gatekeeper); item("Notarization", security.notarization)
                item("Security checked", security.checked.formatted())
                item("Security freshness", AppRevision.status(observed: security.revision, current: model.revisions[app.id]))
                DisclosureGroup("Diagnostics") { Text(security.diagnostics).font(.system(.caption, design: .monospaced)) }
            } else { Text("Security and receipt evidence has not been collected.").font(.caption).foregroundStyle(.secondary) }
            Text("Gatekeeper may consult Apple services. Confirmed notarized means explicit Developer ID notarization evidence. Apple system and App Store distribution identify other accepted trust routes, not notarization verdicts. Not established is inconclusive; inspect the diagnostics for the reason. Legacy snapshots retain their original labels.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Button("Collect integrity hashes", systemImage: "number.square") { model.collectIntegrity([app]) }.disabled(model.working)
            if let value = model.integrity[app.id] {
                item("Integrity checked", value.checked.formatted())
                item("Integrity freshness", AppRevision.status(observed: value.revision, current: model.revisions[app.id]))
                ForEach(value.hashes.keys.sorted(), id: \.self) { key in item("SHA-256 \(key)", value.hashes[key] ?? "") }
                ForEach(value.errors.keys.sorted(), id: \.self) { key in item("Unavailable: \(key)", value.errors[key] ?? "") }
            }
            Text("Hashes cover the main executable, Info.plist and CodeResources when readable, not every bundle file.").font(.caption).foregroundStyle(.secondary)
            if let checked = model.revisionsChecked { Text("File metadata freshness refreshed " + checked.formatted() + ". Refresh is periodic while this window is open; selected-file metadata cannot detect every bundle change.").font(.caption).foregroundStyle(.secondary) }
            Text("An update status is not a vulnerability assessment.").font(.caption).foregroundStyle(.secondary)
        }.padding(20).textSelection(.enabled)
    }
    private func ageColor(_ band: UpdateAge) -> Color {
        switch band { case .recent: return .green; case .middle: return .orange; case .aging: return .orange; case .older: return .red; case .unknown: return .secondary }
    }
    private func item(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary); Text(value).font(.callout).textSelection(.enabled) }
    }
    private func reveal(_ app: InstalledApp) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)]) }
    private func restoreSort() {
        let order: SortOrder = model.preferences.ascending ? .forward : .reverse
        switch model.preferences.sort {
        case "version": sortOrder = [KeyPathComparator(\AuditTableRow.version, order: order)]
        case "installed": sortOrder = [KeyPathComparator(\AuditTableRow.installSort, order: order)]
        case "used": sortOrder = [KeyPathComparator(\AuditTableRow.usedSort, order: order)]
        case "path": sortOrder = [KeyPathComparator(\AuditTableRow.path, order: order)]
        case "update": sortOrder = [KeyPathComparator(\AuditTableRow.update, order: order)]
        case "ageSort": sortOrder = [KeyPathComparator(\AuditTableRow.ageSort, order: order)]
        case "architecture": sortOrder = [KeyPathComparator(\AuditTableRow.architecture, order: order)]
        case "signature": sortOrder = [KeyPathComparator(\AuditTableRow.signature, order: order)]
        case "publisher": sortOrder = [KeyPathComparator(\AuditTableRow.publisher, order: order)]
        case "gatekeeper": sortOrder = [KeyPathComparator(\AuditTableRow.gatekeeper, order: order)]
        case "notarization": sortOrder = [KeyPathComparator(\AuditTableRow.notarization, order: order)]
        default: sortOrder = [KeyPathComparator(\AuditTableRow.name, order: order)]
        }
    }
    private func persistSort() {
        guard let first = sortOrder.first else { return }
        model.preferences.ascending = first.order == .forward
        switch first.keyPath {
        case \AuditTableRow.version: model.preferences.sort = "version"
        case \AuditTableRow.installSort: model.preferences.sort = "installed"
        case \AuditTableRow.usedSort: model.preferences.sort = "used"
        case \AuditTableRow.path: model.preferences.sort = "path"
        case \AuditTableRow.update: model.preferences.sort = "update"
        case \AuditTableRow.ageSort: model.preferences.sort = "ageSort"
        case \AuditTableRow.architecture: model.preferences.sort = "architecture"
        case \AuditTableRow.signature: model.preferences.sort = "signature"
        case \AuditTableRow.publisher: model.preferences.sort = "publisher"
        case \AuditTableRow.gatekeeper: model.preferences.sort = "gatekeeper"
        case \AuditTableRow.notarization: model.preferences.sort = "notarization"
        default: model.preferences.sort = "name"
        }
    }
    private var folders: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scan scope and coverage").font(.title2.bold())
            Text("Default: the accessible filesystem (/), including hidden folders, nested apps and mounted volumes. Apps are read without launching them. Protected or unreadable paths are coverage gaps, listed below and in reports. Full Disk Access can improve coverage; it does not bypass all macOS protections.").foregroundStyle(.secondary)
            List {
                ForEach(model.roots, id: \.self) { root in
                    HStack { Text(root.path); Spacer(); Button("Remove") { model.preferences.folders.removeAll { $0 == root.path }; model.savePreferences() }.disabled(model.working) }
                }
            }
            if !model.warnings.isEmpty { ScrollView { Text(model.warnings.joined(separator: "\n")).font(.caption).textSelection(.enabled) }.frame(maxHeight: 100) }
            HStack { Button("Scan entire filesystem") { model.preferences.folders = ["/"]; model.savePreferences(); showFolders = false; model.scan() }.disabled(model.working); Button("Add folder…") { model.addFolder() }.disabled(model.working); Spacer(); Button("Done") { showFolders = false; model.scan() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 800, height: 500)
    }
}
