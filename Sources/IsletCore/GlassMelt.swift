import CoreGraphics

/// The Glass theme's open island, stem and body: only the notch-wide stem in the menu bar row
/// is black, and the body is glass from the bottom of the menu bar. Right under the stem the
/// black melts a little way into the glass, and a smoke stays over the glass so text keeps its
/// contrast. "Glass level" sets both, and every part of the slider changes something: the
/// default sits in the middle, with a short melt and a light smoke; towards Glass both thin out
/// further; towards Black the melt reaches further down and the glass darkens.
public enum GlassMelt {
    /// The default level (`IsletSettings.glassLevel`), where the curves below change pace.
    public static let standardLevel = 0.6
    /// The smoke at the default level (Apple's dimming layer for clear glass).
    public static let standardSmoke = 0.3
    /// The least black left over the glass, at the Glass end, so text keeps some contrast.
    public static let smokeFloor = 0.15
    /// The melt under the stem at the default level: short, so nothing dark hangs below the
    /// menu bar.
    public static let standardDepth: CGFloat = 12
    /// The shortest melt under the stem, at the Glass end.
    public static let shortest: CGFloat = 6

    /// How far (points) the black under the stem melts into a glass body `body` points tall:
    /// `shortest` at the Glass end, `standardDepth` at the default level, and up to half the
    /// body at the Black end.
    public static func depth(body: CGFloat, level: Double) -> CGFloat {
        let half = max(shortest, max(0, body) / 2)
        let middle = min(standardDepth, half)
        let l = clamped(level)
        if l >= standardLevel {
            return shortest + (middle - shortest) * CGFloat((1 - l) / (1 - standardLevel))
        }
        let black = CGFloat((standardLevel - l) / standardLevel)
        return middle + (half - middle) * black * black
    }

    /// The smoke over the glass: `standardSmoke` at the default level, thinning to `smokeFloor`
    /// at the Glass end and darkening towards Black, so that end still looks mostly black.
    public static func smoke(level: Double) -> Double {
        let l = clamped(level)
        if l >= standardLevel {
            return standardSmoke - (standardSmoke - smokeFloor) * (l - standardLevel) / (1 - standardLevel)
        }
        return standardSmoke + 0.55 * (standardLevel - l) / standardLevel
    }

    /// The level within 0...1; anything that isn't a number counts as the Glass end.
    private static func clamped(_ level: Double) -> Double {
        min(1, max(0, level.isFinite ? level : 1))
    }
}
