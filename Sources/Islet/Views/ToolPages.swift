import AppKit
import AVFoundation
import IsletCore
import IsletSystem
import SwiftUI

// The pages of the tools under "More": Mirror, Teleprompter, Stocks and Sales, and the AI usage
// lines on Home. Each page fits the open island's content area at every size; anything longer
// scrolls.

// MARK: - Mirror

/// The camera, centred under the notch where the lens is. It runs only while this page shows.
struct MirrorTab: View {
    let model: AppModel
    let size: CGSize
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        let mirror = model.mirror
        switch mirror.state {
        case .needsAccess:
            EmptyHint(symbol: "camera", text: Self.accessText(mirror.access)) {
                Button(mirror.access == .notDetermined ? "Allow camera" : "Open System Settings") { mirror.allow() }
                    .buttonStyle(CapsuleButtonStyle(tint: .blue, filled: true))
            }
        case .noCamera:
            EmptyHint(symbol: "video.slash", text: "No camera is connected. Connect one, or open the lid, then come back to this page.")
        case .off, .running:
            let height = size.height
            let width = min(size.width, (height * 16 / 9).rounded())
            ZStack {
                RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.black)
                if snapshotMode {
                    MirrorPlaceholder()
                } else if mirror.state == .running {
                    CameraPreview(session: mirror.session, flipped: model.settings.mirror.flipped)
                } else {
                    Image(systemName: "camera").font(.system(size: 16, weight: .medium)).foregroundStyle(Ink.tertiary)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .help("The camera is on only while this page is open. Nothing is recorded.")
            .accessibilityLabel("Camera mirror")
        }
    }

    static func accessText(_ access: PermissionStatus) -> String {
        switch access {
        case .notDetermined: return "See yourself before a call. The camera is on only while this page is open, and nothing is recorded."
        case .restricted: return "This Mac doesn’t allow apps to use the camera."
        default: return "Islet isn’t allowed to use the camera. Turn it on in System Settings."
        }
    }
}

/// The camera's picture, flipped like a mirror when asked.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let flipped: Bool

    final class PreviewView: NSView {
        let preview: AVCaptureVideoPreviewLayer
        var mirrored = true { didSet { applyMirroring() } }
        private var observer: NSObjectProtocol?

        init(session: AVCaptureSession) {
            preview = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            wantsLayer = true
            preview.videoGravity = .resizeAspectFill
            layer?.addSublayer(preview)
            // The connection appears once the camera is the session's input.
            observer = NotificationCenter.default.addObserver(forName: AVCaptureSession.didStartRunningNotification, object: session,
                                                              queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyMirroring() }
            }
        }

        required init?(coder: NSCoder) { nil }

        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            preview.frame = bounds
            CATransaction.commit()
        }

        func applyMirroring() {
            guard let c = preview.connection, c.isVideoMirroringSupported else { return }
            c.automaticallyAdjustsVideoMirroring = false
            c.isVideoMirrored = mirrored
        }
    }

    func makeNSView(context: Context) -> PreviewView {
        let v = PreviewView(session: session)
        v.mirrored = flipped
        return v
    }

    func updateNSView(_ view: PreviewView, context: Context) {
        if view.mirrored != flipped { view.mirrored = flipped }
    }
}

/// Snapshots can't draw the camera: a soft stand-in.
private struct MirrorPlaceholder: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.30, green: 0.33, blue: 0.40), Color(red: 0.16, green: 0.17, blue: 0.21)],
                           startPoint: .top, endPoint: .bottom)
            Image(systemName: "person.fill")
                .font(.system(size: 54))
                .foregroundStyle(Color.white.opacity(0.22))
                .offset(y: 14)
        }
    }
}

// MARK: - Teleprompter

/// The script, moving up under the camera at the reading pace. Scroll to move it by hand.
struct TeleprompterTab: View {
    let model: AppModel
    let size: CGSize
    @ViewState private var shown: Double = 0
    /// One line of the script and two, as set, measured: the line's height and the pitch from
    /// one line to the next, so lines rest whole and the fades cover whole gaps.
    @ViewState private var oneLine: CGFloat = 0
    @ViewState private var twoLines: CGFloat = 0

    private static let controls: CGFloat = 28

    var body: some View {
        let t = model.teleprompter
        if t.script.isEmpty {
            EmptyHint(symbol: "text.alignleft",
                      text: "Paste a script, then press play. It moves up just under the camera, so you read while looking into it.") {
                Button("Paste") { paste() }
                    .buttonStyle(CapsuleButtonStyle(tint: .blue, filled: true))
                    // Only whether there is text, never the text itself, until Paste is pressed.
                    .disabled(NSPasteboard.general.availableType(from: [.string]) == nil)
                Button("Write in Settings") { AppActions.openSettings(.tools, at: "tools.teleprompter") }
                    .buttonStyle(CapsuleButtonStyle())
            }
        } else {
            let textWidth = size.width - Self.controls - Space.m
            let lines = TeleprompterLines(height: size.height, line: oneLine, pitch: twoLines - oneLine)
            HStack(alignment: .top, spacing: Space.m) {
                script(t, width: textWidth, pitch: lines.pitch)
                    .frame(width: textWidth, height: lines.shown, alignment: .top)
                    .clipped()
                    .mask(Self.fade(lines))
                    .frame(height: size.height, alignment: .top)
                    .background(alignment: .topLeading) { measure }
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Back to the top") { t.restart() }
                        Button("Edit the script…") { AppActions.openSettings(.tools, at: "tools.teleprompter") }
                        Button("Paste a new script") { paste() }
                    }
                controlColumn(t)
                    .frame(width: Self.controls, height: size.height)
            }
            .onChange(of: t.playback, initial: true) { _, playback in follow(playback) }
        }
    }

    private func script(_ t: TeleprompterController, width: CGFloat, pitch: CGFloat) -> some View {
        styled(Text(t.script))
            .multilineTextAlignment(.leading)
            .frame(width: width, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                t.layout(textHeight: Double(h), viewport: Double(size.height), linePitch: Double(pitch))
            }
            // Paused, it rests on a whole line where the playback says; playing, `shown`
            // carries the animation.
            .offset(y: -(t.isPlaying ? shown
                : TeleprompterPlayback.onLine(t.playback.position(at: Date()), pitch: Double(pitch), end: t.playback.end)))
    }

    private func styled(_ text: Text) -> some View {
        text
            .font(.system(size: model.settings.teleprompter.textSize, weight: .medium, design: model.settings.roundedFont ? .rounded : .default))
            .foregroundStyle(Ink.primary)
            .lineSpacing(model.settings.teleprompter.textSize * 0.25)
    }

    /// One line and two in the script's type, never drawn: their heights give the line pitch.
    private var measure: some View {
        VStack(spacing: 0) {
            styled(Text("Ag")).fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { oneLine = $0 }
            styled(Text("Ag\nAg")).fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { twoLines = $0 }
        }
        .hidden()
        .accessibilityHidden(true)
    }

    private func controlColumn(_ t: TeleprompterController) -> some View {
        let atEnd = !t.isPlaying && t.playback.isAtEnd(at: Date()) && t.playback.end > 0
        let pace = Int(model.settings.teleprompter.wordsPerMinute)
        return VStack(spacing: Space.xs) {
            IconButton(symbol: t.isPlaying ? "pause.fill" : atEnd ? "arrow.counterclockwise" : "play.fill",
                       help: t.isPlaying ? "Pause" : atEnd ? "From the top" : "Play", size: Self.controls, glyph: 12, ink: Ink.primary) {
                t.togglePlay()
            }
            .disabled(t.playback.end <= 0 && !t.isPlaying)
            IconButton(symbol: "plus", help: "Faster (\(pace) words a minute)", size: Self.controls, glyph: 10) {
                model.nudgeTeleprompterPace(by: 1)
            }
            IconButton(symbol: "minus", help: "Slower (\(pace) words a minute)", size: Self.controls, glyph: 10) {
                model.nudgeTeleprompterPace(by: -1)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Lines fade out at the top and in at the bottom, over the gap between two lines (and
    /// the part of the next line that peeks in), so a line at rest is never dimmed or cut.
    private static func fade(_ l: TeleprompterLines) -> some View {
        let stops = l.fade
        return LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: stops.top),
                                      .init(color: .black, location: stops.bottom), .init(color: .clear, location: 1)],
                              startPoint: .top, endPoint: .bottom)
    }

    /// While playing: from where the script is, one linear move to the end. Nothing ticks;
    /// the app's deadline timer marks the end.
    private func follow(_ playback: TeleprompterPlayback) {
        let now = Date()
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { shown = playback.position(at: now) }
        guard playback.isPlaying else { return }
        let remaining = playback.remaining(at: now)
        DispatchQueue.main.async {
            guard model.teleprompter.playback == playback else { return }
            withAnimation(.linear(duration: remaining)) { shown = playback.end }
        }
    }

    private func paste() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        model.teleprompter.setScript(text)
        model.teleprompter.restart()
    }
}

// MARK: - Stocks

/// The watchlist: price, the day's change and the day's line.
struct StocksTab: View {
    let model: AppModel
    let size: CGSize
    @Environment(\.snapshotMode) private var snapshotMode

    static let rowHeight: CGFloat = 24
    static let spacing: CGFloat = Space.s

    /// Rows that fit without scrolling.
    static func fitting(in height: CGFloat) -> Int { max(1, Int((height + spacing) / (rowHeight + spacing))) }

    var body: some View {
        let stocks = model.stocks
        if stocks.symbols.isEmpty {
            EmptyHint(symbol: "chart.line.uptrend.xyaxis", text: "Add shares or indices to the watchlist in Settings.") {
                Button("Open Settings") { AppActions.openSettings(.tools, at: "tools.stocks") }
                    .buttonStyle(CapsuleButtonStyle(tint: .blue, filled: true))
            }
        } else {
            let fits = Self.fitting(in: size.height)
            // Snapshots can't scroll, so they show what fits.
            let shown = snapshotMode ? Array(stocks.symbols.prefix(fits)) : stocks.symbols
            AdaptiveScroll(scrolls: stocks.symbols.count > fits) {
                VStack(spacing: Self.spacing) {
                    ForEach(shown, id: \.self) { symbol in
                        StockRow(symbol: symbol, quote: stocks.quotes[symbol], problem: stocks.problems[symbol], loading: stocks.refreshing)
                    }
                }
            }
            .help("Prices from Yahoo Finance, which may be delayed. Asked for only while this page is open.")
        }
    }
}

struct StockRow: View {
    let symbol: String
    let quote: StockQuote?
    let problem: WebProblem?
    let loading: Bool

    var body: some View {
        let pct = quote?.changePercent ?? 0
        // A price kept after a refresh failed is drawn quietly, so it can't pass for a live one.
        let earlier = StocksAPI.isEarlier(quote: quote, problem: problem)
        let tint: Color = earlier ? Ink.tertiary
            : pct > 0.005 ? Color(tint: "#34C759") : pct < -0.005 ? Color(tint: "#FF453A") : Ink.secondary
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 0) {
                // One name whether or not the price has come: an index by its plain name.
                Text(StocksAPI.title(symbol: symbol, quote: quote))
                    .textStyle(.body, emphasized: true)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                Text(StocksAPI.subtitle(symbol: symbol, quote: quote, problem: problem) ?? " ")
                    .textStyle(.caption)
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let quote {
                SparklineView(values: quote.closes, baseline: quote.previousClose, tint: tint)
                    .frame(width: 72, height: 20)
                Text(quote.priceText)
                    .textStyle(.body, emphasized: true, numeric: true)
                    .foregroundStyle(earlier ? Ink.tertiary : Ink.primary)
                    .frame(minWidth: 64, alignment: .trailing)
                Text(quote.changeText ?? "–")
                    .textStyle(.caption, emphasized: true, numeric: true)
                    .foregroundStyle(tint)
                    .frame(width: 58, alignment: .trailing)
            } else if loading && problem == nil {
                SpinnerArc(tint: Ink.tertiary, lineWidth: 1.5).frame(width: 10, height: 10)
            }
        }
        .frame(height: StocksTab.rowHeight)
        .help(earlier ? problem.map { "An earlier price. " + $0.text("Yahoo Finance") } ?? "" : "")
        .accessibilityElement(children: .combine)
    }
}

/// The day's prices as a line, with the previous close as a faint dotted line.
struct SparklineView: View {
    let values: [Double]
    var baseline: Double?
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let w = Double(geo.size.width), h = Double(geo.size.height)
            let line = Sparkline.points(values, width: w, height: h, including: baseline)
            ZStack {
                if let base = baseline, let y = Sparkline.y(of: base, in: values, including: base, height: h) {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(Ink.quaternary, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
                Path { p in
                    guard let first = line.first else { return }
                    p.move(to: first)
                    for pt in line.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Sales

/// Today's takings: one total, large, and each store beside it.
struct SalesTab: View {
    let model: AppModel
    let size: CGSize

    var body: some View {
        let sales = model.sales
        if model.settings.sales.stores.isEmpty {
            EmptyHint(symbol: "cart",
                      text: "Connect a store in Settings to see today’s sales here. Your sign-in details stay on this Mac, and Islet only reads your sales.") {
                Button("Open Settings") { AppActions.openSettings(.tools, at: "tools.sales") }
                    .buttonStyle(CapsuleButtonStyle(tint: .blue, filled: true))
            }
        } else {
            let left = (size.width * 0.44).rounded()
            let connected = model.settings.sales.stores
            let fits = Self.fitting(in: size.height)
            // More stores than fit: the last row says how many more, and its help lists them.
            let shown = connected.count > fits ? Array(connected.prefix(max(1, fits - 1))) : connected
            let hidden = Array(connected.dropFirst(shown.count))
            HStack(alignment: .top, spacing: 0) {
                summary(sales).frame(width: left, height: size.height, alignment: .topLeading)
                ColumnRule().frame(height: size.height).padding(.horizontal, Space.l)
                VStack(alignment: .leading, spacing: Space.s) {
                    ForEach(shown) { store in
                        StoreRow(store: store, sales: sales.stores.first { $0.store == store })
                    }
                    if !hidden.isEmpty {
                        let lines = hidden.map { store in
                            let s = sales.stores.first { $0.store == store }
                            return "\(store.title): \(s?.problem?.shortText ?? s.map(StoreRow.amount) ?? "…")"
                        }
                        Text("+\(hidden.count) more")
                            .textStyle(.caption, emphasized: true, numeric: true)
                            .foregroundStyle(Ink.tertiary)
                            .frame(height: StoreRow.height)
                            .padding(.leading, StoreRow.dot + Space.s)
                            .help(lines.joined(separator: "\n"))
                            .accessibilityLabel("\(hidden.count) more: " + lines.joined(separator: ", "))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    /// Store rows that fit without scrolling.
    static func fitting(in height: CGFloat) -> Int { max(1, Int((height + Space.s) / (StoreRow.height + Space.s))) }

    private func summary(_ sales: SalesModel) -> some View {
        let figures = sales.total
        let headline = SalesSummary.headline(figures, preferred: Locale.current.currency?.identifier)
        return VStack(alignment: .leading, spacing: Space.hair) {
            Text("Today").textStyle(.caption).foregroundStyle(Ink.tertiary)
            Text(headline?.main.formatted() ?? (sales.refreshing ? "…" : "Nothing yet"))
                .textStyle(.display)
                .foregroundStyle(Ink.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let others = headline?.others, !others.isEmpty {
                Text("+ " + others.map { $0.formatted() }.joined(separator: ", "))
                    .textStyle(.caption, numeric: true)
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: Space.xs) {
                Text(figures.orders == 1 ? "1 order" : "\(figures.orders) orders")
                if let at = sales.lastRefresh {
                    Text("·")
                    TimelineView(.everyMinute) { ctx in Text(Format.relative(to: at, now: ctx.date)) }
                }
                Button { sales.refresh() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 16).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(sales.refreshing)
                .help("Ask again now")
                .accessibilityLabel("Refresh")
            }
            .textStyle(.caption)
            .foregroundStyle(Ink.tertiary)
            // Under the total at every size, not down at the column's foot.
            .padding(.top, Space.m)
        }
    }
}

struct StoreRow: View {
    let store: SalesStore
    let sales: StoreSales?

    static let height: CGFloat = 20
    static let dot: CGFloat = 6

    /// "£462.00 + €89.00", largest first; "–" for nothing yet today.
    static func amount(_ s: StoreSales) -> String {
        let all = s.figures.amounts.map { Money(minor: $0.value, currency: $0.key) }.sorted { $0.major > $1.major }
        return all.isEmpty ? "–" : all.map { $0.formatted() }.joined(separator: " + ")
    }

    var body: some View {
        HStack(spacing: Space.s) {
            Circle().fill(Color(tint: store.tint)).frame(width: Self.dot, height: Self.dot)
            Text(store.title).textStyle(.body).foregroundStyle(Ink.primary).lineLimit(1)
            Spacer(minLength: Space.s)
            if let problem = sales?.problem {
                // What to do, in a word or two, beside the sign; the whole sentence in the help.
                HStack(spacing: Space.xs) {
                    Text(problem.shortText).textStyle(.caption).foregroundStyle(Ink.tertiary).lineLimit(1)
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(Color.orange)
                        .accessibilityHidden(true)
                }
                .help(problem.text(store.title))
            } else if let s = sales {
                Text(Self.amount(s))
                    .textStyle(.body, numeric: true)
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
            } else {
                SpinnerArc(tint: Ink.tertiary, lineWidth: 1.5)
                    .frame(width: 10, height: 10)
                    .help("Asking \(store.title)")
                    .accessibilityLabel("Loading")
            }
        }
        .frame(height: Self.height)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - AI usage on Home

/// OpenRouter, Copilot or Ollama in Home's column: the tool, its figure, and a bar or a line.
struct ToolUsageGlance: View {
    let card: ToolUsageCard

    var body: some View {
        let tint = Color(tint: card.source.tint)
        GlanceRow(title: card.source.title) {
            Image(systemName: card.source.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
        } trailing: {
            Text(card.headline)
                .textStyle(.caption, numeric: true)
                .foregroundStyle(Ink.secondary)
                .lineLimit(1)
        } detail: {
            if let fraction = card.fraction {
                LevelBar(value: fraction, tint: fraction >= 0.9 ? Color(tint: "red") : tint, height: 4)
                    .padding(.top, Space.xs)
                    .help(card.detail ?? "")
            } else {
                Text(card.detail ?? " ")
            }
        }
        .accessibilityElement(children: .combine)
    }
}
