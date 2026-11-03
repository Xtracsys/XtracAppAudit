import SwiftUI
import AuditCore

struct MonitorView: View {
    @Bindable var model: AuditModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Scheduled audits & alerts").font(.title2.bold()); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            if model.offline { Label("Global offline mode is on: scheduled online and trust checks are skipped.", systemImage: "wifi.slash").font(.callout) }
            Label(model.monitorEnabled ? "Daily schedule installed" : "Schedule disabled", systemImage: model.monitorEnabled ? "clock.badge.checkmark" : "clock")
            Form {
                HStack { Stepper("Hour: \(model.monitorConfig.hour)", value: $model.monitorConfig.hour, in: 0...23); Stepper("Minute: \(model.monitorConfig.minute)", value: $model.monitorConfig.minute, in: 0...59) }
                Toggle("Check online update sources", isOn: $model.monitorConfig.checkUpdates)
                Toggle("Inspect signing, Gatekeeper and receipts", isOn: $model.monitorConfig.inspectSecurity)
                Toggle("Notify about new meaningful changes", isOn: $model.monitorConfig.notifications)
            }.disabled(model.working)
            Text("Runs at the selected daily local time, including when this window is closed. Current scan folders, context, policy and custom publisher rules are copied when you save/enable or run now. Current exception decisions and global offline mode are read at run time. Integrity hashes are always collected. Online checks contact vendor feeds; Gatekeeper may contact Apple.").font(.callout).foregroundStyle(.secondary)
            Text("First audit creates a quiet baseline. Later alerts summarize newly observed apps, comparable integrity/publisher changes, verified updates and new actionable findings. Unchanged unknowns stay quiet; missing-app alerts are suppressed for incomplete or changed scan scopes.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(model.monitorEnabled ? "Apply daily schedule" : "Enable daily audits") { model.setMonitorEnabled(true) }
                Button("Disable schedule") { model.setMonitorEnabled(false) }.disabled(!model.monitorEnabled)
                Button("Save options") { do { try model.persistMonitorConfiguration(); model.progress = "Monitor options saved; apply schedule to change its time." } catch { model.error = error.localizedDescription } }
                Spacer(); Button("Run audit now") { model.runMonitorNow() }
            }.disabled(model.working)
            if model.monitorRunning { HStack { ProgressView("Audit or schedule operation in progress…"); if model.canStop { Button("Stop current audit") { model.cancel() } } } }
            Divider()
            if let status = model.monitorStatus {
                Text("Last attempt: \(status.completed.formatted())").font(.headline)
                Text(status.message)
                Text("\(status.appCount) apps · \(status.findingCount) findings · \(status.newEventCount) new alert events")
                if let note = status.notification { Text(note).font(.caption).foregroundStyle(.secondary) }
                if let error = status.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                HStack { Button("Review latest saved audit") { model.openLatestMonitorAudit(); dismiss() }; Button("Refresh status") { model.refreshMonitor() } }
            } else { Text("No background-style audit has completed yet.").foregroundStyle(.secondary) }
            Text("History retains up to 30 audits including the last complete baseline. Keep the app at its current location for the LaunchAgent to run; an external drive must stay available. Notification permission is requested only when enabling notifications. No schedule is installed until you enable it.").font(.caption).foregroundStyle(.secondary)
            Text("Data: \(NativeMonitor.directory.path)").font(.caption2).textSelection(.enabled)
        }.padding(24).frame(width: 800, height: 640).onAppear { model.refreshMonitor() }
    }
}
