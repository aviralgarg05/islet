import Foundation
import CasementCore
@testable import CasementSystem
import Testing

/// Scripts to Music and Spotify never launch a player that has quit.
@Suite struct PlayerScriptTests {
    @Test func everyScriptChecksThePlayerIsOpen() {
        let wrapped = ScriptablePlayerProvider.whileRunning("tell application id \"com.apple.Music\" to return player position",
                                                            bundleID: "com.apple.Music")
        #expect(wrapped.hasPrefix("if application id \"com.apple.Music\" is running then\n"))
        #expect(wrapped.hasSuffix("\nend if"))
        #expect(wrapped.contains("tell application id \"com.apple.Music\" to return player position"))
    }

    @MainActor @Test func scriptsGoOutWrapped() {
        let spotify = SpotifyProvider()
        var sent: [String] = []
        spotify.scriptRunner = { script, _ in sent.append(script) }
        NotificationCenter.default.post(name: .casementAutomationStatus, object: "com.spotify.client", userInfo: ["status": PermissionStatus.granted])
        spotify.refresh()
        #expect(sent.count == 1)
        #expect(sent.first?.hasPrefix("if application id \"com.spotify.client\" is running then") == true)
    }
}
