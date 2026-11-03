import SwiftUI
import AppKit
import AuditCore

@main struct AppAuditApp: App {
    init() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--export-audit"), args.indices.contains(index + 2) {
            do {
                var snapshot = try AuditSnapshot.decode(Data(contentsOf: URL(fileURLWithPath: args[index + 1])))
                if args.contains("--redact") { snapshot = try ShareExport([snapshot]).snapshot(snapshot) }
                let output = URL(fileURLWithPath: args[index + 2])
                let data: Data
                switch output.pathExtension.lowercased() {
                case "json": data = try snapshot.encoded()
                case "html": data = Data(HTMLReport.render(snapshot, baseline: nil, policy: snapshot.policy ?? AuditPolicy()).utf8)
                case "pdf": data = try PDFReport.data(snapshot, baseline: nil, policy: snapshot.policy ?? AuditPolicy())
                case "csv": data = Data(CSV.export(snapshot.apps, updates: snapshot.updates, evidence: snapshot.evidence, integrity: snapshot.integrity ?? [:], developerLinks: snapshot.developerLinks ?? [:], revisions: snapshot.revisions ?? [:], findings: snapshot.findings ?? FindingEngine.evaluate(snapshot, baseline: nil, policy: snapshot.policy ?? AuditPolicy()), context: snapshot.context, asOf: snapshot.captured).utf8)
                default: throw AuditFileError.invalid("Choose a .json, .html, .pdf or .csv output path.")
                }
                try data.write(to: output, options: .atomic)
                print("Exported \(snapshot.apps.count) apps" + (snapshot.redacted == true ? " (redacted)" : "")); exit(0)
            } catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1) }
        }
        if let index = args.firstIndex(of: "--report-pdf"), args.indices.contains(index + 2) {
            do {
                let snapshot = try AuditSnapshot.decode(Data(contentsOf: URL(fileURLWithPath: args[index + 1])))
                let data = try PDFReport.data(snapshot, baseline: nil, policy: snapshot.policy ?? AuditPolicy())
                try data.write(to: URL(fileURLWithPath: args[index + 2]), options: .atomic)
                print("Saved PDF for \(snapshot.apps.count) apps")
                exit(0)
            } catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1) }
        }
        if let index = args.firstIndex(of: "--scheduled-audit"), args.indices.contains(index + 1) {
            let url = URL(fileURLWithPath: args[index + 1])
            Task.detached {
                do {
                    let run = try await MonitorRunner.run(configurationURL: url)
                    let config = try JSONDecoder().decode(MonitorConfiguration.self, from: Data(contentsOf: url)).validated()
                    let notification = await MonitorNotifications.deliver(run, enabled: config.notifications)
                    MonitorRunner.recordNotification(directory: url.deletingLastPathComponent(), latestFile: run.status.latestFile, message: notification)
                    print(run.status.message + " " + notification)
                    exit(0)
                } catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1) }
            }
            RunLoop.current.run()
        }
        if args.contains("--scan-json") {
            let result = Scanner.scan(roots: Scanner.defaultRoots)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(result.apps) { FileHandle.standardOutput.write(data) }
            for warning in result.warnings { FileHandle.standardError.write(Data((warning + "\n").utf8)) }
            exit(0)
        }
        if let index = args.firstIndex(of: "--inspect-json"), args.indices.contains(index + 1) {
            let path = args[index + 1]
            guard let app = Scanner.scan(roots: [URL(fileURLWithPath: path)]).apps.first else { exit(2) }
            let allowed = (try? AuditStorage.loadSettings().offlineMode != true) ?? false
            let result = SecurityEvidence.inspect(app, allowNetwork: allowed)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(result) { FileHandle.standardOutput.write(data) }
            exit(0)
        }
        if let index = args.firstIndex(of: "--snapshot-json"), args.indices.contains(index + 1) {
            do {
                let result = Scanner.scan(roots: Scanner.defaultRoots)
                let snapshot = AuditSnapshot(apps: result.apps, roots: Scanner.defaultRoots.map(\.path), warnings: result.warnings, updates: [:], evidence: [:])
                try snapshot.encoded().write(to: URL(fileURLWithPath: args[index + 1]), options: .atomic)
                print("Saved \(snapshot.apps.count) apps")
                exit(0)
            } catch { FileHandle.standardError.write(Data(error.localizedDescription.utf8)); exit(1) }
        }
        if args.contains("--check-json") {
            let apps = Scanner.scan(roots: Scanner.defaultRoots).apps
            let checker = UpdateChecker()
            Task.detached {
                var results: [String: UpdateResult] = [:]
                for app in apps.filter({ $0.name == "Google Chrome" || $0.name == "Code" || $0.name == "Cursor" }).prefix(3) { results[app.name] = await checker.check(app, allowNetwork: (try? AuditStorage.loadSettings().offlineMode != true) ?? false) }
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
                if let data = try? encoder.encode(results) { FileHandle.standardOutput.write(data) }
                exit(results.isEmpty ? 2 : 0)
            }
            RunLoop.current.run()
        }
    }
    var body: some Scene {
        WindowGroup("Xtracsys · App Audit") {
            ContentView().frame(minWidth: 1050, minHeight: 650)
                .tint(Color(red: 178 / 255, green: 70 / 255, blue: 48 / 255))
                .accentColor(Color(red: 178 / 255, green: 70 / 255, blue: 48 / 255))
        }
        .defaultSize(width: 1420, height: 850)
        .commands { CommandGroup(replacing: .appInfo) { Button("About Xtracsys App Audit") {
            var options: [NSApplication.AboutPanelOptionKey: Any] = [.applicationName: "Xtracsys App Audit", .credits: NSAttributedString(string: "Local inventory, integrity evidence and version review.\nRead-only audits. No automatic app installation.")]
            if let data = Brand.logoData, let logo = NSImage(data: data) { options[.applicationIcon] = logo }
            NSApplication.shared.orderFrontStandardAboutPanel(options: options)
        } } }
    }
}
