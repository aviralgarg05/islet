import Foundation
import IsletCore
import IsletSystem
import Observation

/// The iPhone bridge: a second listener, on the local network, with its own token and only the
/// routes Shortcuts needs (`APIScope.lan`). It is plain HTTP, so the token can be read by anyone
/// on the same Wi-Fi; the narrow routes keep that from reaching anything else.
@MainActor
@Observable
final class LANBridge {
    private(set) var status = "Off"
    /// Loaded when the bridge starts or Settings shows it.
    private(set) var token: String?
    @ObservationIgnored private var server: LocalAPIServer?
    @ObservationIgnored private var backend: (any IsletBackend)?
    @ObservationIgnored private var version = ""

    /// Neutral, so the network doesn't learn the Mac's name from Islet.
    static let bonjourName = "Islet"

    func start(port: Int, backend: any IsletBackend, version: String) {
        guard server == nil else { return }
        self.backend = backend
        self.version = version
        let server = LocalAPIServer.localNetwork(router: router(token: loadToken(), backend: backend))
        self.server = server
        server.start(port: UInt16(port), onAllInterfaces: true, bonjourName: Self.bonjourName) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let p): self?.status = "Listening on \(ProcessInfo.processInfo.hostName):\(p)"
                case .failure(let e): self?.status = "Could not listen: \(e.localizedDescription)"
                }
            }
        }
    }

    func stop() {
        server?.stop()
        server = nil
        status = "Off"
    }

    @discardableResult
    func loadToken() -> String {
        if let token { return token }
        let loaded = LANTokenStore.loadOrCreate(distinctFrom: APIDiscoveryStore.read()?.token)
        token = loaded
        return loaded
    }

    /// A new token. The old one stops working at once; the listener keeps running.
    func rotateToken() {
        let fresh = LANTokenStore.rotate(distinctFrom: APIDiscoveryStore.read()?.token)
        token = fresh
        if let server, let backend { server.update(router: router(token: fresh, backend: backend)) }
    }

    private func router(token: String, backend: any IsletBackend) -> APIRouter {
        APIRouter(token: token, version: version, backend: backend, scope: .lan)
    }
}
