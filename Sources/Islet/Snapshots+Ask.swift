import Foundation
import IsletCore

extension Snapshots {
    /// The Ask tab: not ready, empty, missing key, answered, streaming and failed.
    static func renderAsk(model: AppModel, shoot: (String) -> Void, size: (SizePreset) -> Void) {
        let ask = model.ask
        model.forcedPresentation = .expanded
        model.tab = .ask
        ask.clearForSnapshot()
        for kind in AskProviderKind.allCases { ask.setStatusForSnapshot(.ready, for: kind) }

        ask.sessionProvider = .onDevice
        ask.setStatusForSnapshot(.unavailable(AskProviderStatus.onDeviceReason("modelNotReady")), for: .onDevice)
        shoot("22-expanded-ask-unavailable")

        ask.sessionProvider = .anthropic
        shoot("23-expanded-ask-empty")

        ask.sessionProvider = .openai
        ask.setStatusForSnapshot(.needsKey, for: .openai)
        shoot("24-expanded-ask-needs-key")

        ask.showForSnapshot(
            question: "What does git rebase --onto do?",
            answer: "It moves a range of commits onto a new base. `git rebase --onto main feature~3 feature` takes the last three commits of **feature** and replays them on top of **main**, leaving out anything older. Handy when a branch was cut from the wrong place.",
            provider: .anthropic, usage: AskUsage(model: "claude-opus-5-5", inputTokens: 58, outputTokens: 71), phase: .done)
        ask.draft = "And how do I undo it?"
        shoot("25-expanded-ask-answer")
        // The same answer with room for more of it.
        size(.standard)
        shoot("25c-expanded-ask-answer-standard")
        size(.compact)
        increasedContrast = true
        shoot("86-contrast-ask-answer")
        increasedContrast = false

        ask.draft = ""
        ask.showForSnapshot(question: "Summarise the difference between TCP and QUIC", answer: "QUIC runs over UDP and builds in TLS 1.3, so a connection",
                            provider: .claudeCode, usage: nil, phase: .streaming)
        shoot("26-expanded-ask-streaming")

        ask.showForSnapshot(question: "Hello", answer: "", provider: .anthropic, usage: nil,
                            phase: .failed(AskErrorText.http(status: 401, body: Data(), retryAfter: nil, provider: .anthropic), needsKey: true))
        shoot("27-expanded-ask-error")

        ask.clearForSnapshot()
        ask.sessionProvider = nil
        model.tab = .home
    }
}
