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
        case .gif: return "GIF"
        case .off: return "None"
        }
    }

    private static let columns = Array(repeating: GridItem(.fixed(52), spacing: 8), count: 5)

    var body: some View {
        SettingsRow(title: "Playing indicator") {
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 10) {
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
                .frame(width: 52, height: 34)
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2.5 : 1)
                }
                Text(Self.name(style)).font(.caption).foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1).fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style == .gif ? "GIF sticker" : Self.name(style))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The GIF look's rows: which sticker, where it sits, how big, and whether it stays when
/// nothing plays. Shown only while the GIF look is chosen.
struct StickerSettingsRows: View {
    @Bindable var model: AppModel

    var body: some View {
        StickerGallery(model: model)
            .settingsAnchor("nowPlaying.sticker")
        if let problem = model.stickers.problem {
            Label(problem, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
        }
        SettingsSlider(title: "Left and right", value: $model.settings.sticker.offsetX, range: StickerSettings.offsetRange,
                       step: 1, format: Self.offset)
            .settingsAnchor("nowPlaying.stickerPosition")
        SettingsSlider(title: "Up and down", value: $model.settings.sticker.offsetY, range: StickerSettings.offsetRange,
                       step: 1, format: Self.offset)
        SettingsSlider(title: "Size", value: $model.settings.sticker.scale, range: StickerSettings.scaleRange, step: 0.1) {
            String(format: "%.1f×", $0)
        }
        .settingsAnchor("nowPlaying.stickerSize")
        Toggle(isOn: $model.settings.sticker.whenIdle) {
            Text("Also when nothing is playing")
            Text("The sticker rests beside the notch, still, instead of the island going away.")
        }
        .settingsAnchor("nowPlaying.stickerIdle")
    }

    /// "0 pt", "+3 pt", "−3 pt".
    static func offset(_ v: Double) -> String {
        let n = Int(v.rounded())
        return n == 0 ? "0 pt" : n > 0 ? "+\(n) pt" : "\u{2212}\(-n) pt"
    }
}

/// Islet's stickers, then yours, then "Add GIF…". Drop a file on it to add it too; a context
/// menu removes one of yours.
struct StickerGallery: View {
    @Bindable var model: AppModel
    @ViewState private var dropTargeted = false

    /// As many tiles a row as fit, so "Add GIF…" sits beside the others when there's room.
    private static let columns = [GridItem(.adaptive(minimum: 48, maximum: 48), spacing: 8, alignment: .top)]

    var body: some View {
        let library = model.stickers
        VStack(alignment: .leading, spacing: 6) {
            Text("Sticker")
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 8) {
                ForEach(BuiltInSticker.allCases, id: \.self) { b in
                    tile(.builtIn(b), name: b.title)
                }
                ForEach(Array(library.custom.enumerated()), id: \.element) { i, id in
                    tile(.custom(id), name: "Yours \(i + 1)")
                        .contextMenu {
                            Button("Remove", role: .destructive) { remove(id) }
                        }
                }
                if !library.isFull { addTile }
            }
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .opacity(dropTargeted ? 1 : 0)
            }
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                loadFileURLs(providers) { urls in add(urls) }
                return true
            }
            Text(library.isFull
                 ? "You have \(StickerLimits.maxCustom) of your own. Right-click one to remove it."
                 : "Add a GIF, animated PNG, WebP or HEIC of up to 5 MB, or drop one here. Right-click one of yours to remove it.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { library.loadIfNeeded() }
    }

    private func tile(_ choice: StickerChoice, name: String) -> some View {
        let selected = model.settings.sticker.choice == choice
        return Button {
            model.settings.sticker.id = choice.id
            model.stickers.problem = nil
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.black)
                    StickerThumbnail(library: model.stickers, choice: choice, size: 30)
                }
                .frame(width: 48, height: 40)
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2.5 : 1)
                }
                Text(name).font(.caption2).foregroundStyle(selected ? .primary : .secondary).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) sticker")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var addTile: some View {
        Button(action: choose) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    if model.stickers.adding {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "plus").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 48, height: 40)
                Text("Add GIF…").font(.caption2).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.stickers.adding)
        .settingsAnchor("nowPlaying.stickerAdd")
        .help("Add a GIF of your own")
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
