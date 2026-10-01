import CoreGraphics
import Foundation
import Testing
@testable import IsletCore

private func decode(_ json: String) -> IsletSettings { IsletSettings.decodeLenient(Data(json.utf8)) }

@Suite struct IndicatorLookTests {
    @Test func mirrorVinylAndGIFAreLooks() {
        #expect(VisualiserStyle.allCases == [.bars, .slim, .dots, .wave, .pulse, .mirror, .vinyl, .gif, .off])
        for look in ["mirror", "vinyl", "gif"] {
            #expect(decode(#"{"visualiserStyle": "\#(look)"}"#).visualiserStyle.rawValue == look)
        }
        // A look this build doesn't know (a newer one, a typo) is the bars, and nothing else changes.
        let s = decode(#"{"visualiserStyle": "lava", "sticker": {"id": "star"}}"#)
        #expect(s.visualiserStyle == .bars)
        #expect(s.sticker.id == "star")
    }
}

@Suite struct StickerSettingsTests {
    @Test func startsAsTheCatInItsPlace() {
        let s = IsletSettings().sticker
        #expect(s == StickerSettings(id: "cat", offsetX: 0, offsetY: 0, scale: 1, whenIdle: false))
        #expect(s.choice == .builtIn(.cat))
    }

    @Test func decodesEachValueOnItsOwn() {
        let s = decode(#"{"sticker": {"id": "jelly", "offsetX": -4, "offsetY": "down", "scale": 1.3, "whenIdle": true}}"#).sticker
        #expect(s.id == "jelly")
        #expect(s.offsetX == -4)
        #expect(s.offsetY == 0, "a value that can't be read is the default, alone")
        #expect(s.scale == 1.3)
        #expect(s.whenIdle)
        // Not an object at all: the defaults.
        #expect(decode(#"{"sticker": "cat"}"#).sticker == StickerSettings())
    }

    @Test func outOfRangeValuesComeBackInside() {
        let s = decode(#"{"sticker": {"offsetX": 40, "offsetY": -99, "scale": 9}}"#).sticker
        #expect(s.offsetX == 12 && s.offsetY == -12 && s.scale == 1.6)
        let small = StickerSettings(offsetX: 2.6, offsetY: -0.4, scale: 0.1).sanitized()
        #expect(small.offsetX == 3 && small.offsetY == 0 && small.scale == 0.6)
        let odd = StickerSettings(offsetX: .nan, offsetY: .infinity, scale: .nan).sanitized()
        #expect(odd.offsetX == 0 && odd.offsetY == 0 && odd.scale == 1)
        #expect(StickerSettings(scale: 1.26).sanitized().scale == 1.3)
    }

    @Test(arguments: ["../../etc/passwd", "custom-../x", "custom-", "custom-ABCDEF", "custom-a/b", "custom-a.b", "dog", "",
                      "custom-" + String(repeating: "a", count: 65)])
    func idsThatNameNothingBecomeTheCat(id: String) {
        #expect(StickerChoice(id: id) == nil)
        #expect(StickerSettings(id: id).sanitized().id == "cat")
        #expect(decode(#"{"sticker": {"id": "\#(id)"}}"#).sticker.id == "cat")
    }

    @Test func customIDsRoundTrip() {
        let name = CustomStickerID.make()
        #expect(CustomStickerID.isValid(name))
        let choice = StickerChoice.custom(name)
        #expect(StickerChoice(id: choice.id) == choice)
        #expect(choice.id == "custom-\(name)")
        for b in BuiltInSticker.allCases {
            #expect(StickerChoice(id: b.rawValue) == .builtIn(b))
            #expect(b.fileName == "\(b.rawValue).gif")
            #expect(!b.title.isEmpty)
        }
    }

    @Test func aCustomFileStaysInItsFolder() {
        let dir = URL(fileURLWithPath: "/tmp/stickers")
        #expect(CustomStickerID.file("../escape", in: dir) == nil)
        #expect(CustomStickerID.file("a/b", in: dir) == nil)
        let ok = CustomStickerID.file("0a1b-2c", in: dir)
        #expect(ok?.deletingLastPathComponent().path == dir.path)
        #expect(ok?.pathExtension == "png")
    }

    @Test func resetAppearancePutsTheStickerBack() {
        var s = IsletSettings()
        s.visualiserStyle = .gif
        s.sticker = StickerSettings(id: "star", offsetX: 5, offsetY: -3, scale: 1.4, whenIdle: true)
        let r = s.resettingAppearance()
        #expect(r.visualiserStyle == .bars)
        #expect(r.sticker == StickerSettings())
    }
}

@Suite struct StickerTimingTests {
    @Test func delaysAreMadeSafe() {
        let d = StickerTiming.delays([0.05, 0, nil, -1, .nan, .infinity, 60, 0.02, 0.015])
        #expect(d == [0.05, 0.1, 0.1, 0.1, 0.1, 0.1, 10, 0.02, 0.02])
    }

    /// Old tools wrote 0 or 10 ms for "as fast as you can", and every browser plays those at
    /// 100 ms, so that is how the GIF was meant to look; 20 ms and up is taken as asked.
    @Test func tenMillisecondFramesPlayAsBrowsersPlayThem() {
        #expect(StickerTiming.delays([0.01, 0.001, 0.0109]) == [0.1, 0.1, 0.1])
        #expect(StickerTiming.delays([0.011, 0.02, 0.03]) == [0.02, 0.02, 0.03])
    }

    @Test func theLoopAsksForNoMoreThanThirtyFramesASecond() {
        #expect(StickerTiming.frameRate([0.02, 0.05]) == 30, "50 a second asked, 30 given")
        #expect(StickerTiming.frameRate([0.05, 0.1]) == 20)
        #expect(StickerTiming.frameRate([0.1]) == 10)
        #expect(StickerTiming.frameRate([4, 10]) == 1)
        #expect(StickerTiming.frameRate([]) == 10)
        for d in StickerTiming.delays([0, 0.001, 0.01, 0.02, nil]) {
            #expect(StickerTiming.frameRate([d]) <= 30)
        }
    }

    @Test func keyTimesStartEachFrameAtItsShare() {
        let d = [0.1, 0.3, 0.1]
        let k = StickerTiming.keyTimes(d)
        #expect(k.count == d.count + 1)
        #expect(k.first == 0 && k.last == 1)
        #expect(abs(k[1] - 0.2) < 1e-9 && abs(k[2] - 0.8) < 1e-9)
        #expect(zip(k, k.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(StickerTiming.keyTimes([]) == [0, 1])
        #expect(StickerTiming.keyTimes([0.5]) == [0, 1])
    }

    @Test func longAnimationsKeepTheirWholeLoop() {
        let kept = StickerTiming.kept(count: 1000, limit: 150)
        #expect(kept.count == 150)
        #expect(kept.first == 0)
        #expect(kept.last! >= 990)
        #expect(Set(kept).count == kept.count && kept == kept.sorted())
        let delays = Array(repeating: 0.04, count: 1000)
        let merged = StickerTiming.delays(delays, keeping: kept)
        #expect(merged.count == 150)
        #expect(abs(StickerTiming.duration(merged) - 40) < 1e-6)
        // Short ones keep every frame.
        #expect(StickerTiming.kept(count: 24) == Array(0..<24))
        #expect(StickerTiming.kept(count: 0).isEmpty)
        #expect(StickerTiming.kept(count: 151, limit: 150).count == 150)
    }

    @Test func theFrameAtATime() {
        let d = [0.1, 0.2, 0.1]
        #expect(StickerTiming.frame(at: 0, delays: d) == 0)
        #expect(StickerTiming.frame(at: 0.15, delays: d) == 1)
        #expect(StickerTiming.frame(at: 0.35, delays: d) == 2)
        #expect(StickerTiming.frame(at: 0.45, delays: d) == 0, "the loop starts again")
        #expect(StickerTiming.frame(at: -0.05, delays: d) == 2)
        #expect(StickerTiming.frame(at: .nan, delays: d) == 0)
        #expect(StickerTiming.frame(at: 3, delays: []) == 0)
        #expect(abs(StickerTiming.start(of: 2, delays: d) - 0.3) < 1e-9)
        #expect(StickerTiming.start(of: 9, delays: d) == StickerTiming.duration(d))
        // Freezing on a frame and starting again from it shows the same frame.
        for i in d.indices {
            #expect(StickerTiming.frame(at: StickerTiming.start(of: i, delays: d) + 0.001, delays: d) == i)
        }
    }
}

@Suite struct StickerPlaybackTests {
    private func plan(_ mode: StickerMode, animated: Bool = true, reduceMotion: Bool = false, lowPower: Bool = false,
                      current: Int = 7) -> StickerPlayback {
        StickerPlayback.plan(mode: mode, animated: animated, reduceMotion: reduceMotion, lowPower: lowPower, current: current)
    }

    @Test func itLoopsOnlyWhileTheMusicPlays() {
        #expect(plan(.playing) == .loop(from: 7), "carries on from the frame it was on")
        #expect(plan(.paused) == .hold(7), "paused: frozen on the frame it had reached")
        #expect(plan(.idle) == .hold(0), "resting with nothing playing: the first frame")
    }

    @Test func reduceMotionShowsTheFirstFrameAndLowPowerHoldsTheCurrentOne() {
        for mode in [StickerMode.playing, .paused, .idle] {
            #expect(plan(mode, reduceMotion: true) == .hold(0), "\(mode)")
            #expect(plan(mode, reduceMotion: true, lowPower: true) == .hold(0), "\(mode)")
        }
        #expect(plan(.playing, lowPower: true) == .hold(7))
        #expect(plan(.paused, lowPower: true) == .hold(7))
        #expect(plan(.idle, lowPower: true) == .hold(0))
    }

    @Test func aStillPictureNeverLoops() {
        #expect(plan(.playing, animated: false, current: 0) == .hold(0))
        #expect(plan(.playing, current: -3) == .loop(from: 0))
    }

    @Test func pausedDimsAsTheBarsDo() {
        #expect(StickerPlayback.opacity(.paused, paused: 0.55) == 0.55)
        #expect(StickerPlayback.opacity(.playing, paused: 0.55) == 1)
        #expect(StickerPlayback.opacity(.idle, paused: 0.55) == 1)
    }

    @Test func oneOfYoursThatHasGoneShowsTheCat() {
        let mine = CustomStickerID.make()
        let s = StickerSettings(id: StickerChoice.custom(mine).id)
        #expect(s.shown { $0 == mine } == .custom(mine))
        #expect(s.shown { _ in false } == .builtIn(.cat))
        // Islet's own are always there; the existence check isn't asked about them.
        #expect(StickerSettings(id: "star").shown { _ in Issue.record("asked about a built-in"); return false } == .builtIn(.star))
    }
}

@Suite struct StickerLayoutTests {
    let row: CGFloat = 32

    @Test func atRestItSitsAtTheOuterEdgeInTheMiddleOfTheRow() {
        let r = StickerLayout.frame(room: 60, row: row, outerSpace: 5, aspect: 1, settings: StickerSettings())
        #expect(r.height == 24 && r.width == 24)
        #expect(r.maxX == 60)
        #expect(r.midY == row / 2)
    }

    @Test func neverLeavesTheRowOrTheWing() {
        for room in [8, 20, 40, 90] as [CGFloat] {
            for rowHeight in [22, 32, 38] as [CGFloat] {
                for x in [-12.0, 0, 12] {
                    for y in [-12.0, 0, 12] {
                        for scale in [0.6, 1, 1.6] {
                            for aspect in [0.3, 1, 3.5] as [CGFloat] {
                                let s = StickerSettings(offsetX: x, offsetY: y, scale: scale)
                                let r = StickerLayout.frame(room: room, row: rowHeight, outerSpace: 5, aspect: aspect, settings: s)
                                let e: CGFloat = 1e-9
                                #expect(r.minY >= 1 - e && r.maxY <= rowHeight - 1 + e, "below the row: \(r)")
                                #expect(r.minX >= 1 - e && r.maxX <= room + 5 - 1 + e, "outside the wing: \(r)")
                                #expect(r.width > 0 && r.height > 0)
                                #expect(abs(r.width / r.height - min(4, max(0.25, aspect))) < 0.01, "keeps its shape")
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func offsetsAndSizeMoveIt() {
        let base = StickerLayout.frame(room: 80, row: row, outerSpace: 6, aspect: 1, settings: StickerSettings())
        let left = StickerLayout.frame(room: 80, row: row, outerSpace: 6, aspect: 1, settings: StickerSettings(offsetX: -10))
        #expect(left.minX == base.minX - 10)
        let right = StickerLayout.frame(room: 80, row: row, outerSpace: 6, aspect: 1, settings: StickerSettings(offsetX: 12))
        #expect(abs(right.maxX - (80 + 6 - 1)) < 1e-9, "into the edge space, no further: \(right)")
        let down = StickerLayout.frame(room: 80, row: row, outerSpace: 6, aspect: 1, settings: StickerSettings(offsetY: 3))
        #expect(down.minY == base.minY + 3)
        let small = StickerLayout.frame(room: 80, row: row, outerSpace: 6, aspect: 1, settings: StickerSettings(scale: 0.6))
        #expect(abs(small.height - 24 * 0.6) < 0.001)
        let big = StickerLayout.frame(room: 80, row: row, outerSpace: 6, aspect: 1, settings: StickerSettings(scale: 1.6))
        #expect(big.height == row - 2, "as tall as the row allows")
    }

    @Test func aNarrowWingShowsLess() {
        // Icon-only wings: the sticker shrinks to the room rather than spilling over.
        let r = StickerLayout.frame(room: 14, row: row, outerSpace: 3, aspect: 1, settings: StickerSettings(scale: 1.6))
        #expect(r.width <= 14 + 3 - 2)
        #expect(StickerLayout.frame(room: 0, row: row, outerSpace: 3, aspect: 1, settings: StickerSettings()) == .zero)
    }

    @Test func pixelSizes() {
        #expect(StickerLayout.pixelSize(CGSize(width: 24, height: 24), scale: 2) == 48)
        #expect(StickerLayout.pixelSize(CGSize(width: 36, height: 18), scale: 2) == 72)
        #expect(StickerLayout.pixelSize(CGSize(width: 10, height: 10), scale: .nan) == 20)
        #expect(StickerLayout.standardHeight(row: 22) == 14)
    }
}

@Suite struct IdleStickerTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    private func settings(look: VisualiserStyle = .gif, idle: Bool = true, media: Bool = true) -> IsletSettings {
        var s = IsletSettings()
        s.visualiserStyle = look
        s.sticker.whenIdle = idle
        s.mediaEnabled = media
        return s
    }

    @Test func onlyTheGIFLookWithItsSwitchKeepsIt() {
        #expect(Presenter.showsIdleSticker(settings()))
        #expect(!Presenter.showsIdleSticker(settings(idle: false)))
        #expect(!Presenter.showsIdleSticker(settings(look: .bars)))
        #expect(!Presenter.showsIdleSticker(settings(media: false)))
        #expect(!Presenter.showsIdleSticker(IsletSettings()), "off by default: the island stays hidden when idle")
    }

    @Test func itTakesTheIdlePlaceAndNothingElse() {
        let c = ActivityCenter()
        #expect(Presenter.present(PresenterInputs(now: t0, center: c, idleSticker: true)) == .compact(.sticker))
        #expect(Presenter.present(PresenterInputs(now: t0, center: c, idleSticker: false)) == .idle)
        // Music, when there is some, comes first.
        let np = NowPlaying(source: .appleMusic, title: "Song", isPlaying: true, timestamp: t0)
        #expect(Presenter.present(PresenterInputs(now: t0, center: c, nowPlaying: np, idleSticker: true)) == .compact(.nowPlaying(np)))
        // Hidden in full screen, and out of the way while the island is open.
        #expect(Presenter.present(PresenterInputs(now: t0, center: c, isSuppressed: true, idleSticker: true)) == .hidden)
        #expect(Presenter.present(PresenterInputs(now: t0, center: c, isExpanded: true, idleSticker: true)) == .expanded)
        // "Only on hover" waits for the pointer, as the rest of the closed island does.
        #expect(Presenter.untilHover(.compact(.sticker)) == .idle)
        #expect(GestureSurface.from(.compact(.sticker), homeShowsMedia: false) == .closed)
    }
}

@Suite struct StickerSearchTests {
    @Test(arguments: ["sticker", "gif", "vinyl", "mirror bars", "add gif", "sticker size", "sticker position"])
    func stickerRowsAreFound(query: String) {
        #expect(SettingsIndex.search(query).first?.page == .nowPlaying, "\(query)")
    }

    @Test func rowsShownOnlyForTheGIFLookScrollToThePicker() {
        for id in ["nowPlaying.sticker", "nowPlaying.stickerAdd", "nowPlaying.stickerPosition", "nowPlaying.stickerSize",
                   "nowPlaying.stickerIdle"] {
            #expect(SettingsIndex.entries.first { $0.id == id }?.anchor == "nowPlaying.indicator", "\(id)")
        }
    }

    @Test func importProblemsAreInPlainWords() {
        let all: [StickerImportError] = [.full, .tooLarge, .tooBigPicture, .notAnimation, .unreadable, .couldNotSave]
        for e in all {
            #expect(e.message.hasSuffix("."))
            #expect(!e.message.contains("—"))
            for word in ["ImageIO", "CGImage", "error", "API"] { #expect(!e.message.contains(word), "\(e)") }
        }
    }
}
