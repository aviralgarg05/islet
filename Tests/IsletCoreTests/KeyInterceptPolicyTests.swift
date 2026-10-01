import Foundation
import Testing
@testable import IsletCore

/// The key tap takes a key only when Islet can do its job; everything else goes to macOS.
@Suite struct KeyInterceptPolicyTests {
    /// Every combination of the nine facts.
    static let everyState: [KeyInterceptState] = (0..<(1 << 9)).map { bits in
        func bit(_ i: Int) -> Bool { bits & (1 << i) != 0 }
        return KeyInterceptState(builtInDisplayOnline: bit(0), canSetBrightness: bit(1), pointerOnBuiltInDisplay: bit(2),
                                 volumeSettable: bit(3), muteSettable: bit(4), canSetKeyboardBacklight: bit(5),
                                 displayToolRunning: bit(6), optionHeld: bit(7), shiftHeld: bit(8))
    }

    @Test(arguments: MediaKey.allCases)
    func everyStateForEveryKey(key: MediaKey) {
        for s in Self.everyState {
            let expected: Bool
            if s.optionHeld && !s.shiftHeld {
                expected = false
            } else {
                switch key {
                case .volumeUp, .volumeDown: expected = s.volumeSettable
                case .mute: expected = s.muteSettable
                case .brightnessUp, .brightnessDown:
                    expected = s.builtInDisplayOnline && s.canSetBrightness && s.pointerOnBuiltInDisplay && !s.displayToolRunning
                case .backlightUp, .backlightDown: expected = s.canSetKeyboardBacklight
                }
            }
            #expect(KeyInterceptPolicy.shouldIntercept(key, s) == expected, "\(key) \(s)")
        }
    }

    @Test(arguments: [
        // (what, key, state, taken)
        ("MacBook, everything works", MediaKey.brightnessUp, KeyInterceptState(), true),
        ("lid closed on an external display", .brightnessUp, KeyInterceptState(builtInDisplayOnline: false, pointerOnBuiltInDisplay: false), false),
        ("pointer on the external display", .brightnessDown, KeyInterceptState(pointerOnBuiltInDisplay: false), false),
        ("macOS removed the brightness symbols", .brightnessUp, KeyInterceptState(canSetBrightness: false), false),
        ("BetterDisplay is running", .brightnessUp, KeyInterceptState(displayToolRunning: true), false),
        ("a display tool doesn't take volume", .volumeUp, KeyInterceptState(displayToolRunning: true), true),
        ("fixed-volume DAC", .volumeUp, KeyInterceptState(volumeSettable: false), false),
        ("fixed-volume DAC that can mute", .mute, KeyInterceptState(volumeSettable: false), true),
        ("output that can't mute", .mute, KeyInterceptState(muteSettable: false), false),
        ("Option opens Sound settings", .volumeUp, KeyInterceptState(optionHeld: true), false),
        ("Option opens Displays settings", .brightnessUp, KeyInterceptState(optionHeld: true), false),
        ("Shift and Option is a fine step", .volumeDown, KeyInterceptState(optionHeld: true, shiftHeld: true), true),
        ("Shift alone", .volumeDown, KeyInterceptState(shiftHeld: true), true),
        ("no keyboard backlight", .backlightUp, KeyInterceptState(canSetKeyboardBacklight: false), false),
        ("keyboard backlight with the lid closed", .backlightDown, KeyInterceptState(builtInDisplayOnline: false), true),
    ])
    func namedCases(what: String, key: MediaKey, state: KeyInterceptState, taken: Bool) {
        #expect(KeyInterceptPolicy.shouldIntercept(key, state) == taken, "\(what)")
    }

    @Test func displayTools() {
        #expect(KeyInterceptPolicy.displayToolRunning(["com.apple.finder", "me.guillaumeb.MonitorControl"]))
        #expect(KeyInterceptPolicy.displayToolRunning(["pro.betterdisplay.BetterDisplay"]))
        #expect(KeyInterceptPolicy.displayToolRunning(["fyi.lunar.Lunar"]))
        #expect(!KeyInterceptPolicy.displayToolRunning(["com.apple.finder", "com.apple.Safari"]))
        #expect(!KeyInterceptPolicy.displayToolRunning([String]()))
    }
}
