import CoreAudio
import Foundation
import IOKit.ps
import IsletCore
import Testing
@testable import IsletSystem

/// Pure parsing and command building only: nothing here sends a command to a real player,
/// changes the audio output or touches the volume.
@Suite struct MediaControlSystemTests {
    @Test func bridgeReadsShuffleAndRepeat() {
        let (np, _, _) = SystemNowPlayingBridge.parse(["title": "Song", "playing": true, "shuffleMode": 3, "repeatMode": 2])
        #expect(np?.shuffle == true)
        #expect(np?.repeatMode == .one)
        let (off, _, _) = SystemNowPlayingBridge.parse(["title": "Song", "shuffleMode": 1, "repeatMode": 1])
        #expect(off?.shuffle == false)
        #expect(off?.repeatMode == .off)
        // Players that don't report the modes get no buttons.
        let (plain, _, _) = SystemNowPlayingBridge.parse(["title": "Song"])
        #expect(plain?.shuffle == nil)
        #expect(plain?.repeatMode == nil)
        let (unknown, _, _) = SystemNowPlayingBridge.parse(["title": "Song", "shuffleMode": 0, "repeatMode": 0])
        #expect(unknown?.shuffle == nil && unknown?.repeatMode == nil)
    }

    @Test func appleScriptForTheNewCommands() {
        let spotify = "com.spotify.client", music = "com.apple.Music"
        #expect(ScriptablePlayerProvider.verb(for: .toggleShuffle, position: nil, bundleID: spotify) == "set shuffling to not shuffling")
        #expect(ScriptablePlayerProvider.verb(for: .toggleRepeat, position: nil, bundleID: spotify) == "set repeating to not repeating")
        #expect(ScriptablePlayerProvider.verb(for: .toggleShuffle, position: nil, bundleID: music) == "set shuffle enabled to not shuffle enabled")
        #expect(ScriptablePlayerProvider.verb(for: .toggleRepeat, position: nil, bundleID: music)?.contains("set song repeat to all") == true)
        #expect(ScriptablePlayerProvider.verb(for: .skipForward, position: nil, bundleID: spotify) == "set player position to (player position + 15)")
        #expect(ScriptablePlayerProvider.verb(for: .skipBackward, position: nil, bundleID: music) == "set player position to (player position - 15)")
        #expect(ScriptablePlayerProvider.verb(for: .seek, position: 42.5, bundleID: spotify) == "set player position to 42.5")
        #expect(ScriptablePlayerProvider.verb(for: .seek, position: nil, bundleID: spotify) == nil)
        #expect(ScriptablePlayerProvider.verb(for: .next, position: nil, bundleID: music) == "next track")
    }
}

@Suite struct BatteryAdapterTests {
    @Test func adapterWatts() {
        #expect(BatteryMonitor.adapterWatts([kIOPSPowerAdapterWattsKey: 96]) == 96)
        #expect(BatteryMonitor.adapterWatts([kIOPSPowerAdapterWattsKey: NSNumber(value: 140)]) == 140)
        #expect(BatteryMonitor.adapterWatts([kIOPSPowerAdapterWattsKey: 0]) == nil)
        #expect(BatteryMonitor.adapterWatts([:]) == nil)
    }
}

@Suite struct AudioOutputTests {
    @Test func transportTypes() {
        #expect(AudioTransport(code: kAudioDeviceTransportTypeBuiltIn) == .builtIn)
        #expect(AudioTransport(code: kAudioDeviceTransportTypeBluetooth) == .bluetooth)
        #expect(AudioTransport(code: kAudioDeviceTransportTypeBluetoothLE) == .bluetooth)
        #expect(AudioTransport(code: kAudioDeviceTransportTypeAirPlay) == .airPlay)
        #expect(AudioTransport(code: kAudioDeviceTransportTypeHDMI) == .hdmi)
        #expect(AudioTransport(code: kAudioDeviceTransportTypeUSB) == .usb)
        #expect(AudioTransport(code: 0) == .other)
    }

    /// Read-only: lists devices without changing anything.
    @Test func listingIsWellFormed() {
        let devices = AudioOutputs.all()
        #expect(Set(devices.map(\.id)).count == devices.count)
        #expect(devices.allSatisfy { !$0.name.isEmpty && !$0.uid.isEmpty })
    }
}

@Suite struct PowerAssertionTests {
    /// Holds a display-sleep assertion for a moment and releases it.
    @Test func holdAndRelease() {
        let a = PowerAssertion()
        #expect(!a.isHeld)
        #expect(a.hold(reason: "Islet test"))
        #expect(a.isHeld)
        #expect(a.hold(reason: "Islet test"))      // idempotent
        a.release()
        #expect(!a.isHeld)
        a.release()
        #expect(!a.isHeld)
    }
}
