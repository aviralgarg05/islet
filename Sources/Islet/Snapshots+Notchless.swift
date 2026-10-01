import AppKit
import IsletCore
import SwiftUI

@MainActor
extension Snapshots {
    /// An external display: no notch, a 24 pt menu bar.
    static let notchlessScreen = ScreenDescriptor(
        id: 2, name: "External", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        safeAreaTop: 0, menuBarHeight: 24, isBuiltIn: false
    )

    /// `<dir>/50-notchless-*.png`: the island on a display without a notch, as a floating pill
    /// and as a notch shape, with music, a timer, a HUD and a peek.
    static func renderNotchless(to dir: URL, model: AppModel, now: Date) {
        let saved = model.settings
        defer {
            model.settings = saved
            model.closedPlacements[2] = nil
        }
        var center = ActivityCenter()
        let timer = try! center.apply(ActivitySpec(id: "tea", source: "timer", title: "Tea", icon: .symbol("timer"), tint: "orange",
                                                   endsAt: now.addingTimeInterval(272)), now: now)
        let hud = HUDEvent(kind: .volume, value: 0.62, until: now.addingTimeInterval(2))
        let states: [(String, IslandPresentation)] = [
            ("media", .compact(.nowPlaying(model.nowPlaying!))),
            ("timer", .compact(.activity(timer, others: 0))),
            ("hud", .hud(hud)),
            ("song-peek", .songPeek(model.nowPlaying!)),
        ]
        // Glass on displays without a notch, and the subtle outline. (Snapshots draw glass as
        // its solid stand-in.)
        do {
            model.settings.notchlessStyle = .pill
            model.settings.glassOnNotchless = true
            let s = model.settings
            let metrics = NotchGeometry.metrics(for: notchlessScreen, expandedSize: CGSize(width: s.expandedSize.width, height: s.expandedSize.height),
                                                wingWidth: s.effectiveWingWidth, adjust: s.notchAdjust, notchless: .pill)
            model.closedPlacements[2] = ClosedPlacement(wing: metrics.wingWidth, slack: .infinity)
            model.forcedPresentation = .compact(.nowPlaying(model.nowPlaying!))
            shootNotchless("51-notchless-pill-glass", model: model, metrics: metrics, dir: dir)
            model.settings.outline = true
            shootNotchless("51-notchless-pill-glass-outline", model: model, metrics: metrics, dir: dir)
            model.settings = saved
        }
        for style in [NotchlessStyle.pill, .notch] {
            model.settings.notchlessStyle = style
            let s = model.settings
            let metrics = NotchGeometry.metrics(for: notchlessScreen, expandedSize: CGSize(width: s.expandedSize.width, height: s.expandedSize.height),
                                                wingWidth: s.effectiveWingWidth, adjust: s.notchAdjust, notchless: style)
            model.closedPlacements[2] = ClosedPlacement(wing: metrics.wingWidth, slack: .infinity)
            for (name, presentation) in states {
                model.forcedPresentation = presentation
                shootNotchless("50-notchless-\(style.rawValue)-\(name)", model: model, metrics: metrics, dir: dir)
            }
        }
    }

    /// `<dir>/52-notchless-pill-morph-*.png`: the silhouette part of the way from the floating
    /// pill to the open island and to a song peek, one frame per row. Every frame should be a
    /// step between its neighbours: no jump from the pill to the hanging shape at the end.
    static func renderPillMorph(to dir: URL, model: AppModel) {
        let s = model.settings
        let metrics = NotchGeometry.metrics(for: notchlessScreen, expandedSize: CGSize(width: s.expandedSize.width, height: s.expandedSize.height),
                                            wingWidth: s.effectiveWingWidth, adjust: s.notchAdjust, notchless: .pill)
        guard let np = model.nowPlaying else { return }
        let wing = metrics.wingWidth
        let pill = IslandLayout.geometry(for: .compact(.nowPlaying(np)), metrics: metrics, wing: wing)
        let targets: [(String, IslandGeometry)] = [
            ("open", IslandLayout.geometry(for: .expanded, metrics: metrics, wing: wing, look: IslandLook(stemmedOpen: true))),
            ("song-peek", IslandLayout.geometry(for: .songPeek(np), metrics: metrics, wing: wing)),
        ]
        let steps: [Double] = [0, 0.2, 0.5, 0.8, 0.95, 0.99, 1]
        for (name, end) in targets {
            let frames = VStack(spacing: 0) {
                ForEach(steps, id: \.self) { k in
                    let g = morph(pill, end, k)
                    ZStack(alignment: .top) {
                        notchlessBackdrop(metrics: metrics)
                        g.shape.fill(Color.black).frame(width: g.outerWidth, height: g.size.height)
                    }
                    .frame(width: 760, height: end.size.height + 8)
                    .clipped()
                }
            }
            write(frames, to: dir.appendingPathComponent("52-notchless-pill-morph-\(name).png"))
        }
    }

    /// `a` moved `k` of the way to `b`, as the island's spring moves it.
    private static func morph(_ a: IslandGeometry, _ b: IslandGeometry, _ k: Double) -> IslandGeometry {
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * CGFloat(k) }
        var g = b
        g.size = CGSize(width: mix(a.size.width, b.size.width), height: mix(a.size.height, b.size.height))
        g.top = mix(a.top, b.top)
        g.bottom = mix(a.bottom, b.bottom)
        g.stemWidth = mix(a.stemWidth, b.stemWidth)
        g.stemHeight = mix(a.stemHeight, b.stemHeight)
        g.inset = mix(a.inset, b.inset)
        return g
    }

    static func shootNotchless(_ name: String, model: AppModel, metrics: IslandMetrics, dir: URL) {
        let view = IslandView(model: model, display: 2, metrics: metrics)
            .frame(width: 760, height: 140, alignment: .top)
            .background(notchlessBackdrop(metrics: metrics))
        write(view, to: dir.appendingPathComponent("\(name).png"))
    }

    /// A wallpaper with a menu bar strip and no notch.
    static func notchlessBackdrop(metrics: IslandMetrics) -> some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.62), Color(red: 0.62, green: 0.45, blue: 0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Rectangle().fill(Color.white.opacity(0.18)).frame(height: metrics.notch.height)
        }
    }
}
