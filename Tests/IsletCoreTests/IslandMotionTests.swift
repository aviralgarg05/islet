import CoreGraphics
import Foundation
import Testing
@testable import IsletCore

/// Times from 0 to `end` in steps of `step`.
private func times(to end: Double, step: Double = 1.0 / 240) -> [Double] {
    stride(from: 0, through: end, by: step).map { $0 }
}

@Suite struct SpringTests {
    @Test func startsAtRestAndArrives() {
        for spring in [IslandMotion.open, IslandMotion.close, IslandMotion.settle, IslandMotion.bud, IslandMotion.bounce] {
            #expect(spring.value(at: 0) == 0)
            #expect(spring.value(at: -1) == 0)
            #expect(abs(spring.value(at: 3) - 1) < 0.001)
        }
    }

    @Test func matchesTheDampedOscillator() {
        // Critically damped, response 1: ω = 2π, x(t) = 1 − e^(−ωt)(1 + ωt).
        let w = 2 * Double.pi
        let critical = MotionSpring(response: 1, damping: 1)
        #expect(abs(critical.value(at: 0.5) - (1 - exp(-w * 0.5) * (1 + w * 0.5))) < 1e-9)
        // Underdamped: a known sample, worked out by hand from the same formula.
        let s = MotionSpring(response: 0.5, damping: 0.5)
        let w0 = 2 * Double.pi / 0.5, wd = w0 * (1 - 0.25).squareRoot()
        let expected = 1 - exp(-0.5 * w0 * 0.2) * (cos(wd * 0.2) + 0.5 * w0 / wd * sin(wd * 0.2))
        #expect(abs(s.value(at: 0.2) - expected) < 1e-9)
        // Overdamped never overshoots.
        let slow = MotionSpring(response: 0.4, damping: 1.4)
        #expect(times(to: 2).allSatisfy { slow.value(at: $0) <= 1 })
    }

    @Test func openingOvershootsATouchAndClosingLandsWithoutOne() {
        let openPeak = IslandMotion.open.peak
        #expect(openPeak > 1.01 && openPeak < 1.05)
        #expect(IslandMotion.close.peak < 1.003)
        // Opening is lively, closing a little longer: both settle within a few tenths.
        #expect(IslandMotion.open.settlingTime() < 0.9)
        #expect(IslandMotion.close.settlingTime() < 0.8)
        #expect(IslandMotion.settle.settlingTime() < 0.5)
    }

    @Test func animationSpeedStretchesTime() {
        let spring = IslandMotion.open
        for t in [0.05, 0.1, 0.2, 0.4] {
            #expect(abs(spring.paced(1.25).value(at: t * 1.25) - spring.value(at: t)) < 1e-9)
        }
    }

    @Test func aSettledSpringLandsExactlyOnTime() {
        #expect(IslandMotion.settled(IslandMotion.bud, at: IslandMotion.splitDuration, over: IslandMotion.splitDuration) == 1)
        #expect(IslandMotion.settled(IslandMotion.bud, at: 0, over: IslandMotion.splitDuration) == 0)
    }

    @Test func easeCurvesRunFromZeroToOne() {
        for curve in [EaseCurve.easeIn, .easeOut, .easeInOut] {
            #expect(curve.value(0) == 0)
            #expect(curve.value(1) == 1)
            let samples = stride(from: 0.0, through: 1, by: 0.01).map(curve.value)
            #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 + 1e-9 })
        }
        #expect(EaseCurve.easeOut.value(0.5) > 0.5)
        #expect(EaseCurve.easeIn.value(0.5) < 0.5)
        #expect(abs(EaseCurve.easeInOut.value(0.5) - 0.5) < 1e-6)
    }
}

@Suite struct ShapeFirstTests {
    @Test func contentArrivesAfterTheShape() {
        #expect(IslandMotion.contentReveal(at: 0) == 0)
        #expect(IslandMotion.contentReveal(at: IslandMotion.contentDelay) == 0)
        #expect(IslandMotion.contentReveal(at: IslandMotion.contentDelay + 0.05) > 0)
        #expect(IslandMotion.contentReveal(at: IslandMotion.contentDelay + IslandMotion.contentFade) == 1)
        // The shell is well under way by the time content starts.
        #expect(IslandMotion.shellProgress(at: IslandMotion.contentDelay, opening: true) > 0.3)
    }

    @Test func contentWaitsForTheShellToMakeRoom() {
        // Opening, the shell is most of the way out before text starts to show, so a word is
        // never cut by the edge still growing round it.
        #expect(IslandMotion.shellProgress(at: IslandMotion.contentDelay, opening: true) >= 0.6)
        // Closing, the smaller shape's row waits until the body has nearly gone back into it.
        #expect(IslandMotion.shellProgress(at: IslandMotion.contentDelayClosing, opening: false) >= 0.85)
    }

    @Test func closingClearsTheContentBeforeTheShellMoves() {
        #expect(IslandMotion.contentLeft(at: IslandMotion.contentExit) == 0)
        #expect(IslandMotion.shellProgress(at: IslandMotion.closeDelay, opening: false) == 0)
        #expect(IslandMotion.contentLeft(at: IslandMotion.closeDelay) < 0.5)
        // The switcher goes first.
        #expect(IslandMotion.switcherExit < IslandMotion.contentExit)
    }

    @Test func theSwitcherRisesInTurnAfterTheContent() {
        let capsule = IslandMotion.switcherStart(0), discs = IslandMotion.switcherStart(1)
        #expect(abs(capsule - IslandMotion.contentDelay - 0.06) < 1e-9)
        #expect(discs > capsule)
        // Nothing shows before its turn; everything has landed by the end of the span.
        #expect(IslandMotion.switcherPart(0, at: 0).rise == 0 && IslandMotion.switcherPart(0, at: 0).opacity == 0)
        #expect(IslandMotion.switcherPart(1, at: IslandMotion.switcherStep * 0.9).opacity == 0)
        for index in [0, 1] {
            let end = IslandMotion.switcherPart(index, at: IslandMotion.switcherSpan)
            #expect(abs(end.rise - 1) < 0.01)
            #expect(end.opacity == 1)
        }
        // Mid-way the capsule is ahead of the discs.
        let mid = IslandMotion.switcherStep * 1.5
        #expect(IslandMotion.switcherPart(0, at: mid).rise > IslandMotion.switcherPart(1, at: mid).rise)
    }

    @Test func theIslandAppearsAtOnceOverANotchAndGoesOnceClosed() {
        #expect(IslandMotion.presence(at: 0, showing: true, notch: true) == 1)
        #expect(IslandMotion.presence(at: 0, showing: true, notch: false) == 0)
        #expect(IslandMotion.presence(at: IslandMotion.showFade, showing: true, notch: false) == 1)
        #expect(IslandMotion.presence(at: IslandMotion.hideDelay, showing: false, notch: true) == 1)
        #expect(IslandMotion.presence(at: IslandMotion.hideDelay + IslandMotion.hideFade, showing: false, notch: true) == 0)
        // It fades only once the shell has (nearly) closed.
        #expect(IslandMotion.shellProgress(at: IslandMotion.hideDelay, opening: false) > 0.9)
    }
}

@Suite struct SquashAndStretchTests {
    @Test func nothingAtRest() {
        for opening in [true, false] {
            #expect(IslandMotion.stretch(at: 0, opening: opening, delta: 300) == 0)
            #expect(IslandMotion.stretch(at: IslandMotion.stretchSpan, opening: opening, delta: 300) == 0)
            #expect(IslandMotion.stretch(at: 0.3, opening: opening, delta: 0) == 0)
        }
    }

    @Test func openingWidensAndClosingNarrowsByAFewPoints() {
        let open = times(to: IslandMotion.stretchSpan).map { IslandMotion.stretch(at: $0, opening: true, delta: 400) }
        let close = times(to: IslandMotion.stretchSpan).map { IslandMotion.stretch(at: $0, opening: false, delta: -400) }
        #expect(open.allSatisfy { $0 >= 0 && $0 <= IslandMotion.stretchLimit })
        #expect(close.allSatisfy { $0 <= 0 && $0 >= -IslandMotion.stretchLimit })
        #expect(open.max()! > 1)
        #expect(close.min()! < -1)
        // A small change squashes less.
        let small = times(to: IslandMotion.stretchSpan).map { IslandMotion.stretch(at: $0, opening: true, delta: 30) }
        #expect(small.max()! < open.max()!)
    }

    @Test func closingNeverPullsInsideTheClosedShape() {
        // From the open island down to the notch and its wings, and from a peek back down.
        for (from, to) in [(CGFloat(480), CGFloat(269)), (321, 289), (289, 185)] {
            let widths = times(to: 1).map { IslandMotion.shellWidth(from: from, to: to, at: $0, opening: false) }
            #expect(widths.allSatisfy { $0 >= to - 0.5 })
            #expect(widths.allSatisfy { $0 <= from + 0.01 })
            #expect(abs(widths.last! - to) < 0.05)
        }
    }

    @Test func theClosedIslandStretchesAsAWhole() {
        // The compact island (its stem as wide as its body), squashed or stretched a few
        // points a side: still one width from top to bottom, so no lip hangs below the row.
        let width: CGFloat = 289, height: CGFloat = 32, flare: CGFloat = 6
        for d in [IslandMotion.stretchLimit, -2] {
            let stem = IslandMotion.stretchedStem(width, width: width, by: d)
            let rect = CGRect(x: 0, y: 0, width: width + 2 * flare + 2 * d, height: height)
            let o = IslandSilhouette.solve(in: rect, topRadius: flare, bottomRadius: 12, stemWidth: stem,
                                           stemHeight: height, inset: 0, pillInset: 1.5)
            #expect(o.overhang == 0)
            #expect(abs(o.bodyRight - o.bodyLeft - (width + 2 * d)) < 1e-9)
        }
        // A stemmed shape (a peek, the Glass island) keeps its stem the width of the row and
        // stretches only its body; no stem stays no stem.
        #expect(IslandMotion.stretchedStem(289, width: 321, by: 2) == 289)
        #expect(IslandMotion.stretchedStem(0, width: 321, by: 2) == 0)
    }

    @Test func growingIntoTheRowKeepsClearOfTheMenuBar() {
        // An activity growing out of the notch with the default wings: the closed island lands
        // on the open spring alone, its wings never reaching further past their place than
        // the room kept clear beside them leaves (with the hover response on top).
        let wing = CGFloat(IsletSettings().wingWidth), notch: CGFloat = 185
        #expect(!IslandMotion.squashes(opening: true, delta: 2 * wing, intoRow: true))
        for t in times(to: 1) {
            #expect(IslandMotion.stretch(at: t, opening: true, delta: 2 * wing, intoRow: true) == 0)
            let width = IslandMotion.shellWidth(from: notch, to: notch + 2 * wing, at: t, opening: true, intoRow: true)
            #expect((width - notch - 2 * wing) / 2 <= IslandMotion.rowRoom)
        }
        #expect(IslandMotion.rowRoom + NotchGeometry.hoverGrow <= MenuBarLayoutEngine.clearance)
        // Opening out of the row still stretches, and closing into it still pulls in.
        #expect(IslandMotion.squashes(opening: true, delta: 211, intoRow: false))
        #expect(IslandMotion.squashes(opening: false, delta: -211, intoRow: true))
        #expect(times(to: 1).contains { IslandMotion.stretch(at: $0, opening: false, delta: -211, intoRow: true) < 0 })
    }

    @Test func theBounceKeepsTheRowClearOfTheMenuBar() {
        // However wide the island's part in the menu bar row, the bounce on a new activity
        // never takes it more than `rowRoom` past its place on a side; a narrow one gets the
        // whole bounce, and it ends where it started.
        for row in stride(from: CGFloat(40), through: 900, by: 10) {
            for scale in stride(from: CGFloat(0.94), through: 1.06, by: 0.002) {
                let sx = IslandMotion.pulseWidthScale(scale, rowWidth: row)
                #expect((sx - 1) * row / 2 <= IslandMotion.rowRoom + 1e-9, "row \(row), scale \(scale)")
            }
            #expect(IslandMotion.pulseWidthScale(1, rowWidth: row) == 1)
        }
        #expect(IslandMotion.pulseWidthScale(IslandMotion.pulsePeak, rowWidth: 100) == IslandMotion.pulsePeak)
        #expect(IslandMotion.pulseWidthScale(IslandMotion.pulsePeak, rowWidth: 345) < IslandMotion.pulsePeak)
    }

    @Test func openingOvershootsOnlyATouch() {
        let widths = times(to: 1).map { IslandMotion.shellWidth(from: 269, to: 480, at: $0, opening: true) }
        let over = widths.max()! - 480
        #expect(over > 2 && over < 0.04 * 211 + 2 * IslandMotion.stretchLimit)
        #expect(abs(widths.last! - 480) < 0.1)
    }
}

@Suite struct LiquidBubbleTests {
    @Test func aSplitStartsInsideTheIslandAndEndsAtRest() {
        let start = IslandMotion.bud(.split, progress: 0)
        #expect(start.travel == 0)
        #expect(start.scale == IslandMotion.budStartScale)
        #expect(start.icon == 0)
        // Its centre starts just inside the island, by its own starting radius.
        #expect(IslandMotion.budCentre(travel: start.travel, rest: 28, radius: 16) == -8)
        #expect(IslandMotion.bud(.split, progress: 1) == .resting)
        #expect(IslandMotion.budCentre(travel: 1, rest: 28, radius: 16) == 28)
    }

    @Test func aSplitSettlesWithASmallOvershoot() {
        let travel = times(to: 1, step: 0.005).map { IslandMotion.bud(.split, progress: $0).travel }
        #expect(travel.max()! > 1.02)
        #expect(travel.max()! < 1.12)
    }

    @Test func theBridgeThinsAndSnapsWithoutLeavingSpikes() {
        let widths = times(to: 1, step: 0.005).map { IslandMotion.bridgeWidth(.split, progress: $0) }
        #expect(widths.first! > 0.5)
        #expect(zip(widths, widths.dropFirst()).allSatisfy { $0 >= $1 })
        // Never a thread thinner than the snap: it is either a bridge or gone.
        #expect(widths.allSatisfy { $0 == 0 || $0 >= IslandMotion.bridgeSnap })
        // Gone well before the split ends, so no goo is left once it has.
        #expect(IslandMotion.bridgeWidth(.split, progress: IslandMotion.snap) == 0)
        #expect(times(to: 1, step: 0.005).filter { $0 >= 0.5 }.allSatisfy { IslandMotion.bud(.split, progress: $0).bridge == 0 })
    }

    @Test func aMergeGrowsABridgeOnlyOnceTheBubbleIsClose() {
        let widths = times(to: 1, step: 0.005).map { IslandMotion.bridgeWidth(.merge, progress: $0) }
        #expect(widths.first! == 0)
        #expect(zip(widths, widths.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(widths.allSatisfy { $0 == 0 || $0 >= IslandMotion.bridgeSnap })
        #expect(widths.last! <= IslandMotion.bridgeMax)
        let end = IslandMotion.bud(.merge, progress: 1)
        #expect(end.travel == 0)
        #expect(end.icon == 0)
        // Where the bridge appears, the bubble is already within a point of the island.
        let first = times(to: 1, step: 0.005).first { IslandMotion.bridgeWidth(.merge, progress: $0) > 0 }!
        let pose = IslandMotion.bud(.merge, progress: first)
        let centre = IslandMotion.budCentre(travel: pose.travel, rest: 28, radius: 16)
        #expect(centre - 16 * pose.scale < 3)
    }

    @Test func nothingOutgrowsTheMenuBarRow() {
        for kind in [IslandMotion.BudKind.split, .merge] {
            for p in times(to: 1, step: 0.005) {
                let pose = IslandMotion.bud(kind, progress: p)
                // The bubble and its bridge are never taller than the bubble at rest, which is
                // the row's height.
                #expect(pose.scale <= 1)
                #expect(pose.bridge <= pose.scale)
                #expect(pose.icon >= 0 && pose.icon <= 1)
            }
        }
    }
}

@Suite struct GlyphMotionTests {
    @Test func aNewGlyphBouncesOnceAfterTheOldOneStartsToGo() {
        #expect(IslandMotion.glyphArrival(at: 0) == 0)
        #expect(IslandMotion.glyphArrival(at: IslandMotion.glyphDelay) == 0)
        let values = times(to: 1).map { IslandMotion.glyphArrival(at: $0) }
        let peak = values.max()!
        #expect(peak > 1.02 && peak < 1.15)
        // One bounce: once past its peak it comes back down and stays within a hair of rest.
        let after = values.drop { $0 < peak }.dropFirst()
        #expect(after.allSatisfy { $0 > 0.97 })
    }

    @Test func valuesSwapWithBarelyAnyOverlap() {
        #expect(IslandMotion.morphOut(at: 0) == 1)
        #expect(IslandMotion.morphOut(at: IslandMotion.morphOutLength) == 0)
        #expect(IslandMotion.morphIn(at: IslandMotion.morphInDelay) == 0)
        #expect(IslandMotion.morphIn(at: IslandMotion.morphInDelay + IslandMotion.morphInLength) == 1)
        // By the time the new value is half in, the old one is all but gone.
        let half = times(to: 1).first { IslandMotion.morphIn(at: $0) >= 0.5 }!
        #expect(IslandMotion.morphOut(at: half) < 0.15)
    }
}

@Suite struct IslandSilhouetteTests {
    /// The notch (185 × 32) with 52-point wings: compact, and a peek 46 points deeper and 32
    /// wider, as `IslandLayout` builds them; `k` of the way between, as the spring moves them.
    private func peekMorph(_ k: CGFloat, pill: Bool = false) -> IslandSilhouette {
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * k }
        let h: CGFloat = pill ? 24 : 32
        let row: CGFloat = 185 + 2 * 52
        let width = mix(row, row + 32), height = mix(h, h + 46)
        let top = mix(pill ? 0 : 6, 8)
        let bottom = mix(pill ? (h - 3) / 2 : 12, 18)
        let rect = CGRect(x: 0, y: 0, width: width + 2 * top, height: height)
        return IslandSilhouette.solve(in: rect, topRadius: top, bottomRadius: bottom, stemWidth: row, stemHeight: h,
                                      inset: pill ? mix(1.5, 0) : 0, pillInset: 1.5)
    }

    @Test func restingShapesKeepTheirOutline() {
        let compact = peekMorph(0)
        #expect(compact.overhang == 0)
        #expect(compact.bottomRadius == 12)
        let peek = peekMorph(1)
        #expect(peek.overhang == 16)
        #expect(peek.junction == 32)
        #expect(peek.shoulderWidth == 8 && peek.shoulderHeight == 8)
        #expect(peek.cornerWidth == 8 && peek.cornerHeight == 8)
        #expect(peek.bottomRadius == 18)
        #expect(peek.fullness == 1)
        // The floating pill is a capsule.
        let pill = peekMorph(0, pill: true)
        #expect(pill.floats)
        #expect(abs(pill.round - pill.bottomRadius) < 1e-9)
        #expect(abs(pill.bottomRadius - (pill.bottom - pill.top) / 2) < 1e-9)
    }

    @Test func theCompactToPeekMorphIsCleanInEveryFrame() {
        for pill in [false, true] {
            var last = peekMorph(0, pill: pill)
            for i in 1...500 {
                let o = peekMorph(CGFloat(i) / 500, pill: pill)
                // Every number moves a little at a time: no jumps, so no ears popping in.
                for (a, b) in [(last.junction, o.junction), (last.bottomRadius, o.bottomRadius), (last.round, o.round),
                               (last.shoulderWidth, o.shoulderWidth), (last.shoulderHeight, o.shoulderHeight),
                               (last.cornerWidth, o.cornerWidth), (last.cornerHeight, o.cornerHeight)] {
                    #expect(abs(a - b) < 0.6, "pill \(pill), frame \(i)")
                }
                // The S from the stem to the body fits the side: below the flare, above the corner.
                #expect(o.junction - o.shoulderHeight >= o.top + o.flare + o.round - 1e-6)
                #expect(o.junction + o.cornerHeight <= o.bottom - o.bottomRadius + 1e-6)
                #expect(o.shoulderWidth + o.cornerWidth <= o.overhang + 1e-6)
                last = o
            }
        }
    }

    @Test func theBodyKeepsItsRoundCornersWhileItIsShort() {
        // The old outline squared the corners off here (the "ears"): the body only a few
        // points wider and deeper than the row.
        for k in [0.02, 0.05, 0.1, 0.15] as [CGFloat] {
            let o = peekMorph(k)
            #expect(o.bottomRadius >= 12)
        }
    }

    /// The left side as a chain of points, top to bottom.
    private func samples(_ side: IslandSilhouette.Side, steps: Int = 80) -> [CGPoint] {
        func quad(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint) -> [CGPoint] {
            (1...steps).map { i in
                let s = CGFloat(i) / CGFloat(steps), u = 1 - s
                return CGPoint(x: u * u * a.x + 2 * u * s * c.x + s * s * b.x, y: u * u * a.y + 2 * u * s * c.y + s * s * b.y)
            }
        }
        return [side.start] + quad(side.start, side.topControl, side.topEnd) + [side.shoulderStart]
            + quad(side.shoulderStart, side.shoulderControl, side.junction) + [side.cornerStart]
            + quad(side.cornerStart, side.cornerControl, side.cornerEnd) + [side.bottomStart]
            + quad(side.bottomStart, side.bottomControl, side.end)
    }

    /// The turn at each sample, in degrees: negative where the left side bends round the
    /// island (convex), positive where it bends back (a shoulder).
    private func turns(_ points: [CGPoint]) -> [Double] {
        var out: [Double] = []
        for i in 0..<(points.count - 2) {
            let a = points[i], b = points[i + 1], c = points[i + 2]
            let v1 = CGVector(dx: b.x - a.x, dy: b.y - a.y), v2 = CGVector(dx: c.x - b.x, dy: c.y - b.y)
            guard hypot(v1.dx, v1.dy) > 1e-6, hypot(v2.dx, v2.dy) > 1e-6 else { continue }
            out.append(Double(atan2(v1.dx * v2.dy - v1.dy * v2.dx, v1.dx * v2.dx + v1.dy * v2.dy)) * 180 / .pi)
        }
        return out
    }

    @Test func theSideHasNoCornersInAnyFrame() {
        // Every join sits on the line between the controls either side of it, so the outline
        // turns smoothly from one curve into the next.
        func direction(_ a: CGPoint, _ b: CGPoint) -> CGVector? {
            let d = CGVector(dx: b.x - a.x, dy: b.y - a.y)
            let l = hypot(d.dx, d.dy)
            return l > 1e-6 ? CGVector(dx: d.dx / l, dy: d.dy / l) : nil
        }
        for pill in [false, true] {
            for i in 0...200 {
                let side = peekMorph(CGFloat(i) / 200, pill: pill).left
                // Each curve meets the next on the leg between their controls.
                for (join, before, after) in [(side.topEnd, side.topControl, side.shoulderControl),
                                              (side.junction, side.shoulderControl, side.cornerControl),
                                              (side.cornerEnd, side.cornerControl, side.bottomControl)] {
                    guard let d1 = direction(before, join), let d2 = direction(join, after) else { continue }
                    #expect(abs(d1.dx * d2.dy - d1.dy * d2.dx) < 1e-6, "pill \(pill), frame \(i)")
                    #expect(d1.dx * d2.dx + d1.dy * d2.dy > 0, "pill \(pill), frame \(i)")
                }
            }
        }
    }

    @Test func aFloatingPillOpensWithoutANub() {
        // While the pill is still short, its end sweeps out in one curve: no shoulder squeezed
        // between its round corners. (The old outline turned back by more than 30 degrees here,
        // a nub on each end in the first frames.)
        for k in [0.01, 0.02, 0.04, 0.06, 0.08, 0.1] as [CGFloat] {
            let o = peekMorph(k, pill: true)
            #expect(o.tilt > 0.7)
            let back = turns(samples(o.left)).filter { $0 > 0 }.reduce(0, +)
            #expect(back < 6, "k \(k): turns back \(back) degrees")
        }
        // The shoulders form as the body drops, and the peek ends as the hanging shape.
        #expect(peekMorph(1, pill: true).tilt == 0)
        // A shape hanging from the top edge never tilts: its S is unchanged.
        for k in stride(from: 0, through: 1, by: 0.05) {
            #expect(peekMorph(CGFloat(k)).tilt == 0)
        }
    }

    @Test func neverOutsideItsFrame() {
        for k in stride(from: 0, through: 1, by: 0.05) {
            for pill in [false, true] {
                let o = peekMorph(CGFloat(k), pill: pill)
                #expect(o.bodyLeft >= 0)
                #expect(o.stemLeft >= o.bodyLeft)
                #expect(o.top >= 0)
                #expect(o.junction <= o.bottom)
            }
        }
    }
}

/// The Glass theme opening and closing: every layer is the island's own shape, and only how much
/// of each shows changes.
@Suite struct GlassCloseTests {
    @Test func atRestTheOpenIslandIsGlassAndTheClosedOneBlack() {
        #expect(GlassMelt.layers(expanded: true) == GlassLayers(glass: 1, row: 1, black: 0))
        #expect(GlassMelt.layers(expanded: false) == GlassLayers(glass: 0, row: 0, black: 1))
    }

    /// Closing reads as one shape shrinking into the notch: the black is back over the whole
    /// shape quickly, and the menu bar row never shows the wallpaper on the way.
    @Test func closingBringsTheBlackBackOverTheWholeShapeFirst() {
        for pace in [0.8, 1.0, 1.25] {
            let back = GlassMelt.unmelt * pace
            var lastBlack = 0.0, lastGlass = 1.0
            for t in times(to: 1) {
                let l = GlassMelt.layers(at: t, opening: false, pace: pace)
                #expect(l.black >= lastBlack && l.glass <= lastGlass, "the black only comes back and the glass only goes")
                lastBlack = l.black
                lastGlass = l.glass
                #expect(l.rowCover > 0.999, "the row stays black at \(t) s")
                if t >= back { #expect(l.black == 1, "all black by \(back) s, before the shell has shrunk far") }
            }
            #expect(GlassMelt.layers(at: 1, opening: false, pace: pace) == GlassMelt.layers(expanded: false))
        }
        // Black over the whole shape by the time the shell starts to move in earnest (0.15 s,
        // the frame where the old close showed a black stem over a grey slab).
        let early = GlassMelt.layers(at: 0.15, opening: false)
        #expect(early.black == 1 && early.glass == 0)
    }

    /// Opening is unchanged: the glass is there at once under the black, the menu bar row stays
    /// black, and the black melts away once the island has grown clear of the notch.
    @Test func openingKeepsTheRowBlackAndMeltsTheRestLater() {
        for t in times(to: 1) {
            let l = GlassMelt.layers(at: t, opening: true)
            #expect(l.glass == 1 && l.row == 1)
            if t <= GlassMelt.meltDelay { #expect(l.black == 1) }
            if t >= GlassMelt.meltDelay + GlassMelt.melt { #expect(l.black == 0) }
        }
    }
}

@Suite struct LoopPoseTests {
    /// Reduce Motion holds the playing indicator still but lets it breathe, so a playing song
    /// never looks paused; Off and out-of-date content hold it completely still.
    @Test func reduceMotionBreathesAndOffHoldsStill() {
        #expect(IslandLoops.pose(reduceMotion: false, animationOff: false) == .moving)
        #expect(IslandLoops.pose(reduceMotion: true, animationOff: false) == .breathing)
        #expect(IslandLoops.pose(reduceMotion: true, animationOff: true) == .still)
        #expect(IslandLoops.pose(reduceMotion: false, animationOff: true) == .still)
        #expect(IslandLoops.pose(reduceMotion: true, animationOff: false, stale: true) == .still)
        #expect(IslandLoops.breatheLow > 0.5 && IslandLoops.breatheLow < 1, "a gentle breath, never close to paused")
    }

    /// Minimal only turns moves into fades: loops keep going, as with every style but Off.
    @Test func minimalKeepsTheLoopsGoing() {
        for style in AnimationStyle.allCases {
            #expect(IslandLoops.holdStill(style: style, reduceMotion: false) == (style == .off), "\(style)")
            #expect(IslandLoops.holdStill(style: style, reduceMotion: true))
            #expect(IslandLoops.holdStill(style: style, reduceMotion: false, stale: true))
        }
    }

    /// A loop started again at a new frame rate carries on from where it was.
    @Test func aRetimedLoopCarriesOnFromWhereItWas() {
        #expect(IslandLoops.resumeOffset(elapsed: 2.5) == 2.5)
        #expect(IslandLoops.resumeOffset(elapsed: 2.5, offset: 0.3) == 2.8)
        #expect(IslandLoops.resumeOffset(elapsed: -1) == 0)
        #expect(IslandLoops.resumeOffset(elapsed: .nan) == 0)
    }
}

@Suite struct FloatingPillAppearTests {
    /// A floating pill appearing from nothing grows out of a capsule at the middle of the row,
    /// however far, without its ends ever reaching past their place towards the menu bar.
    @Test func itGrowsWithoutOvershooting() {
        #expect(IslandMotion.appear.peak <= 1 + 1e-9)
        let from: CGFloat = 32
        for to in [CGFloat(212), 284, 380, 520] {
            for t in times(to: 1.5) {
                let k = IslandMotion.shellProgress(at: t, opening: true, appearing: true)
                let width = from + (to - from) * CGFloat(k)
                #expect(width <= to + 1e-9, "\(to) pt pill at \(t) s")
            }
            #expect(IslandMotion.shellProgress(at: 1.5, opening: true, appearing: true) > 0.995)
        }
        // Everything else moves as before.
        #expect(IslandMotion.shellProgress(at: 0.2, opening: true) == IslandMotion.open.value(at: 0.2))
    }

    /// Its content waits until the pill is nearly its full width, so it never shows cut off.
    @Test func itsContentWaitsForTheRoom() {
        let start = IslandMotion.contentStart(opening: true, appearing: true)
        #expect(start > IslandMotion.contentStart(opening: true))
        #expect(IslandMotion.shellProgress(at: start, opening: true, appearing: true) > 0.9)
        #expect(IslandMotion.contentStart(opening: false) == IslandMotion.contentDelayClosing)
    }
}
