import Foundation
import Network
import Observation

public struct DiscoveredNetworkService: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let type: String
    public let domain: String
    public let interfaceName: String?
}

public enum NetworkDiscoveryState: Equatable, Sendable {
    case idle
    case browsing
    case accessDenied
    case failed(String)
}

@MainActor @Observable public final class NetworkDeviceDiscovery {
    public static let serviceTypes = [
        "_workstation._tcp",
        "_device-info._tcp",
        "_ssh._tcp",
        "_smb._tcp",
        "_ipp._tcp",
        "_ipps._tcp",
        "_printer._tcp",
        "_airplay._tcp",
        "_raop._tcp",
        "_googlecast._tcp"
    ]

    public private(set) var services: [DiscoveredNetworkService] = []
    public private(set) var state: NetworkDiscoveryState = .idle

    @ObservationIgnored private var browsers: [String: NWBrowser] = [:]
    @ObservationIgnored private var states: [String: NWBrowser.State] = [:]
    @ObservationIgnored private var failures: [String: String] = [:]
    @ObservationIgnored private var servicesByType: [String: [String: DiscoveredNetworkService]] = [:]

    public init() {}

    public func start() {
        guard browsers.isEmpty else { return }
        states.removeAll()
        failures.removeAll()
        servicesByType.removeAll()
        services = []
        state = .browsing

        for type in Self.serviceTypes {
            let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: .tcp)
            browsers[type] = browser
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                Task { @MainActor [weak self] in
                    self?.update(results, for: type)
                }
            }
            browser.stateUpdateHandler = { [weak self] browserState in
                Task { @MainActor [weak self] in
                    self?.update(browserState, for: type)
                }
            }
            browser.start(queue: .main)
        }
    }

    public func stop() {
        cancelBrowsers()
        services = []
        state = .idle
    }

    private func cancelBrowsers() {
        for browser in browsers.values { browser.cancel() }
        browsers.removeAll()
        states.removeAll()
        failures.removeAll()
        servicesByType.removeAll()
    }

    private func update(_ results: Set<NWBrowser.Result>, for type: String) {
        guard browsers[type] != nil else { return }
        var current: [String: DiscoveredNetworkService] = [:]
        for result in results {
            guard case let .service(name, serviceType, domain, interface) = result.endpoint else { continue }
            let interfaceName = interface?.name
            let id = [serviceType, name, domain, interfaceName ?? ""].joined(separator: "|")
            current[id] = DiscoveredNetworkService(
                id: id,
                name: name,
                type: serviceType,
                domain: domain,
                interfaceName: interfaceName
            )
        }
        servicesByType[type] = current
        services = servicesByType.values.flatMap(\.values).sorted {
            let nameOrder = $0.name.localizedCaseInsensitiveCompare($1.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            if $0.type != $1.type { return $0.type < $1.type }
            return $0.domain < $1.domain
        }
    }

    private func update(_ browserState: NWBrowser.State, for type: String) {
        guard browsers[type] != nil else { return }
        states[type] = browserState

        switch browserState {
        case .waiting(let error), .failed(let error):
            if isLocalNetworkAccessDenied(error) {
                cancelBrowsers()
                services = []
                state = .accessDenied
                return
            }
            failures[type] = error.localizedDescription
        case .ready:
            failures.removeValue(forKey: type)
        case .setup, .cancelled:
            break
        @unknown default:
            failures[type] = "An unrecognized Bonjour browser state occurred."
        }

        let ready = states.values.contains { if case .ready = $0 { return true }; return false }
        let allFailed = states.count == Self.serviceTypes.count && failures.count == Self.serviceTypes.count
        if ready || !allFailed {
            state = .browsing
        } else {
            state = .failed(failures.values.sorted().first ?? "Bonjour discovery could not start.")
        }
    }

    private func isLocalNetworkAccessDenied(_ error: NWError) -> Bool {
        guard case let .dns(code) = error else { return false }
        return Int(code) == kDNSServiceErr_PolicyDenied
    }
}
