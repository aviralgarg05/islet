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
