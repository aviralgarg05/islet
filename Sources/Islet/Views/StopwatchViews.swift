import IsletCore
import SwiftUI

// The stopwatch on Home: Home's primary thing when nothing plays and no timer runs, otherwise a
// glance. It starts from the timer composer once turned on in Settings → Timers.

private let stopwatchTint = Color(tint: "teal")

/// The stopwatch large: a ring that goes round once a minute, the time, and its controls.
struct StopwatchHero: View {
    let model: AppModel
    let stopwatch: Stopwatch

    var body: some View {
        if stopwatch.isRunning {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in dial(now: ctx.date) }
        } else {
            dial(now: Date())
        }
    }

    private func dial(now: Date) -> some View {
        let elapsed = stopwatch.elapsed(at: now)
        let paused = !stopwatch.isRunning
        let tint = paused ? Ink.tertiary : stopwatchTint
        return HStack(alignment: .center, spacing: Space.l) {
            ZStack {
                ProgressRing(progress: elapsed.truncatingRemainder(dividingBy: 60) / 60, tint: tint, size: 56, lineWidth: 4)
                Image(systemName: "stopwatch.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Space.s) {
                    Text("Stopwatch").textStyle(.body, emphasized: true).foregroundStyle(Ink.primary).lineLimit(1)
                    if let detail = StopwatchText.detail(stopwatch, now: now) {
                        Text(detail).textStyle(.caption, numeric: true).foregroundStyle(Ink.tertiary).lineLimit(1).fixedSize()
                    }
                }
                Text(Format.clock(elapsed))
                    .textStyle(.display)
                    .foregroundStyle(paused ? Ink.secondary : stopwatchTint)
                    .contentTransition(.numericText())
                StopwatchControls(model: model, stopwatch: stopwatch)
                    .padding(.leading, -Space.xs)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Pause or carry on, a lap, and reset.
struct StopwatchControls: View {
    let model: AppModel
    let stopwatch: Stopwatch

    var body: some View {
        HStack(spacing: 0) {
            IconButton(symbol: stopwatch.isRunning ? "pause.fill" : "play.fill", help: stopwatch.isRunning ? "Pause" : "Carry on",
                       size: 24, glyph: 10) { model.tools.stopwatch.toggle() }
            if stopwatch.isRunning {
                IconButton(symbol: "flag.fill", help: "Lap", size: 24, glyph: 10) { model.tools.stopwatch.lap() }
            }
            IconButton(symbol: "xmark", help: "Reset", size: 24, glyph: 10) { model.tools.stopwatch.reset() }
        }
    }
}

/// The stopwatch in Home's column; its controls when the pointer is on it.
struct StopwatchGlance: View {
    let stopwatch: Stopwatch
    let model: AppModel
    @ViewState private var hovering = false

    var body: some View {
        let paused = !stopwatch.isRunning
        TimelineView(.periodic(from: .now, by: stopwatch.isRunning ? 1 : 3600)) { ctx in
            let elapsed = stopwatch.elapsed(at: ctx.date)
            GlanceRow(title: "Stopwatch") {
                Image(systemName: "stopwatch.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(paused ? Ink.tertiary : stopwatchTint)
            } trailing: {
                Text(Format.clock(elapsed))
                    .textStyle(.body, emphasized: true, numeric: true)
                    .foregroundStyle(paused ? Ink.secondary : stopwatchTint)
                    .contentTransition(.numericText())
            } detail: {
                if hovering {
                    StopwatchControls(model: model, stopwatch: stopwatch)
                        .frame(height: 14)
                        .padding(.leading, -Space.xs - 1)
                } else {
                    Text(StopwatchText.glance(stopwatch, now: ctx.date))
                }
            }
        }
        .onHover { hovering = $0 }
    }
}

enum StopwatchText {
    /// "Paused", or the lap under way ("Lap 3") once there are laps.
    static func detail(_ s: Stopwatch, now: Date) -> String? {
        if !s.isRunning { return "Paused" }
        return s.laps.isEmpty ? nil : "Lap \(s.laps.count + 1)"
    }

    /// The glance's line: the lap under way and how long the last one took ("Lap 3 · last 4:48").
    static func glance(_ s: Stopwatch, now: Date) -> String {
        if !s.isRunning { return "Paused" }
        guard let last = s.lapDurations.last else { return "Running" }
        return "Lap \(s.laps.count + 1) · last \(Format.clock(last))"
    }
}
