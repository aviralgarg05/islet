import Foundation
@_weakLinked import FoundationModels
import IsletCore

/// Ask answers from Apple's on-device model (macOS 26+, Apple Intelligence on and downloaded).
/// Nothing leaves the Mac. The context is small (about 4k tokens), so follow-ups are trimmed hard.
enum OnDeviceAsk {
    static var status: AskProviderStatus {
        guard #available(macOS 26, *) else { return .unavailable(AskProviderStatus.onDeviceReason("needsNewerMacOS")) }
        switch SystemLanguageModel.default.availability {
        case .available: return .ready
        case .unavailable(let reason): return .unavailable(AskProviderStatus.onDeviceReason(String(describing: reason)))
        @unknown default: return .unavailable(AskProviderStatus.onDeviceReason(""))
        }
    }

    static func run(_ turns: [AskTurn], emit: @Sendable (AskEvent) -> Void) async {
        guard #available(macOS 26, *) else {
            emit(.error(status.message(for: .onDevice)))
            return
        }
        await stream(turns, emit: emit)
    }

    @available(macOS 26, *)
    private static func stream(_ turns: [AskTurn], emit: @Sendable (AskEvent) -> Void) async {
        let current = status
        guard current.isReady else {
            emit(.error(current.message(for: .onDevice)))
            return
        }
        let session = LanguageModelSession(instructions: AskPrompt.system)
        let prompt = AskPrompt.flattened(Array(AskPrompt.normalized(turns, maxEarlier: 2)))
        var shown = 0
        do {
            // Snapshots are cumulative: each holds the whole answer so far.
            for try await snapshot in session.streamResponse(to: prompt) {
                let text = snapshot.content
                if text.count > shown {
                    emit(.text(String(text.dropFirst(shown))))
                    shown = text.count
                }
            }
            emit(.done(AskUsage(model: "Apple on-device model")))
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            emit(event(for: error))
        }
    }

    private static func event(for error: Error) -> AskEvent {
        if #available(macOS 27, *), let e = error as? LanguageModelError {
            switch e {
            case .refusal, .guardrailViolation: return .refusal(nil)
            case .contextSizeExceeded: return .error("That's too long for the on-device model. Try a shorter question or another provider.")
            case .rateLimited: return .error("The on-device model is busy. Try again in a moment.")
            case .unsupportedLanguageOrLocale: return .error("The on-device model doesn't support this language yet.")
            case .timeout: return .error("The on-device model took too long to answer.")
            default: break
            }
        }
        // macOS 26 reports the same cases through the older error type.
        let name = String(describing: error)
        if name.contains("refusal") || name.contains("guardrailViolation") { return .refusal(nil) }
        if name.contains("exceededContextWindowSize") {
            return .error("That's too long for the on-device model. Try a shorter question or another provider.")
        }
        return .error("The on-device model failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
    }
}
