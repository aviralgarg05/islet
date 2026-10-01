import AppKit
import IsletCore
import SwiftUI

extension Snapshots {
    /// The closed island's looks from Settings: paused music (the artwork dims and the indicator
    /// settles), the wave and pulse indicators, square and round artwork, the colourful HUDs and
    /// a notch fit. Full-width wings, as when the menu bar has room. Settings are put back after.
    static func renderClosedLooks(to dir: URL, model: AppModel, metrics: IslandMetrics, now: Date,
                                  metricsFor: (IsletSettings) -> IslandMetrics, shoot: (String) -> Void) {
        let saved = model.settings
        defer { model.settings = saved }
        model.closedPlacements[1] = ClosedPlacement(wing: metrics.wingWidth, slack: .infinity)
        let playing = model.nowPlaying!
        var paused = playing
        paused.isPlaying = false

        for style in [VisualiserStyle.bars, .wave, .pulse] {
            model.settings.visualiserStyle = style
            model.forcedPresentation = .compact(.nowPlaying(playing))
            shoot("40-compact-media-\(style.rawValue)")
            model.forcedPresentation = .compact(.nowPlaying(paused))
            shoot("40-compact-media-\(style.rawValue)-paused")
        }
        model.settings.visualiserStyle = saved.visualiserStyle
        model.forcedPresentation = .compact(.nowPlaying(playing))
        for (name, corner) in [("square", 0.0), ("round", 10.0)] {
            model.settings.artworkCornerRadius = corner
            shoot("40-compact-media-artwork-\(name)")
        }
        model.forcedPresentation = .songPeek(playing)
        shoot("40-song-peek-artwork-round")
        model.settings.artworkCornerRadius = saved.artworkCornerRadius

        model.settings.hudColour = .colourful
        for kind in HUDKind.allCases {
            model.forcedPresentation = .hud(HUDEvent(kind: kind, value: 0.62, until: now.addingTimeInterval(2)))
            shoot("41-hud-colourful-\(kind.rawValue)")
        }
        model.settings.hudColour = .accent
        model.settings.accentColor = "pink"
        model.forcedPresentation = .hud(HUDEvent(kind: .volume, value: 0.62, until: now.addingTimeInterval(2)))
        shoot("41-hud-accent-volume")
        model.settings = saved

        // A notch fit: 8 points wider and 2 shorter than the hardware notch drawn behind it.
        var fitted = saved
        fitted.notchWidthAdjust = 8
        fitted.notchHeightAdjust = -2
        model.settings = fitted
        let m = metricsFor(fitted)
        model.closedPlacements[1] = ClosedPlacement(wing: m.wingWidth, slack: .infinity)
        model.forcedPresentation = .compact(.nowPlaying(playing))
        let view = IslandView(model: model, display: 1, metrics: m)
            .frame(width: 760, height: m.expanded.height + 30)
            .background(backdrop(metrics: metrics))
        write(view, to: dir.appendingPathComponent("42-compact-media-notch-fit.png"))
        renderLiveIndicators(to: dir.appendingPathComponent("43-live-indicators.png"))
    }

    /// The layer-drawn indicators themselves (the island draws a stand-in in snapshots), at
    /// rest in each style: playing, just paused, and playing with Reduce Motion. Rows top to
    /// bottom, styles left to right; drawn large on black so their shapes can be checked.
    static func renderLiveIndicators(to url: URL) {
        let styles: [VisualiserStyle] = [.bars, .slim, .dots, .wave, .pulse]
        // (playing first, then, still): "just paused" plays first so it goes through the move.
        let rows: [(Bool?, Bool, Bool)] = [(nil, true, false), (true, false, false), (nil, true, true)]
        let cell = CGSize(width: 18, height: 14), gap: CGFloat = 10, scale: CGFloat = 6
        let size = CGSize(width: CGFloat(styles.count) * (cell.width + gap) + gap, height: CGFloat(rows.count) * (cell.height + gap) + gap)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
        ctx.scaleBy(x: scale, y: scale)
        // AppKit joins a view's layer to its parent's only inside a window, so the views sit in
        // one that is never shown.
        let window = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: 200, height: 200), styleMask: .borderless,
                              backing: .buffered, defer: false)
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        host.wantsLayer = true
        window.contentView = host
        defer { window.close() }
        for (r, row) in rows.enumerated() {
            for (c, style) in styles.enumerated() {
                let view = PlayingIndicatorNSView(style: style)
                view.frame = CGRect(origin: .zero, size: cell)
                host.addSubview(view)
                view.layoutSubtreeIfNeeded()
                if let first = row.0 { view.update(style: style, color: .systemOrange, playing: first, reduceMotion: row.2) }
                view.update(style: style, color: .systemOrange, playing: row.1, reduceMotion: row.2)
                view.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                CATransaction.flush()
                defer { view.removeFromSuperview() }
                ctx.saveGState()
                // Row 0 at the top.
                ctx.translateBy(x: gap + CGFloat(c) * (cell.width + gap), y: size.height - CGFloat(r + 1) * (cell.height + gap))
                view.layer?.render(in: ctx)
                ctx.restoreGState()
            }
        }
        guard let image = ctx.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}
