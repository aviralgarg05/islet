import IsletCore
import SwiftUI

/// How Now Playing follows a new song. The artwork swaps with a short, springy scale and fade
/// and a slight blur; the title and artist push in from below. Only a new track does this (a
/// new title, artist or album), never pausing, resuming or seeking. With less motion it is a
/// quick fade, and with animation off nothing moves. Each change is one SwiftUI transition:
/// nothing runs between songs.
enum TrackChange {
    /// What the artwork shows: the song, and whether its picture has arrived (players often
    /// send it a moment after the title, and that should fade in rather than pop).
    static func artworkID(_ np: NowPlaying) -> String {
        np.trackKey + (np.artworkData != nil ? "#data" : np.artworkURL != nil ? "#url" : "")
    }

    /// The animation for a change of song in `style`.
    static func animation(_ style: AnimationStyle, lively: Bool = false) -> Animation? {
        switch style {
        case .off: return nil
        case .minimal: return .easeInOut(duration: 0.18)
        default: return lively ? Motion.open : Motion.settle
        }
    }

    /// Artwork: the new picture grows in from a little smaller, out of a slight blur, while the
    /// old one fades out quickly underneath.
    static func artwork(_ style: AnimationStyle, size: CGFloat) -> AnyTransition {
        switch style {
        case .off: return .identity
        case .minimal: return .opacity
        default:
            let blur = min(6, max(2, size * 0.1))
            return .asymmetric(
                insertion: .modifier(active: Swap(scale: 0.72, blur: blur, opacity: 0), identity: Swap(scale: 1, blur: 0, opacity: 1)),
                removal: AnyTransition.modifier(active: Swap(scale: 0.9, blur: blur, opacity: 0), identity: Swap(scale: 1, blur: 0, opacity: 1))
                    .animation(.easeIn(duration: 0.12))
            )
        }
    }

    /// Title and artist: pushed up and out by the new ones coming in from below, with a fade.
    static func text(_ style: AnimationStyle) -> AnyTransition {
        switch style {
        case .off: return .identity
        case .minimal: return .opacity
        default: return .push(from: .bottom)
        }
    }

    private struct Swap: ViewModifier {
        var scale: CGFloat
        var blur: CGFloat
        var opacity: Double

        func body(content: Content) -> some View {
            content.scaleEffect(scale).blur(radius: blur).opacity(opacity)
        }
    }
}

/// Album art that swaps with `TrackChange` when the song changes.
struct TrackArtwork: View {
    let media: NowPlaying
    var size: CGFloat
    var corner: CGFloat
    @Environment(\.islandMotion) private var motion

    var body: some View {
        let id = TrackChange.artworkID(media)
        ZStack {
            ArtworkView(media: media, size: size, corner: corner)
                .id(id)
                .transition(TrackChange.artwork(motion, size: size))
        }
        .frame(width: size, height: size)
        .animation(TrackChange.animation(motion, lively: true), value: id)
    }
}

/// The title and artist of a song, pushed in from below when the song changes.
struct TrackText<Content: View>: View {
    let media: NowPlaying
    @ViewBuilder var content: Content
    @Environment(\.islandMotion) private var motion

    var body: some View {
        ZStack(alignment: .leading) {
            content
                .id(media.trackKey)
                .transition(TrackChange.text(motion))
        }
        // The old lines leave through the top edge, the new ones arrive through the bottom.
        .clipped()
        .animation(TrackChange.animation(motion), value: media.trackKey)
    }
}

/// The island's animation style after Reduce Motion (system or Islet's own), for views that
/// animate on their own: `minimal` means quick fades only, `off` means nothing moves.
private struct IslandMotionKey: EnvironmentKey {
    static let defaultValue: AnimationStyle = .fluid
}

extension EnvironmentValues {
    var islandMotion: AnimationStyle {
        get { self[IslandMotionKey.self] }
        set { self[IslandMotionKey.self] = newValue }
    }
}
