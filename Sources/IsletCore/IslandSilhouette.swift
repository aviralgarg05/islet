import CoreGraphics

/// The island's silhouette for one frame, as the numbers `IslandShape` draws: a stem in the
/// menu bar row (as wide as the notch and its wings) and a body that may open out below it,
/// joined on each side by a concave shoulder and a convex corner.
///
/// One outline covers every shape: the closed island (no body wider than the stem), a peek
/// (a body below the row), the open island and the floating pill on a display without a
/// notch. Every number here moves continuously with the shape's parameters, so a morph between
/// any two shapes is clean in every frame. While the body is only a few points wider than the
/// stem, the shoulder and corner are only that wide but spread down the side, so it leans out
/// in a long, gentle S instead of stepping; and the body's bottom corners keep the closed
/// island's radius instead of collapsing into square "ears" under the row.
public struct IslandSilhouette: Equatable, Sendable {
    /// The top edge (inside a floating pill's inset) and the bottom edge.
    public var top: CGFloat
    public var bottom: CGFloat
    /// The outward flare where the stem meets the top of the screen.
    public var flare: CGFloat
    /// A floating pill's rounded top corners (0 once it hangs from the top edge).
    public var round: CGFloat
    /// The stem's sides.
    public var stemLeft: CGFloat
    public var stemRight: CGFloat
    /// The body's sides.
    public var bodyLeft: CGFloat
    public var bodyRight: CGFloat
    /// Where the shoulders meet the body's top edge: the bottom of the menu bar row once the
    /// body is open, higher while it is still too short to round its corners below the row.
    public var junction: CGFloat
    /// The concave fillet from the stem out to the body's top edge: across and down.
    public var shoulderWidth: CGFloat
    public var shoulderHeight: CGFloat
    /// The convex corner from the body's top edge down its side: across and down.
    public var cornerWidth: CGFloat
    public var cornerHeight: CGFloat
    /// How far the shoulders are from leaning (0) to full (1): a lean bends smoothly through
    /// the junction, a full shoulder turns flat along the body's top edge there.
    public var fullness: CGFloat
    /// The body's bottom corners.
    public var bottomRadius: CGFloat
    /// The outline is closed along its top edge too (a floating pill).
    public var floats: Bool

    /// How far the body reaches past the stem on each side.
    public var overhang: CGFloat { max(0, stemLeft - bodyLeft) }

    /// The full shoulder: its height, and half the overhang at which it has its full size.
    public static let shoulder: CGFloat = 8
    /// The least height a full corner has, however narrow.
    public static let cornerFloor: CGFloat = 6

    /// - Parameters:
    ///   - rect: the frame the shape is drawn in, its flare included.
    ///   - stemWidth: width of the part inside the menu bar row; 0 (or anything at least the
    ///     body's width) means the body is as wide as the stem.
    ///   - stemHeight: height of the menu bar row part.
    ///   - inset: a floating pill sits this far inside the frame, top and bottom.
    ///   - pillInset: the inset of a floating pill at rest, for blending its rounded top.
    public static func solve(in rect: CGRect, topRadius: CGFloat, bottomRadius: CGFloat, stemWidth: CGFloat,
                             stemHeight: CGFloat, inset: CGFloat, pillInset: CGFloat) -> IslandSilhouette {
        let inset = min(max(0, inset), rect.height / 3)
        // 1 for a floating pill, 0 for a shape hanging from the top edge.
        let float = pillInset > 0 ? min(1, inset / pillInset) : 0
        let frame = rect.insetBy(dx: 0, dy: inset)
        let t = min(max(0, topRadius), frame.width / 4)
        let bodyL = frame.minX + t, bodyR = frame.maxX - t
        let bodyW = max(0, bodyR - bodyL)
        let stem = stemWidth <= 0 ? bodyW : min(stemWidth, bodyW)
        let sL = rect.midX - stem / 2, sR = rect.midX + stem / 2
        let overhang = max(0, (bodyW - stem) / 2)
        let top = frame.minY, bottom = frame.maxY
        let row = top + min(max(0, stemHeight - inset), frame.height)

        var b = max(0, min(bottomRadius, bodyW / 2, frame.height / 2))
        var r = float * min(b, stem / 2)
        // The shoulder and corner share the overhang across, so both shrink to nothing with
        // it. Down, a full one (an overhang of twice `shoulder` or more) has its own height,
        // turning flat along the body's top edge at the bottom of the row. A narrower one is a
        // lean: the S spreads over the side between the top and bottom corners, bending at a
        // slant through the middle, so a body a few points wider than the stem never steps out.
        let full = min(1, overhang / (2 * shoulder))
        let fh = max(0, min(shoulder, overhang / 2, (row - top) / 2))
        let ch = max(0, min(bottomRadius * 0.6, overhang - fh))
        let fullShoulder = max(0, min(shoulder, (row - top) / 2))
        let fullCorner = max(ch, min(cornerFloor, bottomRadius * 0.6))
        // A lean wants a side about three times as tall as it is wide. A short shape (the
        // floating pill, all round ends) makes room by rounding its corners a little less.
        let need = min(3 * overhang, 24) * (1 - full)
        let side = (bottom - b) - (top + t + r)
        if side < need, b + r > 0 {
            let cut = min(need - max(0, side), b + r)
            let share = b / (b + r)
            b -= cut * share
            r -= cut * (1 - share)
        }
        // A full shoulder meets the body at the bottom of the row, unless the body is still too
        // short to round its bottom corners below it: then the junction rises, so the corners
        // keep their radius. A lean bends halfway down the side.
        var fullJunction = min(row, bottom - b - fullCorner)
        fullJunction = max(fullJunction, top + t + fullShoulder)
        let leanJunction = ((top + t + r) + (bottom - b)) / 2
        let junction = leanJunction + (fullJunction - leanJunction) * full
        b = max(0, min(b, bottom - junction - fullCorner * full))
        r = max(0, min(r, junction - top - t - fullShoulder * full))
        let above = max(0, junction - top - t - r)
        let below = max(0, bottom - b - junction)
        let fv = above + (min(fullShoulder, above) - above) * full
        let cv = below + (min(fullCorner, below) - below) * full
        // (With no overhang the S is a straight line along the side, and a floating pill
        // keeps its round ends.)
        return IslandSilhouette(top: top, bottom: bottom, flare: t, round: r, stemLeft: sL, stemRight: sR,
                                bodyLeft: bodyL, bodyRight: bodyR, junction: junction,
                                shoulderWidth: fh, shoulderHeight: fv, cornerWidth: ch, cornerHeight: cv,
                                fullness: full, bottomRadius: b, floats: inset > 0.01)
    }
}
