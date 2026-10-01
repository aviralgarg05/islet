import AppKit
import IsletCore
import IsletSystem
import SwiftUI

/// Now Playing, the primary thing on Home: large artwork and titles, a scrubber you can drag,
/// and the transport. The volume row is always there when the island is tall enough; otherwise
/// the speaker button swaps it with the transport. A new song cross-fades the artwork and
/// pushes the titles in from below (`TrackChange`).
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
        let showsSound = !roomy && model.controls.soundRowShown
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Space.m) {
                TrackArtwork(media: media, size: art, corner: model.artworkCorner(size: art, standard: art >= 56 ? Radius.m : Radius.s))
                    .shadow(color: media.artworkData == nil ? .clear : accent.opacity(0.35), radius: 10, y: 2)
                    .onTapGesture { model.openPlayer() }
                    .help("Open \(media.appName ?? "player")")
                TrackText(media: media) {
                    VStack(alignment: .leading, spacing: Space.hair) {
                        Text(media.title).textStyle(.title).foregroundStyle(Ink.primary).lineLimit(1)
                        Text(media.artist ?? media.appName ?? "").textStyle(.body).foregroundStyle(Ink.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                // The other players and the volume toggle, close together so the title keeps its room.
                HStack(spacing: Space.xs) {
                    PlayerChips(model: model, current: media)
                    if !roomy {
                        IconButton(symbol: showsSound ? "playpause.fill" : "speaker.wave.2.fill",
                                   help: showsSound ? "Show playback controls" : "Show volume and output",
                                   size: 24, glyph: 11, ink: Ink.tertiary) {
                            model.controls.soundRowShown.toggle()
                        }
                    }
                }
            }
            Spacer(minLength: Space.xs)
            if media.duration != nil {
                MediaScrubber(model: model, media: media, accent: tint)
            }
            if let player = model.controlHint {
                ControlPermissionHint(player: player) { model.openControlPermission() }
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
    }
}

/// The other players live now (a video in Chrome beside a song in Spotify), as small app icons
/// beside the title. Clicking one shows and controls that player instead, and the closed island
/// follows. Nothing shows while there is only one player.
struct PlayerChips: View {
    let model: AppModel
    let current: NowPlaying

    var body: some View {
        let shown = MediaArbiter.playerID(current)
        let others = model.players.filter { MediaArbiter.playerID($0) != shown }
        if !others.isEmpty {
            HStack(spacing: Space.xs) {
                ForEach(Array(others.prefix(3).enumerated()), id: \.offset) { _, np in
                    PlayerChip(media: np) { model.pickPlayer(np) }
                }
            }
        }
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
                .accessibilityLabel("Playback position")
                .accessibilityValue(Format.clock(pos))
                Button { model.toggleRemainingTime() } label: {
                    Text(MediaSeek.trailingLabel(position: pos, duration: duration, remaining: remaining))
                        .contentTransition(.numericText())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(remaining ? "Show track length" : "Show time left")
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
        .animation(.snappy(duration: 0.15), value: dragging || hovering)
    }
}

/// In place of the transport after a press went nowhere: macOS hasn't allowed Islet to control
/// the player. One button, which opens the right place in Settings.
struct ControlPermissionHint: View {
    let player: String
    let allow: () -> Void

    var body: some View {
        Button(action: allow) {
            HStack(spacing: Space.xs) {
                Image(systemName: "lock.fill").font(.system(size: 10, weight: .semibold))
                Text("Allow Islet to control \(player)…").lineLimit(1)
            }
        }
        .buttonStyle(CapsuleButtonStyle(tint: .blue, filled: true))
        .help("Opens Settings → Permissions")
        .frame(maxWidth: .infinity)
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
                IconButton(symbol: "backward.fill", help: "Previous track", size: 30, glyph: 14, ink: Ink.primary) { model.send(.previous) }
                IconButton(symbol: media.isPlaying ? "pause.fill" : "play.fill", help: media.isPlaying ? "Pause" : "Play",
                           size: 32, glyph: 18, ink: Ink.primary) { model.send(.togglePlayPause) }
                IconButton(symbol: "forward.fill", help: "Next track", size: 30, glyph: 14, ink: Ink.primary) { model.send(.next) }
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

/// Shuffle or repeat: tinted with a soft backing when on.
struct ModeToggle: View {
    let symbol: String
    let on: Bool
    let tint: Color
    let label: String
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.play(.tap)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(on ? tint : Ink.tertiary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(on ? tint.opacity(0.16) : .clear))
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
                Image(systemName: Self.speakerSymbol(volume: c.volume, muted: c.muted))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ink.secondary)
                    .frame(width: 24, height: 24)
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
                .accessibilityLabel("Volume")
                .accessibilityValue("\(Int((c.volume * 100).rounded()))%")
            OutputPickerButton(model: model)
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
