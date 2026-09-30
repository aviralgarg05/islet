import AppKit
import CoreImage
import IsletCore
import SwiftUI

/// SwiftUI's `State` property wrapper under another name. The macOS 27 SDK turns `@ViewState`
/// into a macro whose plugin ships only with Xcode; using the wrapper type directly keeps
/// Islet buildable with the Command Line Tools alone.
typealias ViewState<Value> = SwiftUICore.State<Value>

/// The island silhouette: a rectangle hanging from the top edge whose top corners flare
/// outward (like the hardware notch) and whose bottom corners are rounded.
struct IslandShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(topRadius, rect.width / 4)
        let b = min(bottomRadius, (rect.width - 2 * t) / 2, rect.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t), control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY), control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b), control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

extension Color {
    init(tint: String?, fallback: Color = .accentColor) {
        if let tint, let c = RGBA.parse(tint) {
            self = Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
        } else {
            self = fallback
        }
    }

    static let islandSecondary = Color.white.opacity(0.62)
    static let islandTertiary = Color.white.opacity(0.38)
    static let islandFill = Color.white.opacity(0.10)
}

/// Renders any `ActivityIcon` (SF Symbol, emoji, app icon, file or remote image).
struct IconView: View {
    let icon: ActivityIcon
    var size: CGFloat = 16
    var tint: Color = .white

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : "questionmark.circle")
                .font(.system(size: size * 0.9, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
        case .emoji(let e):
            Text(e).font(.system(size: size * 0.85)).frame(width: size, height: size)
        case .app(let bundleID):
            AppIconView(bundleID: bundleID, size: size)
        case .file(let path):
            if let img = NSImage(contentsOfFile: path) {
                Image(nsImage: img).resizable().scaledToFit().frame(width: size, height: size)
            } else {
                Image(nsImage: IconCache.file(path, size: size)).resizable().frame(width: size, height: size)
            }
        case .url(let url):
            AsyncImage(url: url) { img in img.resizable().scaledToFit() } placeholder: { Color.islandFill }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        }
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
}

/// Album art with sensible fallbacks.
struct ArtworkView: View {
    let media: NowPlaying
    var size: CGFloat
    var corner: CGFloat

    var body: some View {
        Group {
            if let data = media.artworkData, let img = ArtworkCache.image(for: data) {
                Image(nsImage: img).resizable().scaledToFill()
            } else if let url = media.artworkURL {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { placeholder }
            } else if let bundle = media.bundleID, NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) != nil {
                AppIconView(bundleID: bundle, size: size * 0.8)
                    .frame(width: size, height: size)
                    .background(Color.islandFill)
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
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

    static func image(for data: Data) -> NSImage? {
        let key = data.hashValue
        if let img = images[key] { return img }
        guard let img = NSImage(data: data) else { return nil }
        if images.count > 16 { images.removeAll() }
        images[key] = img
        return img
    }

    /// Average color of the artwork, brightened so it reads on black.
    static func accent(for media: NowPlaying?) -> Color {
        guard let data = media?.artworkData else { return .white }
        let key = data.hashValue
        if let c = colors[key] { return c }
        guard let ci = CIImage(data: data) else { return .white }
        let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: ci, kCIInputExtentKey: CIVector(cgRect: ci.extent)])
        var px = [UInt8](repeating: 0, count: 4)
        guard let out = filter?.outputImage else { return .white }
        CIContext(options: [.workingColorSpace: NSNull()]).render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
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
            Circle().stroke(tint.opacity(0.25), lineWidth: lineWidth)
            if let progress {
                Circle()
                    .trim(from: 0, to: max(0.02, progress))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
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
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
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
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(tint).frame(width: max(height, geo.size.width * min(1, max(0, value))))
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
                    .fill(i < step ? tint : Color.white.opacity(0.18))
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

/// "Playing" equalizer (Core Animation; static bars in snapshots).
struct PlayingIndicator: View {
    var tint: Color
    var playing: Bool
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        if snapshotMode {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach([0.45, 0.8, 0.35, 0.65], id: \.self) { h in
                    RoundedRectangle(cornerRadius: 1.25).fill(tint).frame(width: 3, height: 14 * h)
                }
            }
            .frame(width: 18, height: 14, alignment: .bottom)
        } else {
            EqualizerView(color: NSColor(tint), playing: playing).frame(width: 18, height: 14)
        }
    }
}

struct PillButton: View {
    let symbol: String
    var size: CGFloat = 13
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.play(.tap)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size * 2.2, height: size * 2.2)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverButtonStyle())
    }
}

struct HoverButtonStyle: ButtonStyle {
    @ViewState private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(Color.white.opacity(configuration.isPressed ? 0.22 : hovering ? 0.12 : 0)))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .onHover { hovering = $0 }
    }
}

/// True while rendering offline snapshots (no platform views such as scroll views or drop targets).
private struct SnapshotModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var snapshotMode: Bool {
        get { self[SnapshotModeKey.self] }
        set { self[SnapshotModeKey.self] = newValue }
    }
}

/// A scroll view that only scrolls when it has to, and never in snapshot mode.
struct AdaptiveScroll<Content: View>: View {
    var axis: Axis.Set = .vertical
    var scrolls: Bool = true
    @ViewBuilder var content: Content
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        if scrolls && !snapshotMode {
            ScrollView(axis, showsIndicators: false) { content }
        } else {
            content
        }
    }
}
