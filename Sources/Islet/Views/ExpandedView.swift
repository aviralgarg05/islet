import AppKit
import IsletCore
import IsletSystem
import SwiftUI

struct ExpandedView: View {
    let model: AppModel
    let metrics: IslandMetrics
    var dropTargeted: Bool

    var body: some View {
        VStack(spacing: 0) {
            topStrip
            Group {
                switch model.tab {
                case .home: HomeTab(model: model, width: metrics.expanded.width - 36, height: metrics.expanded.height - max(metrics.notch.height, 28) - 20)
                case .today: TodayTab(model: model)
                case .shelf: ShelfTab(model: model, dropTargeted: dropTargeted)
                case .widgets: WidgetsTab(model: model)
                case .clipboard: ClipboardTab(model: model)
                case .stats: StatsTab(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 14)
            .clipped()
        }
        .frame(width: metrics.expanded.width, height: metrics.expanded.height, alignment: .top)
    }

    /// The row level with the hardware notch: tabs on the left, status on the right.
    private var topStrip: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(visibleTabs) { tab in
                    Button {
                        Haptics.play(.tap)
                        model.select(tab: tab)
                    } label: {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(model.tab == tab ? Color.white : Color.islandTertiary)
                            .frame(width: 28, height: 22)
                            .background(RoundedRectangle(cornerRadius: 7).fill(model.tab == tab ? Color.islandFill : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(tab.title)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: metrics.notch.width + 12)

            HStack(spacing: 7) {
                if model.cameraInUse { Circle().fill(.green).frame(width: 6, height: 6).help("Camera in use") }
                if model.micInUse { Circle().fill(.orange).frame(width: 6, height: 6).help("Microphone in use") }
                if let b = model.battery {
                    HStack(spacing: 3) {
                        Text("\(b.level)%").font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                            .lineLimit(1).fixedSize()
                        Image(systemName: BatteryGlyph.symbol(b)).font(.system(size: 12))
                    }
                    .foregroundStyle(b.level <= 20 && !b.isPluggedIn ? Color.red : Color.islandSecondary)
                }
                Button {
                    Haptics.play(.snap)
                    model.pinned.toggle()
                } label: {
                    Image(systemName: model.pinned ? "pin.fill" : "pin")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(model.pinned ? Color.white : Color.islandTertiary)
                }
                .buttonStyle(.plain)
                .help("Keep open")
                Button { AppActions.openSettings() } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 12)).foregroundStyle(Color.islandTertiary)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: max(metrics.notch.height, 28))
    }

    private var visibleTabs: [IslandTab] {
        IslandTab.allCases.filter { tab in
            switch tab {
            case .today: return model.settings.calendarEnabled || model.settings.remindersEnabled
            case .shelf: return model.settings.shelfEnabled
            case .widgets: return model.settings.pluginsEnabled
            case .stats: return model.settings.systemStatsEnabled
            default: return true
            }
        }
    }
}

// MARK: - Home

struct HomeTab: View {
    let model: AppModel
    /// Size available for the tab's content.
    var width: CGFloat
    var height: CGFloat
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        let cardWidth = min(260, (width - 16) * 0.5)
        let event = model.upcomingEvent
        // Rows that fit without scrolling (event row and activity rows are ~44 pt with spacing).
        let rowsThatFit = max(1, Int((height - (event == nil ? 0 : 48)) / 48))
        HStack(alignment: .top, spacing: 16) {
            if let np = model.nowPlaying, model.settings.mediaEnabled {
                NowPlayingCard(model: model, media: np)
                    .frame(width: cardWidth)
            } else {
                TodayCard(model: model).frame(width: cardWidth)
            }
            VStack(alignment: .leading, spacing: 6) {
                TimerCard(model: model)
                if let event { EventRow(item: event, theme: model.settings.theme) }
                let acts = model.activities.filter { !model.timers.owns($0) }
                if acts.isEmpty && event == nil {
                    EmptyHint(symbol: "sparkles", text: "Live activities from scripts, agents and CI appear here.",
                              detail: "Try: isletctl notify \"Hello\"")
                } else {
                    let shown = snapshotMode ? Array(acts.prefix(rowsThatFit)) : acts
                    AdaptiveScroll(scrolls: acts.count > rowsThatFit) {
                        VStack(spacing: 6) {
                            ForEach(shown) { a in ActivityRow(activity: a, model: model) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

struct NowPlayingCard: View {
    let model: AppModel
    let media: NowPlaying

    var body: some View {
        let accent = model.mediaAccent(media)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ArtworkView(media: media, size: 48, corner: 10)
                    .onTapGesture { model.openPlayer() }
                    .help("Open \(media.appName ?? "player")")
                VStack(alignment: .leading, spacing: 1) {
                    Text(media.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(media.artist ?? media.appName ?? "").font(.system(size: 11.5)).foregroundStyle(Color.islandSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if media.duration != nil {
                TimelineView(.periodic(from: .now, by: media.isPlaying ? 1 : 3600)) { ctx in
                    let pos = media.position(at: ctx.date) ?? 0
                    HStack(spacing: 6) {
                        Text(Format.clock(pos))
                        LevelBar(value: media.fraction(at: ctx.date) ?? 0, tint: accent, height: 4)
                        Text("-" + Format.clock(max(0, (media.duration ?? 0) - pos)))
                    }
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.islandTertiary)
                }
            }
            HStack(spacing: 14) {
                Spacer()
                PillButton(symbol: "backward.fill", size: 12) { model.send(.previous) }
                PillButton(symbol: media.isPlaying ? "pause.fill" : "play.fill", size: 16) { model.send(.togglePlayPause) }
                PillButton(symbol: "forward.fill", size: 12) { model.send(.next) }
                Spacer()
            }
        }
    }
}

struct TodayCard: View {
    let model: AppModel

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            VStack(alignment: .leading, spacing: 4) {
                Text(ctx.date.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.islandSecondary)
                Text(ctx.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                if let b = model.battery {
                    HStack(spacing: 6) {
                        Image(systemName: BatteryGlyph.symbol(b))
                        Text("\(b.level)%")
                        if let t = Format.batteryTime(minutes: b.minutesRemaining) {
                            Text(b.isCharging ? "· full in \(t)" : "· \(t) left").foregroundStyle(Color.islandTertiary)
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.islandSecondary)
                }
                Text("Nothing playing").font(.system(size: 11)).foregroundStyle(Color.islandTertiary).padding(.top, 4)
            }
        }
    }
}

struct EventRow: View {
    let item: AgendaItem
    var theme: IslandTheme = .black

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(Color(tint: item.calendarColor, fallback: .blue)).frame(width: 4, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(item.isOngoing(at: ctx.date) ? "Now · until \(item.end.formatted(date: .omitted, time: .shortened))"
                         : "\(Format.relative(to: item.start, now: ctx.date)) · \(item.start.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11)).foregroundStyle(Color.islandSecondary)
                }
                Spacer(minLength: 0)
                if let url = item.meetingURL {
                    Button("Join") { NSWorkspace.shared.open(url) }
                        .buttonStyle(CapsuleButtonStyle(tint: .green))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .islandCard(theme)
        }
    }
}

struct ActivityRow: View {
    let activity: Activity
    let model: AppModel
    @ViewState private var hovering = false

    var body: some View {
        let tint = model.tint(for: activity)
        HStack(spacing: 10) {
            IconView(icon: model.icon(for: activity), size: 18, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                if let sub = activity.subtitle {
                    Text(sub).font(.system(size: 11)).foregroundStyle(Color.islandSecondary).lineLimit(1)
                }
                if activity.state == .running, activity.clampedProgress != nil {
                    ActivityProgress(activity: activity, tint: tint, height: 3)
                }
            }
            Spacer(minLength: 0)
            ForEach(Array(activity.actions.prefix(2).enumerated()), id: \.offset) { _, action in
                Button(action.title) { model.perform(action, activityID: activity.id) }
                    .buttonStyle(CapsuleButtonStyle(tint: tint))
            }
            ActivityTrailing(activity: activity, tint: tint)
            if hovering {
                Button { model.remove(activityID: activity.id) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.islandTertiary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .islandCard(model.settings.theme)
        .onHover { hovering = $0 }
    }
}

struct CapsuleButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.6 : 0.85)))
    }
}

struct EmptyHint: View {
    let symbol: String
    let text: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(Color.islandTertiary)
            Text(text).font(.system(size: 12)).foregroundStyle(Color.islandSecondary).fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.islandTertiary).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Today

struct TodayTab: View {
    let model: AppModel
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        let now = Date()
        let rest = Agenda.restOfToday(model.visibleAgenda, now: now)
        let reminders = model.dueReminders
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                header("Calendar", count: rest.timed.count)
                if !model.settings.calendarEnabled || CalendarService.eventAccess != .granted && !snapshotMode {
                    accessHint("Show today's events and a Join button for calls.", action: "Allow Calendar") { model.requestCalendarAccess() }
                } else if rest.timed.isEmpty && rest.allDay.isEmpty {
                    Text("Nothing else today").font(.system(size: 11)).foregroundStyle(Color.islandTertiary)
                } else {
                    AdaptiveScroll(scrolls: rest.timed.count > 3) {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(rest.allDay) { e in
                                Text(e.title).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                                    .padding(.horizontal, 6).padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color(tint: e.calendarColor, fallback: .blue).opacity(0.3)))
                            }
                            ForEach(rest.timed.prefix(snapshotMode ? 3 : 20)) { e in AgendaLine(item: e, now: now) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 4) {
                header("Reminders", count: reminders.count)
                if !model.settings.remindersEnabled || CalendarService.reminderAccess != .granted && !snapshotMode {
                    accessHint("Reminders due today, with an alert when they're due.", action: "Allow Reminders") { model.requestReminderAccess() }
                } else if reminders.isEmpty {
                    Text("All done").font(.system(size: 11)).foregroundStyle(Color.islandTertiary)
                } else {
                    AdaptiveScroll(scrolls: reminders.count > 4) {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(reminders.prefix(snapshotMode ? 4 : 30)) { r in ReminderLine(item: r, now: now) { model.completeReminder(r.id) } }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func header(_ title: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Text(title.uppercased()).font(.system(size: 9.5, weight: .bold)).foregroundStyle(Color.islandTertiary)
            if count > 0 { Text("\(count)").font(.system(size: 9.5, weight: .bold)).foregroundStyle(Color.islandSecondary) }
        }
    }

    private func accessHint(_ text: String, action: String, _ perform: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(text).font(.system(size: 11)).foregroundStyle(Color.islandSecondary).fixedSize(horizontal: false, vertical: true)
            Button(action, action: perform).buttonStyle(CapsuleButtonStyle(tint: .blue))
        }
    }
}

struct AgendaLine: View {
    let item: AgendaItem
    let now: Date

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5).fill(Color(tint: item.calendarColor, fallback: .blue)).frame(width: 3, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(item.isOngoing(at: now) ? "Now · until \(item.end.formatted(date: .omitted, time: .shortened))"
                     : item.start.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10)).foregroundStyle(item.isOngoing(at: now) ? Color.green : Color.islandTertiary)
            }
            Spacer(minLength: 0)
            if let url = item.meetingURL {
                Button("Join") { NSWorkspace.shared.open(url) }.buttonStyle(CapsuleButtonStyle(tint: .green))
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
        HStack(spacing: 6) {
            Button(action: onComplete) {
                Image(systemName: hovering ? "checkmark.circle" : "circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(tint: item.listColor, fallback: .orange))
            }
            .buttonStyle(.plain)
            .help("Mark as done")
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                if let due = item.due {
                    Text(item.isAllDay ? "Today" : due.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundStyle(item.isOverdue(at: now) ? Color.red : Color.islandTertiary)
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
        if items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 26)).foregroundStyle(dropTargeted ? .white : Color.islandTertiary)
                Text("Drop files here to keep them handy").font(.system(size: 12)).foregroundStyle(Color.islandSecondary)
                Text("Drag them out again, or AirDrop them in one click.").font(.system(size: 11)).foregroundStyle(Color.islandTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                .foregroundStyle(dropTargeted ? Color.white.opacity(0.7) : Color.islandTertiary))
        } else {
            HStack(spacing: 12) {
                AdaptiveScroll(axis: .horizontal, scrolls: items.count > 5) {
                    HStack(spacing: 10) {
                        ForEach(items) { item in FileTile(item: item, model: model) }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    Button { ShelfService.airDrop(model.shelfService.urls()) } label: {
                        Label("AirDrop", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .buttonStyle(CapsuleButtonStyle(tint: .blue)).help("AirDrop everything on the shelf")
                    Button { model.clearShelf() } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(CapsuleButtonStyle(tint: Color.white.opacity(0.25))).help("Clear shelf")
                }
                .fixedSize()
            }
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(dropTargeted ? 0.6 : 0), lineWidth: 1.5))
        }
    }
}

struct FileTile: View {
    let item: ShelfItem
    let model: AppModel
    @ViewState private var hovering = false

    var body: some View {
        let url = URL(fileURLWithPath: item.path)
        VStack(spacing: 4) {
            Image(nsImage: IconCache.file(item.path, size: 48))
                .resizable()
                .frame(width: 48, height: 48)
            Text(item.name)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.islandSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 76)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(hovering ? Color.islandFill : .clear))
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
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.path, forType: .string)
            }
            Divider()
            Button("Remove from Shelf") { model.removeFromShelf(item.id) }
        }
        .help(item.path)
    }
}

// MARK: - Widgets (script plugins)

struct WidgetsTab: View {
    let model: AppModel

    var body: some View {
        let results = model.plugins.values.sorted { $0.name < $1.name }
        if results.isEmpty {
            HStack(alignment: .top, spacing: 16) {
                EmptyHint(symbol: "square.grid.2x2", text: "Script widgets: drop an executable into the plugins folder. xbar/SwiftBar plugins work as-is.",
                          detail: "~/.config/islet/plugins/cpu.10s.sh")
                VStack(alignment: .leading, spacing: 8) {
                    Button("Open Plugins Folder") { AppActions.openPluginsFolder(model) }.buttonStyle(CapsuleButtonStyle(tint: .blue))
                    Button("Install Examples") { AppActions.installExamplePlugins(model) }.buttonStyle(CapsuleButtonStyle(tint: .gray))
                }
            }
        } else {
            AdaptiveScroll(scrolls: results.count > 4) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10, alignment: .top), GridItem(.flexible(), spacing: 10, alignment: .top)],
                          alignment: .leading, spacing: 10) {
                    ForEach(results) { r in PluginCard(result: r, model: model) }
                }
            }
        }
    }
}

struct PluginCard: View {
    let result: PluginResult
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(result.name.uppercased()).font(.system(size: 9.5, weight: .bold)).foregroundStyle(Color.islandTertiary)
                Spacer()
                Button { model.runPlugin(result.path) } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.islandTertiary)
                }
                .buttonStyle(.plain)
            }
            if let error = result.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(2)
            }
            switch result.output {
            case .text(let header, let items):
                if let h = header.first { PluginLineView(line: h, prominent: true, model: model, plugin: result) }
                ForEach(Array(items.filter { $0.depth == 0 && $0.text != "---" }.prefix(4).enumerated()), id: \.offset) { _, line in
                    PluginLineView(line: line, prominent: false, model: model, plugin: result)
                }
            case .activity(let spec):
                Text(spec.title ?? "").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                if let s = spec.subtitle { Text(s).font(.system(size: 11)).foregroundStyle(Color.islandSecondary) }
            case .empty:
                Text("No output").font(.system(size: 11)).foregroundStyle(Color.islandTertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .islandCard(model.settings.theme)
    }
}

struct PluginLineView: View {
    let line: ScriptPlugins.Line
    let prominent: Bool
    let model: AppModel
    let plugin: PluginResult

    var body: some View {
        let label = HStack(spacing: 5) {
            if let sf = line.sfSymbol { Image(systemName: sf) }
            Text(line.text).lineLimit(1)
        }
        .font(.system(size: prominent ? 13 : 11.5, weight: prominent ? .semibold : .regular))
        .foregroundStyle(Color(tint: line.color, fallback: prominent ? .white : .islandSecondary))

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
            HStack(alignment: .top, spacing: 16) {
                EmptyHint(symbol: "doc.on.clipboard", text: "Clipboard history is off. It stays on this Mac, skips passwords from password managers, and holds \(model.settings.clipboardLimit) items.")
                Button("Turn On") { AppActions.setClipboard(model, enabled: true) }.buttonStyle(CapsuleButtonStyle(tint: .blue))
            }
        } else if model.clipboard.entries.isEmpty {
            EmptyHint(symbol: "doc.on.clipboard", text: "Copy some text and it will show up here.")
        } else {
            AdaptiveScroll(scrolls: model.clipboard.entries.count > 5) {
                VStack(spacing: 4) {
                    ForEach(model.clipboard.entries) { e in ClipRow(entry: e, model: model) }
                }
            }
        }
    }
}

struct ClipRow: View {
    let entry: ClipboardEntry
    let model: AppModel
    @ViewState private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            if let b = entry.sourceBundleID { AppIconView(bundleID: b, size: 14) }
            Text(entry.text.replacingOccurrences(of: "\n", with: " ⏎ "))
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
            if hovering || entry.pinned {
                Button { model.togglePinClip(entry.id) } label: {
                    Image(systemName: entry.pinned ? "pin.fill" : "pin").font(.system(size: 10))
                }
                .buttonStyle(.plain).foregroundStyle(Color.islandSecondary)
            }
            if hovering {
                Button { model.removeClip(entry.id) } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                    .buttonStyle(.plain).foregroundStyle(Color.islandSecondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Color.islandFill : .clear))
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
        HStack(spacing: 24) {
            Gauge(title: "CPU", value: model.stats?.cpu ?? 0, detail: "\(ProcessInfo.processInfo.activeProcessorCount) cores", tint: .blue)
            Gauge(title: "Memory", value: model.stats?.memoryFraction ?? 0,
                  detail: model.stats.map { "\(Format.bytes(Int64($0.memoryUsed))) of \(Format.bytes(Int64($0.memoryTotal)))" } ?? "–", tint: .purple)
            if let b = model.battery {
                Gauge(title: b.isCharging ? "Charging" : "Battery", value: Double(b.level) / 100,
                      detail: Format.batteryTime(minutes: b.minutesRemaining).map { b.isCharging ? "full in \($0)" : "\($0) left" } ?? "\(b.level)%",
                      tint: b.level <= 20 && !b.isPluggedIn ? .red : .green)
            }
            Spacer()
        }
        .padding(.top, 8)
    }
}

struct Gauge: View {
    let title: String
    let value: Double
    let detail: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                ProgressRing(progress: value, tint: tint, size: 64, lineWidth: 7)
                Text("\(Int((value * 100).rounded()))%").font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            Text(detail).font(.system(size: 10)).foregroundStyle(Color.islandTertiary).lineLimit(1)
        }
        .frame(width: 120)
    }
}
