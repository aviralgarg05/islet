import AppKit
import Foundation
@_weakLinked import FoundationModels
import IsletCore

/// Optional on-device intelligence through Apple's Foundation Models (macOS 26+, Apple
/// Intelligence enabled). Used to pick icons for activities the keyword engine can't place and
/// to condense long notifications into one line. Everything stays on the Mac; when the model is
/// unavailable every call returns nil immediately and Islet falls back to its rules.
public final class AIAssist {
    public static let shared = AIAssist()

    private var symbolCache: [String: String] = [:]
    private var inFlight: Set<String> = []

    public var isAvailable: Bool {
        guard #available(macOS 26, *) else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Human-readable status for Settings.
    public var statusText: String {
        guard #available(macOS 26, *) else { return "Needs macOS 26 or later" }
        switch SystemLanguageModel.default.availability {
        case .available: return "Ready (on-device)"
        case .unavailable(let reason): return "Unavailable: \(reason)"
        @unknown default: return "Unavailable"
        }
    }

    /// Suggest an SF Symbol for a short piece of text. The model picks one of
    /// `IconCategory.names` through structured output, so the answer is always one Islet knows.
    public func suggestSymbol(for text: String, completion: @escaping (String?) -> Void) {
        let key = String(text.prefix(120)).lowercased()
        if let cached = symbolCache[key] { return completion(cached) }
        guard isAvailable, !inFlight.contains(key), #available(macOS 26, *) else { return completion(nil) }
        inFlight.insert(key)
        Task { @MainActor in
            defer { self.inFlight.remove(key) }
            let symbol = await Self.category(for: text).flatMap(IconCategory.symbol(for:))
            guard let symbol, NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil else {
                completion(nil)
                return
            }
            if self.symbolCache.count >= 256 { self.symbolCache.removeAll() }
            self.symbolCache[key] = symbol
            completion(symbol)
        }
    }

    @available(macOS 26, *)
    private static func category(for text: String) async -> String? {
        let choice = DynamicGenerationSchema(name: "Category", anyOf: IconCategory.names)
        let root = DynamicGenerationSchema(name: "Icon", properties: [.init(name: "category", schema: choice)])
        guard let schema = try? GenerationSchema(root: root, dependencies: []) else { return nil }
        let session = LanguageModelSession(
            model: SystemLanguageModel(useCase: .contentTagging),
            instructions: "Pick the category that best describes a short status message from an app or script."
        )
        guard let reply = try? await session.respond(to: "Message: \(text)", schema: schema, includeSchemaInPrompt: false) else {
            return nil
        }
        return try? reply.content.value(String.self, forProperty: "category")
    }

    /// Condense a long notification into one short line.
    public func summarize(_ text: String, completion: @escaping (String?) -> Void) {
        guard isAvailable, text.count > 90, #available(macOS 26, *) else { return completion(nil) }
        Task { @MainActor in
            // The text is the user's own notification: transforming it shouldn't trip the guardrails
            // meant for open-ended generation.
            let session = LanguageModelSession(
                model: SystemLanguageModel(guardrails: .permissiveContentTransformations),
                instructions: "Summarize the notification in at most 12 words. Plain text, no quotes."
            )
            let reply = try? await session.respond(to: text).content
            completion(reply.flatMap { AISanitizer.summary(from: $0) })
        }
    }
}
