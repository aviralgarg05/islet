import AppKit
import IsletCore
import SwiftUI

/// Timers on the Home tab: preset chips, a field that reads "tea 4m" or "at 18:30", the
/// Pomodoro switch, and each timer with its controls.
struct TimerCard: View {
    let model: AppModel

    var body: some View {
        let timers = model.timers.timers
        VStack(alignment: .leading, spacing: 6) {
            if model.timers.isEntering {
                TimerEntryRow(model: model)
            } else {
                ViewThatFits(in: .horizontal) {
                    presets(minutes: " min", labels: true, icon: true)
                    presets(minutes: " min", labels: false, icon: true)
                    presets(minutes: "m", labels: false, icon: false)
                }
            }
            ForEach(timers) { t in
                let engine = model.timers.engine
                TimerRow(timer: t, round: engine.pomodoroRound(t, schedule: model.settings.pomodoro),
                         shortRound: engine.pomodoroRound(t, schedule: model.settings.pomodoro, short: true), model: model)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .islandCard(model.settings.theme)
    }

    private func presets(minutes unit: String, labels: Bool, icon: Bool) -> some View {
        let pomodoro = model.timers.isPomodoroRunning
        let focus = Int(model.settings.pomodoro.sanitized().focusMinutes)
        return HStack(spacing: 4) {
            if icon {
                Image(systemName: "timer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(tint: "orange"))
                    .accessibilityHidden(true)
            }
            ForEach([1, 5, 10, 25], id: \.self) { m in
                TimerChip(label: "\(m)\(unit)", help: "Start a \(m)-minute timer") { model.timers.start(minutes: Double(m)) }
            }
            Spacer(minLength: 2)
            TimerChip(symbol: "keyboard", label: labels ? "Custom" : nil,
                      help: "Type a timer, such as “tea 4m” or “at 18:30”") { model.timers.isEntering = true }
            TimerChip(symbol: pomodoro ? "stop.fill" : nil, label: pomodoro ? (labels ? "Pomodoro" : nil) : (labels ? "🍅 Pomodoro" : "🍅"),
                      tint: pomodoro ? Color(tint: "red") : nil,
                      help: pomodoro ? "Stop the Pomodoro" : "Start a Pomodoro (\(focus) min focus, then a break)") {
                model.timers.togglePomodoro()
            }
        }
    }
}

/// One timer: progress ring, title, time left, and pause or resume, +1 min and stop. A
/// ringing timer gets Stop, Snooze and Restart instead.
struct TimerRow: View {
    let timer: TimerItem
    /// "Round 2 of 4" for the Pomodoro, and "2/4" for when that doesn't fit.
    var round: String?
    var shortRound: String?
    let model: AppModel

    var body: some View {
        let tint = Color(tint: TimerEngine.look(for: timer).tint)
        if timer.status == .ringing {
            ringing(tint: tint)
        } else {
            HStack(spacing: 6) {
                if timer.status == .running {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        dial(tint: tint, now: ctx.date)
                    }
                } else {
                    dial(tint: tint, now: Date())
                }
                controls(tint: tint)
            }
            .frame(height: 22)
            .accessibilityElement(children: .contain)
        }
    }

    /// Ring, title and time left, redrawn once a second while running (only while visible).
    private func dial(tint: Color, now: Date) -> some View {
        let paused = timer.status == .paused
        return HStack(spacing: 6) {
            ProgressRing(progress: timer.fraction(at: now), tint: paused ? Color.islandTertiary : tint, size: 15, lineWidth: 2.2)
            // The round and "Paused" only when the whole title still fits beside them.
            ViewThatFits(in: .horizontal) {
                label(round: round, paused: paused)
                label(round: shortRound, paused: paused)
                label(round: nil, paused: false, fits: false)
            }
            Text(Format.clock(timer.timeLeft(at: now).rounded(.up)))
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(paused ? Color.islandSecondary : tint)
                .fixedSize()
                .contentTransition(.numericText(countsDown: true))
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(paused ? "Paused" : "Running")
    }

    private func label(round: String?, paused: Bool, fits: Bool = true) -> some View {
        HStack(spacing: 6) {
            Text(timer.displayTitle)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize(horizontal: fits, vertical: false)
            if let round {
                Text(round)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.islandTertiary)
                    .fixedSize()
            }
            Spacer(minLength: 4)
            if paused {
                Text("Paused")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.islandTertiary)
                    .fixedSize()
            }
        }
    }

    private func controls(tint: Color) -> some View {
        HStack(spacing: 2) {
            if timer.status == .paused {
                TimerIconButton(symbol: "play.fill", help: "Resume") { model.timers.control(.resume, timer) }
            } else {
                TimerIconButton(symbol: "pause.fill", help: "Pause") { model.timers.control(.pause, timer) }
            }
            TimerIconButton(text: "+1", help: "Add 1 minute") { model.timers.control(.add, timer, seconds: 60) }
            TimerIconButton(symbol: "xmark", help: timer.phase == nil ? "Stop" : "Stop the Pomodoro") { model.timers.control(.stop, timer) }
        }
    }

    private func ringing(tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "alarm.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 15)
                Text(timer.displayTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Time's up")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.islandSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            ViewThatFits(in: .horizontal) {
                ringingButtons(tint: tint, snooze: "Snooze 5 min")
                ringingButtons(tint: tint, snooze: "Snooze 5")
            }
        }
    }

    private func ringingButtons(tint: Color, snooze: String) -> some View {
        HStack(spacing: 6) {
            Button("Stop") { model.timers.control(.stop, timer) }
                .buttonStyle(CapsuleButtonStyle(tint: tint))
            Button(snooze) { model.timers.control(.snooze, timer) }
                .buttonStyle(CapsuleButtonStyle(tint: Color.white.opacity(0.2)))
                .help("Ring again in 5 minutes")
            Button("Restart") { model.timers.control(.restart, timer) }
                .buttonStyle(CapsuleButtonStyle(tint: Color.white.opacity(0.2)))
                .help("Run for \(TimerDurationLabel.text(timer.duration)) again")
        }
        .fixedSize()
    }
}

/// The custom field. Return starts the timer, Escape closes the field; while it is open the
/// island takes the keyboard, and gives it back when the field closes.
struct TimerEntryRow: View {
    let model: AppModel
    @ViewState private var text = ""
    @ViewState private var invalid = false
    @FocusState private var focused: Bool
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        let parsed = try? DurationParser.parse(text)
        HStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(tint: "orange"))
                .accessibilityHidden(true)
            if snapshotMode {
                Text("tea 4m").font(.system(size: 12)).foregroundStyle(Color.islandTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("tea 4m", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(invalid ? Color(tint: "orange") : .white)
                    .focused($focused)
                    .onSubmit(submit)
                    .onExitCommand(perform: close)
                    .onChange(of: text) { _, _ in invalid = false }
                    .accessibilityLabel("Timer")
            }
            Button(parsed.map { "Start \(TimerDurationLabel.text($0.seconds))" } ?? "Start", action: submit)
                .buttonStyle(CapsuleButtonStyle(tint: parsed == nil ? Color.white.opacity(0.2) : Color(tint: "orange")))
                .lineLimit(1)
                .fixedSize()
                .disabled(parsed == nil)
            TimerIconButton(symbol: "xmark", help: "Close") { close() }
        }
        .frame(height: 22)
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

/// A preset or switch in the Timer card.
struct TimerChip: View {
    var symbol: String?
    var label: String?
    /// Filled with this colour when set (the running Pomodoro).
    var tint: Color?
    var help: String
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.play(.tap)
            action()
        } label: {
            HStack(spacing: 3) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
                if let label { Text(label).font(.system(size: 11, weight: .semibold)).monospacedDigit() }
            }
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, label == nil ? 6 : 7)
            .frame(minWidth: 22, minHeight: 22)
        }
        .buttonStyle(ChipButtonStyle(tint: tint))
        .help(help)
        .accessibilityLabel(help)
    }
}

struct ChipButtonStyle: ButtonStyle {
    var tint: Color?
    @ViewState private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Capsule().fill(tint.map { $0.opacity(configuration.isPressed ? 0.6 : 0.85) }
                ?? Color.white.opacity(configuration.isPressed ? 0.24 : hovering ? 0.18 : 0.1)))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .onHover { hovering = $0 }
    }
}

/// Small round control in a timer row.
struct TimerIconButton: View {
    var symbol: String?
    var text: String?
    var help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 9.5, weight: .bold))
                } else if let text {
                    Text(text).font(.system(size: 10.5, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(Color.islandSecondary)
            .frame(width: 20, height: 20)
            .contentShape(Circle())
        }
        .buttonStyle(HoverButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}
