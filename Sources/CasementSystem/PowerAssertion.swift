import Foundation
import IOKit.pwr_mgt

/// Keeps the display (and therefore the Mac) from sleeping while idle, like `caffeinate -d`.
/// Public IOKit API, no permission. macOS drops the assertion if the process exits.
public final class PowerAssertion {
    private var assertionID: IOPMAssertionID = 0
    public private(set) var isHeld = false

    public init() {}
    deinit { release() }

    /// Take the assertion (idempotent). `reason` shows in `pmset -g assertions`.
    @discardableResult
    public func hold(reason: String) -> Bool {
        if isHeld { return true }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { return false }
        assertionID = id
        isHeld = true
        return true
    }

    public func release() {
        guard isHeld else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isHeld = false
    }
}
