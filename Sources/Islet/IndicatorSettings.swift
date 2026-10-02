import AppKit
import IsletCore
import IsletSystem
import SwiftUI
import UniformTypeIdentifiers

// Settings → Now Playing → Look: the playing indicator's looks, and for the GIF look the
// sticker gallery (Islet's own and yours), its position and size, and whether it stays when
// nothing plays.

/// The playing indicator's looks, each drawn as it moves in the island.
struct IndicatorStylePicker: View {
    @Bindable var model: AppModel

    /// In the order the grid shows them: five, then four.
    static let styles: [VisualiserStyle] = [.bars, .slim, .dots, .mirror, .wave, .pulse, .vinyl, .gif, .off]

    static func name(_ style: VisualiserStyle) -> String {
        switch style {
        case .bars: return "Bars"
        case .slim: return "Slim bars"
        case .dots: return "Dots"
        case .mirror: return "Mirror"
        case .wave: return "Wave"
        case .pulse: return "Pulse"
        case .vinyl: return "Vinyl"
        case .gif: return "Sticker"
        case .off: return "None"
        }
    }

    private static let columns = Array(repeating: GridItem(.fixed(LookTile.width), spacing: LookTile.spacing), count: 5)

    var body: some View {
        // The label above its grid, as the sticker gallery's is, so both grids start at the same edge.
        VStack(alignment: .leading, spacing: 6) {
            Text("Playing indicator")
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: LookTile.spacing) {
                ForEach(Self.styles, id: \.self) { style in
                    tile(style)
                }
            }
            .fixedSize()
            // Islet's own Reduce motion holds the previews still, as it does the island.
            .environment(\.islandReduceMotion, model.settings.reduceMotion || model.settings.animationStyle == .off)
        }
    }

    private func tile(_ style: VisualiserStyle) -> some View {
        let selected = model.settings.visualiserStyle == style
        let tint = IslandSketch.indicatorTint(model.settings)
        return Button { model.settings.visualiserStyle = style } label: {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.black)
                    switch style {
                    case .off:
                        Image(systemName: "nosign").foregroundStyle(.white.opacity(0.45))
                    case .vinyl:
                        HStack(spacing: 6) {
                            VinylDisc(image: IslandSketch.artworkImage, size: 18, tint: tint, playing: true)
                            PlayingIndicator(tint: tint, playing: true, height: 10).environment(\.visualiserStyle, .vinyl)
                                .frame(width: 8)
                        }
                    case .gif:
                        StickerThumbnail(library: model.stickers, choice: model.stickers.resolved(model.settings.sticker), size: 26)
                    default:
                        PlayingIndicator(tint: tint, playing: true).environment(\.visualiserStyle, style)
                    }
                }
                .frame(width: LookTile.width, height: LookTile.height)
                .modifier(TileOutline(selected: selected, cornerRadius: 7))
                Text(Self.name(style)).font(LookTile.font).foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1).fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.name(style))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The tiles of the indicator and sticker pickers: one size and one caption for both.
enum LookTile {
    static let width: CGFloat = 52
    static let height: CGFloat = 38
    static let spacing: CGFloat = 8
    static let font = Font.caption
}

/// The Sticker look's rows: which sticker, where it sits, how big, and whether it stays when
/// nothing plays. Shown only while the Sticker look is chosen. The sliders reach only as far
/// as the menu bar row lets the sticker go (`StickerLayout`).
struct StickerSettingsRows: View {
    @Bindable var model: AppModel

    var body: some View {
        let sticker = model.settings.sticker
        let row = IslandSketch.notch.height
        let wing = model.settings.effectiveWingWidth
        let inset = Wings<EmptyView, EmptyView>.inset(for: wing)
        let across = StickerLayout.horizontalRange(room: wing - inset, row: row, outerSpace: inset / 2,
                                                   aspect: model.stickers.aspect(model.stickers.resolved(sticker)), scale: sticker.scale)
        let upDown = StickerLayout.verticalReach(row: row, scale: sticker.scale)
        StickerGallery(model: model)
            .settingsAnchor("nowPlaying.sticker")
        if let problem = model.stickers.problem {
            Label(problem, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
        }
        SettingsSlider(title: "Left and right", value: $model.settings.sticker.offsetX, range: Self.usable(across),
                       step: 1, format: Self.offset)
            .disabled(across.lowerBound == across.upperBound)
            .settingsAnchor("nowPlaying.stickerPosition")
        SettingsSlider(title: "Up and down", value: $model.settings.sticker.offsetY, range: Self.usable(-upDown...upDown),
                       step: 1, format: Self.offset)
            // Filling the row, it has nowhere to go.
            .disabled(upDown == 0)
        SettingsSlider(title: "Size", value: $model.settings.sticker.scale, range: StickerLayout.scaleRange(row: row), step: 0.1) {
            String(format: "%.1f×", $0)
        }
        .settingsAnchor("nowPlaying.stickerSize")
        Toggle(isOn: $model.settings.sticker.whenIdle) {
            Text("Also when nothing is playing")
            Text("The sticker rests beside the notch, still, instead of the island going away.")
        }
        .settingsAnchor("nowPlaying.stickerIdle")
    }

    /// A slider needs some width to its range: one with none draws, disabled, round 0.
    static func usable(_ range: ClosedRange<Double>) -> ClosedRange<Double> {
        range.lowerBound < range.upperBound ? range : -1...1
    }

    /// "0 pt", "+3 pt", "−3 pt".
    static func offset(_ v: Double) -> String {
        let n = Int(v.rounded())
        return n == 0 ? "0 pt" : n > 0 ? "+\(n) pt" : "\u{2212}\(-n) pt"
    }
}

/// Islet's stickers, then yours, then "Add…". Drop a file on it to add it too; a context
/// menu removes one of yours.
struct StickerGallery: View {
    @Bindable var model: AppModel
    @ViewState private var dropTargeted = false

    /// As many tiles a row as fit, so "Add…" sits beside the others when there's room.
    private static let columns = [GridItem(.adaptive(minimum: LookTile.width, maximum: LookTile.width), spacing: LookTile.spacing, alignment: .top)]

    var body: some View {
        let library = model.stickers
        // The one the island shows: the cat stands in for one of yours whose file has gone.
        let shown = library.resolved(model.settings.sticker)
        VStack(alignment: .leading, spacing: 6) {
            Text("Sticker")
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: LookTile.spacing) {
                ForEach(BuiltInSticker.allCases, id: \.self) { b in
                    tile(.builtIn(b), name: b.title, selected: shown == .builtIn(b))
                }
                ForEach(Array(library.custom.enumerated()), id: \.element) { i, id in
                    tile(.custom(id), name: "Yours \(i + 1)", selected: shown == .custom(id))
                        .contextMenu {
                            Button("Remove", role: .destructive) { remove(id) }
                        }
                        // Without a pointer: Delete on the focused tile, or VoiceOver's action.
                        .onDeleteCommand { remove(id) }
                        .accessibilityAction(named: "Remove") { remove(id) }
                }
                if !library.isFull { addTile }
            }
            // The tiles start at the label's edge; the drop outline stands a little outside them.
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .padding(-4)
                    .opacity(dropTargeted ? 1 : 0)
            }
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                loadFileURLs(providers) { urls in add(urls) }
                return true
            }
            Text(library.isFull
                 ? "You have \(StickerLimits.maxCustom) of your own. Right-click one, or press Delete on it, to remove it."
                 : "Add a GIF, animated PNG, WebP or HEIC of up to 5 MB, or drop one here. Right-click one of yours, or press Delete on it, to remove it.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Read the folder each time the gallery shows, so a sticker removed in Finder doesn't
        // linger as an empty tile.
        .onAppear { library.reload() }
    }

    private func tile(_ choice: StickerChoice, name: String, selected: Bool) -> some View {
        Button {
            model.settings.sticker.id = choice.id
            model.stickers.problem = nil
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.black)
                    StickerThumbnail(library: model.stickers, choice: choice, size: 30)
                }
                .frame(width: LookTile.width, height: LookTile.height)
                .modifier(TileOutline(selected: selected, cornerRadius: 7))
                Text(name).font(LookTile.font).foregroundStyle(selected ? .primary : .secondary).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) sticker")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var addTile: some View {
        Button(action: choose) {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    if model.stickers.adding {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "plus").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: LookTile.width, height: LookTile.height)
                Text("Add…").font(LookTile.font).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.stickers.adding)
        .settingsAnchor("nowPlaying.stickerAdd")
        .help("Add a sticker of your own: a GIF, animated PNG, WebP or HEIC")
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = StickerDecoder.types
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose a GIF, animated PNG, WebP or HEIC to show beside the notch."
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    private func add(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task { @MainActor in
            if let id = await model.stickers.add(urls) {
                model.settings.sticker.id = StickerChoice.custom(id).id
            }
        }
    }

    private func remove(_ id: String) {
        if model.settings.sticker.choice == .custom(id) { model.settings.sticker.id = BuiltInSticker.cat.rawValue }
        model.stickers.remove(id)
    }
}

/// The sticker in Settings' drawing of the closed island: placed as in the island, at the
/// drawing's scale.
struct StickerSketch: View {
    let library: StickerLibrary
    let settings: IsletSettings
    var scale: CGFloat
    var playing: Bool

    var body: some View {
        let wing = settings.effectiveWingWidth
        let inset = Wings<EmptyView, EmptyView>.inset(for: wing)
        let row = IslandSketch.notch.height
        let room = wing - inset
        let choice = library.resolved(settings.sticker)
        let rect = StickerLayout.frame(room: room, row: row, outerSpace: inset / 2, aspect: library.aspect(choice),
                                       settings: settings.sticker)
        ZStack(alignment: .topLeading) {
            StickerView(library: library, choice: choice, mode: playing ? .playing : .paused)
                .frame(width: rect.width * scale, height: rect.height * scale)
                .offset(x: rect.minX * scale, y: rect.minY * scale)
        }
        .frame(width: room * scale, height: row * scale, alignment: .topLeading)
    }
}

private struct StickerLibraryKey: EnvironmentKey {
    static let defaultValue: StickerLibrary? = nil
}

extension EnvironmentValues {
    /// The stickers, for Settings' drawings of the island.
    var stickerLibrary: StickerLibrary? {
        get { self[StickerLibraryKey.self] }
        set { self[StickerLibraryKey.self] = newValue }
    }
}
