import AppKit
import CoreImage
import IsletCore
import SwiftUI

/// SwiftUI's `State` property wrapper under another name. The macOS 27 SDK turns `@State`
/// into a macro whose plugin ships only with Xcode; using the wrapper type directly keeps
/// Islet buildable with the Command Line Tools alone.
typealias ViewState<Value> = SwiftUICore.State<Value>

/// The island silhouette, hanging from the top edge of the screen.
///
/// Classic: a rectangle whose top corners flare outward like the hardware notch and whose
/// bottom corners are rounded. With a `stemWidth` narrower than the body, the part in the menu
/// bar row stays that narrow (the notch and its wings) and the body opens out below the menu
/// bar, joined by soft shoulders. The sneak peek uses it so menu bar icons beside the wings stay
/// uncovered. One shape covers both, so switching between them animates as a morph.
struct IslandShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    /// Width of the part inside the menu bar row. 0 (or ≥ body width) means classic.
    var stemWidth: CGFloat = 0
    /// Height of the menu bar row part.
    var stemHeight: CGFloat = 0
    /// A floating pill: a capsule this far inside the frame, top and bottom (0 = hangs from the
    /// top edge, with the flare).
    var inset: CGFloat = 0

    var animatableData: AnimatablePair<AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>, CGFloat> {
        get { AnimatablePair(AnimatablePair(AnimatablePair(topRadius, bottomRadius), AnimatablePair(stemWidth, stemHeight)), inset) }
        set {
            topRadius = newValue.first.first.first
            bottomRadius = newValue.first.first.second
            stemWidth = newValue.first.second.first
            stemHeight = newValue.first.second.second
            inset = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path { outline(in: rect, closed: true) }

    /// The silhouette; open (`closed: false`) leaves out the top edge, which sits at the top of
    /// the screen, so an outline traces only the sides and the bottom. A floating pill is
    /// always closed.
    ///
    /// A floating pill is the same outline `inset` points inside the frame, top and bottom,
    /// with its top corners rounded like its bottom ones instead of flared. The inset, that
    /// rounding and the flare all change together, so opening from the pill, or a peek growing
    /// out of it, morphs smoothly instead of jumping to the hanging shape at the end.
    ///
    /// `IslandSilhouette` solves the outline. Its shoulders grow with the body's overhang and its
    /// bottom corners keep their radius while the body is short, and a floating pill's end
    /// sweeps out in one curve before its shoulders form, so a morph never passes through
    /// square "ears" or a nub under the row.
    func outline(in rect: CGRect, closed: Bool) -> Path {
        let o = IslandSilhouette.solve(in: rect, topRadius: topRadius, bottomRadius: bottomRadius, stemWidth: stemWidth,
                                    stemHeight: stemHeight, inset: inset, pillInset: NotchGeometry.pillInset)
        let l = o.left, r = o.right
        var p = Path()
        p.move(to: l.start)
        p.addQuadCurve(to: l.topEnd, control: l.topControl)
        p.addLine(to: l.shoulderStart)
        p.addQuadCurve(to: l.junction, control: l.shoulderControl)
        p.addLine(to: l.cornerStart)
        p.addQuadCurve(to: l.cornerEnd, control: l.cornerControl)
        p.addLine(to: l.bottomStart)
        p.addQuadCurve(to: l.end, control: l.bottomControl)
        p.addLine(to: r.end)
        p.addQuadCurve(to: r.bottomStart, control: r.bottomControl)
        p.addLine(to: r.cornerEnd)
        p.addQuadCurve(to: r.cornerStart, control: r.cornerControl)
        p.addLine(to: r.junction)
        p.addQuadCurve(to: r.shoulderStart, control: r.shoulderControl)
        p.addLine(to: r.topEnd)
        p.addQuadCurve(to: r.start, control: r.topControl)
        if closed || o.floats { p.closeSubpath() }
        return p
    }
}

/// The island's outline without its top edge (Appearance → Subtle outline).
struct IslandEdge: Shape {
    var shape: IslandShape

    var animatableData: IslandShape.AnimatableData {
        get { shape.animatableData }
        set { shape.animatableData = newValue }
    }

    func path(in rect: CGRect) -> Path { shape.outline(in: rect, closed: false) }
}

extension Color {
    init(tint: String?, fallback: Color = .accentColor) {
        if let tint, let c = RGBA.parse(tint) {
            self = Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
        } else {
            self = fallback
        }
    }

    // Older names for the design system's ink and wash (DesignSystem.swift).
    @MainActor static var islandSecondary: Color { Ink.secondary }
    @MainActor static var islandTertiary: Color { Ink.tertiary }
    @MainActor static var islandFill: Color { Wash.regular }
}

/// Renders any `ActivityIcon` (SF Symbol, emoji, app icon, file or remote image).
struct IconView: View {
    let icon: ActivityIcon
    var size: CGFloat = 16
    var tint: Color = .white
    @Environment(\.islandMotion) private var motion

    var body: some View {
        switch icon {
        case .symbol(let name):
            // A new symbol (one stage giving way to the next) morphs into place.
            let known = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : "questionmark.circle"
            Image(systemName: known)
                .font(.system(size: Self.pointSize(known, size: size), weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(motion.symbolSwap)
                .animation(motion.inPlace, value: name)
                .frame(width: size, height: size)
        case .emoji(let e):
            Text(e).font(.system(size: size * 0.85)).frame(width: size, height: size)
        case .app(let bundleID):
            AppIconView(bundleID: bundleID, size: size)
        case .file(let path):
            Image(nsImage: IconCache.picture(path, size: size) ?? IconCache.file(path, size: size))
                .resizable().scaledToFit().frame(width: size, height: size)
        case .url(let url):
            AsyncImage(url: url) { img in img.resizable().scaledToFit() } placeholder: { Color.islandFill }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        }
    }

    @MainActor private static var widths: [String: CGFloat] = [:]

    /// The symbol's point size: 90% of `size`, less for a wide symbol ("video.fill") so it
    /// stays inside its square instead of crowding what sits beside it.
    @MainActor static func pointSize(_ name: String, size: CGFloat) -> CGFloat {
        let base = size * 0.9
        let key = "\(name)@\(base)"
        let width = widths[key] ?? {
            let config = NSImage.SymbolConfiguration(pointSize: base, weight: .semibold)
            let w = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)?.size.width ?? 0
            widths[key] = w
            return w
        }()
        return width > size ? base * size / width : base
    }
}

/// App and file icons rasterised once into bitmaps. `NSWorkspace` icons are lazy multi-resolution
/// images; drawing them fresh on every render is wasteful, and offline rendering can't use them.
@MainActor
enum IconCache {
    private static var cache: [String: NSImage] = [:]

    static func app(_ bundleID: String, size: CGFloat) -> NSImage? {
        let key = "app:\(bundleID)@\(Int(size))"
        if let hit = cache[key] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let img = rasterize(NSWorkspace.shared.icon(forFile: url.path), size: size)
        cache[key] = img
        return img
    }

    /// Largest image file used as an icon; anything bigger shows the file's Finder icon.
    static let pictureLimit = 5 * 1024 * 1024

    /// An image file used as an icon, decoded once per file version and size. Only regular
    /// files under `pictureLimit` are decoded, so a huge file can't stall the island.
    static func picture(_ path: String, size: CGFloat) -> NSImage? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              attrs[.type] as? FileAttributeType == .typeRegular,
              let bytes = (attrs[.size] as? NSNumber)?.intValue, bytes <= pictureLimit else { return nil }
        let stamp = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = "picture:\(path)@\(Int(size))#\(stamp)"
        if let hit = cache[key] { return hit }
        if failed.contains(key) { return nil }
        guard let img = NSImage(contentsOfFile: path) else {
            failed.insert(key)
            return nil
        }
        let out = rasterize(img, size: size)
        if cache.count > 400 { cache.removeAll() }
        cache[key] = out
        return out
    }

    private static var failed: Set<String> = []

    static func file(_ path: String, size: CGFloat) -> NSImage {
        let key = "file:\(path)@\(Int(size))"
        if let hit = cache[key] { return hit }
        let img = rasterize(NSWorkspace.shared.icon(forFile: path), size: size)
        if cache.count > 400 { cache.removeAll() }
        cache[key] = img
        return img
    }

    static func rasterize(_ image: NSImage, size: CGFloat, scale: CGFloat = 2) -> NSImage {
        let px = Int(size * scale)
        guard px > 0, let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0, bitsPerPixel: 0) else { return image }
        rep.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: NSSize(width: size, height: size))
        out.addRepresentation(rep)
        return out
    }
}

struct AppIconView: View {
    let bundleID: String
    var size: CGFloat = 16

    var body: some View {
        if let icon = IconCache.app(bundleID, size: size) {
            Image(nsImage: icon).resizable().frame(width: size, height: size)
        } else {
            Image(systemName: "app.fill").font(.system(size: size * 0.8)).foregroundStyle(Color.islandSecondary).frame(width: size, height: size)
        }
    }

    static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }
}

/// Album art with sensible fallbacks.
struct ArtworkView: View {
    let media: NowPlaying
    var size: CGFloat
    var corner: CGFloat

    var body: some View {
        if media.artworkData == nil, media.artworkURL == nil, let bundle = media.bundleID, AppIconView.isInstalled(bundle) {
            // No artwork: the player's own icon at full size. It carries its own shape, so no
            // tile behind it and no clip (a box in a box).
            AppIconView(bundleID: bundle, size: size)
        } else {
            Group {
                if let data = media.artworkData, let img = ArtworkCache.image(for: data) {
                    Image(nsImage: img).resizable().scaledToFill()
                } else if let url = media.artworkURL {
                    AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { placeholder }
                } else {
                    placeholder
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.islandFill
            Image(systemName: "music.note").font(.system(size: size * 0.45)).foregroundStyle(Color.islandSecondary)
        }
    }
}

/// Decodes artwork once and derives an accent color from it.
enum ArtworkCache {
    private static var images: [Int: NSImage] = [:]
    private static var colors: [Int: Color] = [:]
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    /// A cheap identity for artwork bytes (length and both ends), instead of hashing whole
    /// images on every render.
    static func key(_ data: Data) -> Int {
        var h = Hasher()
        h.combine(data.count)
        h.combine(data.prefix(512))
        h.combine(data.suffix(512))
        return h.finalize()
    }

    static func image(for data: Data) -> NSImage? {
        let key = key(data)
        if let img = images[key] { return img }
        guard let img = NSImage(data: data) else { return nil }
        if images.count >= 3 { images.removeAll() }
        images[key] = img
        return img
    }

    /// Average color of the artwork, brightened so it reads on black.
    static func accent(for media: NowPlaying?) -> Color {
        guard let data = media?.artworkData else { return .white }
        let key = key(data)
        if let c = colors[key] { return c }
        guard let ci = CIImage(data: data) else { return .white }
        let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: ci, kCIInputExtentKey: CIVector(cgRect: ci.extent)])
        var px = [UInt8](repeating: 0, count: 4)
        guard let out = filter?.outputImage else { return .white }
        context.render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        let ns = NSColor(srgbRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let color = Color(hue: Double(h), saturation: Double(min(1, s * 1.2)), brightness: Double(max(0.75, b)))
        if colors.count > 16 { colors.removeAll() }
        colors[key] = color
        return color
    }
}

struct ProgressRing: View {
    var progress: Double?
    var tint: Color
    var size: CGFloat = 16
    var lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            if let progress {
                // A neutral hairline track: the tint at low opacity reads as a muddy ring on black.
                Circle().stroke(Wash.ringTrack, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: max(0.02, progress))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                // Working with no known progress: the moving arc alone, no track.
                SpinnerArc(tint: tint, lineWidth: lineWidth)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Indeterminate spinner (Core Animation; static arc in snapshots).
struct SpinnerArc: View {
    var tint: Color
    var lineWidth: CGFloat
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        if snapshotMode {
            // A still can't spin, and a lone arc reads as a ring filled to a share. So the arc
            // trails off behind its head the way a turning one does.
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(AngularGradient(colors: [tint.opacity(0), tint], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(252)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        } else {
            LayerSpinner(color: NSColor(tint), lineWidth: lineWidth)
        }
    }
}

/// Slim level bar used by the HUD and media progress.
struct LevelBar: View {
    var value: Double
    var tint: Color = .white
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Wash.track)
                // Nothing at all for an empty or muted level: a minimum fill would leave a dot.
                Capsule().fill(tint).frame(width: value > 0 ? max(height, geo.size.width * min(1, value)) : 0)
            }
        }
        .frame(height: height)
    }
}

/// Segmented progress: one pill per step, filled up to the current step.
struct SegmentedBar: View {
    var steps: Int
    var step: Int
    var tint: Color
    var height: CGFloat = 4

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(1, min(steps, 24)), id: \.self) { i in
                Capsule()
                    .fill(i < step ? tint : Wash.track)
                    .overlay(Capsule().stroke(i == step - 1 ? Color.white.opacity(0.55) : .clear, lineWidth: 1))
            }
        }
        .frame(height: height)
    }
}

/// Progress for an activity: segmented when it has steps, a plain bar otherwise.
struct ActivityProgress: View {
    let activity: Activity
    let tint: Color
    var height: CGFloat = 4

    var body: some View {
        if let steps = activity.steps, let step = activity.step {
            SegmentedBar(steps: steps, step: step, tint: tint, height: height)
        } else if let p = activity.clampedProgress {
            LevelBar(value: p, tint: tint, height: height)
        }
    }
}

/// The "playing" indicator in the look chosen in Settings (Core Animation; its resting pose in
/// snapshots). 18 × 14 points in the island; `height` scales it for drawings in Settings.
struct PlayingIndicator: View {
    var tint: Color
    var playing: Bool
    var height: CGFloat = 14
    @Environment(\.snapshotMode) private var snapshotMode
    @Environment(\.visualiserStyle) private var style

    private var width: CGFloat { height * 18 / 14 }

    var body: some View {
        if style == .off {
            EmptyView()
        } else if snapshotMode {
            // Snapshots can't host the layer view: draw the resting pose of the same look.
            // Paused, every look settles on the middle line.
            still
                .opacity(playing ? 1 : Double(PausedLook.indicatorOpacity))
                .frame(width: width, height: height, alignment: playing ? .bottom : .center)
        } else {
            EqualizerView(color: NSColor(tint), playing: playing, style: style).frame(width: width, height: height)
        }
    }

    @ViewBuilder private var still: some View {
        let k = height / 14
        switch style {
        case .wave:
            let line = 1.5 * max(1, k)
            Path(IndicatorWave.path(in: CGRect(x: 0, y: 0, width: width, height: height),
                                    phase: IndicatorWave.stillPhase, amplitude: playing ? 1 : 0, lineWidth: line))
                .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
        case .pulse:
            ZStack {
                Circle().strokeBorder(tint, lineWidth: 1.5 * max(1, k))
                    .frame(width: height, height: height)
                    .scaleEffect(0.8)
                    .opacity(playing ? 0.45 : 0)
                Circle().fill(tint)
                    .frame(width: height / 2, height: height / 2)
                    .scaleEffect(playing ? 1 : 0.8)
            }
            .frame(width: height, height: height)
            .frame(width: width, height: height, alignment: .trailing)
        case .dots:
            HStack(alignment: playing ? .bottom : .center, spacing: 3 * k) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(tint).frame(width: 4 * k, height: 4 * k).offset(y: playing ? -CGFloat([3, 6, 2][i]) * k : 0)
                }
            }
        case .mirror:
            let heights = EqualizerNSView.mirrorLively
            let w = (width - 1.5 * k * 4) / 5
            HStack(alignment: .center, spacing: 1.5 * k) {
                ForEach(Array(heights.enumerated()), id: \.offset) { _, h in
                    RoundedRectangle(cornerRadius: min(1.25 * k, w / 2)).fill(tint)
                        .frame(width: w, height: height * (playing ? h : 0.2))
                }
            }
            .frame(height: height)
        case .vinyl:
            Circle().fill(tint)
                .frame(width: DotNSView.diameter * k, height: DotNSView.diameter * k)
                .scaleEffect(playing ? 1 : 0.8)
                .frame(width: width, height: height, alignment: .trailing)
        default:
            // Bars, slim bars, and the bars that stand in for a sticker outside the closed island.
            let heights: [CGFloat] = style == .slim ? [0.55, 0.9, 0.45, 0.75, 0.6, 0.8] : [0.45, 0.8, 0.35, 0.65]
            HStack(alignment: .bottom, spacing: (style == .slim ? 1.5 : 2) * k) {
                ForEach(Array(heights.enumerated()), id: \.offset) { _, h in
                    RoundedRectangle(cornerRadius: 1.25 * k).fill(tint)
                        .frame(width: (style == .slim ? 1.75 : 3) * k, height: height * (playing ? h : 0.2))
                }
            }
        }
    }
}

private struct VisualiserStyleKey: EnvironmentKey {
    static let defaultValue: VisualiserStyle = .bars
}

extension EnvironmentValues {
    /// How the playing indicator looks (Settings → Now Playing).
    var visualiserStyle: VisualiserStyle {
        get { self[VisualiserStyleKey.self] }
        set { self[VisualiserStyleKey.self] = newValue }
    }
}

/// Round hover wash and a little give when pressed, for borderless icon buttons.
struct HoverButtonStyle: ButtonStyle {
    @ViewState private var hovering = false
    @Environment(\.islandMotion) private var motion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(configuration.isPressed ? Wash.strong : hovering ? Wash.regular : .clear))
            .scaleEffect(configuration.isPressed ? Motion.pressScale : 1)
            .animation(Motion.press(motion), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

/// True while rendering offline snapshots (no platform views such as scroll views or drop targets).
private struct SnapshotModeKey: EnvironmentKey {
    static let defaultValue = false
}

/// Width left for a value in the closed island's trailing wing (infinite outside the wings).
private struct WingRoomKey: EnvironmentKey {
    static let defaultValue: CGFloat = .infinity
}

/// Islet's own "Reduce motion" or "Animation: Off", on top of the system setting.
private struct IslandReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

/// Loops are held completely still, not even breathing: animation Off or out-of-date content.
private struct IslandLoopsFrozenKey: EnvironmentKey {
    static let defaultValue = false
}

/// "Hide from screenshots" is on. A window kept out of captures can lose the backdrop Liquid
/// Glass samples and draw it as a black slab, so glass surfaces use their solid fill instead.
private struct HiddenFromCaptureKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var hiddenFromCapture: Bool {
        get { self[HiddenFromCaptureKey.self] }
        set { self[HiddenFromCaptureKey.self] = newValue }
    }
}

extension EnvironmentValues {
    var snapshotMode: Bool {
        get { self[SnapshotModeKey.self] }
        set { self[SnapshotModeKey.self] = newValue }
    }

    var islandReduceMotion: Bool {
        get { self[IslandReduceMotionKey.self] }
        set { self[IslandReduceMotionKey.self] = newValue }
    }

    /// Animation Off or out-of-date content: looping decorations don't even breathe.
    var islandLoopsFrozen: Bool {
        get { self[IslandLoopsFrozenKey.self] }
        set { self[IslandLoopsFrozenKey.self] = newValue }
    }

    var wingRoom: CGFloat {
        get { self[WingRoomKey.self] }
        set { self[WingRoomKey.self] = newValue }
    }

    /// Perpetual animations stop when either the system or Islet asks for less motion.
    var reduceMotionAnywhere: Bool { accessibilityReduceMotion || islandReduceMotion }

    /// How a looping decoration shows it is live: moving, breathing under Reduce Motion, or
    /// still with animation Off and on out-of-date content.
    var loopPose: IslandLoops.StillPose {
        IslandLoops.pose(reduceMotion: reduceMotionAnywhere, animationOff: islandLoopsFrozen)
    }
}

extension CAAnimation {
    /// Looping decorations don't need the display's full 120 Hz, and in Low Power Mode they
    /// run at half their usual rate rather than stopping.
    func capFrameRate() {
        let rate = IslandLoops.frameRate(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        preferredFrameRateRange = CAFrameRateRange(minimum: min(10, rate), maximum: rate, preferred: rate)
    }
}

/// A scroll view that only scrolls when it has to, and never in snapshot mode. When it has more
/// than fits, its far edge fades out, so the cut-off row reads as "more below" rather than as
/// content the island's edge has sliced through; the end can scroll clear of the fade.
struct AdaptiveScroll<Content: View>: View {
    var axis: Axis.Set = .vertical
    var scrolls: Bool = true
    @ViewBuilder var content: Content
    @Environment(\.snapshotMode) private var snapshotMode

    /// How far the fade reaches in from the edge.
    static var fade: CGFloat { Space.m }

    var body: some View {
        let horizontal = axis == .horizontal
        Group {
            if scrolls && !snapshotMode {
                ScrollView(axis, showsIndicators: false) {
                    content.padding(horizontal ? .trailing : .bottom, Self.fade)
                }
            } else if scrolls {
                // A snapshot shows it as the scroll view would, scrolled to the top.
                Color.clear
                    .overlay(alignment: .topLeading) { content.fixedSize(horizontal: horizontal, vertical: !horizontal) }
                    .clipped()
            } else {
                content
            }
        }
        .mask { OverflowFade(on: scrolls, horizontal: horizontal, length: Self.fade) }
    }
}

/// Opaque, with the last `length` points at the far edge fading to clear while `on`.
private struct OverflowFade: View {
    let on: Bool
    let horizontal: Bool
    let length: CGFloat

    var body: some View {
        let edge = LinearGradient(colors: [.black, .black.opacity(0)], startPoint: horizontal ? .leading : .top,
                                  endPoint: horizontal ? .trailing : .bottom)
            .frame(width: horizontal ? length : nil, height: horizontal ? nil : length)
        if !on {
            Rectangle()
        } else if horizontal {
            HStack(spacing: 0) { Rectangle(); edge }
        } else {
            VStack(spacing: 0) { Rectangle(); edge }
        }
    }
}
