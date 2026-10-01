import AppKit
import IsletCore
import SwiftUI

// Timers on Home. A running timer is the primary thing when nothing is playing (a ring and the
// time, large), or a glance beside the music. New timers start from the composer, opened with
// the timer button under the island: a field that reads "tea 4m" or "at 18:30", a few presets
// and the Pomodoro.

/// A timer as Home's primary thing: the ring, the time left in large type, and its controls.
/// A ringing timer gets Stop, Snooze and Restart instead.
struct TimerHero: View {
    let timer: TimerItem
    let model: AppModel

    init(model: AppModel, timer: TimerItem) {
        self.model = model
        self.timer = timer
    }

    var body: some View {
        let tint = Color(tint: TimerEngine.look(for: timer).tint)
        if timer.status == .ringing {
            ringing(tint: tint)
        } else if timer.status == .running {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in dial(tint: tint, now: ctx.date) }
        } else {
            dial(tint: tint, now: Date())
        }
    }

    private func dial(tint: Color, now: Date) -> some View {
        let paused = timer.status == .paused
        let schedule = model.settings.pomodoro
        let round = model.timers.engine.pomodoroRound(timer, schedule: schedule)
        return HStack(alignment: .center, spacing: Space.l) {
            ZStack {
                ProgressRing(progress: timer.fraction(at: now), tint: paused ? Ink.tertiary : tint, size: 56, lineWidth: 4)
                IconView(icon: TimerEngine.look(for: timer).icon, size: 20, tint: paused ? Ink.tertiary : tint)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Space.s) {
                    Text(timer.displayTitle).textStyle(.body, emphasized: true).foregroundStyle(Ink.primary).lineLimit(1)
                    if let detail = paused ? "Paused" : round {
                        Text(detail).textStyle(.caption).foregroundStyle(Ink.tertiary).lineLimit(1).fixedSize()
                    }
                }
                Text(Format.clock(timer.timeLeft(at: now).rounded(.up)))
                    .textStyle(.display)
                    .foregroundStyle(paused ? Ink.secondary : tint)
                    .contentTransition(.numericText(countsDown: true))
                TimerControls(timer: timer, model: model)
                    .padding(.leading, -Space.xs)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func ringing(tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                Image(systemName: "alarm.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(timer.displayTitle).textStyle(.title).foregroundStyle(Ink.primary).lineLimit(1)
                    Text("Time's up").textStyle(.body).foregroundStyle(tint)
                }
            }
            .accessibilityElement(children: .combine)
            ViewThatFits(in: .horizontal) {
                ringingButtons(tint: tint, snooze: "Snooze 5 min")
                ringingButtons(tint: tint, snooze: "Snooze")
            }
        }
    }

    private func ringingButtons(tint: Color, snooze: String) -> some View {
        HStack(spacing: Space.s) {
            Button("Stop") { model.timers.control(.stop, timer) }
                .buttonStyle(CapsuleButtonStyle(tint: tint, filled: true))
            Button(snooze) { model.timers.control(.snooze, timer) }
                .buttonStyle(CapsuleButtonStyle())
                .help("Ring again in 5 minutes")
            Button("Restart") { model.timers.control(.restart, timer) }
                .buttonStyle(CapsuleButtonStyle())
                .help("Run for \(TimerDurationLabel.text(timer.duration)) again")
        }
        .fixedSize()
    }
}

/// Pause or resume, one more minute, and stop.
struct TimerControls: View {
    let timer: TimerItem
    let model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            if timer.status == .paused {
                IconButton(symbol: "play.fill", help: "Resume", size: 24, glyph: 10) { model.timers.control(.resume, timer) }
            } else {
                IconButton(symbol: "pause.fill", help: "Pause", size: 24, glyph: 10) { model.timers.control(.pause, timer) }
            }
            IconButton(symbol: "goforward.60", help: "Add 1 minute", size: 24, glyph: 11) { model.timers.control(.add, timer, seconds: 60) }
            IconButton(symbol: "xmark", help: timer.phase == nil ? "Stop" : "Stop the Pomodoro", size: 24, glyph: 10) {
                model.timers.control(.stop, timer)
            }
        }
    }
}

/// A timer in Home's column: its ring, title and time left; controls when the pointer is on it.
struct TimerGlance: View {
    let timer: TimerItem
    let model: AppModel
    @ViewState private var hovering = false

    var body: some View {
        let tint = Color(tint: TimerEngine.look(for: timer).tint)
        let paused = timer.status == .paused
        TimelineView(.periodic(from: .now, by: timer.status == .running ? 1 : 3600)) { ctx in
            GlanceRow(title: timer.displayTitle) {
                ProgressRing(progress: timer.fraction(at: ctx.date), tint: paused ? Ink.tertiary : tint, size: 14, lineWidth: 2)
            } trailing: {
                Text(timer.status == .ringing ? "Time's up" : Format.clock(timer.timeLeft(at: ctx.date).rounded(.up)))
                    .textStyle(.body, emphasized: true, numeric: true)
                    .foregroundStyle(paused ? Ink.secondary : tint)
                    .contentTransition(.numericText(countsDown: true))
            } detail: {
                if hovering {
                    TimerControls(timer: timer, model: model)
                        .frame(height: 14)
                        .padding(.leading, -Space.xs - 1)
                } else {
                    Text(paused ? "Paused" : "Ends \((ctx.date.addingTimeInterval(timer.timeLeft(at: ctx.date))).formatted(date: .omitted, time: .shortened))")
                }
            }
        }
        .onHover { hovering = $0 }
    }
}

/// Starting a timer: type one ("tea 4m", "25 min", "at 18:30"), or pick a preset or the
/// Pomodoro. Return starts it, Escape closes. The island takes the keyboard while it is open.
struct TimerComposer: View {
    let model: AppModel
    @ViewState private var text = ""
    @ViewState private var invalid = false
    @FocusState private var focused: Bool
    @Environment(\.snapshotMode) private var snapshotMode

    private static let orange = Color(tint: "orange")

    var body: some View {
        let parsed = try? DurationParser.parse(text)
        let pomodoro = model.timers.isPomodoroRunning
        let focus = Int(model.settings.pomodoro.sanitized().focusMinutes)
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                field
                Button(parsed.map { "Start \(TimerDurationLabel.text($0.seconds))" } ?? "Start", action: submit)
                    .buttonStyle(CapsuleButtonStyle(tint: parsed == nil ? nil : Self.orange, filled: true))
                    .fixedSize()
                    .disabled(parsed == nil)
                IconButton(symbol: "xmark", help: "Close", size: 24, glyph: 10, ink: Ink.tertiary) { close() }
            }
            // The presets give way first when the stopwatch needs the room.
            ViewThatFits(in: .horizontal) {
                startRow(presets: [1, 5, 10, 25], pomodoro: pomodoro, focus: focus)
                startRow(presets: [5, 10, 25], pomodoro: pomodoro, focus: focus)
                startRow(presets: [5, 25], pomodoro: pomodoro, focus: focus)
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            guard !snapshotMode else { return }
            IslandKeyboard.take(on: model.expandedScreen)
            DispatchQueue.main.async { focused = true }
        }
        .onDisappear {
            guard !snapshotMode else { return }
            IslandKeyboard.giveBack()
            model.timers.isEntering = false
        }
    }

    private func startRow(presets: [Int], pomodoro: Bool, focus: Int) -> some View {
        HStack(spacing: Space.s) {
            ForEach(presets, id: \.self) { m in
                Button("\(m) min") {
                    Haptics.play(.tap)
                    model.timers.start(minutes: Double(m))
                    close()
                }
                .buttonStyle(CapsuleButtonStyle())
                .help("Start a \(m)-minute timer")
                .fixedSize()
            }
            Spacer(minLength: Space.s)
            if model.settings.stopwatchEnabled {
                Button {
                    if !model.tools.stopwatch.stopwatch.isActive { model.tools.stopwatch.toggle() }
                    close()
                } label: {
                    Label("Stopwatch", systemImage: "stopwatch")
                }
                .buttonStyle(CapsuleButtonStyle())
                .help(model.tools.stopwatch.stopwatch.isActive ? "Show the stopwatch" : "Start the stopwatch")
                // Whole words or a shorter row: `ViewThatFits` picks the row, the row never clips.
                .fixedSize()
            }
            HStack(spacing: 2) {
                Button {
                    Haptics.play(.tap)
                    model.timers.togglePomodoro()
                    close()
                } label: {
                    Label(pomodoro ? "Stop Pomodoro" : "Pomodoro", systemImage: pomodoro ? "stop.fill" : "leaf.fill")
                }
                .buttonStyle(CapsuleButtonStyle(tint: pomodoro ? Color(tint: "red") : nil))
                .help(pomodoro ? "Stop the Pomodoro" : "Start a Pomodoro (\(focus) min focus, then a break)")
                if !pomodoro {
                    IconButton(symbol: "chevron.down", help: "Pomodoro lengths", size: 20, glyph: 9, ink: Ink.tertiary) {
                        showPomodoroLengths()
                    }
                }
            }
            .fixedSize()
        }
    }

    /// 25 / 5, 50 / 10 or 90 / 20: picking one starts it and keeps those lengths for next time.
    private func showPomodoroLengths() {
        let current = PomodoroPreset.matching(model.settings.pomodoro)
        var items = PomodoroPreset.all.map { preset in
            IslandMenu.Item(title: preset.title, checked: preset == current) {
                model.settings.pomodoro = preset.applied(to: model.settings.pomodoro)
                model.saveSettings()
                model.timers.togglePomodoro()
                close()
            }
        }
        items.append(.separator)
        items.append(IslandMenu.Item(title: "Pomodoro settings…") { AppActions.openSettings(.timers, at: "timers.lengths") })
        IslandMenu.show(items, model: model)
    }

    private var field: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "timer")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Self.orange)
                .accessibilityHidden(true)
            if snapshotMode {
                Text("tea 4m, 25 min or at 18:30").textStyle(.body).foregroundStyle(Ink.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("tea 4m, 25 min or at 18:30", text: $text)
                    .textFieldStyle(.plain)
                    .textStyle(.body)
                    .foregroundStyle(invalid ? Self.orange : Ink.primary)
                    .focused($focused)
                    .onSubmit(submit)
                    .onExitCommand(perform: close)
                    .onChange(of: text) { _, _ in invalid = false }
                    .accessibilityLabel("Timer")
            }
        }
        .padding(.horizontal, Space.m)
        .frame(height: 28)
        .background(Capsule().fill(Wash.regular))
    }

    private func submit() {
        if model.timers.start(text: text) {
            Haptics.play(.tap)
            close()
        } else {
            invalid = true
        }
    }

    private func close() {
        model.timers.isEntering = false
    }
}

/// "45 s", "4 min", "4:30", "1 h 30 min".
enum TimerDurationLabel {
    static func text(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s) s" }
        if s < 3600 { return s % 60 == 0 ? "\(s / 60) min" : Format.clock(Double(s)) }
        let m = (s % 3600) / 60
        return m == 0 ? "\(s / 3600) h" : "\(s / 3600) h \(m) min"
    }
}
