import Foundation

extension APIRouter {
    /// Longest `?wait=` accepted, in seconds.
    public static let maxApprovalWait = 3600

    /// The approvals part of `POST /v1/hooks/{provider}`.
    ///
    /// Every event may settle stale cards. With `?wait=N` the request is a blocking hook: the
    /// status is still mapped, and if the payload asks for a decision the backend shows a card
    /// and the request is held for up to N seconds. The reply is then exactly what the hook
    /// prints: 200 with the decision JSON, or 204 for none. Returns nil when the plain status
    /// mapping should answer. Nothing here accepts a decision; answers come only from the app.
    func approvalHook(_ r: HTTPRequest, provider: String) async -> HTTPResponse? {
        // The local-network bridge never takes part in approvals.
        guard !allowRemoteHosts else { return nil }
        if let settlement = ApprovalSettlement.parse(provider: provider, payload: r.body) {
            _ = await backend.handleApproval(.settle(settlement))
        }
        guard let raw = r.query["wait"] else { return nil }
        guard let wait = Int(raw), (1...Self.maxApprovalWait).contains(wait) else {
            return .error(400, "'wait' must be a whole number of seconds from 1 to \(Self.maxApprovalWait)")
        }
        // The hook prints whatever comes back, so the activity JSON is never returned here.
        switch try? AgentHooks.map(provider: provider, payload: r.body, now: clock()) {
        case .upsert(let spec): _ = try? await backend.applyActivity(spec)
        case .remove(let id): _ = await backend.removeActivity(id: id)
        case .ignore, nil: break
        }
        guard let request = ApprovalRequest.parse(provider: provider, payload: r.body) else { return .noContent }
        let backend = self.backend
        let decision = await Self.first(within: TimeInterval(wait)) { await backend.handleApproval(.ask(request)) }
        guard let decision, let body = ApprovalOutput.encode(decision, for: request) else { return .noContent }
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json; charset=utf-8"], body: body)
    }

    /// Runs `operation` for at most `seconds`, then cancels it and returns nil.
    static func first<T: Sendable>(within seconds: TimeInterval, _ operation: @escaping @Sendable () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
}
