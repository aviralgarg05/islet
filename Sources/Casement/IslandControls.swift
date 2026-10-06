import Foundation
import CasementCore
import CasementSystem
import Observation

/// State for the Now Playing controls, swipe gestures and keep awake. The behaviour lives in
/// `AppModel+Controls.swift`; views observe this object through `model.controls`.
@MainActor
@Observable
final class IslandControls {
    // MARK: Now Playing

    /// Set after a seek so the scrubber doesn't jump back while the player catches up.
    var seekGrace: SeekGrace?
    /// Short cards show the volume row in place of the transport controls while this is on.
    var soundRowShown = false
    var outputs: [AudioOutputDevice] = []
    var defaultOutputID: UInt32 = 0
    var volume: Double = 0.5
    var muted = false
    /// How many volume rows are on screen; the audio watcher runs only while there is one.
    @ObservationIgnored var soundViewers = 0
    @ObservationIgnored let outputWatcher = AudioOutputWatcher()

    // MARK: Gestures

    /// The activity brought forward by a sideways swipe on the closed island.
    var focusedActivityID: String?
    /// After the island closes with the pointer on the notch (a swipe, the shortcut, a menu, a
    /// link), hovering doesn't reopen it until the pointer leaves.
    @ObservationIgnored var hoverOpenBlocked = false
    /// A menu is open or a slider is being dragged: moving past the island's edge doesn't close it.
    @ObservationIgnored var holdsOpen = false
    /// Any menu of Casement's is open, a right-click menu included (`NSMenu` tracking).
    @ObservationIgnored var menuOpen = false
    /// A file is being dragged out of the shelf (until the mouse button comes up).
    @ObservationIgnored var draggingOut = false
    /// The page switcher's width as drawn, so only the switcher itself takes clicks.
    @ObservationIgnored var switcherWidth: CGFloat?

    // MARK: Keep awake

    var awake: KeepAwakeSession?
    @ObservationIgnored let assertion = PowerAssertion()
    @ObservationIgnored var awakeTimer: Timer?
    /// Watches the battery for the low-battery release while keep awake is on.
    @ObservationIgnored var awakeBattery: BatteryMonitor?
}
