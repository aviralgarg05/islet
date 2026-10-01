import AppKit
import Testing
@testable import IsletSystem

/// A shortcut field suspends Islet's shortcuts while it records. Only the counting is tested
/// here: registering real system-wide shortcuts from a test would take them from the user.
@Suite(.serialized) struct GlobalHotkeyTests {
    @Test func suspendingNestsAndResumesOnce() {
        #expect(!GlobalHotkey.isSuspended)
        // Two fields (or one asked twice) each suspend; the shortcuts come back after both.
        GlobalHotkey.suspendAll()
        GlobalHotkey.suspendAll()
        #expect(GlobalHotkey.isSuspended)
        GlobalHotkey.resumeAll()
        #expect(GlobalHotkey.isSuspended)
        GlobalHotkey.resumeAll()
        #expect(!GlobalHotkey.isSuspended)
    }

    @Test func anExtraResumeChangesNothing() {
        GlobalHotkey.resumeAll()
        #expect(!GlobalHotkey.isSuspended)
        // The count never went below zero, so one suspend is enough to suspend again.
        GlobalHotkey.suspendAll()
        #expect(GlobalHotkey.isSuspended)
        GlobalHotkey.resumeAll()
        #expect(!GlobalHotkey.isSuspended)
    }

    @Test func recordingEndsWhenFocusMoves() {
        // Recording, then switching to another app: the field can't hear keys any more, so the
        // shortcuts come back and the field is told to stop.
        let center = NotificationCenter()
        let recording = ShortcutRecording(center: center)
        var ended = 0
        recording.onEnd = { ended += 1 }
        recording.begin()
        #expect(GlobalHotkey.isSuspended)
        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        #expect(!recording.isActive)
        #expect(!GlobalHotkey.isSuspended)
        #expect(ended == 1)
        // Later notifications and a second end change nothing.
        center.post(name: NSWindow.didResignKeyNotification, object: nil)
        recording.end()
        #expect(ended == 1)
        #expect(!GlobalHotkey.isSuspended)

        // Closing the Settings window (its window stops being key) ends it too.
        recording.begin()
        #expect(GlobalHotkey.isSuspended)
        center.post(name: NSWindow.didResignKeyNotification, object: nil)
        #expect(!GlobalHotkey.isSuspended)
        #expect(ended == 2)
    }

    @Test func endingByHandDoesNotCallBack() {
        let center = NotificationCenter()
        let recording = ShortcutRecording(center: center)
        var ended = 0
        recording.onEnd = { ended += 1 }
        recording.begin()
        recording.begin()
        recording.end()
        // One begin and one end, however often each is asked.
        #expect(!GlobalHotkey.isSuspended)
        #expect(ended == 0)
    }

    @Test func releasingARecordingGivesTheShortcutsBack() {
        var recording: ShortcutRecording? = ShortcutRecording(center: NotificationCenter())
        recording?.begin()
        #expect(GlobalHotkey.isSuspended)
        recording = nil
        #expect(!GlobalHotkey.isSuspended)
    }
}
