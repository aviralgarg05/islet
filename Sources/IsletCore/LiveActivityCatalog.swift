import Foundation

/// Icon, colour and layout for apps known to publish Live Activities, so a mirrored activity
/// looks like its app rather than a generic pill. Keys are lowercased app names and aliases.
public enum LiveActivityCatalog {
    public struct Look: Equatable, Sendable {
        public var symbol: String
        public var tint: String
    }

    static let entries: [String: Look] = [
        // Apple
        "clock": Look(symbol: "timer", tint: "#FF9F0A"),
        "timer": Look(symbol: "timer", tint: "#FF9F0A"),
        "stopwatch": Look(symbol: "stopwatch.fill", tint: "#FF9F0A"),
        "alarm": Look(symbol: "alarm.fill", tint: "#FF9F0A"),
        "phone": Look(symbol: "phone.fill", tint: "#30D158"),
        "facetime": Look(symbol: "video.fill", tint: "#30D158"),
        "maps": Look(symbol: "arrow.triangle.turn.up.right.diamond.fill", tint: "#0A84FF"),
        "music": Look(symbol: "music.note", tint: "#FF375F"),
        "podcasts": Look(symbol: "mic.fill", tint: "#BF5AF2"),
        "fitness": Look(symbol: "figure.run", tint: "#A2F92F"),
        "workout": Look(symbol: "figure.run", tint: "#A2F92F"),
        "voice memos": Look(symbol: "waveform", tint: "#FF453A"),
        "shortcuts": Look(symbol: "square.stack.3d.up.fill", tint: "#5E5CE6"),
        "wallet": Look(symbol: "wallet.pass.fill", tint: "#0A84FF"),
        "find my": Look(symbol: "location.fill", tint: "#30D158"),
        "sports": Look(symbol: "sportscourt.fill", tint: "#30D158"),
        "tv": Look(symbol: "sportscourt.fill", tint: "#0A84FF"),
        // Rides and delivery
        "uber": Look(symbol: "car.fill", tint: "#FFFFFF"),
        "lyft": Look(symbol: "car.fill", tint: "#FF00BF"),
        "ola": Look(symbol: "car.fill", tint: "#CDDC39"),
        "bolt": Look(symbol: "car.fill", tint: "#34D186"),
        "uber eats": Look(symbol: "takeoutbag.and.cup.and.straw.fill", tint: "#06C167"),
        "doordash": Look(symbol: "takeoutbag.and.cup.and.straw.fill", tint: "#FF3008"),
        "deliveroo": Look(symbol: "takeoutbag.and.cup.and.straw.fill", tint: "#00CCBC"),
        "swiggy": Look(symbol: "takeoutbag.and.cup.and.straw.fill", tint: "#FC8019"),
        "zomato": Look(symbol: "takeoutbag.and.cup.and.straw.fill", tint: "#E23744"),
        "blinkit": Look(symbol: "cart.fill", tint: "#F8CB46"),
        "instacart": Look(symbol: "cart.fill", tint: "#43B02A"),
        "starbucks": Look(symbol: "cup.and.saucer.fill", tint: "#00704A"),
        // Travel
        "flighty": Look(symbol: "airplane", tint: "#0A84FF"),
        "united": Look(symbol: "airplane", tint: "#0A84FF"),
        "delta": Look(symbol: "airplane", tint: "#E01933"),
        "american airlines": Look(symbol: "airplane", tint: "#0078D2"),
        "indigo": Look(symbol: "airplane", tint: "#1A2B6D"),
        "air india": Look(symbol: "airplane", tint: "#DA0E29"),
        // Parcels and shopping
        "amazon": Look(symbol: "shippingbox.fill", tint: "#FF9900"),
        "parcel": Look(symbol: "shippingbox.fill", tint: "#AC8E68"),
        "fedex": Look(symbol: "shippingbox.fill", tint: "#4D148C"),
        "ups": Look(symbol: "shippingbox.fill", tint: "#FFB500"),
        "dhl": Look(symbol: "shippingbox.fill", tint: "#FFCC00"),
        // Sport
        "espn": Look(symbol: "sportscourt.fill", tint: "#E0201B"),
        "cricbuzz": Look(symbol: "figure.cricket", tint: "#1AA355"),
        "fotmob": Look(symbol: "soccerball", tint: "#00985F"),
        "onefootball": Look(symbol: "soccerball", tint: "#FFFFFF"),
        "theScore": Look(symbol: "sportscourt.fill", tint: "#1B6CFF"),
        // Music and media
        "spotify": Look(symbol: "music.note", tint: "#1ED760"),
        "youtube music": Look(symbol: "music.note", tint: "#FF0000"),
        "shazam": Look(symbol: "shazam.logo.fill", tint: "#0A84FF"),
        // AI assistants
        "chatgpt": Look(symbol: "sparkles", tint: "#10A37F"),
        "claude": Look(symbol: "sparkle", tint: "#D97757"),
        "perplexity": Look(symbol: "sparkle.magnifyingglass", tint: "#20B8CD"),
        "gemini": Look(symbol: "sparkles", tint: "#8E75FF"),
        // Productivity and focus
        "forest": Look(symbol: "tree.fill", tint: "#30D158"),
        "focus": Look(symbol: "moon.fill", tint: "#5E5CE6"),
        "strava": Look(symbol: "figure.run", tint: "#FC4C02"),
    ]

    /// Look for an app name as shown in the menu bar ("Uber", "Uber Eats", "Flighty").
    public static func look(for appName: String) -> Look? {
        let name = appName.lowercased().trimmingCharacters(in: .whitespaces)
        if let exact = entries[name] { return exact }
        // Longest alias contained in the name wins ("uber eats" before "uber").
        return entries.filter { name.contains($0.key.lowercased()) }.max { $0.key.count < $1.key.count }?.value
    }
}
