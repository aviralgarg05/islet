import CoreGraphics

/// The Glass theme's open island, stem and body: only the notch-wide stem in the menu bar row
/// is black, and the body is glass from the bottom of the menu bar. Right under the stem the
/// black melts a little way into the glass, and a smoke stays over the glass so text keeps its
/// contrast. "Glass level" sets both: from the default level up the melt is a short fade and
/// the smoke is at its floor; towards Black the melt reaches further down and the glass darkens.
public enum GlassMelt {
    /// The least black left over the glass, at every level (Apple's dimming layer for clear glass).
    public static let smokeFloor = 0.3
    /// The shortest melt under the stem, at the Glass end.
    public static let shortest: CGFloat = 6

    /// How far (points) the black under the stem melts into a glass body `body` points tall: a
    /// short fade from the default level up, so nothing dark hangs below the menu bar, and up
    /// to half the body at the Black end.
    public static func depth(body: CGFloat, level: Double) -> CGFloat {
        let half = max(shortest, max(0, body) / 2)
        let black = CGFloat(1 - min(1, max(0, level.isFinite ? level : 1)))
        return shortest + (half - shortest) * black * black * black
    }

    /// The smoke over the glass: the floor from the default level up, darker towards Black, so
    /// that end of the slider still looks mostly black.
    public static func smoke(level: Double) -> Double {
        let l = min(1, max(0, level.isFinite ? level : 1))
        return smokeFloor + 0.55 * max(0, (0.6 - l) / 0.6)
    }
}
