import SwiftUI
import AppKit
import AuditCore

@MainActor @Observable final class AuditModel {
    var apps: [InstalledApp] = []
    var updates: [String: UpdateResult] = [:]
    var evidence: [String: SecurityEvidence] = [:]
    var integrity: [String: IntegrityEvidence] = [:]
    var settings = AuditSettings()
    var monitorConfig = MonitorConfiguration()
    var monitorStatus: MonitorStatus?
    var monitorEnabled = false
    var monitorRunning = false
    var renderingPDF = false
    var redactExports = false
    var ageFilter = "All ages"
    var revisions: [String: String] = [:]
    var revisionsChecked: Date?
    var offline: Bool { settings.offlineMode == true }
    private var pdfExporter: PDFExporter?
    var preferences: AuditPreferences
    var scannedRoots: [String] = []
    var warnings: [String] = []
    var busy = false
    var checking = false
    var inspecting = false
    var progress = "Ready"
    var error: String?
    var baseline: AuditSnapshot?
    var baselineName = ""
    private var scanGeneration = 0
    private var scanWorker: Task<ScanResult, Never>?
    private var operation: Task<Void, Never>?
    private var monitorWorker: Task<MonitorRun, Error>?
    private let preferencesStore = PreferenceStore()
    let checker = UpdateChecker()
    let networkDiscovery = NetworkDeviceDiscovery()
    var networkDiscoveryEnabled = false
    private var networkDiscoveryForeground = false
    var roots: [URL] { preferences.folders.map { URL(fileURLWithPath: $0) } }
    var canStop: Bool { busy || checking || inspecting || monitorWorker != nil }
    var working: Bool { busy || checking || inspecting || monitorRunning || renderingPDF }
    func updateDisplay(_ app: InstalledApp) -> String {
        guard let value = UpdateRouting.result(app, recorded: updates[app.id]) else { return "Not checked" }
        if let observed = value.revision, let current = revisions[app.id], observed != current { return "Stale · " + value.status }
        return value.status
    }
    var verifiedUpdates: Int { apps.filter { !$0.classification.managedByMacOS && !$0.appStore && updates[$0.id]?.status == "Update available" && updates[$0.id]?.revision != nil && updates[$0.id]?.revision == revisions[$0.id] }.count }
    var changes: [AuditChange] { baseline.map { AuditComparison.changes(baseline: $0, current: rawSnapshot()) } ?? [] }
    var findings: [AuditFinding] { FindingEngine.evaluate(rawSnapshot(), baseline: baseline, policy: settings.policy) }
    var comparisonNotes: [String] { baseline.map { AuditComparison.scopeNotes(baseline: $0, roots: scannedRoots, warnings: warnings) } ?? [] }
    init() {
        preferences = preferencesStore.load()
        do { settings = try AuditStorage.loadSettings() } catch { settings.offlineMode = true; self.error = "Settings could not be loaded; offline mode enabled and no custom policy/rules applied: \(error.localizedDescription)" }
        monitorConfig = NativeMonitor.loadConfiguration(); refreshMonitor()
    }
    func setOffline(_ enabled: Bool) {
        guard !working else { return }
        var value = settings; value.offlineMode = enabled; saveSettings(value)
    }
    func setNetworkDiscoveryEnabled(_ enabled: Bool) {
        guard networkDiscoveryEnabled != enabled else { return }
        networkDiscoveryEnabled = enabled
        if enabled && networkDiscoveryForeground { networkDiscovery.start() }
        else { networkDiscovery.stop() }
    }
    func setNetworkDiscoveryForeground(_ foreground: Bool) {
        guard networkDiscoveryForeground != foreground else { return }
        networkDiscoveryForeground = foreground
        guard networkDiscoveryEnabled else { return }
        if foreground { networkDiscovery.start() }
        else { networkDiscovery.stop() }
    }
    func refreshRevisions() async {
        let targets = apps
        let current = await Task.detached(priority: .utility) { Dictionary(targets.compactMap { app in AppRevision.read(app).map { (app.id, $0) } }, uniquingKeysWith: { first, _ in first }) }.value
        revisions = current; revisionsChecked = Date()
    }
    func saveException(_ value: FindingException, for finding: AuditFinding) throws {
        _ = try value.validated(); var options = settings; var exceptions = options.exceptions ?? [:]
        exceptions[finding.id] = value; options.exceptions = exceptions
        try AuditStorage.saveSettings(options); settings = options
    }
    func refreshMonitor() { monitorEnabled = NativeMonitor.enabled; monitorStatus = MonitorRunner.status(directory: NativeMonitor.directory) }
    func saveSettings(_ value: AuditSettings) {
        do { try AuditStorage.saveSettings(value); settings = value; error = nil; progress = "Audit settings saved." }
        catch { self.error = error.localizedDescription }
    }
    func savePreferences() {
        do { try preferencesStore.save(preferences) } catch { self.error = "Unable to save preferences: \(error.localizedDescription)" }
    }
    func scan() {
        guard !working else { return }
        scanGeneration += 1
        busy = true; progress = "Discovering apps across the configured filesystem scope…"
        let folders = roots
        let generation = scanGeneration
        let reportProgress: @Sendable (Int, String) -> Void = { [weak self] count, path in
            Task { @MainActor [weak self] in
                guard let self, self.busy, self.scanGeneration == generation else { return }
                self.progress = "Scanning \(count) folders · \(path)"
            }
        }
        let worker = Task.detached(priority: .userInitiated) {
            Scanner.scan(roots: folders, cancelled: { Task.isCancelled }, progress: reportProgress)
        }
        scanWorker = worker
        Task {
            let result = await worker.value
            scanWorker = nil
            apps = result.apps; warnings = result.warnings; scannedRoots = folders.map(\.path)
            let paths = Set(apps.map(\.id))
            updates = updates.filter { paths.contains($0.key) }; evidence = evidence.filter { paths.contains($0.key) }; integrity = integrity.filter { paths.contains($0.key) }
            revisions = Dictionary(apps.compactMap { app in app.revision.map { (app.id, $0) } }, uniquingKeysWith: { first, _ in first }); revisionsChecked = Date()
            busy = false; progress = "\(apps.count) apps · \(warnings.isEmpty ? "scan finished" : "scan finished with coverage warnings") · \(Date().formatted(date: .omitted, time: .shortened))"
        }
    }
    func check(_ targets: [InstalledApp]) {
        guard !working else { return }
        guard !offline else { progress = "Offline mode: online checks are disabled; previous observations retain their timestamps."; return }
        guard let rules = try? PublisherRegistry.combined(custom: settings.customRules) else { error = "Publisher rules are invalid; update check stopped."; return }
        checking = true
        operation = Task {
            for (index, app) in targets.enumerated() {
                if Task.isCancelled { break }
                progress = "Checking \(index + 1)/\(targets.count): \(app.name)"
                let result = await checker.check(app, rules: rules)
                if Task.isCancelled { break }
                updates[app.id] = result
            }
            checking = false; await refreshRevisions(); progress = "\(updates.count) update observations/routes · \(apps.count) inventoried"
        }
    }
    func inspect(_ targets: [InstalledApp]) {
        guard !working else { return }
        guard !offline else { progress = "Offline mode skips signing/Gatekeeper commands; local inventory and integrity collection remain available."; return }
        let generation = scanGeneration
        inspecting = true
        operation = Task {
            for (index, app) in targets.enumerated() {
                if Task.isCancelled { break }
                progress = "Inspecting \(index + 1)/\(targets.count): \(app.name)"
                let result = await Task.detached(priority: .utility) { SecurityEvidence.inspect(app) }.value
                if Task.isCancelled || generation != scanGeneration { break }
                evidence[app.id] = result
                integrity[app.id] = await Task.detached(priority: .utility) { IntegrityEvidence.collect(app) }.value
            }
            inspecting = false; await refreshRevisions(); progress = "\(evidence.count) apps inspected · \(apps.count) inventoried"
        }
    }
    func collectIntegrity(_ targets: [InstalledApp]) {
        guard !working else { return }
        inspecting = true
        operation = Task {
            for (index, app) in targets.enumerated() {
                if Task.isCancelled { break }
                progress = "Hashing \(index + 1)/\(targets.count): \(app.name)"
                let value = await Task.detached(priority: .utility) { IntegrityEvidence.collect(app) }.value
                if Task.isCancelled { break }
                integrity[app.id] = value
            }
            inspecting = false; await refreshRevisions(); progress = "\(integrity.count) app integrity records collected"
        }
    }
    func runMonitorNow() {
        guard !working else { return }
        do { try persistMonitorConfiguration() } catch { self.error = error.localizedDescription; return }
        monitorRunning = true; progress = "Running background-style audit; results appear in Monitor…"
        let config = NativeMonitor.configurationURL
        let notify = monitorConfig.notifications
        let worker = Task.detached(priority: .utility) { try await MonitorRunner.run(configurationURL: config) }
        monitorWorker = worker
        operation = Task {
            do {
                let run = try await worker.value
                let note = await MonitorNotifications.deliver(run, enabled: notify)
                MonitorRunner.recordNotification(directory: config.deletingLastPathComponent(), latestFile: run.status.latestFile, message: note)
                progress = run.status.message + " " + note
            } catch is CancellationError { progress = "Audit cancelled; previous completed evidence retained." }
            catch { self.error = error.localizedDescription }
            monitorWorker = nil; monitorRunning = false; refreshMonitor()
        }
    }
    func persistMonitorConfiguration() throws {
        monitorConfig.roots = preferences.folders; monitorConfig.policy = settings.policy; monitorConfig.customRules = settings.customRules
        monitorConfig.exceptions = settings.exceptions; monitorConfig.context = settings.context; monitorConfig.offlineMode = offline
        try NativeMonitor.saveConfiguration(monitorConfig)
    }
    func setMonitorEnabled(_ enabled: Bool) {
        guard !working else { return }
        monitorRunning = true
        Task {
            do {
                if enabled { try persistMonitorConfiguration(); progress = try await NativeMonitor.enable(monitorConfig) }
                else { try await NativeMonitor.disable(); progress = "Scheduled audits disabled." }
            } catch { self.error = error.localizedDescription }
            monitorRunning = false; refreshMonitor()
        }
    }
    func openLatestMonitorAudit() {
        do {
            guard let saved = try MonitorRunner.latest(directory: NativeMonitor.directory) else { throw AuditFileError.invalid("No scheduled audit has completed yet.") }
            baseline = saved; baselineName = "Latest monitor audit"
        } catch { self.error = error.localizedDescription }
    }
    func exportReport(pdf: Bool, saved: Bool = false) {
        guard !working else { return }
        var report = saved ? baseline : snapshot()
        guard report != nil else { error = "Choose a saved audit first."; return }
        var comparison = saved ? nil : baseline
        if redactExports {
            do { let redactor = ShareExport([report!] + (comparison.map { [$0] } ?? [])); report = try redactor.snapshot(report!); comparison = try comparison.map { try redactor.snapshot($0) } }
            catch { self.error = error.localizedDescription; return }
        }
        guard let report else { return }
        let html = HTMLReport.render(report, baseline: comparison, policy: report.policy ?? settings.policy)
        let panel = NSSavePanel(); panel.allowedContentTypes = pdf ? [.pdf] : [.html]; panel.nameFieldStringValue = "App-Audit-Report" + (redactExports ? "-Redacted" : "") + (pdf ? ".pdf" : ".html")
        guard panel.runModal() == .OK, let target = panel.url else { return }
        if pdf {
            renderingPDF = true; let exporter = PDFExporter(); pdfExporter = exporter
            exporter.export(snapshot: report, baseline: comparison, policy: report.policy ?? settings.policy, to: target) { [weak self] result in
                self?.renderingPDF = false; self?.pdfExporter = nil
                if case .failure(let error) = result { self?.error = error.localizedDescription }
                else { self?.progress = "PDF report saved." }
            }
        } else {
            do { try html.write(to: target, atomically: true, encoding: .utf8); progress = "HTML report saved." } catch { self.error = error.localizedDescription }
        }
    }
    func cancel() { scanWorker?.cancel(); operation?.cancel(); monitorWorker?.cancel(); progress = "Stopping after the current bounded inspection/check…" }
    func addFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = true; panel.prompt = "Add scan folders"
        if panel.runModal() == .OK {
            for url in panel.urls where !preferences.folders.contains(url.path) { preferences.folders.append(url.path) }
            savePreferences(); scan()
        }
    }
    func rawSnapshot() -> AuditSnapshot {
        var value = AuditSnapshot(apps: apps, roots: scannedRoots, warnings: warnings, updates: updates, evidence: evidence)
        value.integrity = integrity; value.policy = settings.policy; value.developerLinks = settings.developerLinks
        value.updates = Dictionary(apps.compactMap { app in UpdateRouting.result(app, recorded: updates[app.id]).map { (app.id, $0) } }, uniquingKeysWith: { first, _ in first })
        value.exceptions = settings.exceptions; value.context = settings.context; value.offlineMode = offline; value.revisions = revisions
        return value
    }
    func snapshot() -> AuditSnapshot { var value = rawSnapshot(); value.findings = findings; return value }
    func saveSnapshot() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "App-Audit-" + (redactExports ? "Redacted-" : "") + "\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).json"
        if panel.runModal() == .OK, let url = panel.url {
            do { try exportSnapshot(snapshot()).encoded().write(to: url, options: .atomic); progress = "Saved snapshot: \(url.lastPathComponent)" }
            catch { self.error = error.localizedDescription }
        }
    }
    func loadBaseline() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        panel.prompt = "Use as baseline"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 64_000_000 else { throw AuditFileError.invalid("Snapshot exceeds 64 MB.") }
                baseline = try AuditSnapshot.decode(Data(contentsOf: url)); baselineName = url.lastPathComponent
            } catch { self.error = "Cannot open snapshot: \(error.localizedDescription)" }
        }
    }
    func useCurrentAsBaseline() { baseline = snapshot(); baselineName = "Current audit (in memory)" }
    private func exportSnapshot(_ snapshot: AuditSnapshot) throws -> AuditSnapshot { redactExports ? try ShareExport([snapshot]).snapshot(snapshot) : snapshot }
    private func visibleSnapshot(_ visible: [InstalledApp]) -> AuditSnapshot {
        let appIDs = Set(visible.map(\.id))
        let appPaths = Set(visible.map(\.path))
        var value = AuditSnapshot(
            apps: visible,
            roots: scannedRoots,
            warnings: warnings,
            updates: updates.filter { appIDs.contains($0.key) },
            evidence: evidence.filter { appIDs.contains($0.key) }
        )
        value.integrity = integrity.filter { appIDs.contains($0.key) }
        let linkKeys = Set(visible.map(DeveloperLinks.key))
        value.developerLinks = settings.developerLinks?.filter { linkKeys.contains($0.key) }
        value.revisions = revisions.filter { appIDs.contains($0.key) }
        value.context = settings.context
        value.findings = findings.filter { appPaths.contains($0.path) || $0.path.isEmpty }
        let findingIDs = Set((value.findings ?? []).map(\.id))
        value.exceptions = settings.exceptions?.filter { findingIDs.contains($0.key) }
        return value
    }
    func export(_ visible: [InstalledApp]) {
        do {
            let value = try exportSnapshot(visibleSnapshot(visible))
            saveCSV(CSV.export(value.apps, updates: value.updates, evidence: value.evidence, integrity: value.integrity ?? [:], developerLinks: value.developerLinks ?? [:], revisions: value.revisions ?? [:], findings: value.findings ?? [], context: value.context, asOf: value.captured), name: "App-Audit.csv")
        } catch { self.error = error.localizedDescription }
    }
    func exportJSON(_ visible: [InstalledApp]) {
        do {
            let snapshot = try exportSnapshot(visibleSnapshot(visible))
            let data = try VisibleAppExport(snapshot: snapshot).encoded()
            saveJSON(data, name: "App-Audit.json")
        } catch { self.error = error.localizedDescription }
    }
    func exportBaseline() {
        guard let baseline else { return }
        do { let value = try exportSnapshot(baseline); saveCSV(CSV.export(value.apps, updates: value.updates, evidence: value.evidence, integrity: value.integrity ?? [:], developerLinks: value.developerLinks ?? [:], revisions: value.revisions ?? [:], findings: value.findings ?? [], context: value.context, asOf: value.captured), name: "App-Audit-Saved-Evidence.csv") } catch { self.error = error.localizedDescription }
    }
    func exportChanges() {
        let csv = AuditComparison.csv(changes)
        saveCSV(redactExports ? ShareExport([rawSnapshot()] + (baseline.map { [$0] } ?? [])).text(csv) : csv, name: "App-Audit-Changes.csv")
    }
    private func saveCSV(_ text: String, name: String) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.commaSeparatedText]; panel.nameFieldStringValue = redactExports ? name.replacingOccurrences(of: ".csv", with: "-Redacted.csv") : name
        if panel.runModal() == .OK, let url = panel.url {
            do { try text.write(to: url, atomically: true, encoding: .utf8) }
            catch { self.error = error.localizedDescription }
        }
    }
    private func saveJSON(_ data: Data, name: String) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = redactExports ? name.replacingOccurrences(of: ".json", with: "-Redacted.json") : name
        if panel.runModal() == .OK, let url = panel.url {
            do { try data.write(to: url, options: .atomic) }
            catch { self.error = error.localizedDescription }
        }
    }
}
