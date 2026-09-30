import Foundation
import Testing
@testable import IsletCore

@Suite struct PermissionTests {
    @Test func automationStatusFromOSStatus() {
        #expect(PermissionStatus.automation(0) == .granted)
        #expect(PermissionStatus.automation(-1743) == .denied)
        #expect(PermissionStatus.automation(-1744) == .notDetermined)
        #expect(PermissionStatus.automation(-600) == .appNotRunning)
        #expect(PermissionStatus.automation(-50) == .unknown)
    }

    @Test func buttonAsksOnlyWhenMacOSStillCan() {
        #expect(PermissionStatus.notDetermined.action == .request)
        #expect(PermissionStatus.unknown.action == .request)
        #expect(PermissionStatus.denied.action == .openSettings)
        #expect(PermissionStatus.granted.action == .openSettings)
        #expect(PermissionStatus.appNotRunning.action == .openSettings)
        #expect(PermissionStatus.appNotInstalled.action == PermissionAction.none)
    }

    @Test func settingsLinksOpenPrivacyPanes() {
        for kind in PermissionKind.allCases {
            #expect(kind.settingsURL.scheme == "x-apple.systempreferences")
            #expect(kind.settingsURL.absoluteString.contains("?Privacy_"))
        }
        #expect(PermissionKind.accessibility.settingsURL.absoluteString.hasSuffix("Privacy_Accessibility"))
        #expect(PermissionKind.automationSpotify.settingsURL == PermissionKind.automationMusic.settingsURL)
    }

    @Test func onlyAutomationHasATargetApp() {
        #expect(PermissionKind.automationMusic.automationTarget == "com.apple.Music")
        #expect(PermissionKind.automationSpotify.automationTarget == "com.spotify.client")
        #expect(PermissionKind.allCases.filter { $0.automationTarget != nil }.count == 2)
    }

    @Test func automationGateSendsNothingUntilGranted() {
        var gate = AutomationGate()
        // `#expect` can't take a mutating call, so each step goes through these.
        func check(_ t: AutomationGate.Trigger) -> Bool { gate.shouldCheck(t) }
        func answer(_ s: PermissionStatus) -> Bool { gate.record(s) }
        #expect(!gate.allowsEvents)
        #expect(check(.firstUse))
        // One check at a time.
        #expect(!check(.firstUse))
        #expect(!check(.appActivated))
        #expect(!answer(.notDetermined))
        #expect(!gate.allowsEvents)
        // Once per launch, then again only when the app becomes active.
        #expect(!check(.firstUse))
        #expect(check(.appActivated))
        #expect(!answer(.appNotRunning))
        #expect(check(.appActivated))
        #expect(answer(.granted))
        #expect(gate.allowsEvents)
        // Granted is a lasting answer: no more checks, and no second "just allowed".
        #expect(!check(.appActivated))
        #expect(!check(.firstUse))
        #expect(!answer(.granted))
    }

    @Test func automationGateStopsAskingAfterARefusal() {
        var gate = AutomationGate()
        func check(_ t: AutomationGate.Trigger) -> Bool { gate.shouldCheck(t) }
        #expect(check(.firstUse))
        gate.record(.denied)
        #expect(!gate.allowsEvents)
        #expect(!check(.appActivated))
        #expect(!check(.firstUse))
        // Allow in Settings → Permissions (or the switch in System Settings) still gets through.
        let allowed = gate.record(.granted)
        #expect(allowed)
        #expect(gate.allowsEvents)
    }

    @Test func automationGateTakesAnAnswerWithoutAskingItself() {
        var gate = AutomationGate()
        let allowed = gate.record(.granted)
        #expect(allowed)
        #expect(gate.allowsEvents)
        let due = gate.shouldCheck(.firstUse)
        #expect(!due)
    }

    @Test func promptOnlyAsTheUserSwitchesOn() {
        // At launch a feature found switched on never asks, even without its permission.
        #expect(!PermissionPrompt.shouldAsk(wasOn: nil, isOn: true))
        #expect(!PermissionPrompt.shouldAsk(wasOn: nil, isOn: false))
        #expect(PermissionPrompt.shouldAsk(wasOn: false, isOn: true))
        // Other settings changes while it stays on don't ask again.
        #expect(!PermissionPrompt.shouldAsk(wasOn: true, isOn: true))
        #expect(!PermissionPrompt.shouldAsk(wasOn: true, isOn: false))
        #expect(!PermissionPrompt.shouldAsk(wasOn: false, isOn: false))
    }

    @Test func usesFollowTheSettings() {
        var s = IsletSettings()
        s.replaceSystemHUD = false
        s.notificationMirroring = true
        s.mirrorMenuBarActivities = false
        s.closedLayout = .wings
        #expect(PermissionKind.accessibility.uses(s).map(\.isOn) == [false, true, false, false])
        s.downloadsEnabled = true
        #expect(PermissionKind.downloadsFolder.uses(s).map(\.isOn) == [true])
        #expect(PermissionKind.automationMusic.uses(s).map(\.isOn) == [true])
        s.disabledMediaSources = [.appleMusic]
        #expect(PermissionKind.automationMusic.uses(s).map(\.isOn) == [false])
        #expect(PermissionKind.automationSpotify.uses(s).map(\.isOn) == [true])
        s.mediaEnabled = false
        #expect(PermissionKind.automationSpotify.uses(s).map(\.isOn) == [false])
        for kind in PermissionKind.allCases { #expect(!kind.uses(s).isEmpty) }
    }
}
