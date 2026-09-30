import AppKit
import IsletCore
import IsletSystem
import SwiftUI

/// Now Playing on the Home tab: artwork and titles, a scrubber you can drag, transport
/// controls, and the system volume with an output picker.
struct NowPlayingCard: View {
    let model: AppModel
    let media: NowPlaying
    /// Height available to the card. Tall cards keep the volume row in view; short ones swap
    /// it with the transport controls behind the speaker button.
    var height: CGFloat = 100

    static let roomyHeight: CGFloat = 124

    var body: some View {
        let accent = model.mediaAccent(media)
        let roomy = height >= Self.roomyHeight
        let showsSound = !roomy && model.controls.soundRowShown
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ArtworkView(media: media, size: 48, corner: 10)
                    .onTapGesture { model.openPlayer() }
                    .help("Open \(media.appName ?? "player")")
                VStack(alignment: .leading, spacing: 1) {
                    Text(media.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(media.artist ?? media.appName ?? "").font(.system(size: 11.5)).foregroundStyle(Color.islandSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if !roomy {
                    SmallIconButton(symbol: showsSound ? "playpause.fill" : "speaker.wave.2.fill",
                                    label: showsSound ? "Show playback controls" : "Show volume and output") {
                        model.controls.soundRowShown.toggle()
                    }
                }
            }
            if media.duration != nil {
                MediaScrubber(model: model, media: media, accent: accent)
            }
            if showsSound {
                SoundControls(model: model).frame(height: 33)
            } else {
                TransportControls(model: model, media: media, accent: accent)
            }
            if roomy {
                SoundControls(model: model).padding(.top, -2)
            }
        }
    }
}

/// Elapsed time, a bar you can drag or click to seek, and the time left (tap to show the length).
struct MediaScrubber: View {
    let model: AppModel
    let media: NowPlaying
    let accent: Color
    /// Where the pointer is while dragging (0...1).
    @ViewState private var preview: Double?

    var body: some View {
        let duration = media.duration ?? 0
        TimelineView(.periodic(from: .now, by: media.isPlaying && preview == nil ? 1 : 3600)) { ctx in
            let pos = preview.map { MediaSeek.position(fraction: $0, duration: duration) }
                ?? model.displayPosition(media, now: ctx.date) ?? 0
            let remaining = model.settings.mediaShowsRemainingTime
            HStack(spacing: 6) {
                Text(Format.clock(pos))
                    .foregroundStyle(preview == nil ? Color.islandTertiary : Color.white)
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
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(remaining ? "Show track length" : "Show time left")
            }
            .font(.system(size: 9.5, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.islandTertiary)
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

/// -15 s, previous, play/pause, next, +15 s, with shuffle and repeat at the edges when the
/// player reports them.
struct TransportControls: View {
    let model: AppModel
    let media: NowPlaying
    let accent: Color

    var body: some View {
        let canSkip = media.duration != nil && media.elapsed != nil
        ZStack {
            HStack(spacing: canSkip ? 2 : 14) {
                if canSkip {
                    PillButton(symbol: "gobackward.15", size: 11) { model.send(.skipBackward) }
                        .help("Back 15 seconds").accessibilityLabel("Back 15 seconds")
                }
                PillButton(symbol: "backward.fill", size: 12) { model.send(.previous) }
                    .help("Previous").accessibilityLabel("Previous track")
                PillButton(symbol: media.isPlaying ? "pause.fill" : "play.fill", size: 15) { model.send(.togglePlayPause) }
                    .accessibilityLabel(media.isPlaying ? "Pause" : "Play")
                PillButton(symbol: "forward.fill", size: 12) { model.send(.next) }
                    .help("Next").accessibilityLabel("Next track")
                if canSkip {
                    PillButton(symbol: "goforward.15", size: 11) { model.send(.skipForward) }
                        .help("Forward 15 seconds").accessibilityLabel("Forward 15 seconds")
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
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(on ? tint : Color.islandTertiary)
                .frame(width: 22, height: 22)
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
        HStack(spacing: 8) {
            Button { model.toggleMute() } label: {
                Image(systemName: Self.speakerSymbol(volume: c.volume, muted: c.muted))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.islandSecondary)
                    .frame(width: 18, height: 18)
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
        SmallIconButton(symbol: current.map(Self.symbol) ?? "hifispeaker.fill",
                        label: current.map { "Output: \($0.name)" } ?? "Choose output") {
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
        items.append(IslandMenu.Item(title: "Sound Settings…") {
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

/// A small borderless icon button for the island's secondary controls.
struct SmallIconButton: View {
    let symbol: String
    let label: String
    var tint: Color = .islandTertiary
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.play(.tap)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The cup in the expanded island's header: keep the Mac awake for a while or until turned off.
struct KeepAwakeButton: View {
    let model: AppModel

    var body: some View {
        let session = model.controls.awake
        Button { showMenu() } label: {
            Image(systemName: session == nil ? "cup.and.saucer" : "cup.and.saucer.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(session == nil ? Color.islandTertiary : Color(tint: KeepAwake.tint))
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
        var items = [IslandMenu.Item(title: session.map(Self.status) ?? "Keep Awake", enabled: false)]
        for preset in KeepAwake.presets {
            items.append(IslandMenu.Item(title: preset.title) {
                model.setKeepAwake(.start(minutes: preset.minutes), announce: false)
            })
        }
        if session != nil {
            items.append(.separator)
            items.append(IslandMenu.Item(title: "Turn Off") { model.setKeepAwake(.stop, announce: false) })
        }
        IslandMenu.show(items, model: model)
    }
}
