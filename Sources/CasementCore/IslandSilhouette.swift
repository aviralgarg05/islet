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
/// island's radius instead of collapsing into square "ears" under the row. A floating pill's
/// round end has no straight side for an S to fit in, so while it starts to open its end
/// sweeps out in one convex curve instead (`tilt`), and the S grows in as the shoulders fill.
public struct IslandSilhouette: Equatable, Sendable {
    /// One side of the outline, top to bottom, as quadratic curves joined by straight runs.
    /// Every join lies on the line between the controls either side of it, so the side has no
    /// corners whatever the numbers.
    public struct Side: Equatable, Sendable {
        /// The top corner, from the top edge.
        public var start: CGPoint
        public var topControl: CGPoint
        public var topEnd: CGPoint
        /// The concave shoulder out from the stem.
        public var shoulderStart: CGPoint
        public var shoulderControl: CGPoint
        public var junction: CGPoint
        /// The convex corner down the body's side.
        public var cornerStart: CGPoint
        public var cornerControl: CGPoint
        public var cornerEnd: CGPoint
        /// The bottom corner, to the bottom edge.
        public var bottomStart: CGPoint
        public var bottomControl: CGPoint
        public var end: CGPoint

        /// The same side mirrored about `x = axis`.
        public func mirrored(about axis: CGFloat) -> Side {
            func m(_ p: CGPoint) -> CGPoint { CGPoint(x: 2 * axis - p.x, y: p.y) }
            return Side(start: m(start), topControl: m(topControl), topEnd: m(topEnd), shoulderStart: m(shoulderStart),
                        shoulderControl: m(shoulderControl), junction: m(junction), cornerStart: m(cornerStart),
                        cornerControl: m(cornerControl), cornerEnd: m(cornerEnd), bottomStart: m(bottomStart),
                        bottomControl: m(bottomControl), end: m(end))
        }
    }

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
    /// How far a floating pill's end has turned from an S into one convex sweep: 1 while its
    /// round end starts to open, 0 once its shoulders have room (and always without a pill).
    public var tilt: CGFloat
    /// The left side as drawn; the right side is its mirror image about the frame's middle.
    public var left: Side
    public var right: Side { left.mirrored(about: midX) }
    /// The middle of the frame.
    public var midX: CGFloat

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
        // A floating pill's round end has no straight side for an S: any S squeezed into it
        // reads as a nub. So while it is still mostly a pill, its end sweeps out in one convex
        // curve, and the S grows in as the shoulders fill out.
        let tilt = overhang > 0 ? float * (1 - smoothstep(0.25, 0.7, full)) : 0
        // A lean wants a side about three times as tall as it is wide. A short shape makes room
        // by rounding its corners a little less (a convex sweep needs none).
        let need = min(3 * overhang, 24) * (1 - full) * (1 - tilt)
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
        // The side's controls: the stem's top corner, the shoulder, the corner and the body's
        // bottom corner. The shoulder and corner bend at the junction for a full shoulder, so
        // the body's top edge runs flat there, and halfway up and down them for a lean, so the
        // side passes through the junction at a slant instead of jogging sideways.
        let lean = 1 - full
        let c1 = CGPoint(x: sL, y: top), c2 = CGPoint(x: bodyL, y: bottom)
        var q1 = CGPoint(x: sL, y: junction - fv / 2 * lean), q2 = CGPoint(x: bodyL, y: junction + cv / 2 * lean)
        // The joins sit on the legs between the controls, at the same places whatever the tilt.
        let a1 = fraction(top + t + r, from: top, to: q1.y), a2 = fraction(junction - fv, from: top, to: q1.y)
        let s1 = overhang > 1e-9 ? fh / overhang : 0.5, s2 = overhang > 1e-9 ? (overhang - ch) / overhang : 0.5
        let k1 = fraction(junction + cv, from: q2.y, to: bottom), k2 = fraction(bottom - b, from: q2.y, to: bottom)
        // Tilting slides the shoulder's and corner's controls onto the straight line from the
        // top corner's control to the bottom corner's, where the side is one convex sweep.
        func straight(_ y: CGFloat) -> CGFloat { c1.x + (c2.x - c1.x) * fraction(y, from: top, to: bottom) }
        q1.x += (straight(q1.y) - q1.x) * tilt
        q2.x += (straight(q2.y) - q2.x) * tilt
        func along(_ from: CGPoint, _ to: CGPoint, _ s: CGFloat) -> CGPoint {
            CGPoint(x: from.x + (to.x - from.x) * s, y: from.y + (to.y - from.y) * s)
        }
        let left = Side(start: CGPoint(x: sL - t + r, y: top), topControl: c1, topEnd: along(c1, q1, a1),
                        shoulderStart: along(c1, q1, a2), shoulderControl: q1, junction: along(q1, q2, s1),
                        cornerStart: along(q1, q2, s2), cornerControl: q2, cornerEnd: along(q2, c2, k1),
                        bottomStart: along(q2, c2, k2), bottomControl: c2, end: CGPoint(x: bodyL + b, y: bottom))
        // (With no overhang the S is a straight line along the side, and a floating pill
        // keeps its round ends.)
        return IslandSilhouette(top: top, bottom: bottom, flare: t, round: r, stemLeft: sL, stemRight: sR,
                                bodyLeft: bodyL, bodyRight: bodyR, junction: junction,
                                shoulderWidth: fh, shoulderHeight: fv, cornerWidth: ch, cornerHeight: cv,
                                fullness: full, bottomRadius: b, floats: inset > 0.01, tilt: tilt, left: left, midX: rect.midX)
    }

    /// Where `v` is between `a` and `b`, 0 to 1 (1 when they are the same).
    private static func fraction(_ v: CGFloat, from a: CGFloat, to b: CGFloat) -> CGFloat {
        abs(b - a) < 1e-9 ? 1 : min(1, max(0, (v - a) / (b - a)))
    }

    private static func smoothstep(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }
}
