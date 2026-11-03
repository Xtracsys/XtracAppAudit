import SwiftUI
import AuditCore

struct AuditContextView: View {
    @Bindable var model: AuditModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = AuditContext()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Audit context").font(.title2.bold()); Spacer(); Button("Cancel") { dismiss() } }
            TextField("Client / organisation", text: $draft.client)
            TextField("Site / device label", text: $draft.site)
            TextField("Auditor", text: $draft.auditor)
            Text("Audit notes").font(.headline)
            TextEditor(text: $draft.notes).accessibilityLabel("Audit notes").frame(height: 140).border(.secondary.opacity(0.3))
            Text("Included in snapshots and reports. Redacted exports omit this context because names and free text may identify a client.").font(.caption).foregroundStyle(.secondary)
            Button("Save context") { var settings = model.settings; settings.context = draft; model.saveSettings(settings); if model.error == nil { dismiss() } }.keyboardShortcut(.defaultAction)
        }.textFieldStyle(.roundedBorder).padding(24).frame(width: 650)
        .onAppear { draft = model.settings.context ?? AuditContext() }
    }
}
struct ExceptionEditor: View {
    @Bindable var model: AuditModel
    let finding: AuditFinding
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var reviewer = ""
    @State private var hasExpiry = true
    @State private var expiry = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Document an exception").font(.title2.bold()); Spacer(); Button("Cancel") { dismiss() } }
            Text(finding.app + " · " + finding.title).font(.headline)
            Text("The finding stays visible. This decision applies to its exact evidence; changed evidence, expiry or revocation requires review again.").font(.callout).foregroundStyle(.secondary)
            Text("Reason / compensating controls (required)").font(.headline)
            TextEditor(text: $reason).accessibilityLabel("Exception reason, required").frame(height: 130).border(.secondary.opacity(0.3))
            TextField("Reviewer (required)", text: $reviewer).textFieldStyle(.roundedBorder)
            Toggle("Set expiry", isOn: $hasExpiry)
            if hasExpiry { DatePicker("Expires", selection: $expiry, in: Date()..., displayedComponents: [.date, .hourAndMinute]) }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                if var existing = model.settings.exceptions?[finding.id] {
                    Button("Revoke exception") { existing.revoked = Date(); do { try model.saveException(existing, for: finding); dismiss() } catch { self.error = error.localizedDescription } }
                }
                Spacer(); Button("Save exception") {
                    do { try model.saveException(FindingException(finding: finding, reason: reason, reviewer: reviewer, expires: hasExpiry ? expiry : nil), for: finding); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 700)
        .onAppear { if let old = model.settings.exceptions?[finding.id] { reason = old.reason; reviewer = old.reviewer; hasExpiry = old.expires != nil; if let date = old.expires { expiry = max(date, Date()) } } else { reviewer = model.settings.context?.auditor ?? "" } }
    }
}
struct ExceptionRegister: View {
    @Bindable var model: AuditModel
    @Environment(\.dismiss) private var dismiss
    @State private var filter = "All"
    @State private var reviewing: AuditFinding?
    private let filters = ["All"] + ExceptionReviewBucket.allCases.map(\.rawValue)
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let decisions = model.settings.exceptions ?? [:]
            let findings = Dictionary(model.findings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let keys = decisions.keys.sorted {
                let left = decisions[$0]!, right = decisions[$1]!
                let lb = ExceptionReviewBucket.classify(left, finding: findings[$0], now: context.date)
                let rb = ExceptionReviewBucket.classify(right, finding: findings[$1], now: context.date)
                let li = ExceptionReviewBucket.allCases.firstIndex(of: lb)!, ri = ExceptionReviewBucket.allCases.firstIndex(of: rb)!
                if li != ri { return li < ri }
                if left.expires != right.expires { return (left.expires ?? .distantFuture) < (right.expires ?? .distantFuture) }
                return $0 < $1
            }
            let visible = keys.filter { filter == "All" || ExceptionReviewBucket.classify(decisions[$0]!, finding: findings[$0], now: context.date).rawValue == filter }
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text("Exception review queue").font(.title2.bold()); Spacer(); Button("Done") { dismiss() } }
                Text("Overdue means the recorded expiry has passed. Upcoming means within 30 days. Changed evidence requires review immediately. An absent finding is not proof of resolution. Saved audits retain decisions at capture time; this is not a tamper-proof history.").font(.caption).foregroundStyle(.secondary)
                Picker("Show", selection: $filter) {
                    ForEach(filters, id: \.self) { name in
                        let count = keys.filter { name == "All" || ExceptionReviewBucket.classify(decisions[$0]!, finding: findings[$0], now: context.date).rawValue == name }.count
                        Text("\(name) (\(count))").tag(name)
                    }
                }
                ScrollView { LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(visible, id: \.self) { key in
                        if let value = decisions[key] {
                            let bucket = ExceptionReviewBucket.classify(value, finding: findings[key], now: context.date)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(bucket.rawValue).font(.headline).foregroundStyle(bucket == .overdue || bucket == .changed ? Color.orange : Color.secondary)
                                if let finding = findings[key] {
                                    Text(finding.app + " · " + finding.title).bold()
                                    Text(value.status(for: finding, now: context.date)).font(.caption)
                                    DisclosureGroup("Finding evidence and next step") { Text(finding.evidence); Text(finding.nextStep) }
                                    Button("Review / renew exception…") { reviewing = finding }
                                } else { Text("Finding not present in current scan").bold(); Text(key).font(.caption) }
                                Text(value.description).font(.callout)
                                Button("Revoke") { var updated = value; updated.revoked = Date(); var settings = model.settings; settings.exceptions?[key] = updated; model.saveSettings(settings) }.disabled(value.revoked != nil)
                            }; Divider()
                        }
                    }
                    if visible.isEmpty { Text(decisions.isEmpty ? "No exceptions recorded. Select a finding in the Findings dashboard to add a reason and optional expiry." : "No exceptions in this view.") }
                } }.textSelection(.enabled)
            }.padding(24).frame(width: 850, height: 650)
        }
        .sheet(item: $reviewing) { finding in ExceptionEditor(model: model, finding: finding) }
    }
}
