import Foundation
import Testing
@testable import IsletCore

/// Meeting reminders: from the lead time to the start, then until you join, dismiss it or it ends.
@Suite struct MeetingReminderTests {
    static let start = t0.addingTimeInterval(3600)
    static let zoom = URL(string: "https://acme.zoom.us/j/123456")!
    static let meet = URL(string: "https://meet.google.com/abc-defg-hij")!

    static func meeting(_ id: String = "standup", start: Date = start, minutes: Double = 30, link: URL? = zoom,
                        allDay: Bool = false, declined: Bool = false) -> AgendaItem {
        AgendaItem(id: id, title: "Standup", start: start, end: start.addingTimeInterval(minutes * 60), isAllDay: allDay,
                   calendarColor: "#0A84FF", meetingURL: link, isDeclined: declined)
    }

    let options = MeetingReminderOptions(lead: 10 * 60)
    let start = MeetingReminderTests.start

    func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    @Test func showsFromTheLeadTimeAndCountsDown() {
        let m = MeetingReminders()
        let items = [Self.meeting()]
        #expect(m.live(items, now: at(-10.5), options: options).isEmpty)
        let first = m.live(items, now: at(-10), options: options)
        #expect(first.map(\.phase) == [.soon])
        #expect(first[0].trailing(now: at(-10)) == "10 min")
        #expect(first[0].trailing(now: at(-9.5)) == "10 min")
        #expect(first[0].trailing(now: at(-9)) == "9 min")
        #expect(first[0].trailing(now: at(-0.2)) == "1 min")
        let started = m.live(items, now: at(0), options: options)
        #expect(started.map(\.phase) == [.now])
        #expect(started[0].trailing(now: at(0)) == "Now")
        // Off: nothing at all.
        #expect(m.live(items, now: at(-5), options: nil).isEmpty)
        #expect(m.nextDeadline(items, now: at(-5), options: nil) == nil)
    }

    @Test func wakesOnlyWhenSomethingChanges() {
        let m = MeetingReminders()
        let items = [Self.meeting()]
        #expect(m.nextDeadline(items, now: at(-60), options: options) == at(-10))
        // Each minute while it counts down, then the start, then the end.
        #expect(m.nextDeadline(items, now: at(-10), options: options) == at(-9))
        #expect(m.nextDeadline(items, now: at(-9.5), options: options) == at(-9))
        #expect(m.nextDeadline(items, now: at(-0.5), options: options) == at(0))
        #expect(m.nextDeadline(items, now: at(0), options: options) == at(30))
        #expect(m.nextDeadline(items, now: at(30), options: options) == nil)
    }

    @Test func staysUntilItEndsWhenKeptOtherwiseGoesAfterAFewMinutes() {
        let m = MeetingReminders()
        let items = [Self.meeting()]
        #expect(m.live(items, now: at(29.9), options: options).map(\.phase) == [.now])
        #expect(m.live(items, now: at(30), options: options).isEmpty)

        var brief = options
        brief.keepUntilJoined = false
        #expect(m.live(items, now: at(4.9), options: brief).map(\.phase) == [.now])
        #expect(m.live(items, now: at(5), options: brief).isEmpty)
        #expect(m.nextDeadline(items, now: at(1), options: brief) == at(5))
        // A meeting shorter than that goes when it ends.
        #expect(m.live([Self.meeting(minutes: 3)], now: at(3), options: brief).isEmpty)
    }

    @Test func joinedOrDismissedGoesAndStaysGone() {
        let items = [Self.meeting()]
        var joined = MeetingReminders()
        joined.join(items[0])
        #expect(joined.live(items, now: at(-5), options: options).isEmpty)
        #expect(joined.live(items, now: at(5), options: options).isEmpty)
        #expect(joined.nextDeadline(items, now: at(-5), options: options) == nil)
        #expect(joined.outcome(of: items[0]) == .joined)

        var dismissed = MeetingReminders()
        dismissed.dismiss(items[0])
        #expect(dismissed.live(items, now: at(1), options: options).isEmpty)
        #expect(dismissed.outcome(of: items[0]) == .dismissed)
    }

    @Test func allDayDeclinedAndLinklessMeetingsNeverShow() {
        let m = MeetingReminders()
        #expect(m.live([Self.meeting(allDay: true)], now: at(-5), options: options).isEmpty)
        #expect(m.live([Self.meeting(declined: true)], now: at(-5), options: options).isEmpty)
        #expect(m.live([Self.meeting(link: nil)], now: at(-5), options: options).isEmpty)
        var any = options
        any.onlyWithLink = false
        let plain = m.live([Self.meeting(link: nil)], now: at(-5), options: any)
        #expect(plain.count == 1 && plain[0].app == nil)
        #expect(m.live([Self.meeting(declined: true)], now: at(-5), options: any).isEmpty)
    }

    @Test func eachOccurrenceOfARepeatingMeetingIsItsOwn() {
        let today = Self.meeting("weekly")
        let nextWeek = Self.meeting("weekly", start: start.addingTimeInterval(7 * 86_400))
        #expect(MeetingReminders.key(for: today) != MeetingReminders.key(for: nextWeek))
        var m = MeetingReminders()
        m.dismiss(today)
        #expect(m.live([today, nextWeek], now: at(-5), options: options).isEmpty)
        let later = m.live([today, nextWeek], now: nextWeek.start.addingTimeInterval(-300), options: options)
        #expect(later.map(\.key) == [MeetingReminders.key(for: nextWeek)])
        // The same occurrence listed twice shows once.
        #expect(m.live([nextWeek, nextWeek], now: nextWeek.start, options: options).count == 1)
    }

    @Test func twoOverlappingMeetingsBothShowEarliestFirst() {
        let first = Self.meeting("a", minutes: 60)
        let second = Self.meeting("b", start: at(30), minutes: 30, link: Self.meet)
        let m = MeetingReminders()
        #expect(m.live([second, first], now: at(15), options: options).map(\.item.id) == ["a"])
        let both = m.live([second, first], now: at(25), options: options)
        #expect(both.map(\.item.id) == ["a", "b"])
        #expect(both.map(\.phase) == [.now, .soon])
        var joinedFirst = m
        joinedFirst.join(first)
        #expect(joinedFirst.live([second, first], now: at(25), options: options).map(\.item.id) == ["b"])
    }

    @Test func opensTheIslandOnceWhenItShowsAndOnceAtTheStart() throws {
        var m = MeetingReminders()
        let items = [Self.meeting()]
        let soon = m.live(items, now: at(-10), options: options)
        #expect(m.announce(soon) == [soon[0].key])
        #expect(m.announce(m.live(items, now: at(-9), options: options)).isEmpty)
        let started = m.live(items, now: at(0), options: options)
        #expect(m.announce(started) == [started[0].key])
        #expect(m.announce(m.live(items, now: at(1), options: options)).isEmpty)
        // Not again after a relaunch.
        let data = try MeetingReminders.coder.0.encode(m)
        var reopened = try MeetingReminders.coder.1.decode(MeetingReminders.self, from: data)
        #expect(reopened.announce(reopened.live(items, now: at(2), options: options)).isEmpty)
    }

    @Test func aMacAsleepThroughTheStartCatchesUpOnWake() {
        var m = MeetingReminders()
        let items = [Self.meeting()]
        _ = m.announce(m.live(items, now: at(-9), options: options))
        // Asleep from 9 minutes before until 20 minutes after: on wake it is urgent, and says so once.
        let wake = m.live(items, now: at(20), options: options)
        #expect(wake.map(\.phase) == [.now])
        #expect(m.announce(wake) == [wake[0].key])
        // Asleep through the whole meeting: nothing to show on wake.
        #expect(m.live(items, now: at(31), options: options).isEmpty)
        // Asleep through the start without "Keep reminding": gone a few minutes after it.
        var brief = options
        brief.keepUntilJoined = false
        #expect(MeetingReminders().live(items, now: at(20), options: brief).isEmpty)
    }

    @Test func aMeetingJustAfterMidnightShowsBeforeIt() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/London")!
        let midnight = cal.startOfDay(for: t0.addingTimeInterval(86_400))
        let early = Self.meeting("early", start: midnight.addingTimeInterval(5 * 60))
        let lateNight = midnight.addingTimeInterval(-4 * 60)
        let live = MeetingReminders().live([early], now: lateNight, options: options)
        #expect(live.map(\.phase) == [.soon])
        #expect(live[0].trailing(now: lateNight) == "9 min")
    }

    @Test func savedRecordsSurviveARelaunchAndGoADayAfterTheMeeting() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("islet-meetings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("meetings.json")
        let items = [Self.meeting()]
        var m = MeetingReminders()
        m.join(items[0])
        try m.save(to: url)
        let restored = try #require(MeetingReminders.start(from: url).value)
        #expect(restored == m)
        #expect(restored.live(items, now: at(5), options: options).isEmpty)

        var pruned = restored
        let early = pruned.forget(before: at(30 + 23 * 60))
        #expect(!early)
        let late = pruned.forget(before: at(30 + 24 * 60 + 1))
        #expect(late)
        #expect(pruned.records.isEmpty)

        // A file that doesn't parse is set aside, and reminders start afresh.
        try Data("{nope".utf8).write(to: url)
        let broken = MeetingReminders.start(from: url)
        #expect(broken.value == nil && broken.canSave)
        #expect(broken.setAside != nil)
    }

    @Test func aCallInTheMeetingsAppCountsAsJoining() {
        let zoom = Self.meeting("z")
        let meet = Self.meeting("m", link: Self.meet)
        let teams = Self.meeting("t", link: URL(string: "https://teams.microsoft.com/l/meetup-join/abc")!)
        let live = MeetingReminders().live([zoom, meet, teams], now: at(-3), options: options)
        #expect(live.count == 3)
        func joined(_ bundle: String, browser: Bool = false, since: Double) -> [String] {
            MeetingReminders.joinedByCalls([OngoingCall(bundleID: bundle, isBrowser: browser, since: at(since))], live: live).map(\.item.id)
        }
        #expect(joined("us.zoom.xos", since: -3) == ["z"])
        #expect(joined("com.google.Chrome", browser: true, since: -3) == ["m"])
        #expect(joined("com.microsoft.teams2", since: -3) == ["t"])
        // Another app's call joins nothing.
        #expect(joined("com.tinyspeck.slackmacgap", since: -3).isEmpty)
        // Several calls at once: each joins its own.
        let both = MeetingReminders.joinedByCalls([OngoingCall(bundleID: "us.zoom.xos", isBrowser: false, since: at(-2)),
                                                   OngoingCall(bundleID: "com.google.Chrome", isBrowser: true, since: at(-1))], live: live)
        #expect(both.map(\.item.id) == ["m", "z"] || both.map(\.item.id) == ["z", "m"])
    }

    @Test func aCallJoinedEarlyStillCountsButOneLeftOverFromAnEarlierMeetingDoesnt() {
        let zoom = Self.meeting("z")
        // Joined from the calendar 9 minutes early, before the urgent "Now": the reminder
        // that appeared at -10 goes when Islet next looks, and never glows at you.
        let soon = MeetingReminders().live([zoom], now: at(-8), options: options)
        let early = OngoingCall(bundleID: "us.zoom.xos", isBrowser: false, since: at(-9))
        #expect(MeetingReminders.joinedByCalls([early], live: soon).map(\.item.id) == ["z"])
        let started = MeetingReminders().live([zoom], now: at(1), options: options)
        #expect(MeetingReminders.joinedByCalls([early], live: started).map(\.item.id) == ["z"])
        // Joined before the reminder even showed (a 5 minute lead): still counts once it shows.
        var short = options
        short.lead = 5 * 60
        let late = MeetingReminders().live([zoom], now: at(-5), options: short)
        #expect(MeetingReminders.joinedByCalls([early], live: late).map(\.item.id) == ["z"])
        // A Zoom call from the meeting before, running on since half an hour earlier, doesn't:
        // that reminder is for the next meeting, which you haven't joined.
        let leftOver = OngoingCall(bundleID: "us.zoom.xos", isBrowser: false, since: at(-30))
        #expect(MeetingReminders.joinedByCalls([leftOver], live: started).isEmpty)
        #expect(MeetingReminders.joinedByCalls([OngoingCall(bundleID: "us.zoom.xos", isBrowser: false, since: at(-10.5))], live: soon).isEmpty)
        // A meeting without a link has no app to join it in.
        var any = options
        any.onlyWithLink = false
        let plain = MeetingReminders().live([Self.meeting("p", link: nil)], now: at(1), options: any)
        #expect(MeetingReminders.joinedByCalls([OngoingCall(bundleID: "com.google.Chrome", isBrowser: true, since: at(0))], live: plain).isEmpty)
    }

    @Test func callDetectionReportsEachCallWithItsApp() {
        var calls = CallDetector()
        _ = calls.update(micUsers: ["us.zoom.xos", "com.google.Chrome.helper", "com.example.dictation"], cameraOn: false, now: at(-4))
        #expect(calls.ongoing == [OngoingCall(bundleID: "com.google.Chrome", isBrowser: true, since: at(-4)),
                                  OngoingCall(bundleID: "us.zoom.xos", isBrowser: false, since: at(-4))])
        // A call keeps the moment it began.
        _ = calls.update(micUsers: ["us.zoom.xos"], cameraOn: true, now: at(2))
        #expect(calls.ongoing == [OngoingCall(bundleID: "us.zoom.xos", isBrowser: false, since: at(-4))])
    }

    @Test func theActivityCountsDownThenNeedsYou() throws {
        let item = Self.meeting()
        let soon = try #require(MeetingReminders().live([item], now: at(-9), options: options).first)
        let spec = MeetingReminders.activity(for: soon, now: at(-9), icon: .app(bundleID: "us.zoom.xos"), sneak: true) { _ in "10:00" }
        #expect(spec.id == soon.id && spec.id!.hasPrefix(MeetingReminders.idPrefix))
        #expect(spec.source == MeetingReminders.source)
        #expect(spec.title == "Standup")
        #expect(spec.subtitle == "At 10:00 · Zoom")
        #expect(spec.trailing == "9 min")
        #expect(spec.state == .info && spec.priority == .high && spec.sneak == true)
        #expect(spec.actions == [ActivityAction(title: "Join", url: Self.zoom)])
        // No link to open on a click: the click opens the island on the meeting.
        #expect(spec.url == nil)
        #expect(spec.tint == "#0A84FF")

        let now = try #require(MeetingReminders().live([item], now: at(1), options: options).first)
        let urgent = MeetingReminders.activity(for: now, now: at(1), icon: .symbol("video.fill"), sneak: false) { _ in "10:30" }
        #expect(urgent.state == .waiting && urgent.trailing == "Now" && urgent.subtitle == "Now · until 10:30")
        // High, not critical: a full screen app or an app rule still hides it.
        #expect(urgent.priority == .high)

        var center = ActivityCenter()
        let a = try center.apply(urgent, now: at(1))
        #expect(MeetingReminders.isReminder(a))
        #expect(!MeetingReminders.isReminder(try center.apply(ActivitySpec(id: "meeting-notes", source: "api", title: "Notes"), now: at(1))))
    }

    @Test func aNarrowWingStillSaysNow() {
        // The started meeting's "Now" stays a word in the narrowest wing, like "9 min" does.
        #expect(NarrowValue.glyph(for: "Now", state: .waiting) == nil)
        #expect(NarrowValue.glyph(for: "9 min", state: .info) == nil)
        // Longer status words still become a glyph there, and so does a value with no word.
        #expect(NarrowValue.glyph(for: "Waiting", state: .waiting) == "exclamationmark.bubble.fill")
        #expect(NarrowValue.glyph(for: "Done", state: .success) == "checkmark.circle.fill")
        #expect(NarrowValue.glyph(for: "", state: .running) == "ellipsis")
        #expect(NarrowValue.glyph(for: "", state: .info) == nil)
        #expect(NarrowValue.glyph(for: "Stopped", state: .info) == "info.circle.fill")
    }

    @Test func iconIsTheCallAppWhenInstalled() throws {
        let zoom = try #require(MeetingReminders().live([Self.meeting()], now: at(-1), options: options).first)
        #expect(MeetingReminders.icon(for: zoom, installed: { $0 == "us.zoom.xos" }) == .app(bundleID: "us.zoom.xos"))
        #expect(MeetingReminders.icon(for: zoom, installed: { _ in false }) == .symbol("video.fill"))
        var any = options
        any.onlyWithLink = false
        let plain = try #require(MeetingReminders().live([Self.meeting(link: nil)], now: at(-1), options: any).first)
        #expect(MeetingReminders.icon(for: plain, installed: { _ in true }) == .symbol("calendar"))
    }

    @Test(arguments: [
        ("https://acme.zoom.us/j/1", MeetingApp.zoom),
        ("zoommtg://zoom.us/join?confno=1", .zoom),
        ("https://meet.google.com/abc", .meet),
        ("https://teams.microsoft.com/l/meetup-join/x", .teams),
        ("msteams://teams.microsoft.com/l/x", .teams),
        ("https://acme.webex.com/meet/x", .webex),
        ("https://facetime.apple.com/join#v=1", .facetime),
        ("https://whereby.com/room", .other),
        ("https://zoom.us.example.com/j/1", .other),
    ])
    func callAppFromItsLink(link: String, app: MeetingApp) {
        #expect(MeetingApp(url: URL(string: link)!) == app)
    }

    @Test func optionsFollowTheSettings() {
        var s = IsletSettings()
        #expect(s.meetingReminderMinutes == 10 && s.meetingRemindUntilJoined && s.meetingRemindersNeedLink)
        #expect(MeetingReminderOptions(s) == MeetingReminderOptions(lead: 600))
        s.meetingReminderMinutes = 0
        #expect(MeetingReminderOptions(s) == nil)
        s.meetingReminderMinutes = 30
        s.calendarEnabled = false
        #expect(MeetingReminderOptions(s) == nil)
        s.calendarEnabled = true
        s.meetingRemindUntilJoined = false
        s.meetingRemindersNeedLink = false
        #expect(MeetingReminderOptions(s) == MeetingReminderOptions(lead: 1800, keepUntilJoined: false, onlyWithLink: false))
    }

    @Test(arguments: [(10, 10), (0, 0), (-3, 0), (7, 5), (20, 15), (45, 30), (12, 10)])
    func aHandEditedLeadTimeBecomesTheNearestChoice(written: Int, kept: Int) {
        var s = IsletSettings()
        s.meetingReminderMinutes = written
        #expect(s.sanitized().meetingReminderMinutes == kept)
    }

    @Test func swipingUpDismissesOnlyWhatCanBeDismissed() {
        let s = IsletSettings()
        #expect(GestureMap.dismisses(.up, on: .compactActivity, dismissable: true, settings: s))
        #expect(GestureMap.dismisses(.up, on: .sneak, dismissable: true, settings: s))
        #expect(!GestureMap.dismisses(.up, on: .compactActivity, dismissable: false, settings: s))
        #expect(!GestureMap.dismisses(.down, on: .compactActivity, dismissable: true, settings: s))
        #expect(!GestureMap.dismisses(.up, on: .expanded(media: false), dismissable: true, settings: s))
        var off = s
        off.gesturesEnabled = false
        #expect(!GestureMap.dismisses(.up, on: .compactActivity, dismissable: true, settings: off))
    }
}

/// Calendar access that explains itself: each state in plain words, with the button that helps.
@Suite struct CalendarAccessTests {
    @Test func eachStateSaysWhatToDo() {
        let full = CalendarAccessAdvice.advice(.fullAccess, kind: .calendars)
        #expect(full.isAllowed && full.status == "Allowed" && full.button == nil)

        let ask = CalendarAccessAdvice.advice(.notDetermined, kind: .calendars)
        #expect(ask.action == .ask && ask.button == "Allow…")

        let settings = CalendarAccessAdvice.Action.openSettings(PermissionKind.calendars.settingsURL)
        for access in [CalendarAccess.denied, .restricted] {
            let a = CalendarAccessAdvice.advice(access, kind: .calendars)
            #expect(a.status == "Turned off in System Settings")
            #expect(a.action == settings && a.button == "Open System Settings")
            #expect(a.detail != nil)
        }
        let writeOnly = CalendarAccessAdvice.advice(.writeOnly, kind: .calendars)
        #expect(writeOnly.status == "Islet can only add events")
        #expect(writeOnly.detail?.contains("Full Access") == true)
        #expect(writeOnly.action == settings)

        // "Allow…" pressed and macOS said no without asking: System Settings, not another Allow.
        let refused = CalendarAccessAdvice.advice(.notDetermined, kind: .calendars, refused: true)
        #expect(refused.action == settings && refused.button == "Open System Settings")
    }

    @Test func remindersOpenTheirOwnPage() {
        let a = CalendarAccessAdvice.advice(.denied, kind: .reminders)
        #expect(a.action == .openSettings(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!))
        #expect(a.detail?.contains("Reminders") == true)
        #expect(PermissionKind.calendars.settingsURL.absoluteString.hasSuffix("?Privacy_Calendars"))
    }

    @Test func plainWordsWithoutDashes() {
        for access in CalendarAccess.allCases {
            for kind in [PermissionKind.calendars, .reminders] {
                for refused in [false, true] {
                    let a = CalendarAccessAdvice.advice(access, kind: kind, refused: refused)
                    for text in [a.status, a.detail ?? "", a.button ?? ""] {
                        #expect(!text.contains("—"), "\(text)")
                    }
                }
            }
        }
    }

    @Test func permissionsRowFollowsTheAccess() {
        #expect(PermissionStatus.calendar(.fullAccess) == .granted)
        #expect(PermissionStatus.calendar(.notDetermined) == .notDetermined)
        #expect(PermissionStatus.calendar(.notDetermined, refused: true) == .denied)
        #expect(PermissionStatus.calendar(.denied) == .denied)
        #expect(PermissionStatus.calendar(.writeOnly) == .writeOnly)
        #expect(PermissionStatus.calendar(.restricted) == .restricted)
        #expect(PermissionStatus.writeOnly.action == .openSettings)
        #expect(PermissionStatus.restricted.action == .openSettings)
        #expect(PermissionStatus.calendar(.notDetermined).action == .request)
    }

    @Test func stateEncodesEachAccessByName() throws {
        let status = CalendarStatus(events: .writeOnly, reminders: .notDetermined, upcoming: 3)
        let json = String(decoding: try JSONEncoder().encode(status), as: UTF8.self)
        #expect(json.contains(#""events":"writeOnly""#))
        #expect(json.contains(#""reminders":"notDetermined""#))
        #expect(json.contains(#""upcoming":3"#))
    }
}

/// The API says how the calendar is doing, never what is in it.
extension APIRouterTests {
    @Test func stateHasTheCalendarButNoMeetingTitles() async throws {
        let b = FakeBackend(now: t0)
        let item = MeetingReminderTests.meeting()
        let reminder = try #require(MeetingReminders().live([item], now: item.start, options: MeetingReminderOptions(lead: 600)).first)
        _ = try await b.applyActivity(MeetingReminders.activity(for: reminder, now: item.start, icon: .symbol("video.fill"), sneak: false) { _ in "10:00" })
        _ = try await b.applyActivity(ActivitySpec(id: "build", source: "ci", title: "Build"))
        await b.setCalendar(CalendarStatus(events: .fullAccess, reminders: .denied, upcoming: 2))
        let rt = router(b)

        let state = await rt.handle(request("GET", "/v1/state"))
        let decoded = try APIJSON.decoder.decode(StateSnapshot.self, from: state.body)
        #expect(decoded.calendar == CalendarStatus(events: .fullAccess, reminders: .denied, upcoming: 2))
        #expect(decoded.activities.map(\.id) == ["build"])
        let list = await rt.handle(request("GET", "/v1/activities"))
        #expect(try APIJSON.decoder.decode([Activity].self, from: list.body).map(\.id) == ["build"])
        for r in [state, list] {
            let text = String(decoding: r.body, as: UTF8.self)
            #expect(!text.contains("Standup") && !text.contains("zoom.us"))
        }
        // Also when Live Activities are shared with scripts.
        await b.share(true)
        let shared = await rt.handle(request("GET", "/v1/state"))
        #expect(!String(decoding: shared.body, as: UTF8.self).contains("Standup"))
    }

    @Test func scriptsCantChangeOrDismissAMeetingReminder() async throws {
        let b = FakeBackend(now: t0)
        let item = MeetingReminderTests.meeting()
        let reminder = try #require(MeetingReminders().live([item], now: item.start, options: MeetingReminderOptions(lead: 600)).first)
        _ = try await b.applyActivity(MeetingReminders.activity(for: reminder, now: item.start, icon: .symbol("video.fill"), sneak: false) { _ in "10:00" })
        // A script's own activity under the same source name.
        _ = try await b.applyActivity(ActivitySpec(id: "sync", source: "calendar", title: "Calendar synced"))
        let rt = router(b)

        // Clearing the source removes the script's own, never the reminder, and counts only its own.
        let cleared = await rt.handle(request("DELETE", "/v1/activities?source=calendar"))
        #expect(cleared.status == 200)
        #expect(String(decoding: cleared.body, as: UTF8.self).contains(#""removed":1"#))
        #expect(await b.listActivities().map(\.id) == [reminder.id])

        // By its id, it isn't there as far as a script can tell: not removed, not changed, and
        // the answer doesn't carry its title.
        let delete = await rt.handle(request("DELETE", "/v1/activities/\(reminder.id)"))
        #expect(delete.status == 404)
        for method in ["PUT", "PATCH", "POST"] {
            let put = await rt.handle(request(method, "/v1/activities/\(reminder.id)", body: #"{"source":"mine"}"#))
            #expect(put.status == 404)
            #expect(!String(decoding: put.body, as: UTF8.self).contains("Standup"))
        }
        let post = await rt.handle(request("POST", "/v1/activities", body: #"{"id":"\#(reminder.id)","title":"Mine"}"#))
        #expect(post.status == 404)
        let still = try #require(await b.listActivities().first { $0.id == reminder.id })
        #expect(still.title == "Standup" && still.source == MeetingReminders.source)

        // Other sources clear as before.
        _ = try await b.applyActivity(ActivitySpec(id: "build", source: "ci", title: "Build"))
        let ci = await rt.handle(request("DELETE", "/v1/activities?source=ci"))
        #expect(String(decoding: ci.body, as: UTF8.self).contains(#""removed":1"#))
    }
}
