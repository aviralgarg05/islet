import AppKit
import IsletCore
import IsletSystem
import SwiftUI

/// The open island: a quiet menu bar row, then one page. Pages are picked with the switcher
/// that floats under the island (`PageSwitcher`), so the row beside the notch stays almost empty.
struct ExpandedView: View {
    let model: AppModel
    let metrics: IslandMetrics
    var dropTargeted: Bool
    /// The stem-and-body shape: the menu bar beside the notch isn't the island's, so the row
    /// stays empty (the pin is in the page switcher's menu).
    var stemmed = false

    var body: some View {
        let layout = ExpandedLayout(metrics: metrics)
        VStack(spacing: 0) {
            Group {
                if stemmed { Color.clear } else { MenuBarRow(model: model, metrics: metrics) }
            }
            .frame(height: layout.row)
            page(layout.content)
                .frame(width: layout.content.width, height: layout.content.height, alignment: .topLeading)
                .padding(.top, ExpandedLayout.top)
        }
        .frame(width: metrics.expanded.width, height: metrics.expanded.height, alignment: .top)
    }

    @ViewBuilder
    private func page(_ size: CGSize) -> some View {
        switch model.tab {
        case .home: HomeTab(model: model, size: size)
        case .today: TodayTab(model: model)
        case .shelf: ShelfTab(model: model, dropTargeted: dropTargeted)
        case .widgets: WidgetsTab(model: model)
        case .clipboard: ClipboardTab(model: model)
        case .stats: StatsTab(model: model)
        case .mirror: MirrorTab(model: model, size: size)
        case .teleprompter: TeleprompterTab(model: model, size: size)
        case .stocks: StocksTab(model: model, size: size)
        case .sales: SalesTab(model: model, size: size)
        case .shortcuts: ShortcutsTab(model: model)
        case .weather: WeatherTab(model: model)
        case .ask: AskView(model: model)
        }
    }
}

/// The row level with the hardware notch. It holds at most two quiet things: what the Mac is
/// doing on the left (camera, microphone, keep awake), and the pin on the right.
struct MenuBarRow: View {
    let model: AppModel
    let metrics: IslandMetrics

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: Space.s) {
                if model.cameraInUse { privacyDot(.green, help: "Camera in use") }
                if model.micInUse { privacyDot(.orange, help: "Microphone in use") }
                if model.controls.awake != nil { KeepAwakeButton(model: model) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: metrics.notch.width + Space.m)

            HStack(spacing: Space.xs) {
                if let b = model.battery, b.level <= model.settings.batteryLowThreshold, !b.isPluggedIn {
                    HStack(spacing: Space.xs) {
                        Text("\(b.level)%").textStyle(.caption, emphasized: true, numeric: true)
                        Image(systemName: BatteryGlyph.symbol(b)).font(.system(size: 12))
                    }
                    .foregroundStyle(Color.red)
                    .help("Low battery")
                }
                IconButton(symbol: model.pinned ? "pin.fill" : "pin", help: model.pinned ? "Stop keeping open" : "Keep open",
                           size: 24, glyph: 11, ink: model.pinned ? Ink.primary : Ink.tertiary) {
                    model.pinned.toggle()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        // Glyph edges line up with the content below (the buttons carry 6–7 pt of hit area).
        .padding(.horizontal, ExpandedLayout.inset - 6)
    }

    private func privacyDot(_ color: Color, help: String) -> some View {
        Circle().fill(color).frame(width: 6, height: 6).help(help).accessibilityLabel(help)
    }
}

// MARK: - Home

/// What Home shows: one primary thing, and the rest as a quiet column of glances.
@MainActor
struct HomePlan {
    enum Primary {
        case ringing(TimerItem)
        /// A meeting reminder on show: it leads, with its Join button, until it goes.
        case meeting(MeetingReminder)
        case media(NowPlaying)
        case timer(TimerItem)
        case stopwatch(Stopwatch)
        case activity(Activity)
        case clock

        /// Now Playing uses the whole column; the others are shorter than it.
        var fills: Bool {
            if case .media = self { return true }
            return false
        }
    }

    enum Glance: Identifiable {
        case timer(TimerItem)
        case stopwatch(Stopwatch)
        case event(AgendaItem)
        case activity(Activity)
        case usage(AgentUsage)
        /// OpenRouter, Copilot or Ollama (Settings → Coding agents → Usage limits).
        case toolUsage(ToolUsageCard)
        /// Claude before its figures arrive: an offer to show them, or waiting for them.
        case claudeHint(ClaudeUsageHint)
        /// The calendar is on but macOS doesn't let Islet read it (turned off in System
        /// Settings, restricted, or "Add events only"): what is wrong and the button that helps.
        case calendarAccess(CalendarAccessAdvice)

        var id: String {
            switch self {
            case .timer(let t): return "timer-\(t.id)"
            case .stopwatch: return "stopwatch"
            case .event(let e): return "event-\(e.id)"
            case .activity(let a): return "activity-\(a.id)"
            case .usage(let u): return "usage-\(u.id)"
            case .toolUsage(let c): return "tool-usage-\(c.id)"
            case .claudeHint: return "usage-claude-hint"
            case .calendarAccess: return "calendar-access"
            }
        }

        /// About how tall the glance is, to show only what fits without scrolling.
        var height: CGFloat {
            switch self {
            case .usage(let u): return 18 + CGFloat(u.windows.count) * 16
            case .claudeHint(.offer): return 24
            case .claudeHint(.waiting): return 48
            default: return 32
            }
        }
    }

    var primary: Primary
    var glances: [Glance]

    init(model: AppModel, now: Date = Date()) {
        let timers = model.timers.timers
        let stopwatch = model.tools.stopwatch.stopwatch
        let activities = model.activities.filter { !model.timers.owns($0) && !model.tools.stopwatch.owns($0) }
        var shownTimer: String?
        var shownActivity: String?
        var shownStopwatch = false
        // The meeting that has started, else the next one (`liveMeetings` is earliest first).
        let meetings = model.liveMeetings.filter { model.meetingReminder(for: $0.id) != nil }
        let meeting = meetings.first { $0.phase == .now } ?? meetings.first
        if let ringing = timers.first(where: { $0.status == .ringing }) {
            primary = .ringing(ringing)
            shownTimer = ringing.id
        } else if let meeting {
            primary = .meeting(meeting)
            shownActivity = meeting.id
        } else if let np = model.nowPlaying, model.settings.mediaEnabled {
            primary = .media(np)
        } else if let t = timers.first {
            primary = .timer(t)
            shownTimer = t.id
        } else if stopwatch.isActive {
            primary = .stopwatch(stopwatch)
            shownStopwatch = true
        } else if let a = activities.first {
            primary = .activity(a)
            shownActivity = a.id
        } else {
            primary = .clock
        }

        let rest = activities.filter { $0.id != shownActivity }
        var glances: [Glance] = rest.filter(Self.needsYou).map(Glance.activity)
        glances += timers.filter { $0.id != shownTimer }.map(Glance.timer)
        if stopwatch.isActive && !shownStopwatch { glances.append(.stopwatch(stopwatch)) }
        // The next event, unless it is the meeting leading the page.
        if let e = model.upcomingEvent, !Self.leads(e, primary) { glances.append(.event(e)) }
        // Where the next event would be: a calendar that is on but can't be read, once macOS has
        // said so (not before it has been asked; the Today page offers Allow then).
        let access = model.calendarAdvice(.calendars)
        if model.settings.calendarEnabled, !access.isAllowed, access.action != .ask { glances.append(.calendarAccess(access)) }
        glances += rest.filter { !Self.needsYou($0) }.map(Glance.activity)
        // Claude's hint sits where its card will be, before Codex's.
        if let hint = model.agentUsage.claudeHint { glances.append(.claudeHint(hint)) }
        glances += model.agentUsage.visible(now: now).map(Glance.usage)
        glances += model.toolUsage.visible.map(Glance.toolUsage)
        self.glances = glances
    }

    /// Whether `item` is the meeting `primary` shows.
    static func leads(_ item: AgendaItem, _ primary: Primary) -> Bool {
        guard case .meeting(let m) = primary else { return false }
        return MeetingReminders.key(for: item) == m.key
    }

    /// Waiting on you, or failing loudly: these lead the column.
    static func needsYou(_ a: Activity) -> Bool {
        a.state == .waiting || a.priority == .critical || (a.state == .failure && a.priority >= .high)
    }
}

struct HomeTab: View {
    let model: AppModel
    /// The page's content area.
    let size: CGSize

    var body: some View {
        if model.timers.isEntering {
            TimerComposer(model: model)
        } else {
            let plan = HomePlan(model: model)
            // Lyrics, when on and found, take the glances' column beside the music, under a
            // timer or the stopwatch that is counting.
            let lyrics = LyricsColumn.lyrics(for: plan, model: model, height: size.height)
            let split = !plan.glances.isEmpty || lyrics != nil
            // The primary thing gets the larger share; the glances the rest, past a hairline.
            let share: CGFloat = size.width < 480 ? 0.47 : 0.56
            let primaryWidth = split ? (size.width * share).rounded() : size.width
            HStack(alignment: .top, spacing: 0) {
                // Media fills its column; anything else sits centred in it.
                primary(plan.primary, width: primaryWidth)
                    .frame(width: primaryWidth, height: size.height, alignment: plan.primary.fills ? .topLeading : .leading)
                if split {
                    ColumnRule()
                        .frame(height: size.height)
                        .padding(.horizontal, Space.l)
                    if let lyrics {
                        VStack(alignment: .leading, spacing: Space.m) {
                            if !lyrics.kept.isEmpty {
                                let keptHeight = lyrics.kept.map(\.height).reduce(0, +) + CGFloat(lyrics.kept.count - 1) * Space.m
                                GlanceColumn(model: model, glances: lyrics.kept, height: keptHeight)
                                    .frame(height: keptHeight, alignment: .topLeading)
                            }
                            LyricsColumn(model: model, media: lyrics.media, lyrics: lyrics.lyrics, showsSungLine: lyrics.kept.isEmpty)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        GlanceColumn(model: model, glances: plan.glances, height: size.height)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func primary(_ p: HomePlan.Primary, width: CGFloat) -> some View {
        switch p {
        case .media(let np): NowPlayingHero(model: model, media: np, size: CGSize(width: width, height: size.height))
        case .meeting(let m): MeetingHero(model: model, reminder: m)
        case .ringing(let t), .timer(let t): TimerHero(model: model, timer: t)
        case .stopwatch(let s): StopwatchHero(model: model, stopwatch: s)
        case .activity(let a): ActivityHero(activity: a, model: model)
        case .clock: ClockHero(model: model)
        }
    }
}

/// Home with nothing playing and nothing going on: the time, large, and the day.
struct ClockHero: View {
    let model: AppModel

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(ctx.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .textStyle(.body)
                    .foregroundStyle(Ink.secondary)
                Text(ctx.date.formatted(date: .omitted, time: .shortened))
                    .textStyle(.display)
                    .foregroundStyle(Ink.primary)
                if let b = model.battery {
                    HStack(spacing: Space.xs) {
                        Image(systemName: BatteryGlyph.symbol(b))
                        Text([String("\(b.level)%"), b.detail].compactMap { $0 }.joined(separator: " · "))
                            .lineLimit(1)
                    }
                    .textStyle(.caption)
                    .foregroundStyle(Ink.tertiary)
                    .padding(.top, Space.xs)
                }
            }
        }
    }
}

/// The most important activity when nothing is playing: its template's row, a little larger.
struct ActivityHero: View {
    let activity: Activity
    let model: AppModel

    var body: some View {
        let tint = model.tint(for: activity)
        let showsBar = activity.state == .running && activity.clampedProgress != nil
        if let t = model.visualTemplate(for: activity) {
            VStack(alignment: .leading, spacing: Space.m) {
                TemplateRow(activity: activity, model: model)
                // Rows that draw only their data (a score, a flight) leave the news underneath.
                if t == .score || t == .flight, let sub = activity.subtitle {
                    Text(sub).textStyle(.body).foregroundStyle(Ink.secondary).lineLimit(2)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .top, spacing: Space.m) {
                    IconView(icon: model.icon(for: activity), size: 24, tint: tint)
                    VStack(alignment: .leading, spacing: Space.hair) {
                        Text(activity.title).textStyle(.title).foregroundStyle(Ink.primary).lineLimit(1)
                        if let sub = activity.subtitle {
                            Text(sub).textStyle(.body).foregroundStyle(Ink.secondary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: Space.s)
                    // A bar below says the progress already; a ring beside it would say it twice.
                    if !showsBar || activity.trailing != nil {
                        ActivityTrailing(activity: activity, tint: tint)
                    }
                }
                if showsBar {
                    ActivityProgress(activity: activity, tint: tint, height: 4)
                }
                ActivityActions(activity: activity, model: model, tint: tint)
            }
        }
    }
}

/// An activity's own buttons (at most two), filled with its tint.
struct ActivityActions: View {
    let activity: Activity
    let model: AppModel
    let tint: Color

    var body: some View {
        if !activity.actions.isEmpty {
            HStack(spacing: Space.s) {
                ForEach(Array(activity.actions.prefix(2).enumerated()), id: \.offset) { _, action in
                    Button(action.title) { model.perform(action, activityID: activity.id) }
                        .buttonStyle(CapsuleButtonStyle(tint: tint, filled: true))
                }
            }
        }
    }
}

/// The quiet column beside the primary thing: timers, the next event, activities and usage,
/// one glance each. It scrolls when there are more than fit.
struct GlanceColumn: View {
    let model: AppModel
    let glances: [HomePlan.Glance]
    let height: CGFloat
    @Environment(\.snapshotMode) private var snapshotMode

    private static let spacing: CGFloat = Space.m

    var body: some View {
        let fitting = Self.fitting(glances, in: height)
        AdaptiveScroll(scrolls: fitting < glances.count) {
            VStack(alignment: .leading, spacing: Self.spacing) {
                // Snapshots can't scroll, so they show what fits.
                ForEach(snapshotMode ? Array(glances.prefix(fitting)) : glances) { g in
                    glance(g)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    static func fitting(_ glances: [HomePlan.Glance], in height: CGFloat) -> Int {
        var used: CGFloat = 0
        for (i, g) in glances.enumerated() {
            used += g.height + (i == 0 ? 0 : spacing)
            if used > height + 2 { return i }
        }
        return glances.count
    }

    @ViewBuilder
    private func glance(_ g: HomePlan.Glance) -> some View {
        switch g {
        case .timer(let t): TimerGlance(timer: t, model: model)
        case .stopwatch(let s): StopwatchGlance(stopwatch: s, model: model)
        case .event(let e): EventGlance(item: e, model: model)
        case .activity(let a): ActivityGlance(activity: a, model: model)
        case .usage(let u):
            TimelineView(.everyMinute) { _ in AgentUsageGlance(usage: u, now: Date()) }
        case .toolUsage(let card):
            ToolUsageGlance(card: card)
        case .claudeHint(let hint):
            ClaudeUsageHintRow(hint: hint, model: model)
        case .calendarAccess(let advice):
            GlanceRow(title: "Calendar") {
                Image(systemName: "calendar").font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.tertiary)
            } trailing: {
                Button(advice.button == "Open System Settings" ? "Open" : advice.button ?? "Open") {
                    model.requestCalendarAccess(.calendars)
                }
                .buttonStyle(CapsuleButtonStyle(tint: .blue))
                .help(advice.detail ?? "")
            } detail: {
                Text(advice.status)
            }
        }
    }
}

/// A glance: a mark, a title with its value, and one line of detail.
struct GlanceRow<Lead: View, Trailing: View, Detail: View>: View {
    let title: String
    let lead: Lead
    let trailing: Trailing
    let detail: Detail

    init(title: String, @ViewBuilder lead: () -> Lead, @ViewBuilder trailing: () -> Trailing, @ViewBuilder detail: () -> Detail) {
        self.title = title
        self.lead = lead()
        self.trailing = trailing()
        self.detail = detail()
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            lead.frame(width: 18, height: 16)
            VStack(alignment: .leading, spacing: Space.hair) {
                HStack(spacing: Space.s) {
                    Text(title)
                        .textStyle(.body, emphasized: true)
                        .foregroundStyle(Ink.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    trailing.fixedSize()
                }
                .frame(height: 16)
                detail
                    .textStyle(.caption)
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct EventGlance: View {
    let item: AgendaItem
    let model: AppModel

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            GlanceRow(title: item.title) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color(tint: item.calendarColor, fallback: .blue))
                    .frame(width: 3, height: 30)
                    .frame(height: 16, alignment: .top)
            } trailing: {
                if item.meetingURL != nil {
                    Button("Join") { model.join(item) }
                        .buttonStyle(CapsuleButtonStyle(tint: .green))
                }
            } detail: {
                Text(item.isOngoing(at: ctx.date) ? "Now · until \(item.end.formatted(date: .omitted, time: .shortened))"
                     : "\(Format.relative(to: item.start, now: ctx.date)) · \(item.start.formatted(date: .omitted, time: .shortened))")
            }
        }
    }
}

struct ActivityGlance: View {
    let activity: Activity
    let model: AppModel
    @ViewState private var hovering = false

    var body: some View {
        let a = activity
        let tint = model.tint(for: a)
        GlanceRow(title: a.title) {
            TemplateLeading(activity: a, model: model, tint: tint, size: 14, compact: true)
        } trailing: {
            if hovering {
                Button { model.remove(activityID: a.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Ink.tertiary)
                        .frame(width: 16, height: 16).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            } else if let action = a.actions.first {
                Button(action.title) { model.perform(action, activityID: a.id) }
                    .buttonStyle(CapsuleButtonStyle(tint: tint))
            } else {
                TemplateTrailing(activity: a, model: model, tint: tint, compact: true)
                    .environment(\.wingRoom, 60)
            }
        } detail: {
            if a.state == .running, a.clampedProgress != nil, a.subtitle == nil {
                ActivityProgress(activity: a, tint: tint, height: 3).padding(.top, Space.xs)
            } else {
                Text(a.subtitle ?? a.phase ?? Self.stateText(a.state))
            }
        }
        .onHover { hovering = $0 }
        .onTapGesture { if model.canOpen(a) { model.openActivity(a) } }
        .contextMenu {
            if model.canOpen(a) { Button("Open") { model.openActivity(a) } }
            Button("Dismiss") { model.remove(activityID: a.id) }
            Button("Mute “\(a.source)”") { model.mute(source: a.source) }
        }
    }

    static func stateText(_ s: ActivityState) -> String {
        switch s {
        case .running: return "In progress"
        case .waiting: return "Waiting for you"
        case .success: return "Done"
        case .failure: return "Failed"
        case .warning: return "Needs a look"
        case .info: return ""
        }
    }
}

// MARK: - Today

struct TodayTab: View {
    let model: AppModel
    @Environment(\.snapshotMode) private var snapshotMode

    /// Height of one event or reminder line, and of the shared all-day line.
    static let rowHeight: CGFloat = 30
    static let allDayHeight: CGFloat = 14
    private static let labelHeight: CGFloat = 16

    /// Lines of `rowHeight` that fit under the label, after `taken` points of other lines.
    static func rows(in height: CGFloat, taken: CGFloat = 0) -> Int {
        max(1, Int((height - labelHeight - Space.xs - taken + Space.s) / (rowHeight + Space.s)))
    }

    var body: some View {
        if model.settings.monthCalendar {
            TodayWithMonth(model: model)
        } else {
            dayAndReminders
        }
    }

    private var dayAndReminders: some View {
        let now = Date()
        let rest = Agenda.restOfToday(model.visibleAgenda, now: now)
        let reminders = model.dueReminders
        return GeometryReader { geo in
            let h = geo.size.height
            let events = Self.rows(in: h, taken: rest.allDay.isEmpty ? 0 : Self.allDayHeight + Space.s)
            let todos = Self.rows(in: h)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    let calendarOn = model.settings.calendarEnabled && model.calendarAccess.events.canRead
                    SectionLabel(title: "Calendar", count: calendarOn ? rest.timed.count : 0).frame(height: Self.labelHeight)
                    if !calendarOn {
                        accessHint(.calendars, text: "Today's events, with a Join button for calls.")
                    } else if rest.timed.isEmpty && rest.allDay.isEmpty {
                        quiet("Nothing else today")
                    } else {
                        // Snapshots can't scroll, so they show the lines that fit.
                        AdaptiveScroll(scrolls: rest.timed.count > events) {
                            VStack(alignment: .leading, spacing: Space.s) {
                                if !rest.allDay.isEmpty { allDay(rest.allDay) }
                                ForEach(rest.timed.prefix(snapshotMode ? events : 20)) { e in
                                    AgendaLine(item: e, now: now) { model.join(e) }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                ColumnRule().frame(height: h).padding(.horizontal, Space.l)
                VStack(alignment: .leading, spacing: Space.xs) {
                    let remindersOn = model.settings.remindersEnabled && model.calendarAccess.reminders.canRead
                    SectionLabel(title: "Reminders", count: remindersOn ? reminders.count : 0).frame(height: Self.labelHeight)
                    if !remindersOn {
                        accessHint(.reminders, text: "Reminders due today, with an alert when they're due.")
                    } else if reminders.isEmpty {
                        quiet("All done")
                    } else {
                        AdaptiveScroll(scrolls: reminders.count > todos) {
                            VStack(alignment: .leading, spacing: Space.s) {
                                ForEach(reminders.prefix(snapshotMode ? todos : 30)) { r in ReminderLine(item: r, now: now) { model.completeReminder(r.id) } }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    /// All-day events share one quiet line.
    private func allDay(_ items: [AgendaItem]) -> some View {
        HStack(spacing: Space.s) {
            Circle().fill(Color(tint: items[0].calendarColor, fallback: .blue)).frame(width: 5, height: 5).frame(width: 3)
            Text(items.map(\.title).joined(separator: ", ")).textStyle(.caption).foregroundStyle(Ink.secondary).lineLimit(1)
        }
        .frame(height: Self.allDayHeight)
    }

    private func quiet(_ text: String) -> some View {
        Text(text).textStyle(.body).foregroundStyle(Ink.tertiary)
    }

    /// The feature switched off, or macOS not letting Islet read it: what is wrong in plain words,
    /// and the one button that helps (Allow, Turn on, or System Settings at the right page).
    private func accessHint(_ kind: PermissionKind, text: String) -> some View {
        let on = kind == .reminders ? model.settings.remindersEnabled : model.settings.calendarEnabled
        let advice = model.calendarAdvice(kind)
        let noun = kind == .reminders ? "Reminders" : "Calendar"
        return VStack(alignment: .leading, spacing: Space.s) {
            if advice.isAllowed || !on && advice.action == .ask {
                // Switched off (and allowed, or never asked): what it does, and the switch.
                Text(text).textStyle(.body).foregroundStyle(Ink.secondary).fixedSize(horizontal: false, vertical: true)
                Button(advice.isAllowed ? "Turn on" : "Allow \(noun)") { model.requestCalendarAccess(kind) }
                    .buttonStyle(CapsuleButtonStyle(tint: .blue, filled: true))
            } else {
                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(advice.status).textStyle(.body, emphasized: true).foregroundStyle(Ink.primary)
                    if let detail = advice.detail {
                        Text(detail).textStyle(.caption).foregroundStyle(Ink.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button(advice.button ?? "Open System Settings") { model.requestCalendarAccess(kind) }
                    .buttonStyle(CapsuleButtonStyle(tint: .blue, filled: advice.action == .ask))
            }
        }
    }
}

struct AgendaLine: View {
    let item: AgendaItem
    let now: Date
    var join: () -> Void

    var body: some View {
        let ongoing = item.isOngoing(at: now)
        HStack(spacing: Space.s) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color(tint: item.calendarColor, fallback: .blue))
                .frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(item.title).textStyle(.body, emphasized: true).foregroundStyle(Ink.primary).lineLimit(1)
                Text(ongoing ? "Now · until \(item.end.formatted(date: .omitted, time: .shortened))"
                     : item.start.formatted(date: .omitted, time: .shortened))
                    .textStyle(.caption, numeric: true)
                    .foregroundStyle(ongoing ? Color.green : Ink.tertiary)
            }
            Spacer(minLength: 0)
            if item.meetingURL != nil {
                Button("Join", action: join).buttonStyle(CapsuleButtonStyle(tint: .green))
            }
        }
    }
}

struct ReminderLine: View {
    let item: ReminderItem
    let now: Date
    var onComplete: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        HStack(spacing: Space.s) {
            Button(action: onComplete) {
                Image(systemName: hovering ? "checkmark.circle" : "circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(tint: item.listColor, fallback: .orange))
                    .frame(width: 16, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Mark as done")
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(item.title).textStyle(.body, emphasized: true).foregroundStyle(Ink.primary).lineLimit(1)
                if let due = item.due {
                    Text(item.isAllDay ? "Today" : due.formatted(date: .omitted, time: .shortened))
                        .textStyle(.caption, numeric: true)
                        .foregroundStyle(item.isOverdue(at: now) ? Color.red : Ink.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .onHover { hovering = $0 }
    }
}

// MARK: - Shelf

struct ShelfTab: View {
    let model: AppModel
    var dropTargeted: Bool

    var body: some View {
        let items = model.shelf.items
        let zone = RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
        if items.isEmpty {
            VStack(spacing: Space.s) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(dropTargeted ? Ink.primary : Ink.tertiary)
                VStack(spacing: Space.hair) {
                    Text("Drop files here to keep them handy").textStyle(.body, emphasized: true).foregroundStyle(Ink.primary)
                    Text("Drag them out again, or AirDrop them in one click.").textStyle(.caption).foregroundStyle(Ink.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(zone.fill(dropTargeted ? Wash.subtle : .clear))
            .overlay(zone.strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(dropTargeted ? Ink.secondary : Ink.quaternary))
        } else {
            HStack(alignment: .top, spacing: Space.l) {
                AdaptiveScroll(axis: .horizontal, scrolls: items.count > 4) {
                    HStack(alignment: .top, spacing: Space.s) {
                        ForEach(items) { item in FileTile(item: item, model: model) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: Space.s) {
                    Button { ShelfService.airDrop(model.shelfService.urls()) } label: {
                        Label("AirDrop", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .buttonStyle(CapsuleButtonStyle(tint: .blue))
                    .help("AirDrop everything on the shelf")
                    Button { model.clearShelf() } label: { Label("Clear", systemImage: "trash") }
                        .buttonStyle(CapsuleButtonStyle())
                        .help("Clear shelf")
                }
                .fixedSize()
            }
            .overlay(zone.strokeBorder(Ink.secondary.opacity(dropTargeted ? 1 : 0), lineWidth: 1))
        }
    }
}

struct FileTile: View {
    let item: ShelfItem
    let model: AppModel
    @ViewState private var hovering = false

    var body: some View {
        let url = URL(fileURLWithPath: item.path)
        // On a disk or share that isn't connected: kept, dimmed, until it comes back.
        let available = Shelf.isAvailable(item) { FileManager.default.fileExists(atPath: $0) }
        VStack(spacing: Space.xs) {
            Image(nsImage: IconCache.file(item.path, size: 48))
                .resizable()
                .frame(width: 48, height: 48)
            Text(item.name)
                .textStyle(.caption)
                .foregroundStyle(Ink.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 72)
        }
        .opacity(available ? 1 : 0.4)
        .padding(Space.xs)
        .background(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).fill(hovering ? Wash.subtle : .clear))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { model.removeFromShelf(item.id) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white, Color.gray)
                }
                .buttonStyle(.plain)
            }
        }
        .onHover { hovering = $0 }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { ShelfService.open(url) }
        .contextMenu {
            Button("Open") { ShelfService.open(url) }
            Button("Show in Finder") { ShelfService.reveal([url]) }
            Button("AirDrop") { ShelfService.airDrop([url]) }
            Button("Copy path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.path, forType: .string)
            }
            Divider()
            Button("Remove from shelf") { model.removeFromShelf(item.id) }
        }
        .help(available ? item.path : item.path + "\nOn a disk that isn't connected")
    }
}

/// A calm empty state: a glyph, one line, an optional detail and buttons.
struct EmptyHint<Actions: View>: View {
    let symbol: String
    let text: String
    var detail: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Ink.tertiary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: Space.s) {
                Text(text).textStyle(.body).foregroundStyle(Ink.secondary).fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail).font(.system(size: TextStyle.caption.size, design: .monospaced)).foregroundStyle(Ink.tertiary)
                        .textSelection(.enabled)
                }
                HStack(spacing: Space.s) { actions }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

extension EmptyHint where Actions == EmptyView {
    init(symbol: String, text: String, detail: String? = nil) {
        self.init(symbol: symbol, text: text, detail: detail) { EmptyView() }
    }
}

// MARK: - Widgets (script plugins)

struct WidgetsTab: View {
    let model: AppModel

    var body: some View {
        let results = model.plugins.values.sorted { $0.name < $1.name }
        if results.isEmpty {
            EmptyHint(symbol: "square.grid.2x2", text: "Script widgets: drop an executable into the plugins folder. xbar and SwiftBar plugins work as they are.",
                      detail: "~/.config/islet/plugins/cpu.10s.sh") {
                Button("Open plugins folder") { AppActions.openPluginsFolder(model) }.buttonStyle(CapsuleButtonStyle(tint: .blue, filled: true))
                Button("Install examples") { AppActions.installExamplePlugins(model) }.buttonStyle(CapsuleButtonStyle())
            }
        } else {
            // Up to three side by side, split by hairlines; more scroll.
            let columns = min(3, results.count)
            AdaptiveScroll(scrolls: results.count > 3) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.xl, alignment: .top), count: columns),
                          alignment: .leading, spacing: Space.l) {
                    ForEach(results) { r in PluginCard(result: r, model: model) }
                }
            }
        }
    }
}

struct PluginCard: View {
    let result: PluginResult
    let model: AppModel
    @ViewState private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                Text(result.name.prefix(1).uppercased() + result.name.dropFirst())
                    .textStyle(.caption, emphasized: true)
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if hovering {
                    Button { model.runPlugin(result.path) } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .bold)).foregroundStyle(Ink.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh")
                }
            }
            .frame(height: 16)
            if let error = result.error {
                Text(error).textStyle(.caption).foregroundStyle(.orange).lineLimit(2)
            }
            switch result.output {
            case .text(let header, let items):
                if let h = header.first { PluginLineView(line: h, prominent: true, model: model, plugin: result) }
                ForEach(Array(items.filter { $0.depth == 0 && $0.text != "---" }.prefix(3).enumerated()), id: \.offset) { _, line in
                    PluginLineView(line: line, prominent: false, model: model, plugin: result)
                }
            case .activity(let spec):
                Text(spec.title ?? "").textStyle(.headline).foregroundStyle(Ink.primary)
                if let s = spec.subtitle { Text(s).textStyle(.caption).foregroundStyle(Ink.secondary) }
            case .empty:
                Text("No output").textStyle(.caption).foregroundStyle(Ink.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

struct PluginLineView: View {
    let line: ScriptPlugins.Line
    let prominent: Bool
    let model: AppModel
    let plugin: PluginResult

    var body: some View {
        let label = HStack(spacing: Space.xs) {
            if let sf = line.sfSymbol { Image(systemName: sf) }
            Text(line.text).lineLimit(1)
        }
        .textStyle(prominent ? .body : .caption, emphasized: prominent)
        .foregroundStyle(Color(tint: line.color, fallback: prominent ? Ink.primary : Ink.secondary))

        if line.href != nil || line.shellCommand != nil || line.refreshOnClick {
            Button { AppActions.runPluginLine(line, plugin: plugin, model: model) } label: { label }
                .buttonStyle(.plain)
                .disabled(line.isDisabled)
        } else {
            label
        }
    }
}

// MARK: - Clipboard

struct ClipboardTab: View {
    let model: AppModel

    var body: some View {
        if !model.settings.clipboardEnabled {
            EmptyHint(symbol: "doc.on.clipboard",
                      text: "Clipboard history is off. It stays on this Mac, skips passwords from password managers, and holds \(model.settings.clipboardLimit) items.") {
                Button("Turn on") { AppActions.setClipboard(model, enabled: true) }.buttonStyle(CapsuleButtonStyle(tint: .blue, filled: true))
            }
        } else if model.clipboard.entries.isEmpty {
            EmptyHint(symbol: "doc.on.clipboard", text: "Copy some text and it shows up here.")
        } else {
            let clearable = model.clipboard.hasUnpinned
            AdaptiveScroll(scrolls: model.clipboard.entries.count + (clearable ? 1 : 0) > 4) {
                VStack(spacing: 0) {
                    ForEach(model.clipboard.entries) { e in ClipRow(entry: e, model: model) }
                    // Quiet, after the last item; pinned items stay.
                    if clearable {
                        HStack {
                            Spacer(minLength: 0)
                            Button("Clear unpinned") { model.clearClipboard() }
                                .buttonStyle(.plain)
                                .textStyle(.caption)
                                .foregroundStyle(Ink.tertiary)
                                .help("Remove everything you haven't pinned")
                        }
                        .padding(.horizontal, Space.s)
                        .frame(height: 24)
                    }
                }
            }
            .padding(.horizontal, -Space.s)
        }
    }
}

struct ClipRow: View {
    let entry: ClipboardEntry
    let model: AppModel
    @ViewState private var hovering = false

    var body: some View {
        HStack(spacing: Space.s) {
            Group {
                if let b = entry.sourceBundleID { AppIconView(bundleID: b, size: 16) } else { Color.clear }
            }
            .frame(width: 16, height: 16)
            Text(entry.text.replacingOccurrences(of: "\n", with: " ⏎ "))
                .textStyle(.body)
                .foregroundStyle(Ink.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if hovering || entry.pinned {
                Button { model.togglePinClip(entry.id) } label: {
                    Image(systemName: entry.pinned ? "pin.fill" : "pin").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(Ink.tertiary)
                .help(entry.pinned ? "Unpin" : "Pin")
            }
            if hovering {
                Button { model.removeClip(entry.id) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Ink.tertiary)
                    .help("Remove")
            }
        }
        .padding(.horizontal, Space.s)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).fill(hovering ? Wash.subtle : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { model.copyClip(entry) }
        .help("Click to copy")
    }
}

// MARK: - Stats

struct StatsTab: View {
    let model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: Space.xxl) {
            Gauge(title: "CPU", value: model.stats?.cpu ?? 0, detail: "\(ProcessInfo.processInfo.activeProcessorCount) cores", tint: .blue)
            Gauge(title: "Memory", value: model.stats?.memoryFraction ?? 0,
                  detail: model.stats.map { "\(Format.bytes(Int64($0.memoryUsed))) of \(Format.bytes(Int64($0.memoryTotal)))" } ?? "–", tint: .purple)
            if let b = model.battery {
                Gauge(title: b.isCharging ? "Charging" : "Battery", value: Double(b.level) / 100,
                      detail: b.detail ?? "\(b.level)%",
                      tint: b.level <= model.settings.batteryLowThreshold && !b.isPluggedIn ? .red : .green)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct Gauge: View {
    let title: String
    let value: Double
    let detail: String
    let tint: Color

    var body: some View {
        VStack(spacing: Space.s) {
            ZStack {
                ProgressRing(progress: value, tint: tint, size: 56, lineWidth: 5)
                Text("\(Int((value * 100).rounded()))%").textStyle(.headline, numeric: true).foregroundStyle(Ink.primary)
            }
            VStack(spacing: Space.hair) {
                Text(title).textStyle(.body, emphasized: true).foregroundStyle(Ink.primary)
                Text(detail).textStyle(.caption).foregroundStyle(Ink.tertiary).lineLimit(1)
            }
        }
        .frame(width: 112)
    }
}
