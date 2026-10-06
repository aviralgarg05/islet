import Foundation
import Testing
@testable import CasementCore

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
        #expect(PermissionStatus.appNotRunning.action == .openApp)
        #expect(PermissionStatus.appNotInstalled.action == PermissionAction.none)
    }

    /// Automation can only be checked while the app is open, so the row offers to open it
    /// rather than sending people to System Settings, where there is nothing to switch yet.
    @Test func aClosedAppIsOpenedToCheck() {
        #expect(PermissionKind.automationMusic.statusLabel(.appNotRunning) == "Music isn\u{2019}t open")
        #expect(PermissionKind.automationMusic.buttonTitle(.appNotRunning) == "Open Music")
        #expect(PermissionKind.automationSpotify.buttonTitle(.appNotRunning) == "Open Spotify")
        #expect(PermissionKind.automationSpotify.buttonTitle(.appNotInstalled) == nil)
    }

    /// The same words as the Calendar page: a refusal says where the switch is.
    @Test func statusLabelsMatchTheCalendarPage() {
        #expect(PermissionKind.camera.statusLabel(.granted) == CalendarAccessAdvice.advice(.fullAccess, kind: .calendars).status)
        #expect(PermissionKind.location.statusLabel(.denied) == CalendarAccessAdvice.advice(.denied, kind: .calendars).status)
        #expect(PermissionKind.camera.statusLabel(.notDetermined) == CalendarAccessAdvice.advice(.notDetermined, kind: .calendars).status)
        #expect(PermissionKind.calendars.statusLabel(.writeOnly) == CalendarAccessAdvice.advice(.writeOnly, kind: .calendars).status)
        #expect(PermissionKind.camera.buttonTitle(.denied) == "Open System Settings")
        #expect(PermissionKind.camera.buttonTitle(.notDetermined) == "Allow\u{2026}")
        for kind in PermissionKind.allCases {
            for status in [PermissionStatus.granted, .denied, .notDetermined, .appNotRunning, .appNotInstalled, .unknown, .writeOnly, .restricted] {
                let words = kind.statusLabel(status) + (kind.buttonTitle(status) ?? "")
                #expect(!words.contains("'") && !words.contains("\u{2014}"), "\(kind) \(status): \(words)")
            }
        }
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

    @Test func automationGateAsksAgainWhenTheUserPressesAControl() {
        var gate = AutomationGate()
        func check(_ t: AutomationGate.Trigger) -> Bool { gate.shouldCheck(t) }
        // Never asked (the system bridge was doing the work): a press asks.
        #expect(check(.control))
        gate.record(.appNotRunning)
        // Asked while the player was closed: a press once it's open asks again, as does it opening.
        #expect(!check(.firstUse))
        #expect(check(.control))
        gate.record(.notDetermined)
        #expect(check(.appActivated))
        gate.record(.denied)
        // A refusal is only changed by the user, so presses don't ask again.
        #expect(!check(.control))
    }

    @Test func automationGateKeepsAnAnswerWhenThePlayerIsClosed() {
        var gate = AutomationGate()
        func answer(_ s: PermissionStatus) -> Bool { gate.record(s) }
        #expect(answer(.granted))
        // The Permissions pane checks while the player may be closed: that says nothing about
        // the permission, so scripting stays allowed once the player is back.
        for status in [PermissionStatus.appNotRunning, .appNotInstalled, .unknown] {
            #expect(!answer(status))
            #expect(gate.allowsEvents)
            #expect(gate.status == .granted)
        }
        // A real answer still replaces it (taken away, or reset with tccutil).
        #expect(!answer(.notDetermined))
        #expect(!gate.allowsEvents)
        #expect(!answer(.appNotRunning))
        #expect(gate.status == .notDetermined)
        // With no answer yet, "not running" is kept, so the next open or press asks again.
        var fresh = AutomationGate()
        fresh.record(.appNotRunning)
        #expect(fresh.status == .appNotRunning)
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

    /// Live Activities reach the menu bar from macOS 26 on: before that, showing them is no
    /// reason to grant Accessibility, and Casement doesn't look for them.
    @Test func liveActivitiesNeedMacOS26() {
        #expect(!MenuBarLiveActivities.isSupported(osMajor: 14))
        #expect(!MenuBarLiveActivities.isSupported(osMajor: 15))
        #expect(MenuBarLiveActivities.isSupported(osMajor: 26))
        #expect(MenuBarLiveActivities.isSupported(osMajor: 27))
        let s = CasementSettings()
        #expect(s.mirrorMenuBarActivities)
        let old = PermissionKind.accessibility.uses(s, osMajor: 15).map(\.feature)
        #expect(!old.contains("Show Live Activities"))
        #expect(old.count == 4)
        #expect(PermissionKind.accessibility.uses(s, osMajor: 26).map(\.feature).contains("Show Live Activities"))
    }

    /// The menu bar's layout is followed while either use needs it: showing Live Activities, or
    /// fitting the closed island to the menu bar with Live Activities off. Never in the
    /// background session, on a macOS without MenuBarAgent, or without Accessibility.
    @Test func theMenuBarIsFollowedForEitherUse() {
        func watch(_ show: Bool, _ fit: Bool, inFront: Bool = true, supported: Bool = true, trusted: Bool = true) -> MenuBarLiveActivities.Watch {
            MenuBarLiveActivities.watch(showActivities: show, fitsMenuBar: fit, inFront: inFront, supported: supported, trusted: trusted)
        }
        #expect(watch(true, true) == .mirror)
        #expect(watch(true, false) == .mirror)
        // Live Activities off, "Fit the menu bar": the layout only, nothing read.
        #expect(watch(false, true) == .layout)
        // "Always full width" with Live Activities off: nothing follows the menu bar.
        #expect(watch(false, false) == .off)
        #expect(watch(true, true, inFront: false) == .off)
        #expect(watch(false, true, supported: false) == .off)
        #expect(watch(false, true, trusted: false) == .off)
        // "Fit the menu bar" is the default, and Accessibility already lists it as a use.
        let s = CasementSettings()
        #expect(s.closedLayout == .auto)
        #expect(PermissionKind.accessibility.uses(s, osMajor: 26).contains { $0.feature == "Fit the closed island between menu bar icons" && $0.isOn })
    }

    @Test func usesFollowTheSettings() {
        var s = CasementSettings()
        s.replaceSystemHUD = false
        s.notificationMirroring = true
        s.mirrorMenuBarActivities = false
        s.closedLayout = .wings
        #expect(PermissionKind.accessibility.uses(s, osMajor: 26).map(\.isOn) == [false, true, false, false, false])
        // Typing emoji needs it only while the emoji page is on too.
        s.emojiTypes = true
        #expect(PermissionKind.accessibility.uses(s).last?.isOn == false)
        s.emojiEnabled = true
        #expect(PermissionKind.accessibility.uses(s).last?.isOn == true)
        s.emojiTypes = false
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
