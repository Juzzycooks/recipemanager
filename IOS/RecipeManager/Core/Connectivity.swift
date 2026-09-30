import Foundation
import Network
import Observation

/// Whether we can talk to the server: the network path, plus whether the last request actually got through
/// (a home server can be unreachable while Wi-Fi is fine). While offline it probes the server until it answers.
@MainActor @Observable
final class Connectivity {
    static let shared = Connectivity()

    private(set) var pathOnline = true
    private(set) var serverReachable = true
    var isOffline: Bool { !pathOnline || !serverReachable }

    /// Called when we go from offline to online (replay queued changes, sync).
    var onRegained: (() -> Void)?
    /// Asks the server whether it is back; set by `Session`.
    var probe: (@Sendable () async -> Bool)?

    private let monitor = NWPathMonitor()
    private var probing: Task<Void, Never>?

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.setPath(online) }
        }
        monitor.start(queue: DispatchQueue(label: "connectivity"))
    }

    func setReachable(_ reachable: Bool) {
        let wasOffline = isOffline
        serverReachable = reachable
        update(wasOffline: wasOffline)
    }

    private func setPath(_ online: Bool) {
        let wasOffline = isOffline
        pathOnline = online
        update(wasOffline: wasOffline)
    }

    private func update(wasOffline: Bool) {
        if wasOffline && !isOffline {
            probing?.cancel(); probing = nil
            onRegained?()
        } else if !wasOffline && isOffline {
            startProbing()
        }
    }

    private func startProbing() {
        probing?.cancel()
        probing = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self, !Task.isCancelled, self.isOffline else { return }
                if self.pathOnline, let probe = self.probe, await probe() { self.setReachable(true); return }
            }
        }
    }
}
