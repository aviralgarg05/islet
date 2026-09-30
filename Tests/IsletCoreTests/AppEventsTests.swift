import Foundation
import Testing
@testable import IsletCore

@Suite struct CallDetectorTests {
    @Test func classifiesAppsAndBrowserHelpers() {
        #expect(CallDetector.classify("us.zoom.xos")?.app.name == "Zoom")
        #expect(CallDetector.classify("com.google.Chrome.helper")?.bundleID == "com.google.Chrome")
        #expect(CallDetector.classify("com.google.Chrome.helper")?.app.isBrowser == true)
        #expect(CallDetector.classify("com.brave.Browser.helper.renderer")?.app.name == "Brave")
        #expect(CallDetector.classify("com.apple.VoiceMemos") == nil)
    }

    @Test func lifecycleWithLiveTimer() {
        var d = CallDetector()
        let start = d.update(micUsers: ["us.zoom.xos", "com.apple.VoiceMemos"], cameraOn: true, now: t0)
        guard case .started(let s) = start.first, start.count == 1 else { Issue.record("expected one start: \(start)"); return }
        #expect(s.title == "Zoom")
        #expect(s.subtitle == "Video call")
        #expect(s.icon == .symbol("video.fill"))
        #expect(s.startedAt == t0)
        #expect(s.priority == .high)
        #expect(s.sneak == true)
        // Still on the call: updated, same start time, no second sneak.
        let later = d.update(micUsers: ["us.zoom.xos"], cameraOn: false, now: t0.addingTimeInterval(60))
        guard case .updated(let u) = later.first else { Issue.record("expected update"); return }
        #expect(u.startedAt == t0)
        #expect(u.sneak == false)
        #expect(u.subtitle == "Call")
        // Hang up.
        let ended = d.update(micUsers: [], cameraOn: false, now: t0.addingTimeInterval(90))
        #expect(ended == [.ended(id: "call-us.zoom.xos")])
        #expect(d.active.isEmpty)
    }

    @Test func browserCallTitle() {
        var d = CallDetector()
        let c = d.update(micUsers: ["com.google.Chrome.helper"], cameraOn: false, now: t0)
        if case .started(let s) = c.first { #expect(s.title == "Call in Chrome") } else { Issue.record("expected start") }
    }

    @Test func specIsAcceptedAndCountsUp() throws {
        var d = CallDetector()
        var c = ActivityCenter()
        for change in d.update(micUsers: ["com.apple.FaceTime"], cameraOn: false, now: t0) {
            if case .started(let s) = change { try c.apply(s, now: t0) }
        }
        #expect(c.activities.values.first?.trailingText(now: t0.addingTimeInterval(125)) == "2:05")
    }
}

@Suite struct NotificationParserTests {
    let apps = ["Messages": "com.apple.MobileSMS", "Slack": "com.tinyspeck.slackmacgap", "Calendar": "com.apple.iCal"]

    @Test func appNameFirst() {
        let n = NotificationParser.parse(texts: ["Messages", "now", "Alice", "See you at 7?"], description: nil, knownApps: apps)
        #expect(n?.appName == "Messages")
        #expect(n?.bundleID == "com.apple.MobileSMS")
        #expect(n?.title == "Alice")
        #expect(n?.body == "See you at 7?")
    }

    @Test func titleSubtitleBody() {
        let n = NotificationParser.parse(texts: ["Slack", "#eng", "Priya", "Deploy is green", "Reply"], description: nil, knownApps: apps)
        #expect(n?.title == "#eng")
        #expect(n?.subtitle == "Priya")
        #expect(n?.body == "Deploy is green")
    }

    @Test func fallsBackToDescription() {
        let n = NotificationParser.parse(texts: [], description: "Calendar, Standup, in 5 minutes", knownApps: apps)
        #expect(n?.appName == "Calendar")
        #expect(n?.title == "Standup")
        #expect(n?.body == "in 5 minutes")
    }

    @Test func unknownAppStillParses() {
        let n = NotificationParser.parse(texts: ["Build finished", "All green", "2m ago"], description: nil, knownApps: apps)
        #expect(n?.appName == nil)
        #expect(n?.title == "Build finished")
        #expect(n?.body == "All green")
        #expect(NotificationParser.parse(texts: ["Close", "now"], description: nil, knownApps: apps) == nil)
    }

    @Test func timestamps() {
        for s in ["now", "5m ago", "11:42", "9:05 PM", "3 min", "Yesterday"] { #expect(NotificationParser.isTimestamp(s), "\(s)") }
        #expect(!NotificationParser.isTimestamp("Alice"))
    }

    @Test func activityUsesRulesAndStableIDs() {
        let n = MirroredNotification(appName: "Slack", bundleID: "com.tinyspeck.slackmacgap", title: "#eng", subtitle: "Priya", body: "Deploy is green")
        let a = n.activity(rule: AppRule(bundleID: "com.tinyspeck.slackmacgap", tint: "purple", priority: .high))
        #expect(a.title == "Slack: #eng")
        #expect(a.subtitle == "Priya · Deploy is green")
        #expect(a.icon == .app(bundleID: "com.tinyspeck.slackmacgap"))
        #expect(a.tint == "purple")
        #expect(a.priority == .high)
        #expect(a.id == n.activity(rule: nil).id)
        #expect(ActivityCenter.isValidID(a.id!))
    }
}

@Suite struct DownloadTrackerTests {
    @Test func progressThenFinish() {
        var t = DownloadTracker()
        let e1 = t.scan(partials: [PartialDownload(fileName: "ubuntu.iso.download", bytes: 500_000_000, totalBytes: 2_000_000_000)], existing: [], now: t0)
        guard case .progress(let p) = e1.first else { Issue.record("expected progress"); return }
        #expect(p.title == "ubuntu.iso")
        #expect(p.progress == 0.25)
        #expect(p.trailing == "25%")
        #expect(p.sneak == true)
        let e2 = t.scan(partials: [PartialDownload(fileName: "ubuntu.iso.download", bytes: 1_000_000_000, totalBytes: 2_000_000_000)], existing: [], now: t0)
        if case .progress(let p2) = e2.first { #expect(p2.sneak == false) }
        let e3 = t.scan(partials: [], existing: ["ubuntu.iso"], now: t0)
        guard case .finished(let f, let name) = e3.first else { Issue.record("expected finish"); return }
        #expect(name == "ubuntu.iso")
        #expect(f.state == .success)
        #expect(f.id == p.id)
    }

    @Test func unknownTotalIsIndeterminate() {
        var t = DownloadTracker()
        let e = t.scan(partials: [PartialDownload(fileName: "video.mp4.crdownload", bytes: 12_300_000)], existing: [], now: t0)
        if case .progress(let p) = e.first {
            #expect(p.progress == -1)
            #expect(p.trailing == "12 MB")
        } else { Issue.record("expected progress") }
    }

    @Test func cancelledDownloadVanishes() {
        var t = DownloadTracker()
        _ = t.scan(partials: [PartialDownload(fileName: "a.zip.part", bytes: 10)], existing: [], now: t0)
        let e = t.scan(partials: [], existing: [], now: t0)
        #expect(e == [.vanished(id: DownloadTracker.activityID("a.zip"))])
        #expect(PartialDownload.isPartial("x.crdownload"))
        #expect(!PartialDownload.isPartial("x.zip"))
    }
}

@Suite struct FocusAndAITests {
    @Test func focusPill() {
        let on = FocusPill.activity(name: "Work", on: true)
        #expect(on.icon == .symbol("briefcase.fill"))
        #expect(on.trailing == "On")
        #expect(FocusPill.activity(name: "Sleep", on: true).icon == .symbol("bed.double.fill"))
        #expect(FocusPill.activity(name: "Work", on: false).trailing == "Off")
    }

    @Test func focusURL() throws {
        #expect(try URLCommand.parse(URL(string: "islet://focus?name=Work&state=on")!) == .focus(name: "Work", on: true))
        #expect(try URLCommand.parse(URL(string: "islet://focus?name=Work&state=off")!) == .focus(name: "Work", on: false))
    }

    @Test func symbolSanitizer() {
        #expect(AISanitizer.symbolName(from: "car.fill") == "car.fill")
        #expect(AISanitizer.symbolName(from: " `car.fill`. ") == "car.fill")
        #expect(AISanitizer.symbolName(from: "SF Symbol: airplane") == "airplane")
        #expect(AISanitizer.symbolName(from: "car.fill because it is a ride") == "car.fill")
        #expect(AISanitizer.symbolName(from: "I'm not sure") == nil)
        #expect(AISanitizer.symbolName(from: "") == nil)
    }

    @Test func summarySanitizer() {
        #expect(AISanitizer.summary(from: "\"Driver arrives in 3 min\"\n") == "Driver arrives in 3 min")
        #expect(AISanitizer.summary(from: String(repeating: "a", count: 200))!.count == 90)
        #expect(AISanitizer.summary(from: "   ") == nil)
    }
}

@Suite struct LANTests {
    @Test func rateLimiter() {
        var r = RateLimiter(limit: 3, window: 10)
        let results = [
            r.allow("a", now: t0), r.allow("a", now: t0), r.allow("a", now: t0),
            r.allow("a", now: t0.addingTimeInterval(1)),   // 4th within the window: refused
            r.allow("b", now: t0.addingTimeInterval(1)),   // other clients unaffected
            r.allow("a", now: t0.addingTimeInterval(11)),  // window slid past
        ]
        #expect(results == [true, true, true, false, true, true])
    }

    @Test func remoteRouterAcceptsLANHostButStillNeedsToken() async {
        let b = FakeBackend(now: t0)
        let lan = APIRouter(token: "tok", version: "t", backend: b, allowRemoteHosts: true, clock: { t0 })
        func req(_ headers: [String: String], body: String = #"{"name":"Work","on":true}"#) -> HTTPRequest {
            HTTPRequest(method: "POST", path: "/v1/focus", headers: headers, body: Data(body.utf8))
        }
        #expect(await lan.handle(req(["Host": "aviral-mbp.local:47832", "Authorization": "Bearer tok"])).status == 201)
        #expect(await lan.handle(req(["Host": "aviral-mbp.local:47832"])).status == 401)
        #expect(await lan.handle(req(["Host": "x", "Authorization": "Bearer tok", "Origin": "https://evil.example"])).status == 403)
        let local = APIRouter(token: "tok", version: "t", backend: b, clock: { t0 })
        #expect(await local.handle(req(["Host": "aviral-mbp.local:47832", "Authorization": "Bearer tok"])).status == 403)
    }
}

@Suite struct ActivityKitParityTests {
    @Test func stepsDriveProgressAndTrailing() throws {
        var c = ActivityCenter()
        let a = try c.apply(ActivitySpec(id: "plan", title: "Agent plan", steps: 5, step: 2), now: t0)
        #expect(a.clampedProgress == 0.4)
        #expect(a.trailingText(now: t0) == "2/5")
        let b = try c.apply(ActivitySpec(id: "plan", step: 9), now: t0)
        #expect(b.clampedProgress == 1)
        #expect(b.trailingText(now: t0) == "5/5")
    }

    @Test func relevanceAndStalenessOrder() throws {
        var c = ActivityCenter()
        try c.apply(ActivitySpec(id: "a", title: "a", relevance: 10, sneak: false), now: t0)
        try c.apply(ActivitySpec(id: "b", title: "b", relevance: 90, sneak: false), now: t0)
        try c.apply(ActivitySpec(id: "c", title: "c", staleAt: t0.addingTimeInterval(5), relevance: 200, sneak: false), now: t0)
        #expect(c.ordered(now: t0).map(\.id) == ["c", "b", "a"])
        #expect(c.activities["c"]?.relevance == 100)
        // Once stale, it drops below fresh ones.
        #expect(c.ordered(now: t0.addingTimeInterval(6)).map(\.id) == ["b", "a", "c"])
        #expect(c.nextDeadline(now: t0) == t0.addingTimeInterval(5))
    }

    @Test func urlRoundTripsThroughJSON() throws {
        let spec = try APIJSON.decoder.decode(ActivitySpec.self, from: Data(#"{"title":"PR","url":"https://github.com/o/r/pull/1"}"#.utf8))
        var c = ActivityCenter()
        #expect(try c.apply(spec, now: t0).url == URL(string: "https://github.com/o/r/pull/1"))
    }

    @Test func lowPowerModeEvents() {
        var d = BatteryEventDetector()
        _ = d.ingest(BatteryState(level: 50, isCharging: false, isPluggedIn: false), now: t0)
        let on = d.ingest(BatteryState(level: 50, isCharging: false, isPluggedIn: false, lowPowerMode: true), now: t0)
        let off = d.ingest(BatteryState(level: 50, isCharging: false, isPluggedIn: false, lowPowerMode: false), now: t0)
        #expect(on?.kind == .lowPowerOn)
        #expect(off?.kind == .lowPowerOff)
    }
}

@Suite struct HotkeyTests {
    @Test func parsesCommonShortcuts() {
        let h = Hotkey.parse("ctrl+option+i")
        #expect(h?.keyCode == 34)
        #expect(h?.modifiers == [.control, .option])
        #expect(h?.label == "⌃⌥I")
        #expect(Hotkey.parse("Cmd + Shift + Space")?.modifiers == [.command, .shift])
        #expect(Hotkey.parse("⌥⌘k")?.keyCode == 40)
        #expect(Hotkey.parse("f5")?.modifiers == [])
    }

    @Test func rejectsUnsafeOrUnknown() {
        #expect(Hotkey.parse("i") == nil)          // would swallow typing
        #expect(Hotkey.parse("shift+a") == nil)    // same
        #expect(Hotkey.parse("ctrl+banana") == nil)
        #expect(Hotkey.parse("hyper+i") == nil)
        #expect(Hotkey.parse("") == nil)
    }
}

@Suite struct CalendarAndRemindersTests {
    var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    let now = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15 08:00 UTC

    @Test func restOfTodaySkipsEndedAndTomorrow() {
        let items = [
            AgendaItem(id: "done", title: "Done", start: now.addingTimeInterval(-7200), end: now.addingTimeInterval(-3600)),
            AgendaItem(id: "now", title: "Now", start: now.addingTimeInterval(-600), end: now.addingTimeInterval(1200)),
            AgendaItem(id: "later", title: "Later", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(5400)),
            AgendaItem(id: "tomorrow", title: "Tomorrow", start: now.addingTimeInterval(86400), end: now.addingTimeInterval(90000)),
            AgendaItem(id: "holiday", title: "Holiday", start: cal.startOfDay(for: now), end: cal.startOfDay(for: now).addingTimeInterval(86400), isAllDay: true),
        ]
        let r = Agenda.restOfToday(items, now: now, calendar: cal)
        #expect(r.timed.map(\.id) == ["now", "later"])
        #expect(r.allDay.map(\.id) == ["holiday"])
    }

    @Test func hiddenCalendars() {
        let items = [AgendaItem(id: "a", title: "a", start: now, end: now, calendarID: "work"),
                     AgendaItem(id: "b", title: "b", start: now, end: now, calendarID: "home")]
        #expect(Agenda.visible(items, hiding: ["work"]).map(\.id) == ["b"])
        #expect(Agenda.visible(items, hiding: []).count == 2)
    }

    @Test func remindersOrderAndOverdue() {
        let items = [
            ReminderItem(id: "later", title: "Later", due: now.addingTimeInterval(3600)),
            ReminderItem(id: "overdue", title: "Overdue", due: now.addingTimeInterval(-3600)),
            ReminderItem(id: "today", title: "Today", due: cal.startOfDay(for: now), isAllDay: true),
            ReminderItem(id: "nodate", title: "No date", due: nil),
            ReminderItem(id: "tomorrow", title: "Tomorrow", due: now.addingTimeInterval(86400 + 3600)),
        ]
        #expect(Reminders.dueSoon(items, now: now, calendar: cal).map(\.id) == ["overdue", "later", "today"])
        #expect(items[1].isOverdue(at: now, calendar: cal))
        #expect(!items[2].isOverdue(at: now, calendar: cal))
    }

    @Test func reminderAlertsOnlyForTimedDueNow() {
        #expect(Reminders.shouldAlert(ReminderItem(id: "a", title: "a", due: now.addingTimeInterval(-30)), now: now))
        #expect(!Reminders.shouldAlert(ReminderItem(id: "b", title: "b", due: now.addingTimeInterval(-300)), now: now))
        #expect(!Reminders.shouldAlert(ReminderItem(id: "c", title: "c", due: now, isAllDay: true), now: now))
        let spec = Reminders.activity(for: ReminderItem(id: "x-1", title: "Pay rent", due: now, listTitle: "Home", priority: 1))
        #expect(spec.priority == .high)
        #expect(spec.subtitle == "Reminder · Home")
        #expect(ActivityCenter.isValidID(spec.id!))
    }
}
