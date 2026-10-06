import Foundation

/// The volume, brightness and keyboard backlight keys "Replace the system volume and
/// brightness display" can take over.
public enum MediaKey: Sendable, CaseIterable {
    case volumeUp, volumeDown, mute, brightnessUp, brightnessDown, backlightUp, backlightDown
}

/// What decides whether Casement may take a key from macOS: everything the key's job depends on.
public struct KeyInterceptState: Equatable, Sendable {
    /// The Mac's own display is on (false with the lid closed or no built-in display).
    public var builtInDisplayOnline: Bool
    /// Casement can read and set the built-in display's brightness (the private framework is there).
    public var canSetBrightness: Bool
    /// The pointer is on the built-in display, so that's the display the user means.
    public var pointerOnBuiltInDisplay: Bool
    /// The output's volume can be set (false for fixed-volume DACs, HDMI and some docks).
    public var volumeSettable: Bool
    /// The output can be muted.
    public var muteSettable: Bool
    /// Casement can read and set the keyboard backlight.
    public var canSetKeyboardBacklight: Bool
    /// BetterDisplay, MonitorControl or Lunar is running and handles the brightness keys itself.
    public var displayToolRunning: Bool
    public var optionHeld: Bool
    public var shiftHeld: Bool

    public init(builtInDisplayOnline: Bool = true, canSetBrightness: Bool = true, pointerOnBuiltInDisplay: Bool = true,
                volumeSettable: Bool = true, muteSettable: Bool = true, canSetKeyboardBacklight: Bool = true,
                displayToolRunning: Bool = false, optionHeld: Bool = false, shiftHeld: Bool = false) {
        self.builtInDisplayOnline = builtInDisplayOnline
        self.canSetBrightness = canSetBrightness
        self.pointerOnBuiltInDisplay = pointerOnBuiltInDisplay
        self.volumeSettable = volumeSettable
        self.muteSettable = muteSettable
        self.canSetKeyboardBacklight = canSetKeyboardBacklight
        self.displayToolRunning = displayToolRunning
        self.optionHeld = optionHeld
        self.shiftHeld = shiftHeld
    }
}

/// Whether the key tap swallows a key. It takes a key only when Casement can do that key's job
/// itself; anything else goes on to macOS (and to display tools), which shows its own HUD.
public enum KeyInterceptPolicy {
    /// Apps that set an external display's brightness from the keyboard, by the bundle
    /// identifiers they run under. While one runs, the brightness keys are theirs.
    public static let displayTools: Set<String> = [
        "pro.betterdisplay.BetterDisplay",
        "me.guillaumeb.MonitorControl",
        "fyi.lunar.Lunar",
    ]

    public static func shouldIntercept(_ key: MediaKey, _ s: KeyInterceptState) -> Bool {
        // Option alone opens Sound or Displays settings; Shift and Option together is a fine step.
        if s.optionHeld && !s.shiftHeld { return false }
        switch key {
        case .volumeUp, .volumeDown:
            return s.volumeSettable
        case .mute:
            return s.muteSettable
        case .brightnessUp, .brightnessDown:
            return s.canSetBrightness && s.builtInDisplayOnline && s.pointerOnBuiltInDisplay && !s.displayToolRunning
        case .backlightUp, .backlightDown:
            return s.canSetKeyboardBacklight
        }
    }

    /// Whether `bundleIDs` (the running apps) include a display tool.
    public static func displayToolRunning(_ bundleIDs: some Sequence<String>) -> Bool {
        bundleIDs.contains(where: displayTools.contains)
    }
}

/// One answer for a whole key press. The press decides (`KeyInterceptPolicy`); its repeats and
/// its release get the same answer, even if Option was let go first or the pointer moved to
/// another display meanwhile, so macOS never sees a release without its press, or the reverse.
public struct KeyInterceptLatch: Sendable {
    private var taken: [MediaKey: Bool] = [:]

    public init() {}

    /// Whether to take this event. `decide` is asked on a new press, and on a repeat or release
    /// whose press wasn't seen (the tap started mid-press).
    public mutating func take(_ key: MediaKey, isDown: Bool, isRepeat: Bool, decide: () -> Bool) -> Bool {
        let answer: Bool
        if isDown && !isRepeat {
            answer = decide()
        } else {
            answer = taken[key] ?? decide()
        }
        taken[key] = isDown ? answer : nil
        return answer
    }
}
