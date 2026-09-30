import AppKit
import Foundation
import IsletCore
import IsletSystem
import Observation

/// State of the Ask box: the draft, the streaming answer and follow-up turns. Everything is in
/// memory only. Deltas are batched so the island redraws at most 20 times a second.
@MainActor
@Observable
final class AskController {
    enum Phase: Equatable {
        case idle
        case streaming
        case done
        case stopped
        case refused(String?)
        case failed(String)
    }

    var draft = ""
    /// Provider picked from the chip for this session; nil follows Settings.
    var sessionProvider: AskProviderKind?
    private(set) var phase: Phase = .idle
    private(set) var answer = AskAnswer()
    private(set) var question = ""
    private(set) var usage: AskUsage?
    private(set) var answeredBy: AskProviderKind?
    /// Earlier turns sent with the next question when follow-ups are on.
    private(set) var history: [AskTurn] = []
    /// The Ask field has the keyboard. Only then may the island panel become key.
    private(set) var wantsKeyboard = false
    /// Bumped to move focus into the field.
    private(set) var focusRequest = 0
    private(set) var statuses: [AskProviderKind: AskProviderStatus] = [:]

    @ObservationIgnored let service: AskService
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Tells the current request's events from a stopped one's stragglers.
    @ObservationIgnored private var requestID = 0
    @ObservationIgnored private var coalescer = AskCoalescer()
    @ObservationIgnored private var flushWork: DispatchWorkItem?

    init(service: AskService = AskService()) {
        self.service = service
    }

    var isStreaming: Bool { phase == .streaming }

    func provider(in settings: AskSettings) -> AskProviderKind { sessionProvider ?? settings.provider }

    func status(of kind: AskProviderKind) -> AskProviderStatus { statuses[kind] ?? .ready }

    /// Re-check keys, CLIs and Apple Intelligence (cheap local checks, no network).
    func refreshStatuses() {
        for kind in AskProviderKind.allCases { refreshStatus(kind) }
    }

    private func refreshStatus(_ kind: AskProviderKind) {
        let s = service.status(of: kind)
        if statuses[kind] != s { statuses[kind] = s }
    }

    // MARK: Asking

    func send(settings: AskSettings) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        let kind = provider(in: settings)
        refreshStatus(kind)
        let q = String(text.prefix(AskLimits.questionCharacters))
        let keepHistory = settings.followUps
        let turns = (keepHistory ? history : []) + [.user(q)]
        draft = ""
        question = q
        answer.reset()
        usage = nil
        answeredBy = kind
        phase = .streaming
        coalescer.reset()
        let stream = service.stream(AskRequest(provider: kind, model: settings.model(for: kind), effort: settings.effort, turns: turns))
        task?.cancel()
        requestID &+= 1
        let id = requestID
        task = Task { [weak self] in
            do {
                for try await event in stream {
                    guard let self, self.requestID == id else { return }
                    self.handle(event, turns: turns, keepHistory: keepHistory)
                    if event.isTerminal { break }
                }
            } catch {
                if let self, self.requestID == id { self.fail(error.localizedDescription) }
            }
            guard let self, self.requestID == id, !Task.isCancelled, self.phase == .streaming else { return }
            self.fail("No answer came back.")
        }
    }

    private func handle(_ event: AskEvent, turns: [AskTurn], keepHistory: Bool) {
        guard isStreaming else { return }
        switch event {
        case .text(let s):
            if let now = coalescer.add(s, now: Date()) { answer.append(now) } else { scheduleFlush() }
        case .done(let u):
            flush()
            usage = u
            phase = .done
            if keepHistory, !answer.isEmpty {
                history = Array((turns + [.assistant(answer.shown)]).suffix(AskLimits.followUpTurns))
            }
        case .refusal(let why):
            // A declined answer's partial text isn't an answer.
            flushWork?.cancel()
            flushWork = nil
            coalescer.reset()
            answer.reset()
            phase = .refused(why)
        case .error(let message):
            fail(message)
        }
    }

    private func fail(_ message: String) {
        flush()
        phase = .failed(message)
    }

    private func scheduleFlush() {
        guard flushWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.flushWork = nil
                self?.flush()
            }
        }
        flushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + coalescer.delay(now: Date()), execute: work)
    }

    private func flush() {
        flushWork?.cancel()
        flushWork = nil
        let pending = coalescer.flush(now: Date())
        if !pending.isEmpty { answer.append(pending) }
    }

    func stop() {
        guard isStreaming else { return }
        requestID &+= 1
        task?.cancel()
        task = nil
        flush()
        phase = answer.isEmpty ? .idle : .stopped
    }

    /// Forget the conversation.
    func startOver() {
        stop()
        history = []
        answer.reset()
        question = ""
        usage = nil
        answeredBy = nil
        phase = .idle
    }

    func copyAnswer() {
        guard !answer.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answer.text, forType: .string)
    }

    /// From `islet://ask`: fill in the field and pick the provider. Never sends.
    func prefill(_ query: String?, provider: AskProviderKind?) {
        if let provider { sessionProvider = provider }
        if let query { draft = query }
    }

    // MARK: Keyboard

    func requestKeyboard() {
        wantsKeyboard = true
        focusRequest &+= 1
    }

    func releaseKeyboard() {
        if wantsKeyboard { wantsKeyboard = false }
    }

    /// The island closed: stop the request and hand the keyboard back.
    func islandDidCollapse() {
        stop()
        releaseKeyboard()
    }

    // MARK: Snapshots

    func showForSnapshot(question: String, answer text: String, provider: AskProviderKind, usage: AskUsage?, phase: Phase) {
        self.question = question
        answer.reset()
        answer.append(text)
        self.usage = usage
        answeredBy = provider
        sessionProvider = provider
        statuses[provider] = .ready
        self.phase = phase
    }

    func setStatusForSnapshot(_ status: AskProviderStatus, for kind: AskProviderKind) {
        statuses[kind] = status
    }

    func clearForSnapshot() {
        startOver()
        draft = ""
    }
}
