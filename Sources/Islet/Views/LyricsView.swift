import AppKit
import IsletCore
import SwiftUI

/// Lyrics beside Now Playing on Home, in the column the glances use. The line being sung is
/// bright, the next ones wait below it, and the column moves on at each new line: the view
/// wakes only when a line starts, never on a timer. Clicking a line plays from there; the "x"
/// that appears under the pointer hides the lyrics for this song.
struct LyricsColumn: View {
    let model: AppModel
    let media: NowPlaying
    let lyrics: SongLyrics
    /// The line just sung stays in view above the current one; not when a glance above the
    /// lyrics leaves room for only a couple of lines.
    var showsSungLine = true
    @ViewState private var hovering = false
    @Environment(\.reduceMotionAnywhere) private var reduceMotion
    @Environment(\.islandMotion) private var motion

    /// A line shows a moment before it is sung, so it is read in time.
    static let lead: Double = 0.2

    /// What Home's column shows beside the music, or nil for the glances: the lyrics (when on,
    /// found for the song on show and not hidden for it), or a lookup the lyrics button asked
    /// for, under any timer or stopwatch that is counting; nil too when something needs you or
    /// more is counting than fits (`LyricsPlacement`). The offer to turn lyrics on, opened with
    /// the button, takes the whole column until it is answered, unless something needs you.
    static func side(for plan: HomePlan, model: AppModel, height: CGFloat)
        -> (media: NowPlaying, content: LyricsController.Column, kept: [HomePlan.Glance])? {
        guard case .media(let np) = plan.primary, let content = model.tools.lyrics.column(for: np) else { return nil }
        let kinds = plan.glances.map { g -> LyricsPlacement.Glance in
            switch g {
            case .activity(let a) where HomePlan.needsYou(a): return .needsYou
            case .timer, .stopwatch: return .counting
            default: return .quiet
            }
        }
        if case .offer = content { return LyricsPlacement.offerFits(kinds) ? (np, content, []) : nil }
        guard case .lyrics(let keeping) = LyricsPlacement.column(kinds, room: LyricsPlacement.room(height: Double(height))) else {
            return nil
        }
        return (np, content, keeping.map { plan.glances[$0] })
    }

    var body: some View {
        Group {
            if lyrics.isSynced {
                synced
            } else if let plain = lyrics.plain {
                // No heading, as the synced lines have none: the column beside the song says it.
                AdaptiveScroll {
                    Text(plain)
                        .textStyle(.body)
                        .foregroundStyle(Ink.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Label("Instrumental", systemImage: "music.note")
                    .textStyle(.body)
                    .foregroundStyle(Ink.tertiary)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { model.tools.lyrics.hide(media) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Ink.tertiary)
                        .frame(width: 16, height: 16).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Hide lyrics for this song")
                .accessibilityLabel("Hide lyrics for this song")
            }
        }
        .onHover { hovering = $0 }
        // The × shows only under the pointer.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lyrics")
        .accessibilityAction(named: "Hide lyrics for this song") { model.tools.lyrics.hide(media) }
    }

    private var synced: some View {
        let now = Date()
        let position = (model.displayPosition(media, now: now) ?? 0) + Self.lead
        let rate = media.isPlaying ? max(0.01, media.playbackRate) : 0
        let wakeUps = [now] + lyrics.changes(from: position, rate: rate, now: now)
        return TimelineView(.explicit(wakeUps)) { ctx in
            let current = lyrics.index(at: (model.displayPosition(media, now: ctx.date) ?? 0) + Self.lead)
            LyricLines(lines: lyrics.lines, current: current, showsSungLine: showsSungLine) { line in
                Haptics.play(.tap)
                model.seek(to: line.time)
            }
            // The column moves on with the settle spring; with less motion the lines only fade
            // (`LyricLines`), so a short ease is all it needs, and nothing with Off.
            .animation(model.settings.animationStyle == .off ? nil
                       : reduceMotion || !motion.isRich ? .easeInOut(duration: 0.14 * Motion.pace) : Motion.settle,
                       value: current)
        }
    }
}

/// The line being sung and the few around it. The window starts one line before the current one,
/// so the line just sung stays in view, dimmed (unless `showsSungLine` is off).
struct LyricLines: View {
    let lines: [LyricLine]
    let current: Int?
    var showsSungLine = true
    var onTap: (LyricLine) -> Void
    @Environment(\.islandMotion) private var motion
    @Environment(\.reduceMotionAnywhere) private var reduceMotion

    /// More than ever fit, so the column is always full; the frame clips the rest.
    private static let window = 7

    var body: some View {
        let first = max(0, (current ?? 0) - (showsSungLine ? 1 : 0))
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(first..<min(lines.count, first + Self.window), id: \.self) { i in
                line(i)
            }
        }
        // The column's height, not the lines': the ones that don't fit are cut off below.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        // The last line fades out at the bottom edge instead of being cut through.
        .mask {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: Space.l)
            }
        }
    }

    private func line(_ i: Int) -> some View {
        let isCurrent = i == current
        let sung = current.map { i < $0 } ?? false
        let text = lines[i].text.isEmpty ? "♪" : lines[i].text
        return Button { onTap(lines[i]) } label: {
            Text(text)
                .font(.system(size: TextStyle.headline.size, weight: isCurrent ? .semibold : .medium))
                .foregroundStyle(isCurrent ? Ink.primary : sung ? Ink.quaternary : Ink.tertiary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                // Its own one or two rows, whatever the column has left: the column's frame cuts
                // what doesn't fit at the bottom, never a long line down to one row.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Play from here")
        .accessibilityLabel(lines[i].text.isEmpty ? "Instrumental" : lines[i].text)
        .accessibilityHint("Plays from here")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        // Lines slide up with the richer motion; Minimal and Reduce Motion only fade them.
        .transition(motion.isRich && !reduceMotion
                    ? .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                  removal: .move(edge: .top).combined(with: .opacity))
                    : .opacity)
    }
}

/// What the lyrics column says while it has no lyrics to show: a small spinner while the song
/// is looked up, or a quiet line ("No lyrics for this song") for a moment.
struct LyricsStatus: View {
    let note: String?

    var body: some View {
        Group {
            if let note {
                Text(note)
                    .textStyle(.body)
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(2)
            } else {
                SpinnerArc(tint: Ink.tertiary, lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                    .accessibilityLabel("Looking up lyrics")
            }
        }
        // On the first line's baseline, where the lyrics will start.
        .frame(height: 18, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The lyrics button's offer, in the column beside the song: what turning lyrics on sends, then
/// **Show lyrics** and **Not now**. Nothing is sent before Show lyrics.
struct LyricsOffer: View {
    let model: AppModel
    let media: NowPlaying
    /// The song plays in a web browser: Show lyrics turns lyrics on for browsers too.
    let browser: Bool

    static func line(browser: Bool) -> String {
        browser
            ? "Lyrics come from LRCLIB, a free lyrics library. Islet sends the song\u{2019}s title, artist, album and length, including from your browser."
            : "Lyrics come from LRCLIB, a free lyrics library. Islet sends the song\u{2019}s title, artist, album and length, once per song."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(Self.line(browser: browser))
                .textStyle(.caption)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Space.s) {
                Button("Show lyrics") {
                    Haptics.play(.tap)
                    model.tools.lyrics.accept(media)
                }
                .buttonStyle(CapsuleButtonStyle(tint: .blue, filled: true, compact: true))
                Button("Not now") { model.tools.lyrics.decline() }
                    .buttonStyle(QuietTextButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show lyrics?")
    }
}

/// The lyrics button on the Now Playing card: a quote bubble, lit while the lyrics show. With
/// lyrics off for the song it opens the offer instead.
struct LyricsButton: View {
    let model: AppModel
    let media: NowPlaying
    /// The button's frame: 24 beside the title, less under the other buttons.
    var size = CGSize(width: 24, height: 24)

    var body: some View {
        let lyrics = model.tools.lyrics
        let on = lyrics.isOn(for: media)
        let lit = lyrics.isShowing(media)
        // VoiceOver hears what a click does; the pointer's tooltip also says when none were found.
        let label = !on ? (lit ? "Close the lyrics offer" : "Show lyrics") : lit ? "Hide lyrics for this song" : "Show lyrics"
        let help = on && !lit && lyrics.state(for: media) == .missing ? "No lyrics for this song" : label
        Button {
            Haptics.play(.tap)
            lyrics.toggle(media)
        } label: {
            Image(systemName: lit ? "quote.bubble.fill" : "quote.bubble")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(lit ? Ink.primary : Ink.tertiary)
                .frame(width: min(size.width, size.height), height: min(size.width, size.height))
                .background(Circle().fill(lit ? Wash.strong : .clear))
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label)
        .accessibilityAddTraits(lit ? .isSelected : [])
    }
}
