import AppKit
import ImageIO
import IsletCore
import IsletSystem
import SwiftUI

// MARK: - Clipboard

/// What you copied, each shown as itself: a link by where it goes, a colour as a swatch, a
/// picture as a thumbnail, files by their icons and names. A search field and a row of filters
/// (only for the kinds there are) sit on top; a click copies an item again.
struct ClipboardTab: View {
    let model: AppModel
    let size: CGSize

    var body: some View {
        if !model.settings.clipboardEnabled {
            EmptyHint(symbol: "doc.on.clipboard",
                      text: "Clipboard history is off. It stays on this Mac, skips passwords from password managers, and holds \(model.settings.clipboardLimit) items.") {
                Button("Turn on") { AppActions.setClipboard(model, enabled: true) }.buttonStyle(CapsuleButtonStyle(tint: .blue, filled: true))
            }
        } else if model.clipboard.entries.isEmpty {
            EmptyHint(symbol: "doc.on.clipboard", text: "Copy some text, a link, a colour, a picture or files, and it shows up here.")
        } else {
            let page = model.tools.clipboardPage
            let filters = model.clipboard.filters
            let active = filters.contains(page.filter) ? page.filter : .all
            let entries = model.clipboard.filtered(page.query, filter: active)
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(spacing: Space.s) {
                    IslandField(model: model, placeholder: "Search what you copied", text: Binding(get: { page.query }, set: { page.query = $0 }))
                    if filters.count > 2 {
                        ClipFilterBar(filters: filters, selected: active) { page.filter = $0 }
                    }
                }
                list(entries, query: page.query)
            }
        }
    }

    @ViewBuilder
    private func list(_ entries: [ClipboardEntry], query: String) -> some View {
        let clearable = model.clipboard.hasUnpinned
        if entries.isEmpty {
            Text(query.isEmpty ? "Nothing of this kind yet." : "Nothing you copied matches “\(query)”")
                .textStyle(.body)
                .foregroundStyle(Ink.tertiary)
                .lineLimit(1)
                .padding(.horizontal, Space.xs)
        } else {
            let rows = CGFloat(entries.count + (clearable ? 1 : 0)) * ClipRow.height
            AdaptiveScroll(scrolls: rows > size.height - IslandField.height - Space.s) {
                VStack(spacing: 0) {
                    ForEach(entries) { e in ClipRow(entry: e, model: model) }
                    // Quiet, after the last item; pinned items stay.
                    if clearable {
                        HStack {
                            Spacer(minLength: 0)
                            Button("Clear unpinned") { model.clearClipboard() }
                                .buttonStyle(.plain)
                                .textStyle(.caption)
                                .foregroundStyle(Ink.tertiary)
                                .help("Remove everything you haven't pinned")
                        }
                        .padding(.horizontal, Space.s)
                        .frame(height: 24)
                    }
                }
            }
            .padding(.horizontal, -Space.s)
        }
    }
}

/// All, Pinned and each kind there is, as glyphs; the chosen one says its name.
struct ClipFilterBar: View {
    let filters: [ClipFilter]
    let selected: ClipFilter
    let choose: (ClipFilter) -> Void
    @Namespace private var highlight
    @Environment(\.islandMotion) private var motion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(filters, id: \.self) { filter in
                let on = filter == selected
                Button {
                    Haptics.play(.tap)
                    choose(filter)
                } label: {
                    HStack(spacing: Space.xs) {
                        Image(systemName: Self.symbol(filter)).font(.system(size: 10, weight: .semibold))
                        if on { Text(filter.title).textStyle(.caption, emphasized: true).lineLimit(1).fixedSize() }
                    }
                    .foregroundStyle(on ? Ink.primary : Ink.tertiary)
                    .padding(.horizontal, on ? Space.s : 0)
                    .frame(minWidth: 24, minHeight: IslandField.height - 4)
                    .background {
                        if on { Capsule().fill(Wash.strong).matchedGeometryEffect(id: "filter", in: highlight) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(filter.title)
                .accessibilityLabel(filter.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Wash.regular))
        .contrastEdge(Capsule())
        .fixedSize()
        // The highlight slides like the page switcher's; a fade with less motion, none with Off.
        .animation(motion.inPlace, value: selected)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show")
    }

    static func symbol(_ filter: ClipFilter) -> String {
        switch filter {
        case .all: return "square.stack"
        case .pinned: return "pin"
        case .kind(.text): return "text.alignleft"
        case .kind(.link): return "link"
        case .kind(.colour): return "paintpalette"
        case .kind(.image): return "photo"
        case .kind(.files): return "doc"
        }
    }
}

struct ClipRow: View {
    let entry: ClipboardEntry
    let model: AppModel
    @ViewState private var hovering = false

    static let height: CGFloat = 28

    var body: some View {
        HStack(spacing: Space.s) {
            leading.frame(width: 18, height: 18)
            content
            Spacer(minLength: 0)
            if hovering, let open = openAction {
                Button(action: open.run) { Image(systemName: "arrow.up.forward").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Ink.tertiary)
                    .help(open.title)
            }
            if hovering || entry.pinned {
                Button { model.togglePinClip(entry.id) } label: {
                    Image(systemName: entry.pinned ? "pin.fill" : "pin").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(Ink.tertiary)
                .help(entry.pinned ? "Unpin" : "Pin")
            }
            if hovering {
                Button { model.removeClip(entry.id) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Ink.tertiary)
                    .help("Remove")
            }
        }
        .padding(.horizontal, Space.s)
        .frame(height: Self.height)
        .background(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).fill(hovering ? Wash.subtle : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { model.copyClip(entry) }
        .contextMenu {
            Button("Copy") { model.copyClip(entry) }
            if let open = openAction { Button(open.title, action: open.run) }
            Button(entry.pinned ? "Unpin" : "Pin") { model.togglePinClip(entry.id) }
            Divider()
            Button("Remove") { model.removeClip(entry.id) }
        }
        // The pin and × show only under the pointer, so VoiceOver has them as actions.
        .spokenButton(spoken, value: entry.pinned ? "pinned" : nil, hint: "Copies it") { model.copyClip(entry) }
        .accessibilityAction(named: entry.pinned ? "Unpin" : "Pin") { model.togglePinClip(entry.id) }
        .accessibilityAction(named: "Remove") { model.removeClip(entry.id) }
        .help("Click to copy")
    }

    /// A swatch, a thumbnail, the files' icon, or the app it was copied from.
    @ViewBuilder private var leading: some View {
        switch entry.kind {
        case .colour:
            if let c = entry.colour {
                Circle().fill(Color(red: c.r, green: c.g, blue: c.b, opacity: c.a))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
                    .frame(width: 14, height: 14)
            }
        case .image:
            if let thumb = ClipThumbnails.image(for: entry) {
                Image(nsImage: thumb).resizable().scaledToFill()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            } else {
                Image(systemName: "photo").font(.system(size: 12)).foregroundStyle(Ink.tertiary)
            }
        case .files:
            if let first = entry.paths.first {
                Image(nsImage: IconCache.file(first, size: 18)).resizable().frame(width: 18, height: 18)
            }
        case .link, .text:
            if let b = entry.sourceBundleID {
                AppIconView(bundleID: b, size: 16)
            } else if entry.kind == .link {
                Image(systemName: "link").font(.system(size: 11, weight: .semibold)).foregroundStyle(Ink.tertiary)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch entry.kind {
        case .link:
            if let parts = ClipLink.parts(entry.text) {
                (Text(parts.host).foregroundStyle(Ink.primary) + Text(parts.rest).foregroundStyle(Ink.tertiary))
                    .textStyle(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                plain
            }
        case .colour:
            HStack(spacing: Space.s) {
                Text(entry.text.trimmingCharacters(in: .whitespacesAndNewlines)).textStyle(.body, numeric: true).foregroundStyle(Ink.primary)
                if let c = entry.colour, ClipColour.hex(c).caseInsensitiveCompare(entry.text.trimmingCharacters(in: .whitespaces)) != .orderedSame {
                    Text(ClipColour.hex(c)).textStyle(.caption, numeric: true).foregroundStyle(Ink.tertiary)
                }
            }
            .lineLimit(1)
        case .image:
            HStack(spacing: Space.s) {
                Text("Image").textStyle(.body).foregroundStyle(Ink.primary)
                if let image = entry.image { Text(image.summary).textStyle(.caption, numeric: true).foregroundStyle(Ink.tertiary) }
            }
            .lineLimit(1)
        case .files:
            HStack(spacing: Space.s) {
                Text(entry.text).textStyle(.body).foregroundStyle(Ink.primary).lineLimit(1).truncationMode(.middle)
                if entry.paths.count > 1 {
                    Text("\(entry.paths.count) files").textStyle(.caption, numeric: true).foregroundStyle(Ink.tertiary).fixedSize()
                }
            }
        case .text:
            plain
        }
    }

    private var plain: some View {
        Text(entry.text.replacingOccurrences(of: "\n", with: " ⏎ "))
            .textStyle(.body)
            .foregroundStyle(Ink.primary)
            .lineLimit(1)
    }

    /// Open a link in the browser, or show files in Finder.
    private var openAction: (title: String, run: () -> Void)? {
        switch entry.kind {
        case .link:
            guard let url = ClipLink.url(entry.text) else { return nil }
            return ("Open in browser", { NSWorkspace.shared.open(url) })
        case .files:
            let urls = entry.paths.map { URL(fileURLWithPath: $0) }
            return ("Show in Finder", { ShelfService.reveal(urls) })
        default:
            return nil
        }
    }

    private var spoken: String {
        switch entry.kind {
        case .image: return "Image, \(entry.image?.summary ?? "")"
        case .files: return entry.paths.count == 1 ? "File, \(entry.text)" : "\(entry.paths.count) files, \(entry.text)"
        case .colour: return "Colour, \(entry.text)"
        case .link: return "Link, \(entry.text)"
        case .text: return entry.text.replacingOccurrences(of: "\n", with: " ")
        }
    }
}

/// Small thumbnails of copied pictures, made once per clip without drawing the full picture.
@MainActor
enum ClipThumbnails {
    private static var cache: [String: NSImage] = [:]

    static func image(for entry: ClipboardEntry) -> NSImage? {
        if let hit = cache[entry.id] { return hit }
        guard let data = entry.image?.data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 72,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
        if cache.count > 100 { cache.removeAll() }
        cache[entry.id] = image
        return image
    }

    /// Drops the thumbnails of clips no longer in the history.
    static func forget(except entries: [ClipboardEntry]) {
        guard !cache.isEmpty else { return }
        let keep = Set(entries.lazy.filter { $0.image != nil }.map(\.id))
        guard cache.keys.contains(where: { !keep.contains($0) }) else { return }
        cache = cache.filter { keep.contains($0.key) }
    }
}
