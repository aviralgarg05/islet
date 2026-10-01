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
    @ViewState private var hovering = false
    @Environment(\.reduceMotionAnywhere) private var reduceMotion

    /// A line shows a moment before it is sung, so it is read in time.
    static let lead: Double = 0.2

    /// The lyrics to show in Home's column, or nil for the glances: lyrics are on, found for the
    /// song on show, not hidden for it, and nothing in the column needs you.
    static func lyrics(for plan: HomePlan, model: AppModel) -> (NowPlaying, SongLyrics)? {
        guard model.settings.lyricsEnabled, case .media(let np) = plan.primary, !model.tools.lyrics.isHidden(np),
              let lyrics = model.tools.lyrics.lyrics(for: np) else { return nil }
        let urgent = plan.glances.contains { if case .activity(let a) = $0 { return HomePlan.needsYou(a) } else { return false } }
        return urgent ? nil : (np, lyrics)
    }

    var body: some View {
        Group {
            if lyrics.isSynced {
                synced
            } else if let plain = lyrics.plain {
                VStack(alignment: .leading, spacing: Space.xs) {
                    SectionLabel(title: "Lyrics").frame(height: 16)
                    AdaptiveScroll {
                        Text(plain)
                            .textStyle(.body)
                            .foregroundStyle(Ink.secondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
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
            }
        }
        .onHover { hovering = $0 }
    }

    private var synced: some View {
        let now = Date()
        let position = (model.displayPosition(media, now: now) ?? 0) + Self.lead
        let rate = media.isPlaying ? max(0.01, media.playbackRate) : 0
        let wakeUps = [now] + lyrics.changes(from: position, rate: rate, now: now)
        return TimelineView(.explicit(wakeUps)) { ctx in
            let current = lyrics.index(at: (model.displayPosition(media, now: ctx.date) ?? 0) + Self.lead)
            LyricLines(lines: lyrics.lines, current: current) { line in
                Haptics.play(.tap)
                model.seek(to: line.time)
            }
            .animation(reduceMotion || model.settings.animationStyle == .off ? nil : Motion.settle, value: current)
        }
    }
}

/// The line being sung and the few around it. The window starts one line before the current one,
/// so the line just sung stays in view, dimmed.
struct LyricLines: View {
    let lines: [LyricLine]
    let current: Int?
    var onTap: (LyricLine) -> Void

    /// More than ever fit, so the column is always full; the frame clips the rest.
    private static let window = 7

    var body: some View {
        let first = max(0, (current ?? 0) - 1)
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Play from here")
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)))
    }
}
