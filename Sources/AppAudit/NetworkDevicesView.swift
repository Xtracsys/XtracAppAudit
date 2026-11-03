import SwiftUI
import AuditCore

struct NetworkDevicesView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var discovery: NetworkDeviceDiscovery

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Network devices").font(.title2.bold())
                    Text("Bonjour services advertised on your local network").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                statusLabel
            }

            Group {
                switch discovery.state {
                case .idle:
                    ContentUnavailableView("Discovery is off", systemImage: "wifi.slash", description: Text("Turn on Find network devices to look for Bonjour services."))
                case .browsing:
                    if discovery.services.isEmpty {
                        ContentUnavailableView("Looking for services", systemImage: "dot.radiowaves.left.and.right", description: Text("No supported Bonjour advertisements have appeared yet. This does not mean the network has no devices."))
                    } else {
                        List(discovery.services) { service in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(service.name).font(.headline)
                                Text(service.type + " · " + service.domain)
                                    .font(.caption).foregroundStyle(.secondary)
                                if let interfaceName = service.interfaceName {
                                    Text("Network interface: " + interfaceName).font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                case .accessDenied:
                    ContentUnavailableView(
                        "Local network access is off",
                        systemImage: "lock.slash",
                        description: Text("Allow App Audit in System Settings → Privacy & Security → Local Network, then turn discovery off and on to try again.")
                    )
                case .failed(let message):
                    ContentUnavailableView(
                        "Bonjour discovery could not start",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("Bonjour only shows services using supported types. Several services can belong to one device, and quiet devices may not appear. App Audit does not probe network addresses, inspect remote apps, or save these results. Turning discovery off clears them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(minWidth: 560, minHeight: 440)
    }

    @ViewBuilder private var statusLabel: some View {
        switch discovery.state {
        case .idle:
            Label("Off", systemImage: "wifi.slash").foregroundStyle(.secondary)
        case .browsing:
            Label("Searching", systemImage: "dot.radiowaves.left.and.right").foregroundStyle(.tint)
        case .accessDenied:
            Label("Permission needed", systemImage: "lock.slash").foregroundStyle(.orange)
        case .failed:
            Label("Unavailable", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
    }
}
