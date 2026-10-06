import AppKit
import CasementCore
import CasementSystem
import SwiftUI

/// Now Playing, the primary thing on Home: large artwork and titles, a scrubber you can drag,
/// and the transport. The volume row is always there when the island is tall enough; otherwise
/// the speaker button swaps it with the transport, when the title leaves room for the button
/// (`NowPlayingTitleRow`). A new song cross-fades the artwork and
/// pushes the titles in from below (`TrackChange`). The progress bar and the volume bar start
/// and end in the same places (`MediaScrubber.edge`).
struct NowPlayingHero: View {
    let model: AppModel
    let media: NowPlaying
    /// The space the hero may use.
    let size: CGSize
    @Environment(\.snapshotMode) private var snapshotMode

    /// Tall enough for artwork, transport and the volume row together.
    static let roomyHeight: CGFloat = 150

    var body: some View {
        let accent = model.mediaAccent(media)
        // The progress bar, shuffle and repeat take the music colour, as the indicator does.
        let tint = model.musicTint(media)
        let roomy = size.height >= Self.roomyHeight
        let art: CGFloat = roomy ? 72 : size.height >= 110 ? 56 : 40
        let shown = MediaArbiter.playerID(media)
        let others = model.players.filter { MediaArbiter.playerID($0) != shown }
        // The title keeps its room: the lyrics button moves under the others, then chips past
        // the first fold, then the volume button goes.
        let row = NowPlayingTitleRow.layout(width: Double(size.width - art - Space.m), spacing: Double(Space.m),
                                            otherPlayers: others.count, volumeRow: roomy,
                                            lyrics: LyricsQuery.couldHaveLyrics(media))
        let stacked = row.lyrics == .below
        let showsSound = row.showsVolume && model.controls.soundRowShown
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Space.m) {
                TrackArtwork(media: media, size: art, corner: model.artworkCorner(size: art, standard: art >= 56 ? Radius.m : Radius.s))
                    .shadow(color: media.artworkData == nil ? .clear : accent.opacity(0.35), radius: 10, y: 2)
                    .onTapGesture { model.openPlayer() }
                    .help("Open \(media.appName ?? "player")")
                    .spokenButton("Open \(media.appName ?? "player")") { model.openPlayer() }
                TrackText(media: media) {
                    VStack(alignment: .leading, spacing: Space.hair) {
                        Text(media.title).textStyle(.title).foregroundStyle(Ink.primary).lineLimit(1)
                        Text(media.artist ?? media.appName ?? "").textStyle(.body).foregroundStyle(Ink.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // The other players, the volume toggle and the lyrics button, close together so the
                // title keeps its room. Where they don't fit in a line, the lyrics button sits under
                // the others, within the artwork's height.
                if !row.isEmpty {
                    VStack(alignment: .trailing, spacing: 0) {
                        HStack(spacing: Space.xs) {
                            PlayerChips(model: model, others: others, chips: row.chips)
                            if row.showsVolume {
                                // The same speaker either way; on, it sits on a wash, as shuffle does.
                                ModeToggle(symbol: "speaker.wave.2.fill", on: showsSound, tint: nil,
                                           label: showsSound ? "Show playback controls" : "Show volume and output",
                                           size: stacked ? 22 : 24) {
                                    model.controls.soundRowShown.toggle()
                                }
                            }
                            if row.lyrics == .beside {
                                LyricsButton(model: model, media: media)
                            }
                        }
                        if stacked {
                            LyricsButton(model: model, media: media, size: CGSize(width: 22, height: 18))
                        }
                    }
                }
            }
            Spacer(minLength: Space.xs)
            if media.duration != nil {
                MediaScrubber(model: model, media: media, accent: tint)
            }
            if let hint = model.controlHint {
                Group {
                    switch hint {
                    case .allowControl(let player):
                        ControlPermissionHint(player: player) { model.openControlPermission() }
                    case .otherApp(let other):
                        OtherAppHintView(hint: other) { model.openPlayer(bundleID: other.bundleID) }
                    }
                }
                .frame(height: TransportControls.height)
            } else if showsSound {
                SoundControls(model: model).frame(height: TransportControls.height)
            } else {
                TransportControls(model: model, media: media, accent: tint, wide: size.width >= 330)
            }
            if roomy {
                SoundControls(model: model).padding(.top, Space.xs)
            }
        }
        .frame(height: size.height, alignment: .top)
        // Lyrics are looked up while Now Playing is on show, once per song.
        .onAppear { if !snapshotMode { model.tools.lyrics.want(media) } }
        .onChange(of: media.trackKey) { _, _ in if !snapshotMode { model.tools.lyrics.want(media) } }
        // A browser can send a video's length a moment after its title (`LyricsQuery.isSameLookup`).
        .onChange(of: media.duration) { _, _ in if !snapshotMode { model.tools.lyrics.want(media) } }
        // Lyrics just turned on in Settings (or browsers switched): this song, not the next.
        .onChange(of: model.tools.lyrics.resets) { _, _ in if !snapshotMode { model.tools.lyrics.want(media) } }
    }
}

/// The other players (a video in Chrome beside a song in Spotify, and every other player macOS
/// lists, however long ago it paused), as small app icons beside the title, as many as
/// `NowPlayingTitleRow` leaves room for. Clicking one shows and controls that player instead; the
/// closed island keeps showing what plays. When there are more
/// players than chips, the last chip counts the rest ("+3") and offers them in a menu. Nothing
/// shows while there is only one player.
struct PlayerChips: View {
    let model: AppModel
    let others: [NowPlaying]
    /// Chips drawn (`NowPlayingTitleRow.Layout.chips`).
    let chips: Int

    var body: some View {
        let own = others.count > chips ? max(0, chips - 1) : chips
        let rest = Array(others.dropFirst(own))
        if chips > 0, !others.isEmpty {
            HStack(spacing: Space.xs) {
                ForEach(Array(others.prefix(own).enumerated()), id: \.offset) { _, np in
                    PlayerChip(media: np) { model.pickPlayer(np) }
                }
                if rest.count > 1 {
                    PlayerCountChip(count: rest.count) { showMenu(rest) }
                }
            }
        }
    }

    private func showMenu(_ players: [NowPlaying]) {
        Haptics.play(.tap)
        let items = players.map { np in
            IslandMenu.Item(title: [np.appName, np.title].compactMap { $0 }.joined(separator: ": ")) { model.pickPlayer(np) }
        }
        IslandMenu.show(items, model: model)
    }
}

/// Other players folded into one chip: how many, as the closed island counts ("+3").
struct PlayerCountChip: View {
    let count: Int
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            Text("+\(count)")
                .textStyle(.caption, emphasized: true, numeric: true)
                .foregroundStyle(hovering ? Ink.primary : Ink.secondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(hovering ? Wash.strong : Wash.regular))
                .contrastEdge(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(count) other players")
        .accessibilityLabel("\(count) other players")
        .accessibilityHint("Shows a menu to switch to one")
    }
}

/// One other player: its app's icon on a quiet wash, with a small dot while it plays.
struct PlayerChip: View {
    let media: NowPlaying
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        let name = media.appName ?? "another player"
        Button(action: action) {
            Group {
                if let bundle = media.bundleID {
                    AppIconView(bundleID: bundle, size: 16)
                } else {
                    Image(systemName: "music.note").font(.system(size: 10, weight: .semibold)).foregroundStyle(Ink.secondary)
                }
            }
            .frame(width: 22, height: 22)
            .background(Circle().fill(hovering ? Wash.strong : Wash.regular))
            .contrastEdge(Circle())
            .overlay(alignment: .bottomTrailing) {
                if media.isPlaying {
                    Circle().fill(Color.green).frame(width: 5, height: 5)
                }
            }
            .opacity(hovering ? 1 : 0.85)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Switch to \(name): \(media.title)")
        .accessibilityLabel("Switch to \(name)")
        .accessibilityValue([media.title, media.isPlaying ? "playing" : nil].compactMap { $0 }.joined(separator: ", "))
    }
}

/// Elapsed time, a bar you can drag or click to seek, and the time left (tap to show the length).
struct MediaScrubber: View {
    let model: AppModel
    let media: NowPlaying
    let accent: Color
    /// Where the pointer is while dragging (0...1).
    @ViewState private var preview: Double?
    @Environment(\.islandMotion) private var motion

    /// The width of each time label ("−88:88"), and of the volume row's buttons under them, so
    /// the two bars share their edges whatever the times say.
    static let edge: CGFloat = 36

    var body: some View {
        let duration = media.duration ?? 0
        TimelineView(.periodic(from: .now, by: media.isPlaying && preview == nil ? 1 : 3600)) { ctx in
            let pos = preview.map { MediaSeek.position(fraction: $0, duration: duration) }
                ?? model.displayPosition(media, now: ctx.date) ?? 0
            let remaining = model.settings.mediaShowsRemainingTime
            HStack(spacing: Space.s) {
                Text(Format.clock(pos))
                    .foregroundStyle(preview == nil ? Ink.tertiary : Ink.primary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .frame(minWidth: Self.edge, alignment: .leading)
                    // The scrubber says where the song is.
                    .accessibilityHidden(true)
                ScrubBar(value: duration > 0 ? pos / duration : 0, tint: accent) { f in
                    model.controls.holdsOpen = true
                    preview = f
                } onEnd: { f in
                    model.controls.holdsOpen = false
                    preview = nil
                    model.seek(to: MediaSeek.position(fraction: f, duration: duration))
                } onCancel: {
                    model.controls.holdsOpen = false
                    preview = nil
                }
                // VoiceOver moves it as far as the ±15 s buttons do.
                .accessibilityElement()
                .accessibilityLabel("Playback position")
                .accessibilityValue(SpokenText.position(pos, of: duration))
                .accessibilityAdjustableAction { direction in
                    let k = MediaSeek.skipInterval
                    let step: Double = direction == .increment ? k : direction == .decrement ? -k : 0
                    guard step != 0, duration > 0 else { return }
                    model.seek(to: min(duration, max(0, pos + step)))
                }
                Button { model.toggleRemainingTime() } label: {
                    Text(MediaSeek.trailingLabel(position: pos, duration: duration, remaining: remaining))
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .frame(minWidth: Self.edge, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(remaining ? "Show track length" : "Show time left")
                .accessibilityLabel(remaining ? "Time left" : "Track length")
                .accessibilityValue(SpokenText.duration(remaining ? max(0, duration - pos) : duration))
                .accessibilityHint(remaining ? "Shows the track length instead" : "Shows the time left instead")
            }
            .textStyle(.caption, numeric: true)
            .foregroundStyle(Ink.tertiary)
            // A new song rolls the times over and runs the bar back; ticking stays instant.
            .animation(TrackChange.animation(motion), value: media.trackKey)
        }
    }
}

/// A slim bar you can click or drag. Reports the fraction while dragging and on release,
/// with a haptic detent at either end.
struct ScrubBar: View {
    var value: Double
    var tint: Color
    var height: CGFloat = 4
    var onChange: (Double) -> Void
    var onEnd: (Double) -> Void
    /// The bar went away mid-drag (the island closed, the track lost its length). SwiftUI
    /// doesn't end the drag then, so this is the only chance to undo what `onChange` started.
    var onCancel: () -> Void = {}
    @ViewState private var dragging = false
    @ViewState private var hovering = false
    @ViewState private var last: Double?
    @Environment(\.islandMotion) private var motion

    var body: some View {
        GeometryReader { geo in
            LevelBar(value: value, tint: tint, height: dragging || hovering ? height + 2 : height)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let f = MediaSeek.fraction(x: g.location.x, width: geo.size.width)
                            if MediaSeek.reachedEnd(from: last, to: f) { Haptics.play(.snap) }
                            last = f
                            dragging = true
                            onChange(f)
                        }
                        .onEnded { g in
                            last = nil
                            dragging = false
                            onEnd(MediaSeek.fraction(x: g.location.x, width: geo.size.width))
                        }
                )
        }
        .frame(height: 14)
        .onHover { hovering = $0 }
        .onDisappear {
            guard dragging else { return }
            dragging = false
            last = nil
            onCancel()
        }
        .animation(motion == .off ? nil : .snappy(duration: 0.15), value: dragging || hovering)
    }
}

/// In place of the transport after a press went nowhere: macOS hasn't allowed Casement to control
/// the player. One button, which opens the right place in Settings.
struct ControlPermissionHint: View {
    let player: String
    let allow: () -> Void

    var body: some View {
        Button(action: allow) {
            HStack(spacing: Space.xs) {
                Image(systemName: "lock.fill").font(.system(size: 10, weight: .semibold))
                Text("Allow Casement to control \(player)…").lineLimit(1)
            }
        }
        .buttonStyle(CapsuleButtonStyle(tint: .blue, filled: true))
        .help("Opens Settings → Permissions")
        .frame(maxWidth: .infinity)
    }
}

/// In place of the transport after a press went nowhere because macOS gives the controls to
/// another app (a command would reach that one instead): who has them, and a button that brings
/// this player's app forward, to control it there. The words come first: where "Open Google
/// Chrome" would leave them too little room, the button says Open beside the app's icon.
struct OtherAppHintView: View {
    let hint: OtherAppHint
    let open: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(compact: false)
            row(compact: true)
        }
        .accessibilityElement(children: .contain)
        .frame(maxWidth: .infinity)
    }

    private func row(compact: Bool) -> some View {
        HintRow(spacing: Space.s) {
            // A long name ("Google Chrome has the controls") takes a second line.
            Text(hint.message)
                .textStyle(.caption)
                .foregroundStyle(Ink.secondary)
            Button(action: open) {
                HStack(spacing: Space.xs) {
                    if compact {
                        AppIconView(bundleID: hint.bundleID, size: 14)
                        Text("Open")
                    } else {
                        Image(systemName: "arrow.up.forward.app").font(.system(size: 10, weight: .semibold))
                        Text(hint.button)
                    }
                }
                .lineLimit(1)
            }
            .buttonStyle(CapsuleButtonStyle(tint: .blue, filled: true))
            .help("Brings \(hint.app) to the front, to control it there")
            .accessibilityLabel(hint.button)
            .accessibilityHint("Brings \(hint.app) to the front, to control it there")
        }
    }
}

/// The hint's words and its button: the button at its own width, the words in the room left
/// beside it, on up to two lines. Its ideal width is the least that keeps every word whole on two
/// lines, so `ViewThatFits` takes the long button only where the words still fit beside it.
private struct HintRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let button = subviews[1].sizeThatFits(.unspecified)
        let room = proposal.width.map { max(0, $0 - spacing - button.width) } ?? Self.twoLineWidth(of: subviews[0])
        let words = subviews[0].sizeThatFits(Self.proposal(for: subviews[0], width: room))
        return CGSize(width: proposal.width == nil ? room + spacing + button.width : words.width + spacing + button.width,
                      height: max(button.height, words.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let button = subviews[1].sizeThatFits(.unspecified)
        let words = Self.proposal(for: subviews[0], width: max(0, bounds.width - spacing - button.width))
        let used = subviews[0].sizeThatFits(words)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: words)
        subviews[1].place(at: CGPoint(x: bounds.minX + used.width + spacing, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(button))
    }

    /// The words at `width`, no taller than two lines (a third is cut short).
    private static func proposal(for words: LayoutSubview, width: CGFloat) -> ProposedViewSize {
        ProposedViewSize(width: width, height: words.sizeThatFits(.unspecified).height * 2.5)
    }

    /// The least width at which the words take two lines at most, every word whole.
    private static func twoLineWidth(of words: LayoutSubview) -> CGFloat {
        let line = words.sizeThatFits(.unspecified)
        var (low, high) = (CGFloat(0), line.width.rounded(.up))
        while high - low > 1 {
            let mid = ((low + high) / 2).rounded()
            if words.sizeThatFits(ProposedViewSize(width: mid, height: nil)).height < line.height * 2.5 { high = mid } else { low = mid }
        }
        return high
    }
}

/// Previous, play/pause and next in the middle; shuffle and repeat at the edges when the player
/// reports them; ±15 s beside the middle only when there is room (the scrubber seeks too).
struct TransportControls: View {
    let model: AppModel
    let media: NowPlaying
    let accent: Color
    var wide = false

    static let height: CGFloat = 32

    var body: some View {
        let canSkip = wide && media.duration != nil && media.elapsed != nil
        ZStack {
            HStack(spacing: Space.xs) {
                if canSkip {
                    IconButton(symbol: "gobackward.15", help: "Back 15 seconds", size: 28, glyph: 12, ink: Ink.secondary) { model.send(.skipBackward) }
                }
                // Faint for a player that says it has none (a video in Chrome outside a playlist).
                IconButton(symbol: "backward.fill", help: media.takes(.previous) ? "Previous track" : "No previous track",
                           size: 30, glyph: 14, ink: Ink.primary, enabled: media.takes(.previous)) { model.send(.previous) }
                IconButton(symbol: media.isPlaying ? "pause.fill" : "play.fill", help: media.isPlaying ? "Pause" : "Play",
                           size: 32, glyph: 18, ink: Ink.primary) { model.send(.togglePlayPause) }
                IconButton(symbol: "forward.fill", help: media.takes(.next) ? "Next track" : "No next track",
                           size: 30, glyph: 14, ink: Ink.primary, enabled: media.takes(.next)) { model.send(.next) }
                if canSkip {
                    IconButton(symbol: "goforward.15", help: "Forward 15 seconds", size: 28, glyph: 12, ink: Ink.secondary) { model.send(.skipForward) }
                }
            }
            HStack(spacing: 0) {
                if let shuffle = media.shuffle {
                    ModeToggle(symbol: "shuffle", on: shuffle, tint: accent, label: shuffle ? "Shuffle is on" : "Shuffle is off") {
                        model.send(.toggleShuffle)
                    }
                }
                Spacer(minLength: 0)
                if let mode = media.repeatMode {
                    ModeToggle(symbol: mode == .one ? "repeat.1" : "repeat", on: mode != .off, tint: accent,
                               label: mode == .off ? "Repeat is off" : mode == .one ? "Repeating this track" : "Repeating all") {
                        model.send(.toggleRepeat)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
    }
}

/// Shuffle or repeat: tinted with a soft backing when on. Without a tint (the volume row's
/// toggle) it is white on the strong wash when on.
struct ModeToggle: View {
    let symbol: String
    let on: Bool
    let tint: Color?
    let label: String
    /// The circle's diameter.
    var size: CGFloat = 24
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.play(.tap)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(on ? tint ?? Ink.primary : Ink.tertiary)
                .frame(width: size, height: size)
                .background(Circle().fill(on ? tint?.opacity(0.16) ?? Wash.strong : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Mute, the system volume and the output device.
struct SoundControls: View {
    let model: AppModel
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        let c = model.controls
        HStack(spacing: Space.s) {
            Button { model.toggleMute() } label: {
                // Under the elapsed time, with its glyph at the same edge.
                Image(systemName: Self.speakerSymbol(volume: c.volume, muted: c.muted))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ink.secondary)
                    .frame(width: MediaScrubber.edge, height: 24, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(c.muted ? "Unmute" : "Mute")
            .accessibilityLabel(c.muted ? "Unmute" : "Mute")
            ScrubBar(value: c.muted ? 0 : c.volume, tint: .white) { v in
                c.holdsOpen = true
                model.setVolume(v)
            } onEnd: { v in
                c.holdsOpen = false
                model.setVolume(v)
            } onCancel: {
                c.holdsOpen = false
            }
                // VoiceOver moves it a sixteenth at a time, as the volume keys do.
                .accessibilityElement()
                .accessibilityLabel("Volume")
                .accessibilityValue(c.muted ? "muted" : SpokenText.percent(c.volume))
                .accessibilityAdjustableAction { direction in
                    let step: Double = direction == .increment ? 1.0 / 16 : direction == .decrement ? -1.0 / 16 : 0
                    guard step != 0 else { return }
                    model.setVolume((c.muted ? 0 : c.volume) + step)
                }
            OutputPickerButton(model: model)
                .frame(width: MediaScrubber.edge, alignment: .trailing)
        }
        .onAppear { if !snapshotMode { model.soundControlsAppeared() } }
        .onDisappear { if !snapshotMode { model.soundControlsDisappeared() } }
    }

    static func speakerSymbol(volume: Double, muted: Bool) -> String {
        if muted || volume <= 0 { return "speaker.slash.fill" }
        return volume < 0.34 ? "speaker.wave.1.fill" : volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }
}

/// Shows the current output's icon; click for a menu of output devices.
struct OutputPickerButton: View {
    let model: AppModel

    var body: some View {
        let current = model.currentOutput
        IconButton(symbol: current.map(Self.symbol) ?? "hifispeaker.fill",
                   help: current.map { "Output: \($0.name)" } ?? "Choose output",
                   size: 24, glyph: 11, ink: Ink.secondary) {
            showMenu()
        }
    }

    private func showMenu() {
        model.refreshSound()
        var items: [IslandMenu.Item] = [IslandMenu.Item(title: "Output", enabled: false)]
        for device in model.controls.outputs {
            items.append(IslandMenu.Item(title: device.name, symbol: Self.symbol(device),
                                         checked: device.id == model.controls.defaultOutputID) {
                model.selectOutput(device.id)
            })
        }
        items.append(.separator)
        items.append(IslandMenu.Item(title: "Sound settings…") {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") { NSWorkspace.shared.open(url) }
        })
        IslandMenu.show(items, model: model)
    }

    static func symbol(_ d: AudioOutputDevice) -> String {
        switch d.transport {
        case .airPlay: return "airplayaudio"
        case .hdmi, .displayPort: return "tv"
        default: return AppModel.symbol(forDevice: d.name, bluetooth: d.transport == .bluetooth)
        }
    }
}

/// The cup in the menu bar row while keep awake is on: click for the durations or to turn it off.
struct KeepAwakeButton: View {
    let model: AppModel

    var body: some View {
        let session = model.controls.awake
        Button { showMenu() } label: {
            Image(systemName: session == nil ? "cup.and.saucer" : "cup.and.saucer.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(session == nil ? Ink.tertiary : Color(tint: KeepAwake.tint))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(session == nil ? "Keep awake" : Self.status(session!))
        .accessibilityLabel(session == nil ? "Keep awake" : Self.status(session!))
    }

    static func status(_ s: KeepAwakeSession) -> String {
        s.until.map { "Keeping awake until \($0.formatted(date: .omitted, time: .shortened))" } ?? "Keeping awake until turned off"
    }

    private func showMenu() {
        Haptics.play(.tap)
        let session = model.controls.awake
        var items = [IslandMenu.Item(title: session.map(Self.status) ?? "Keep awake", enabled: false)]
        for preset in KeepAwake.presets {
            items.append(IslandMenu.Item(title: preset.title) {
                model.setKeepAwake(.start(minutes: preset.minutes), announce: false)
            })
        }
        if session != nil {
            items.append(.separator)
            items.append(IslandMenu.Item(title: "Turn off") { model.setKeepAwake(.stop, announce: false) })
        }
        IslandMenu.show(items, model: model)
    }
}
