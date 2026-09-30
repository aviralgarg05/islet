import Foundation

/// The categories the on-device model chooses from when the keyword rules can't place an
/// activity. Asking for a category rather than a symbol name means every answer is valid:
/// structured output limits the model to these names, and each maps to a symbol that exists
/// on macOS 14.
public enum IconCategory {
    public static let all: [(name: String, symbol: String)] = [
        ("flight", "airplane"),
        ("ride", "car.fill"),
        ("food delivery", "takeoutbag.and.cup.and.straw.fill"),
        ("parcel", "shippingbox.fill"),
        ("shopping", "cart.fill"),
        ("money", "creditcard.fill"),
        ("build", "hammer.fill"),
        ("tests", "checkmark.seal.fill"),
        ("deploy", "paperplane.fill"),
        ("code", "chevron.left.forwardslash.chevron.right"),
        ("database", "cylinder.split.1x2.fill"),
        ("server", "server.rack"),
        ("download", "arrow.down.circle.fill"),
        ("upload", "arrow.up.circle.fill"),
        ("sync", "arrow.triangle.2.circlepath"),
        ("backup", "externaldrive.fill"),
        ("security", "lock.fill"),
        ("ai", "sparkles"),
        ("music", "music.note"),
        ("video", "play.rectangle.fill"),
        ("podcast", "mic.fill"),
        ("call", "phone.fill"),
        ("meeting", "video.fill"),
        ("message", "message.fill"),
        ("email", "envelope.fill"),
        ("calendar", "calendar"),
        ("reminder", "bell.fill"),
        ("timer", "timer"),
        ("workout", "figure.run"),
        ("health", "heart.fill"),
        ("weather", "cloud.sun.fill"),
        ("sports", "sportscourt.fill"),
        ("game", "gamecontroller.fill"),
        ("news", "newspaper.fill"),
        ("document", "doc.fill"),
        ("photo", "photo.fill"),
        ("print", "printer.fill"),
        ("home", "house.fill"),
        ("food", "fork.knife"),
        ("travel", "suitcase.fill"),
        ("learning", "graduationcap.fill"),
        ("warning", "exclamationmark.triangle.fill"),
        ("other", ""),
    ]

    public static var names: [String] { all.map(\.name) }

    /// The symbol for a category the model picked; nil for "other" or anything unknown.
    public static func symbol(for name: String) -> String? {
        let key = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let s = all.first(where: { $0.name == key })?.symbol, !s.isEmpty else { return nil }
        return s
    }
}
