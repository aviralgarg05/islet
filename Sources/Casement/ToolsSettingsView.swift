import AppKit
import CasementCore
import CasementSystem
import SwiftUI

// Settings → Tools, continued: the camera mirror, the teleprompter, stocks and sales. Each starts
// off and, once on, is a page under the switcher's "More" menu. The page itself is ToolsSettings.

struct MirrorSettingsSection: View {
    @Bindable var model: AppModel
    @ViewState private var access = PermissionStatus.notDetermined
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        Section {
            Toggle(isOn: $model.settings.mirror.enabled) {
                Text("Camera mirror")
                Text("Your camera in the island, for a quick look before a call. It’s on only while the Mirror page is open, and nothing is recorded.")
            }
            .settingsAnchor("tools.mirror")
            if model.settings.mirror.enabled {
                Toggle("Flip like a mirror", isOn: $model.settings.mirror.flipped)
                    .settingsAnchor("tools.mirrorFlip")
                if access == .denied || access == .restricted {
                    AccessRow(text: "Casement isn’t allowed to use the camera.", button: "Open System Settings") {
                        NSWorkspace.shared.open(PermissionKind.camera.settingsURL)
                    }
                }
            }
        } header: {
            Text("Mirror")
        }
        // Read again when Casement comes back (from System Settings, say) and when the island's
        // Mirror page asks, so the row follows a change made while this page shows.
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .onChange(of: model.mirror.access) { _, _ in refresh() }
    }

    private func refresh() {
        guard !snapshotMode else { return }
        let now = CameraMirror.access
        if access != now { access = now }
    }
}

struct TeleprompterSettingsSection: View {
    @Bindable var model: AppModel

    /// Six lines of the script, with the editor's padding.
    static let editorHeight: CGFloat = {
        let line = NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: NSFont.systemFontSize))
        return (line * 6).rounded(.up) + 12
    }()

    var body: some View {
        let t = model.teleprompter
        let pace = model.settings.teleprompter.wordsPerMinute
        Section {
            Toggle(isOn: $model.settings.teleprompter.enabled) {
                Text("Show the teleprompter")
                Text("A script that moves up just under the camera, so you read it while looking into the lens.")
            }
            .settingsAnchor("tools.teleprompter")
            if model.settings.teleprompter.enabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Script")
                    TextEditor(text: Binding(get: { t.script }, set: { t.setScript($0) }))
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                        // Whole lines, so the last one isn't cut through.
                        .frame(height: Self.editorHeight)
                        .accessibilityLabel("Script")
                    Text(t.words == 0 ? "Type or paste what you’ll say."
                         : "\(t.words) words. \(Teleprompter.durationLabel(words: t.words, wordsPerMinute: pace)) at this speed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .settingsAnchor("tools.script")
                SettingsSlider(title: "Words a minute", value: $model.settings.teleprompter.wordsPerMinute,
                               range: TeleprompterSettings.wordsPerMinuteRange, step: TeleprompterSettings.wordsPerMinuteStep) {
                    "\(Int($0))"
                }
                .settingsAnchor("tools.teleprompterSpeed")
                SettingsSlider(title: "Text size", value: $model.settings.teleprompter.textSize,
                               range: TeleprompterSettings.textSizeRange, step: 1, format: SettingsSlider.points)
                    .settingsAnchor("tools.teleprompterSize")
                Toggle(isOn: $model.settings.teleprompter.seeThrough) {
                    Text("See-through while reading")
                    Text("The open island turns to clear glass while the script shows.")
                }
                .settingsAnchor("tools.seeThrough")
            }
        } header: {
            Text("Teleprompter")
        } footer: {
            if model.settings.teleprompter.enabled {
                SettingsFooter("Play it from the Teleprompter page. Scroll over the script to move it by hand. The script stays on this Mac.")
            }
        }
        .onAppear { t.load() }
    }
}

struct StocksSettingsSection: View {
    @Bindable var model: AppModel
    @ViewState private var draft = ""
    @ViewState private var note: String?

    var body: some View {
        Section {
            Toggle(isOn: $model.settings.stocks.enabled) {
                Text("Show stocks")
                Text("A watchlist with each price, the day’s change and a line for the day.")
            }
            .settingsAnchor("tools.stocks")
            if model.settings.stocks.enabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Watchlist")
                    FlowLayout(spacing: 6) {
                        ForEach(model.settings.stocks.symbols, id: \.self) { symbol in
                            SymbolChip(symbol: symbol) { model.settings.stocks.symbols.removeAll { $0 == symbol } }
                        }
                    }
                    HStack(spacing: 8) {
                        TextField("", text: $draft, prompt: Text("Add a symbol, such as AAPL or ^GSPC"))
                            .multilineTextAlignment(.leading)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 260)
                            .onSubmit(add)
                        Button("Add", action: add)
                            .disabled(StocksAPI.normalisedSymbol(draft) == nil
                                      || model.settings.stocks.symbols.count >= StocksSettings.maxSymbols)
                    }
                    if let note { Text(note).font(.caption).foregroundStyle(.orange) }
                }
                .settingsAnchor("tools.stockSymbols")
            }
        } header: {
            Text("Stocks")
        } footer: {
            if model.settings.stocks.enabled {
                SettingsFooter("Prices come from Yahoo Finance, without an account, and only while the Stocks page is open. They may be delayed. Indices start with ^, currencies end in =X.")
            }
        }
    }

    private func add() {
        guard let symbol = StocksAPI.normalisedSymbol(draft) else {
            note = "Use letters, digits and . - ^ = only."
            return
        }
        note = nil
        draft = ""
        guard !model.settings.stocks.symbols.contains(symbol) else { return }
        guard model.settings.stocks.symbols.count < StocksSettings.maxSymbols else {
            note = "The watchlist holds \(StocksSettings.maxSymbols) symbols."
            return
        }
        model.settings.stocks.symbols.append(symbol)
    }
}

/// "AAPL ×" in the watchlist.
private struct SymbolChip: View {
    let symbol: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(symbol).font(.system(.callout, design: .monospaced))
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).frame(width: 12, height: 12).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove \(symbol)")
            .accessibilityLabel("Remove \(symbol)")
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(height: 22)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
    }
}

struct SalesSettingsSection: View {
    @Bindable var model: AppModel

    var body: some View {
        Section {
            Toggle(isOn: $model.settings.sales.enabled) {
                Text("Sales today")
                Text("Today’s takings from your stores, as one total and per store, on the Sales page.")
            }
            .settingsAnchor("tools.sales")
            if model.settings.sales.enabled {
                ForEach(Array(SalesStore.allCases.enumerated()), id: \.element) { i, store in
                    SalesStoreRow(model: model, store: store)
                        .settingsAnchor(i == 0 ? "tools.salesStores" : "tools.salesStore.\(store.rawValue)")
                }
            }
        } header: {
            Text("Sales")
        } footer: {
            if model.settings.sales.enabled {
                SettingsFooter("Keys stay in your Keychain, and Casement only reads. While this is on and the Mac is unlocked, Casement asks each connected store every 15 minutes, and when you open the Sales page.")
            }
        }
    }
}

/// A store: connected (with Remove), or Connect… with its key, and Shopify's address.
private struct SalesStoreRow: View {
    @Bindable var model: AppModel
    let store: SalesStore
    @ViewState private var connecting = false
    @ViewState private var draft = ""
    @ViewState private var shop = ""
    @ViewState private var checking = false
    @ViewState private var error: String?
    @ViewState private var confirmingDisconnect = false

    private var connected: Bool { model.settings.sales.stores.contains(store) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                // The store's colour, square so it isn't read as a status dot.
                RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(Color(tint: store.tint)).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(store.title)
                        if connected, store == .shopify, let host = SalesAPI.shopifyHost(model.settings.sales.shopifyStore) {
                            Text(host).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    // As a coding agent's connection reads: a dot and a few words under the name.
                    if connected {
                        let problem = model.sales.stores.first(where: { $0.store == store })?.problem
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            StatusDot(colour: problem == nil ? .green : .orange)
                            // The same few words the island's Sales page shows for it.
                            Text(problem?.shortText ?? "Connected")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .help(problem?.text(store.title) ?? "")
                    }
                }
                Spacer(minLength: 8)
                if connected {
                    Button("Disconnect\u{2026}") { confirmingDisconnect = true }
                        .confirmationDialog("Disconnect \(store.title)?", isPresented: $confirmingDisconnect) {
                            Button("Disconnect", role: .destructive) {
                                model.sales.disconnect(store)
                                model.settings.sales.stores.removeAll { $0 == store }
                            }
                        } message: {
                            Text("Its key is removed from your Keychain. You can connect it again at any time.")
                        }
                } else if !connecting {
                    Button("Connect…") {
                        connecting = true
                        shop = model.settings.sales.shopifyStore
                    }
                }
            }
            if connecting && !connected {
                if store == .shopify {
                    TextField("", text: $shop, prompt: Text("Store address, such as example.myshopify.com"))
                        .multilineTextAlignment(.leading)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                }
                HStack(spacing: 8) {
                    SecureField("", text: $draft, prompt: Text(store.hasReadOnlyKeys ? "Paste a read-only key" : "Paste a key"))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                        .onSubmit(save)
                    Button(checking ? "Checking…" : "Save", action: save)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || checking)
                    Button("Cancel") {
                        connecting = false
                        draft = ""
                        error = nil
                    }
                }
                Text(error ?? store.keyHelp)
                    .font(.caption)
                    .foregroundStyle(error == nil ? Color.secondary : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func save() {
        guard !checking else { return }
        checking = true
        error = nil
        let key = draft
        let address = shop
        Task { @MainActor in
            do {
                _ = try await model.sales.connect(store, key: key, shop: address)
                if store == .shopify { model.settings.sales.shopifyStore = SalesAPI.shopifyHost(address) ?? address }
                if !model.settings.sales.stores.contains(store) { model.settings.sales.stores.append(store) }
                draft = ""
                connecting = false
            } catch {
                self.error = (error as? WebProblem)?.text(store.title) ?? error.localizedDescription
            }
            checking = false
        }
    }
}

/// Coding agents → Usage limits: OpenRouter, Copilot and Ollama beside Claude and Codex.
struct MoreUsageRows: View {
    @Bindable var model: AppModel

    var body: some View {
        Toggle(isOn: $model.settings.openRouterUsageEnabled) {
            Text("OpenRouter spending")
            Text("What your key has spent today, and what’s left of its limit, on Home.")
        }
        .settingsAnchor("agents.openRouterUsage")
        if model.settings.openRouterUsageEnabled {
            PastedKeyRow(label: "Key", service: "OpenRouter", prompt: "Paste your OpenRouter key",
                         help: "Create a key at openrouter.ai under Keys. It is checked once, then kept in your Keychain.",
                         problem: model.toolUsage.problems[.openRouter].map { $0.text("OpenRouter") },
                         load: { model.toolUsage.maskedKey(.openRouter) },
                         save: { try await model.toolUsage.saveKey($0, for: .openRouter) },
                         remove: { model.toolUsage.removeKey(.openRouter) })
        }
        Toggle(isOn: $model.settings.copilotUsageEnabled) {
            Text("Copilot premium requests")
            Text("This month’s premium requests against your plan, on Home.")
        }
        .settingsAnchor("agents.copilotUsage")
        if model.settings.copilotUsageEnabled {
            Picker("Copilot plan", selection: $model.settings.copilotPlan) {
                ForEach(CopilotPlan.allCases, id: \.self) { plan in Text("\(plan.title) (\(plan.rawValue) a month)").tag(plan) }
            }
            PastedKeyRow(label: "Key", service: "GitHub", prompt: "Paste your GitHub key",
                         help: "Make a read-only key on GitHub (Settings, Developer settings, Fine-grained tokens) that can read Plan, and paste it here. It is checked once, then kept in your Keychain.",
                         problem: model.toolUsage.problems[.copilot].map { $0.text("GitHub") },
                         load: { model.toolUsage.maskedKey(.copilot) },
                         save: { try await model.toolUsage.saveKey($0, for: .copilot) },
                         remove: { model.toolUsage.removeKey(.copilot) })
        }
        Toggle(isOn: $model.settings.ollamaUsageEnabled) {
            Text("Ollama models")
            Text("The models Ollama has loaded on this Mac and the memory they use, on Home.")
        }
        .settingsAnchor("agents.ollamaUsage")
    }
}

/// Add, replace or remove a key the user pastes. It is checked with the service before it is
/// kept in the Keychain; afterwards only its last four characters show.
struct PastedKeyRow: View {
    let label: String
    /// Named in error messages.
    let service: String
    let prompt: String
    let help: String
    var problem: String?
    let load: () -> String?
    let save: (String) async throws -> Void
    let remove: () -> Void
    @ViewState private var masked: String?
    @ViewState private var draft = ""
    @ViewState private var editing = false
    @ViewState private var checking = false
    @ViewState private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(label) {
                if let masked, !editing {
                    HStack(spacing: 8) {
                        Text(AskKeys.savedLabel(masked)).foregroundStyle(.secondary)
                        Button("Replace") { editing = true }
                        Button("Remove", role: .destructive) {
                            remove()
                            self.masked = nil
                            editing = false
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        SecureField("", text: $draft, prompt: Text(prompt))
                            .multilineTextAlignment(.leading)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                            .onSubmit(commit)
                        Button(checking ? "Checking…" : "Save", action: commit)
                            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || checking)
                        if editing {
                            Button("Cancel") {
                                editing = false
                                draft = ""
                                error = nil
                            }
                        }
                    }
                }
            }
            if let text = error ?? (masked != nil ? problem : nil) {
                Text(text).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            } else if masked == nil {
                Text(help).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { masked = load() }
    }

    private func commit() {
        guard !checking else { return }
        checking = true
        error = nil
        let key = draft
        Task { @MainActor in
            do {
                try await save(key)
                masked = load()
                draft = ""
                editing = false
            } catch {
                self.error = (error as? WebProblem)?.text(service) ?? error.localizedDescription
            }
            checking = false
        }
    }
}

/// Lays children out in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width {
                y += row + spacing
                x = 0
                row = 0
            }
            x += s.width + spacing
            row = max(row, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: subviews.isEmpty ? 0 : y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX {
                y += row + spacing
                x = bounds.minX
                row = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            row = max(row, s.height)
        }
    }
}
