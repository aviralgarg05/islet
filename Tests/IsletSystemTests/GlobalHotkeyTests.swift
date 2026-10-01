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
}
