// A silent "media player" used by the end-to-end tests. It publishes Now Playing info
// through MPNowPlayingInfoCenter and logs remote commands it receives, so the MediaRemote
// bridge can be verified without playing real audio or touching the user's players.
import AppKit
import MediaPlayer

let title = CommandLine.arguments.dropFirst().first ?? "Islet Test Track"
let center = MPNowPlayingInfoCenter.default()
var playing = true

func publish() {
    center.nowPlayingInfo = [
        MPMediaItemPropertyTitle: title,
        MPMediaItemPropertyArtist: "Islet Test Artist",
        MPMediaItemPropertyAlbumTitle: "Islet Test Album",
        MPMediaItemPropertyPlaybackDuration: 180.0,
        MPNowPlayingInfoPropertyElapsedPlaybackTime: 42.0,
        MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
    ]
    center.playbackState = playing ? .playing : .paused
}

func log(_ s: String) {
    print(s)
    fflush(stdout)
}

let rc = MPRemoteCommandCenter.shared()
rc.togglePlayPauseCommand.addTarget { _ in playing.toggle(); publish(); log("command togglePlayPause"); return .success }
rc.playCommand.addTarget { _ in playing = true; publish(); log("command play"); return .success }
rc.pauseCommand.addTarget { _ in playing = false; publish(); log("command pause"); return .success }
rc.nextTrackCommand.addTarget { _ in log("command next"); return .success }
rc.previousTrackCommand.addTarget { _ in log("command previous"); return .success }
rc.changePlaybackPositionCommand.addTarget { event in
    let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime ?? -1
    log("command seek \(position)")
    return .success
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
publish()
log("fake player ready: \(title)")
DispatchQueue.main.asyncAfter(deadline: .now() + (Double(ProcessInfo.processInfo.environment["FAKE_PLAYER_SECONDS"] ?? "60") ?? 60)) { exit(0) }
app.run()
