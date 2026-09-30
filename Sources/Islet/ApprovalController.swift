import AppKit
import IsletCore
import Observation

/// Pending coding-agent approvals and the card that answers them.
///
/// Each `ask` parks its caller (the held API request) until the user decides, the wait from
/// Settings runs out, a later hook event settles it, or the hook goes away (task cancelled).
/// Nothing runs while cards wait: one-shot work items, no polling.
@MainActor
@Observable
final class ApprovalController {
    private unowned let model: AppModel
    private(set) var queue = ApprovalQueue()
    /// Whether the card is shown. It appears a moment after a request arrives, so the terminal
    /// can print its own prompt first and requests that settle at once never flash a card.
    private(set) var presented = false

    @ObservationIgnored private var waiters: [String: CheckedContinuation<ApprovalDecision?, Never>] = [:]
    @ObservationIgnored private var expiries: [String: DispatchWorkItem] = [:]
    @ObservationIgnored private var showWork: DispatchWorkItem?
    /// Island state to put back when the last card goes; set while cards hold the island open.
    @ObservationIgnored private var restore: (wasOpen: Bool, pinned: Bool)?
    /// The card on top and when it got there. Clicks just after a card appears are ignored, so
    /// the second click of a double-click can't answer the next card before it has been seen.
    @ObservationIgnored private var front: (id: String?, since: Date) = (nil, .distantPast)

    static let arrivalDelay: TimeInterval = 0.25
    static let clickGuard: TimeInterval = 0.5

    init(model: AppModel) {
        self.model = model
    }

    /// The card to show, if any.
    var current: ApprovalQueue.Entry? { presented ? queue.current : nil }
    /// Cards waiting behind the current one.
    var waitingBehind: Int { max(0, queue.count - 1) }

    // MARK: Requests

    func ask(_ request: ApprovalRequest) async -> ApprovalDecision? {
        guard model.settings.approvalsEnabled, !Task.isCancelled else { return nil }
        let id = UUID().uuidString
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (waiter: CheckedContinuation<ApprovalDecision?, Never>) in
                guard queue.enqueue(request, id: id, now: Date()) else { return waiter.resume(returning: nil) }
                waiters[id] = waiter
                let expiry = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated { self?.finish(id, with: nil) }
                }
                expiries[id] = expiry
                DispatchQueue.main.asyncAfter(deadline: .now() + model.settings.approvalWait, execute: expiry)
                scheduleCard()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(id, with: nil) }
        }
    }

    /// A later event made some cards moot (answered in the terminal, turn ended…).
    func settle(_ settlement: ApprovalSettlement) {
        let gone = queue.settle(settlement)
        guard !gone.isEmpty else { return }
        for id in gone {
            expiries.removeValue(forKey: id)?.cancel()
            waiters.removeValue(forKey: id)?.resume(returning: nil)
        }
        queueChanged()
    }

    /// The user's answer from the card.
    func decide(_ decision: ApprovalDecision, for entry: ApprovalQueue.Entry) {
        guard waiters[entry.id] != nil, Date().timeIntervalSince(front.since) >= Self.clickGuard else { return }
        Haptics.play(.tap)
        if decision == .terminal { TerminalJump.jump(entry.request.terminal) }
        if let status = entry.request.statusUpdate(after: decision) { _ = try? model.applyLocal(status) }
        finish(entry.id, with: decision)
    }

    private func finish(_ id: String, with decision: ApprovalDecision?) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        expiries.removeValue(forKey: id)?.cancel()
        if decision == .terminal { queue.handOff(id: id) } else { queue.remove(id: id) }
        waiter.resume(returning: decision)
        queueChanged()
    }

    // MARK: Showing the card

    private func scheduleCard() {
        guard showWork == nil, !(presented && model.expandedScreen != nil) else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.showCard() }
        }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.arrivalDelay, execute: work)
    }

    /// Opens the island (without the hover haptic: nobody asked for it) and keeps it open.
    /// Where the island can't be seen (a fullscreen app, a per-app rule, no island display),
    /// the requests go back to the terminal at once: the hook blocks the agent, and a card
    /// nobody can see would hold it up for the whole wait.
    private func showCard() {
        showWork = nil
        guard !queue.isEmpty else { return }
        presented = true
        noteFront()
        if model.expandedScreen == nil {
            guard let display = Self.islandDisplay(model.settings), model.presentation(for: display) != .hidden else {
                for id in queue.entries.map(\.id) { finish(id, with: nil) }
                return
            }
            if restore == nil { restore = (false, model.pinned) }
            model.pinned = true
            model.expandedScreen = display
            // The island opens under whatever the pointer is doing: guard against a stray click.
            front.since = Date()
            NotificationCenter.default.post(name: .isletLayoutChanged, object: nil)
        } else {
            if restore == nil { restore = (true, model.pinned) }
            model.pinned = true
        }
    }

    /// Restarts the click guard when a different card comes to the top.
    private func noteFront() {
        let id = current?.id
        if id != front.id { front = (id, Date()) }
    }

    private func queueChanged() {
        noteFront()
        guard queue.isEmpty else { return }
        showWork?.cancel()
        showWork = nil
        presented = false
        if let r = restore {
            restore = nil
            if r.wasOpen { model.pinned = r.pinned } else { model.setExpanded(nil) }
        }
    }

    /// Puts the card away. It's still pending and comes back when the island opens.
    func hide() {
        Haptics.play(.tap)
        restore = nil
        model.setExpanded(nil)
    }

    /// The display whose island shows cards (the same choice the app makes for its panels).
    static func islandDisplay(_ s: IsletSettings) -> CGDirectDisplayID? {
        let screens = NSScreen.screens
        var candidates: [NSScreen]
        switch s.displayMode {
        case .allScreens:
            candidates = screens.filter { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } + screens
        case .mainScreen:
            candidates = Array(screens.prefix(1))
        case .notchedScreen:
            candidates = [screens.first { $0.safeAreaInsets.top > 0 } ?? screens.first].compactMap { $0 }
        }
        if !s.showOnNonNotchDisplays { candidates = candidates.filter { $0.safeAreaInsets.top > 0 } }
        return candidates.first?.displayID
    }

    /// Snapshot rendering: show these requests as if they had just arrived.
    func showForSnapshot(_ requests: [ApprovalRequest]) {
        queue = ApprovalQueue()
        for (i, r) in requests.enumerated() { _ = queue.enqueue(r, id: "snapshot-\(i)", now: Date()) }
        presented = !requests.isEmpty
    }
}

// MARK: - Local API backend

extension AppModel {
    nonisolated func handleApproval(_ event: ApprovalEvent) async -> ApprovalDecision? {
        let controller = await MainActor.run { self.approvals }
        switch event {
        case .ask(let request):
            return await controller.ask(request)
        case .settle(let settlement):
            await controller.settle(settlement)
            return nil
        }
    }
}

// MARK: - Jump back to the terminal

/// Brings the agent's terminal forward. Only apps that are already running are activated, and
/// tmux and WezTerm are driven with fixed arguments (no shell), so a hook payload can't launch
/// or run anything else.
@MainActor
enum TerminalJump {
    static func canJump(_ t: TerminalContext) -> Bool { runningHost(t) != nil || t.tmux != nil || t.weztermPane != nil }

    static func runningHost(_ t: TerminalContext) -> NSRunningApplication? {
        guard let id = t.hostBundleID else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).first
    }

    static func jump(_ t: TerminalContext) {
        var commands: [(String, [String])] = []
        if let (socket, pane) = t.tmux, let tmux = executable("tmux") {
            commands.append((tmux, ["-S", socket, "select-window", "-t", pane]))
            commands.append((tmux, ["-S", socket, "select-pane", "-t", pane]))
        }
        if let pane = t.weztermPane, let wezterm = executable("wezterm") {
            commands.append((wezterm, ["cli", "activate-pane", "--pane-id", pane]))
        }
        if !commands.isEmpty {
            DispatchQueue.global(qos: .userInitiated).async {
                for (exe, args) in commands {
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: exe)
                    p.arguments = args
                    p.standardInput = FileHandle.nullDevice
                    p.standardOutput = FileHandle.nullDevice
                    p.standardError = FileHandle.nullDevice
                    guard (try? p.run()) != nil else { continue }
                    p.waitUntilExit()
                }
            }
        }
        if let url = runningHost(t)?.bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
    }

    static func executable(_ name: String) -> String? {
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/run/current-system/sw/bin",
                    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".nix-profile/bin").path]
        return dirs.map { $0 + "/" + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
