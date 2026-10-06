import AppKit
import CasementCore
import SwiftUI

/// Settings → Advanced → iPhone bridge: the switch, its port, the bridge's own token, and
/// what it can and can't do.
struct LANBridgeSection: View {
    @Bindable var model: AppModel
    @ViewState private var copied = false
    @ViewState private var confirming = false
    @Environment(\.snapshotMode) private var snapshotMode

    private var enabled: Bool { model.settings.lanBridgeEnabled }
    /// The bridge only runs while the local API does.
    private var apiOn: Bool { model.settings.apiEnabled }

    var body: some View {
        Section {
            Toggle(isOn: $model.settings.lanBridgeEnabled) {
                Text("Accept requests from this network")
                Text("Lets Shortcuts on your iPhone, Home Assistant and other devices on this network show things in the island.")
            }
            .disabled(!apiOn)
            .task(id: enabled) {
                if enabled { model.lan.loadToken() }
            }
            .settingsAnchor("advanced.bridge")
            if !apiOn {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary).font(.callout)
                    Text("Needs Accept requests from apps on this Mac.").font(.callout).foregroundStyle(.secondary)
                }
            }
            LabeledContent("Status") { Text(model.lan.status).foregroundStyle(.secondary) }
            LabeledContent("Port") { PortField(port: $model.settings.lanPort, other: model.settings.apiPort) }
                .settingsAnchor("advanced.bridgePort")
            LabeledContent("Token") {
                HStack(spacing: 8) {
                    if enabled, let token = model.lan.token {
                        Text("Ends in \(String(token.suffix(4)))").foregroundStyle(.secondary).monospacedDigit()
                        Button(copied ? "Copied" : "Copy") {
                            Self.copy(token)
                            copied = true
                        }
                        Button("New token…") { confirming = true }
                    } else {
                        Text("Made when the bridge is on").foregroundStyle(.secondary)
                    }
                }
            }
            .settingsAnchor("advanced.bridgeToken")
            .alert("Make a new bridge token?", isPresented: $confirming) {
                Button("New token") {
                    model.lan.rotateToken()
                    copied = false
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Shortcuts that send the current token stop working until you give them the new one.")
            }
            if enabled {
                // Verbatim, so the port isn't shown as "47,832".
                CodeBlock(title: "In Shortcuts on iPhone, add Get Contents of URL",
                          code: "POST http://\(host):\(model.settings.lanPort)/v1/notify\nAuthorization: Bearer <token>\n{\"title\": \"…\"}")
            }
        } header: {
            Text("iPhone bridge")
        } footer: {
            SettingsFooter("The bridge is not encrypted, so anyone on this network can read what is sent, token included. It only takes notifications, timers, Focus and simple activities, without links, buttons or image files, and its token doesn't work on the local API.")
        }
    }

    /// This Mac's name on the network; snapshots show a stand-in rather than the real one.
    private var host: String { snapshotMode ? "my-mac.local" : ProcessInfo.processInfo.hostName }

    /// Concealed and transient, so clipboard managers skip it. Unlike the API token it isn't
    /// kept to this Mac: the token is needed on the iPhone.
    static func copy(_ token: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(token, forType: .string)
        pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
    }
}

/// Text to copy into a terminal, a file or another app, with a Copy button.
struct CodeBlock: View {
    let title: String
    let code: String
    /// Long blocks scroll inside this height, with the bottom edge fading to say there is more.
    var maxHeight: CGFloat = 150
    @ViewState private var copied = false
    @ViewState private var width: CGFloat = 0

    /// Space round the code inside its box.
    private static let inset: CGFloat = 8
    /// How far the fade at the bottom of a block that scrolls reaches in.
    private static let fade: CGFloat = 24

    var body: some View {
        // Measured from the box's width, which doesn't depend on what is in it.
        let height = width > 0 ? CodeText.height(code, width: width - Self.inset * 2) + Self.inset * 2 : 0
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.callout)
                Spacer(minLength: 8)
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                }
            }
            // Every line wraps, at spaces only, so nothing is out of sight sideways and a path
            // never splits at a slash.
            let text = CodeText(code: code).padding(Self.inset)
            Group {
                if height > maxHeight {
                    // Taller than it may be: it scrolls, and the end can scroll clear of the fade.
                    ScrollView(.vertical) {
                        text.padding(.bottom, Self.fade)
                    }
                    .frame(height: maxHeight)
                    .mask {
                        VStack(spacing: 0) {
                            Rectangle()
                            LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                                .frame(height: Self.fade)
                        }
                    }
                } else {
                    text
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.05)))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }
        .padding(.vertical, 2)
    }
}

/// Monospaced code that wraps only at spaces (`CodeWrap`), so a long path moves to the next
/// line whole rather than splitting at a slash, and a wrapped line goes on a little further in.
/// Selectable, and copies exactly the code.
private struct CodeText: NSViewRepresentable {
    let code: String

    private static let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private static let advance = ("0" as NSString).size(withAttributes: [.font: font]).width

    func makeNSView(context: Context) -> NSTextView {
        let view = CodeTextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.isRichText = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        // Until a width is known, the code as it is; `sizeThatFits` wraps it for its width.
        if context.coordinator.code != code { show(in: view, columns: nil, context.coordinator) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: NSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let columns = Self.columns(width)
        if context.coordinator.code != code || context.coordinator.columns != columns {
            show(in: view, columns: columns, context.coordinator)
        }
        return CGSize(width: width, height: Self.height(code, width: width))
    }

    private func show(in view: NSTextView, columns: Int?, _ shown: Shown) {
        shown.code = code
        shown.columns = columns
        view.textStorage?.setAttributedString(Self.attributed(code, columns: columns))
    }

    func makeCoordinator() -> Shown { Shown() }

    /// What the view holds, so it is set again only when the code or the width changes.
    final class Shown {
        var code: String?
        var columns: Int?
    }

    /// Whole characters that fit in `width`, with a little to spare so layout never wraps again.
    private static func columns(_ width: CGFloat) -> Int { max(1, Int(((width - 0.5) / advance).rounded(.down))) }

    /// The height the code takes at `width`.
    static func height(_ code: String, width: CGFloat) -> CGFloat {
        let storage = NSTextStorage(attributedString: attributed(code, columns: columns(width)))
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: max(1, width), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        return ceil(layout.usedRect(for: container).height)
    }

    /// The code wrapped for `columns`, each line with its hanging indent.
    private static func attributed(_ code: String, columns: Int?) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false)
        for (i, line) in lines.enumerated() {
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byWordWrapping
            if let columns { style.headIndent = CGFloat(CodeWrap.hangingIndent(line, columns: columns)) * advance }
            let text = (columns.map { CodeWrap.wrapped(String(line), columns: $0) } ?? String(line)) + (i < lines.count - 1 ? "\n" : "")
            out.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor,
                                                                    .paragraphStyle: style]))
        }
        return out
    }
}

/// Copies and drags the code with the spaces it wrapped at, not the line ends shown there.
private final class CodeTextView: NSTextView {
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }

    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let all = string as NSString
        let selected = selectedRanges.map { all.substring(with: $0.rangeValue) }.joined(separator: "\n")
        pboard.declareTypes([.string], owner: nil)
        return pboard.setString(CodeWrap.copied(selected), forType: .string)
    }
}
