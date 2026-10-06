import Foundation
import Testing
@testable import CasementCore

/// Music and Spotify switched off send nothing, and a control that can't reach them says why.
@Suite struct PlayerIntegrationTests {
    @Test func aSourceSwitchedOffDoesNotRunAtAll() {
        for source in [MediaSourceKind.appleMusic, .spotify] {
            #expect(PlayerIntegration.runs(source, disabled: []))
            #expect(!PlayerIntegration.runs(source, disabled: [source]))
            // Bridge down: it fetches its own details only while it is on.
            #expect(PlayerIntegration.enriches(source, disabled: [], bridgeRunning: false))
            #expect(!PlayerIntegration.enriches(source, disabled: [source], bridgeRunning: false))
            #expect(!PlayerIntegration.enriches(source, disabled: [], bridgeRunning: true))
        }
        // Switching off one leaves the other.
        #expect(PlayerIntegration.runs(.spotify, disabled: [.appleMusic]))
    }

    @Test(arguments: [
        // (source, sent, bridge, canScript, hint)
        (MediaSourceKind.appleMusic, false, false, false, "Music" as String?),
        (.spotify, false, false, false, "Spotify"),
        (.spotify, true, false, false, nil),       // it went through
        (.spotify, false, true, false, nil),       // the bridge is there; something else went wrong
        (.spotify, false, false, true, nil),       // allowed: the player itself didn't take it
        (.system, false, false, false, nil),       // only Music and Spotify need Automation
        (.browser, false, false, false, nil),
    ])
    func whenToAskForControl(source: MediaSourceKind, sent: Bool, bridge: Bool, canScript: Bool, hint: String?) {
        #expect(PlayerIntegration.controlHint(for: source, sent: sent, bridgeRunning: bridge, canScript: canScript) == hint)
    }
}
