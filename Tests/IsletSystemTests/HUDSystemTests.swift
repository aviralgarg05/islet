import Foundation
import IsletCore
@testable import IsletSystem
import Testing

/// Smoke tests against this Mac: they read state only and change nothing.
@Suite struct HUDSystemTests {
    @Test func settableChecksAnswerWithoutChangingAnything() {
        let before = AudioMonitor.readOutput()
        _ = AudioMonitor.isVolumeSettable()
        _ = AudioMonitor.isMuteSettable()
        // No device at all is never settable.
        #expect(!AudioMonitor.isVolumeSettable(device: 0))
        #expect(!AudioMonitor.isMuteSettable(device: 0))
        #expect(AudioMonitor.readOutput() == before)
    }

    @Test func capabilityChecksAnswer() {
        // Whatever this Mac has: the calls return rather than crash.
        _ = BrightnessMonitor.canSet
        _ = KeyboardBacklight.isAvailable
        if !BrightnessMonitor.isAvailable { #expect(!BrightnessMonitor.canSet) }
    }

    @Test func keyCodesMapToKeys() {
        #expect(MediaKeyInterceptor.key(for: 0) == .volumeUp)
        #expect(MediaKeyInterceptor.key(for: 7) == .mute)
        #expect(MediaKeyInterceptor.key(for: 3) == .brightnessDown)
        #expect(MediaKeyInterceptor.key(for: 22) == .backlightDown)
        #expect(MediaKeyInterceptor.key(for: 16) == nil)
    }
}
