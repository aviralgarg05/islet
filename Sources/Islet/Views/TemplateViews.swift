import AppKit
import IsletCore
import SwiftUI

// Live Activity templates (research report 07, §5): per-kind looks for the wings, the dropped
// pill, the sneak peek, the bubble and the expanded row. Identity sits on the left and the one
// changing value on the right. The island stays black; the tint colours only glyphs, rings,
// bars and keylines. `progress` and unknown templates fall back to the generic views.

extension AppModel {
    /// The template an activity is drawn with, or nil for the generic look.
    func visualTemplate(for a: Activity) -> ActivityTemplate? {
        let t = a.resolvedTemplate
        return t == .progress ? nil : t
    }
}

extension Color {
    /// This colour, lifted in lightness (hue kept) until it has 3:1 contrast on black.
    var readableOnBlack: Color {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return self }
        let rgba = RGBA(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent), a: Double(c.alphaComponent))
        guard rgba.contrastOnBlack < 3 else { return self }
        let lifted = rgba.readableOnBlack()
        return Color(.sRGB, red: lifted.r, green: lifted.g, blue: lifted.b, opacity: lifted.a)
    }

    init(readable hex: String?, fallback: Color) {
        self = hex.flatMap(RGBA.parse).map { $0.readableOnBlack() }.map { Color(.sRGB, red: $0.r, green: $0.g, blue: $0.b, opacity: $0.a) } ?? fallback
    }
}

/// The user's motion settings as the template views apply them.
struct TemplateMotion {
    let style: AnimationStyle

    @MainActor
    init(_ model: AppModel, systemReduceMotion: Bool) {
        if model.settings.animationStyle == .off {
            style = .off
        } else if systemReduceMotion || model.settings.reduceMotion {
            style = .minimal
        } else {
            style = model.settings.animationStyle
        }
    }

    /// Waveforms and breathing segments: off with Reduce Motion or Motion Off.
    var perpetual: Bool { style != .off && style != .minimal }
    /// Countdown rings tell the time, so they keep draining with Reduce Motion; Off freezes them.
    var drains: Bool { style != .off }
    /// Value changes: the ETA tracker glides, digits roll. Reduce Motion gets a short fade.
    var value: Animation? {
        switch style {
        case .off: return nil
        case .minimal: return .easeInOut(duration: 0.2)
        default: return .easeOut(duration: 0.6)
        }
    }
}

/// Re-renders `content` only when the activity's time-based text can change: every second for
/// clocks, once a minute (aligned to the deadline) for minute counts, never otherwise.
struct TemplateClock<Content: View>: View {
    let activity: Activity
    @ViewBuilder var content: (Date) -> Content

    var body: some View {
        if let r = activity.templateRefresh(now: Date()) {
            TimelineView(.periodic(from: r.anchor, by: r.interval)) { ctx in content(ctx.date) }
        } else {
            content(Date())
        }
    }
}

// MARK: - Building blocks

/// The template's changing value as text, rolling digits when it changes (per-second clocks
/// tick without animation, which keeps them cheap).
struct TemplateValueText: View {
    let activity: Activity
    let model: AppModel
    var size: CGFloat = 12.5
    var tint: Color?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let motion = TemplateMotion(model, systemReduceMotion: reduceMotion)
        let perSecond = activity.templateRefresh(now: Date())?.interval == 1
        TemplateClock(activity: activity) { now in
            let text = activity.templateTrailing(now: now) ?? ""
            Text(text)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint ?? model.tint(for: activity))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText(countsDown: activity.endsAt != nil))
                .animation(perSecond ? nil : motion.value, value: text)
        }
    }
}

/// A number that rolls when it changes (scores, metrics, levels).
struct RollingNumber: View {
    let text: String
    var size: CGFloat
    var weight: Font.Weight = .bold
    var color: Color = .white
    var animation: Animation?

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText())
            .animation(animation, value: text)
    }
}

/// A team's badge: its abbreviation inside a keyline in the team colour.
struct TeamBadge: View {
    let team: ActivityTeam
    var height: CGFloat
    /// Round badge for roomy layouts, a rounded tag for the narrow wings.
    var round = false

    var body: some View {
        let c = Color(readable: team.tint, fallback: .white)
        Text(team.badge)
            .font(.system(size: height * (round ? 0.34 : 0.56), weight: .heavy, design: .rounded))
            .foregroundStyle(c)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, round ? 2 : 3)
            .frame(minWidth: height, maxWidth: round ? height : height * 2.2)
            .frame(height: height)
            .overlay {
                if round {
                    Circle().stroke(c, lineWidth: 1.3)
                } else {
                    RoundedRectangle(cornerRadius: height * 0.3, style: .continuous).stroke(c, lineWidth: 1.2)
                }
            }
            .fixedSize(horizontal: !round, vertical: false)
    }
}

/// A team's badge and score for the wings: side by side when there is room, the abbreviation
/// stacked over the score in the narrow wings.
struct TeamScore: View {
    let team: ActivityTeam
    var height: CGFloat
    /// Team B, on the right: score first.
    var trailing = false
    var animation: Animation?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                if trailing {
                    score(height * 0.9)
                    TeamBadge(team: team, height: height)
                } else {
                    TeamBadge(team: team, height: height)
                    score(height * 0.9)
                }
            }
            VStack(alignment: trailing ? .trailing : .leading, spacing: -1) {
                Text(team.badge)
                    .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(readable: team.tint, fallback: .white))
                    .lineLimit(1)
                score(height * 0.8)
            }
        }
    }

    private func score(_ size: CGFloat) -> some View {
        RollingNumber(text: team.score ?? "0", size: size, animation: animation).fixedSize()
    }
}

/// Transit line badge ("N") in a keyline, or the leg's glyph when there is no line.
struct RouteMark: View {
    let route: ActivityRoute
    var height: CGFloat
    var tint: Color

    var body: some View {
        if let line = route.line, !line.isEmpty {
            let c = Color(readable: route.lineTint, fallback: tint)
            Text(line)
                .font(.system(size: height * 0.62, weight: .heavy, design: .rounded))
                .foregroundStyle(c)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 3)
                .frame(minWidth: height)
                .frame(height: height)
                .overlay(RoundedRectangle(cornerRadius: height * 0.28, style: .continuous).stroke(c, lineWidth: 1.3))
                .fixedSize()
        } else {
            Image(systemName: route.symbol)
                .font(.system(size: height * 0.8, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: height, height: height)
        }
    }
}

/// Lyft's 10-step track: segments filled up to the tracker, the vehicle riding it, a pin at the end.
struct EtaTrack: View {
    var progress: Double
    var tint: Color
    var tracker: ActivityIcon
    var glyph: CGFloat = 11
    var animation: Animation?

    var body: some View {
        GeometryReader { geo in
            let trackWidth = max(20, geo.size.width - glyph - 3)
            let x = min(max(0, trackWidth * progress - glyph / 2), trackWidth - glyph)
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    ForEach(0..<10, id: \.self) { i in
                        Capsule().fill(Double(i) + 0.5 <= progress * 10 ? tint : Color.white.opacity(0.18))
                    }
                }
                .frame(width: trackWidth, height: 3)
                IconView(icon: tracker, size: glyph, tint: .white)
                    .background(Circle().fill(Color.black).padding(-1.5))
                    .offset(x: x)
                    .animation(animation, value: progress)
                Image(systemName: "mappin")
                    .font(.system(size: glyph * 0.8, weight: .semibold))
                    .foregroundStyle(Color.islandSecondary)
                    .frame(width: glyph)
                    .offset(x: trackWidth + 3)
            }
            .frame(height: geo.size.height)
        }
        .frame(height: glyph + 2)
    }
}

/// Stages as dots on a bar: done filled, current ringed, the leg in progress breathing, future dim.
struct MilestoneBar: View {
    var count: Int
    var current: Int
    var tint: Color
    var labels: [String]? = nil
    var dot: CGFloat = 7
    var animate: Bool
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        let n = max(1, min(count, TemplateLimits.stages))
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(0..<n, id: \.self) { i in
                    ZStack {
                        HStack(spacing: 0) {
                            leg(i == 0 ? nil : i).frame(maxWidth: .infinity)
                            leg(i == n - 1 ? nil : i + 1).frame(maxWidth: .infinity)
                        }
                        stageDot(i + 1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: dot + 2)
            if let labels, !labels.isEmpty {
                HStack(spacing: 0) {
                    ForEach(0..<n, id: \.self) { i in
                        Text(i < labels.count ? labels[i] : "")
                            .font(.system(size: 8.5, weight: i + 1 == current ? .bold : .medium))
                            .foregroundStyle(i + 1 == current ? Color.white : Color.islandTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    /// Half of the leg that ends at stage `to` (1-based): complete once reached, breathing while under way.
    @ViewBuilder
    private func leg(_ to: Int?) -> some View {
        if let to {
            let stageTo = to + 1
            if current >= stageTo {
                Capsule().fill(tint).frame(height: 2.5)
            } else if current == stageTo - 1 {
                if animate && !snapshotMode {
                    BreathingCapsule(color: NSColor(tint), animate: true).frame(height: 2.5)
                } else {
                    Capsule().fill(tint.opacity(0.55)).frame(height: 2.5)
                }
            } else {
                Capsule().fill(Color.white.opacity(0.16)).frame(height: 2.5)
            }
        } else {
            Color.clear.frame(height: 2.5)
        }
    }

    @ViewBuilder
    private func stageDot(_ stage: Int) -> some View {
        if stage < current {
            Circle().fill(tint).frame(width: dot, height: dot)
        } else if stage == current {
            Circle().fill(tint).frame(width: dot + 2, height: dot + 2)
                .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1.2))
        } else {
            Circle().stroke(Color.white.opacity(0.35), lineWidth: 1.2).frame(width: dot - 1, height: dot - 1)
                .background(Circle().fill(Color.black))
        }
    }
}

/// Airport code over its time; the time turns amber when the flight is delayed.
struct AirportColumn: View {
    var code: String
    var time: Date?
    var delayed: Bool
    var alignment: HorizontalAlignment
    var size: CGFloat = 14

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(code)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            if let time {
                Text(time.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: size * 0.7, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(delayed ? Color.orange : Color.islandSecondary)
                    .contentTransition(.numericText())
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// A thin line with the plane at the share of the flight flown.
struct FlightLine: View {
    var progress: Double?
    var tint: Color
    var number: String?

    var body: some View {
        VStack(spacing: 1) {
            if let number {
                Text(number)
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.islandTertiary)
                    .lineLimit(1)
            }
            GeometryReader { geo in
                let p = progress ?? 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18)).frame(height: 1.5)
                    Capsule().fill(tint).frame(width: max(0, geo.size.width * p), height: 1.5)
                    Image(systemName: "airplane")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(tint)
                        .offset(x: min(max(0, geo.size.width * p - 5), geo.size.width - 10))
                }
                .frame(height: geo.size.height)
            }
            .frame(height: 10)
        }
        .frame(minWidth: 24)
    }
}

/// Flight status in a keyline chip: green on time, amber delayed, red cancelled.
struct StatusChip: View {
    var text: String
    var kind: ActivityFlight.StatusKind

    var body: some View {
        let c: Color = kind == .cancelled ? .red : kind == .delayed ? .orange : .green
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(c)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .overlay(Capsule().stroke(c.opacity(0.8), lineWidth: 1))
    }
}

/// A ring filled to a level, with the percentage inside.
struct GaugeRing: View {
    var level: Double?
    var tint: Color
    var size: CGFloat
    var lineWidth: CGFloat
    var showsValue = true
    var animation: Animation?

    var body: some View {
        ZStack {
            ProgressRing(progress: level, tint: tint, size: size, lineWidth: lineWidth)
                .animation(animation, value: level)
            if showsValue, let level {
                RollingNumber(text: "\(Int((level * 100).rounded()))", size: size * 0.36, animation: animation)
                    .frame(width: size - 2 * lineWidth - 2)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Timer ring: drains to `endsAt` by Core Animation; a quiet full ring for a count-up.
struct TimerRing: View {
    let activity: Activity
    var tint: Color
    var size: CGFloat
    var lineWidth: CGFloat
    var motion: TemplateMotion
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        Group {
            if let end = activity.endsAt, let f = activity.timerFractionLeft(now: Date()) {
                if snapshotMode {
                    ZStack {
                        Circle().stroke(tint.opacity(0.25), lineWidth: lineWidth)
                        Circle().trim(from: 0, to: f)
                            .stroke(end.timeIntervalSinceNow <= 10 ? Color.red : tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .padding(lineWidth / 2)
                } else {
                    CountdownRing(endsAt: end, fraction: f, color: NSColor(tint), lineWidth: lineWidth, animate: motion.drains)
                }
            } else {
                Circle().stroke(tint.opacity(0.4), lineWidth: lineWidth).padding(lineWidth / 2)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Voice waveform (Core Animation; static bars in snapshots and with motion off).
struct VoiceWave: View {
    var tint: Color
    var active: Bool
    var width: CGFloat
    var height: CGFloat
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        Group {
            if snapshotMode {
                HStack(spacing: 1.5) {
                    ForEach(Array(WaveformNSView.rest.prefix(5).enumerated()), id: \.offset) { _, h in
                        Capsule().fill(tint).frame(height: height * h * (active ? 1 : 0.5))
                    }
                }
            } else {
                Waveform(color: NSColor(tint), active: active)
            }
        }
        .frame(width: width, height: height)
    }
}

/// "Ends 12:40" / "Started 12:02" for a timer without a subtitle.
private func timeLine(_ a: Activity) -> String? {
    if let end = a.endsAt { return "Ends \(end.formatted(date: .omitted, time: .shortened))" }
    if let start = a.startedAt { return "Started \(start.formatted(date: .omitted, time: .shortened))" }
    return nil
}

// MARK: - Wings and the dropped pill

/// Left of the closed island: what the activity is.
struct TemplateLeading: View {
    let activity: Activity
    let model: AppModel
    /// The caller's tint, used as is by the generic look and lifted for templates.
    var tint: Color
    var size: CGFloat = 15
    /// Dropped pill and sneak header: both score sides get the same width.
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let a = activity
        let base = self.tint
        let tint = base.readableOnBlack
        let motion = TemplateMotion(model, systemReduceMotion: reduceMotion)
        switch model.visualTemplate(for: a) {
        case .stages?:
            IconView(icon: a.currentStageSymbol ?? model.icon(for: a), size: size, tint: tint)
        case .flight?:
            TemplateClock(activity: a) { now in
                let phase = a.flightPhase(now: now)
                HStack(spacing: 3) {
                    Image(systemName: phase == "airborne" ? "airplane" : phase == "landed" ? "airplane.arrival" : "airplane.departure")
                        .font(.system(size: size * 0.8, weight: .semibold))
                        .foregroundStyle(tint)
                    if phase == nil || phase == "predeparture" || phase == "boarding", let gate = a.flight?.gate {
                        Text(gate)
                            .font(.system(size: size * 0.75, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        case .route?:
            if let route = a.route {
                RouteMark(route: route, height: size + 1, tint: tint)
            } else {
                IconView(icon: model.icon(for: a), size: size, tint: tint)
            }
        case .score?:
            if let teams = a.teams, teams.count == 2 {
                TeamScore(team: teams[0], height: size, animation: motion.value)
                    .frame(minWidth: 0, maxWidth: compact ? 58 : .infinity, alignment: .leading)
            } else {
                IconView(icon: model.icon(for: a), size: size, tint: tint)
            }
        case .timer? where a.endsAt != nil || a.startedAt != nil:
            ZStack {
                TimerRing(activity: a, tint: tint, size: size + 4, lineWidth: 1.8, motion: motion)
                IconView(icon: model.icon(for: a), size: size - 6, tint: tint)
            }
        case .gauge? where a.clampedProgress != nil:
            GaugeRing(level: a.clampedProgress, tint: tint, size: size + 5, lineWidth: 2, showsValue: size + 5 >= 19, animation: motion.value)
        case nil:
            IconView(icon: model.icon(for: a), size: size, tint: base)
        default:
            IconView(icon: model.icon(for: a), size: size, tint: tint)
        }
    }
}

/// Right of the closed island: the one value that changes.
struct TemplateTrailing: View {
    let activity: Activity
    let model: AppModel
    /// The caller's tint, used as is by the generic look and lifted for templates.
    var tint: Color
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var size: CGFloat { compact ? 11.5 : 12.5 }

    var body: some View {
        let a = activity
        let base = self.tint
        let tint = base.readableOnBlack
        let motion = TemplateMotion(model, systemReduceMotion: reduceMotion)
        switch model.visualTemplate(for: a) {
        case nil:
            ActivityTrailing(activity: a, tint: base, compact: compact)
        case .eta? where a.trailing == nil && a.phase == "arrived":
            let here = Text("Here").font(.system(size: size, weight: .semibold, design: .rounded)).foregroundStyle(tint)
                .lineLimit(1).fixedSize()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 3) {
                    IconView(icon: a.trackerIcon ?? model.icon(for: a), size: size, tint: tint)
                    here
                }
                here
            }
        case .score? where a.trailing == nil && a.teams?.count == 2:
            TeamScore(team: a.teams![1], height: compact ? 14 : 15, trailing: true, animation: motion.value)
                .frame(minWidth: 0, maxWidth: compact ? 58 : .infinity, alignment: .trailing)
        case .liveAudio? where a.templateTrailing(now: Date()) == nil:
            VoiceWave(tint: tint, active: a.state == .running && motion.perpetual, width: 18, height: 13)
        case .media? where a.templateTrailing(now: Date()) == nil:
            PlayingIndicator(tint: tint, playing: a.state == .running && motion.perpetual)
                .scaleEffect(compact ? 0.85 : 1)
        default:
            TemplateValueText(activity: a, model: model, size: size, tint: tint)
        }
    }
}

/// Middle of the dropped pill: the title, or what matters more for the template.
struct TemplateDropCenter: View {
    let activity: Activity
    let model: AppModel

    var body: some View {
        let a = activity
        switch model.visualTemplate(for: a) {
        case .score? where a.teams?.count == 2:
            Text(a.period ?? a.title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.islandSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        case .flight?:
            title(flightTitle(a) ?? a.title)
        case .route?:
            title(a.route?.instruction ?? a.title)
        case .stages?:
            title(a.currentStageLabel ?? a.title)
        default:
            title(a.title)
        }
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
    }
}

private func flightTitle(_ a: Activity) -> String? {
    guard let f = a.flight, let from = f.from, let to = f.to else { return nil }
    return "\(from) → \(to)"
}

// MARK: - Bubble

/// Minimal view inside a bubble: one glyph, a ring, or a few characters.
struct TemplateBubble: View {
    let activity: Activity
    let model: AppModel
    let diameter: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let a = activity
        let tint = model.tint(for: a)
        let motion = TemplateMotion(model, systemReduceMotion: reduceMotion)
        let ring = diameter - 8
        let glyph = diameter - 17
        let plain = IconView(icon: model.icon(for: a), size: diameter - 13, tint: tint)
        TemplateClock(activity: a) { now in
            let text = a.minimalText(now: now)
            switch model.visualTemplate(for: a) {
            case .eta? where a.trackProgress(now: now) != nil:
                ZStack {
                    ProgressRing(progress: a.trackProgress(now: now), tint: tint, size: ring, lineWidth: 2.2)
                        .animation(motion.value, value: a.trackProgress(now: now))
                    if let text { label(text, color: .white) } else { IconView(icon: a.trackerIcon ?? model.icon(for: a), size: glyph, tint: tint) }
                }
            case .stages? where a.stageCount != nil:
                ZStack {
                    ProgressRing(progress: stageFraction(a), tint: tint, size: ring, lineWidth: 2.2)
                    IconView(icon: a.currentStageSymbol ?? model.icon(for: a), size: glyph, tint: tint)
                }
            case .flight? where a.flight != nil:
                ZStack {
                    ProgressRing(progress: a.flight?.progress(now: now) ?? 0, tint: tint, size: ring, lineWidth: 2.2)
                    Image(systemName: "airplane").font(.system(size: glyph * 0.8, weight: .semibold)).foregroundStyle(tint)
                }
            case .route?:
                if let text {
                    ringed(label(text, color: tint), tint: tint, ring: ring)
                } else if let route = a.route {
                    RouteMark(route: route, height: glyph, tint: tint)
                } else {
                    plain
                }
            case .score?:
                if let text {
                    label(text, color: .white)
                } else if let team = a.teams?.first {
                    TeamBadge(team: team, height: ring - 2, round: true)
                } else {
                    plain
                }
            case .timer? where a.endsAt != nil || a.startedAt != nil:
                ZStack {
                    TimerRing(activity: a, tint: tint, size: ring, lineWidth: 2.2, motion: motion)
                    if let text { label(text, color: .white) }
                }
            case .workout?:
                if let end = a.endsAt, end > now {
                    ZStack {
                        TimerRing(activity: a, tint: tint, size: ring, lineWidth: 2.2, motion: motion)
                        if let text { label(text, color: .white) }
                    }
                } else if let text {
                    ringed(label(text, color: tint), tint: tint, ring: ring)
                } else {
                    plain
                }
            case .gauge? where a.clampedProgress != nil:
                GaugeRing(level: a.clampedProgress, tint: tint, size: ring, lineWidth: 2.2, animation: motion.value)
            case .liveAudio?:
                if let text {
                    label(text, color: tint)
                } else {
                    VoiceWave(tint: tint, active: a.state == .running && motion.perpetual, width: diameter * 0.5, height: diameter * 0.4)
                }
            case .agent?:
                IconView(icon: model.icon(for: a), size: diameter - 13, tint: tint)
                    .overlay(alignment: .bottomTrailing) {
                        Circle().fill(stateColor(a.state, tint: tint)).frame(width: 6, height: 6)
                            .overlay(Circle().stroke(Color.black, lineWidth: 1.2))
                    }
            default:
                if let text { ringed(label(text, color: tint), tint: tint, ring: ring) } else { plain }
            }
        }
    }

    private func ringed<V: View>(_ content: V, tint: Color, ring: CGFloat) -> some View {
        ZStack {
            Circle().stroke(tint.opacity(0.3), lineWidth: 1.5).frame(width: ring - 1, height: ring - 1)
            content
        }
    }

    private func label(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: diameter * 0.3, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .frame(width: diameter - 11)
            .contentTransition(.numericText())
    }

    private func stageFraction(_ a: Activity) -> Double {
        guard let n = a.stageCount, n > 0, let i = a.currentStage else { return 0 }
        return Double(i) / Double(n)
    }

    private func stateColor(_ s: ActivityState, tint: Color) -> Color {
        switch s {
        case .waiting, .warning: return .orange
        case .success: return .green
        case .failure: return .red
        case .info, .running: return tint
        }
    }
}

// MARK: - Sneak peek

/// The detail under the title in a sneak peek. `roomy` is the taller dropped layout.
struct TemplateDetail<Fallback: View>: View {
    let activity: Activity
    let model: AppModel
    var roomy = false
    @ViewBuilder var fallback: Fallback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let a = activity
        let tint = model.tint(for: a)
        let motion = TemplateMotion(model, systemReduceMotion: reduceMotion)
        switch model.visualTemplate(for: a) {
        case .eta?:
            TemplateClock(activity: a) { now in
                HStack(spacing: 7) {
                    if let sub = a.subtitle { secondary(sub).layoutPriority(1) }
                    if let p = a.trackProgress(now: now) {
                        EtaTrack(progress: p, tint: tint, tracker: a.trackerIcon ?? model.icon(for: a), animation: motion.value)
                    }
                }
            }
        case .stages? where a.stageCount != nil:
            VStack(alignment: .leading, spacing: 2) {
                if roomy || a.stageLabels == nil, let sub = a.subtitle { secondary(sub) }
                MilestoneBar(count: a.stageCount ?? 1, current: a.currentStage ?? 1, tint: tint, labels: a.stageLabels,
                             dot: 6, animate: motion.perpetual)
            }
        case .flight? where a.flight != nil:
            FlightBoard(activity: a, tint: tint, size: 11.5)
        case .route? where a.route != nil:
            HStack(spacing: 6) {
                if a.route?.line != nil { Image(systemName: a.route!.symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(tint) }
                secondary([a.route?.instruction, a.subtitle].compactMap { $0 }.first ?? "")
            }
        case .score? where a.teams?.count == 2:
            TemplateClock(activity: a) { now in
                let clock = a.endsAt != nil || a.startedAt != nil ? a.trailingText(now: now) : nil
                HStack(spacing: 6) {
                    if let head = [a.period, clock].compactMap({ $0 }).joined(separator: " ").nilIfEmpty {
                        Text(head).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                            .lineLimit(1).fixedSize()
                    }
                    if let sub = a.subtitle { secondary(sub) }
                }
            }
        case .timer?:
            if let line = a.subtitle ?? timeLine(a) { secondary(line) }
        case .workout? where a.metrics != nil:
            MetricsLine(metrics: a.metrics ?? [], size: 12.5, motion: motion)
        case .gauge? where a.clampedProgress != nil:
            TemplateClock(activity: a) { now in
                HStack(spacing: 7) {
                    LevelBar(value: a.clampedProgress ?? 0, tint: tint, height: 4).animation(motion.value, value: a.clampedProgress)
                    if let line = a.subtitle ?? a.endsAt.map({ "Full in " + TemplateFormat.minutes(until: $0, now: now) }) {
                        secondary(line).layoutPriority(1)
                    }
                }
            }
        case .liveAudio?:
            HStack(spacing: 7) {
                if let sub = a.subtitle { secondary(sub) }
                Spacer(minLength: 0)
                VoiceWave(tint: tint, active: a.state == .running && motion.perpetual, width: 24, height: 12)
            }
        case .agent? where a.subtitle == nil && a.phase != nil:
            VStack(alignment: .leading, spacing: 2) {
                secondary(a.phase ?? "")
                fallback
            }
        default:
            fallback
        }
    }

    private func secondary(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(Color.islandSecondary).lineLimit(1)
    }
}

/// "SFO 08:05 ✈── JFK 16:40 [On time]".
struct FlightBoard: View {
    let activity: Activity
    var tint: Color
    var size: CGFloat

    var body: some View {
        let f = activity.flight ?? ActivityFlight()
        let delayed = f.statusKind == .delayed
        TemplateClock(activity: activity) { now in
            HStack(spacing: 6) {
                if let from = f.from { AirportColumn(code: from, time: f.departs, delayed: delayed, alignment: .leading, size: size) }
                FlightLine(progress: f.progress(now: now), tint: tint, number: f.number)
                if let to = f.to { AirportColumn(code: to, time: f.arrives, delayed: delayed, alignment: .trailing, size: size) }
                if let status = f.status { StatusChip(text: status, kind: f.statusKind).fixedSize() }
            }
        }
    }
}

/// Badge, score · period · score, badge, with both sides the same width.
struct ScoreLine: View {
    let activity: Activity
    var badge: CGFloat
    var score: CGFloat
    var round = false
    var motion: TemplateMotion

    var body: some View {
        let teams = activity.teams ?? []
        if teams.count == 2 {
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    TeamBadge(team: teams[0], height: badge, round: round)
                    RollingNumber(text: teams[0].score ?? "0", size: score, animation: motion.value)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 0) {
                    if let period = activity.period {
                        Text(period).font(.system(size: 10.5, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                    }
                    if activity.endsAt != nil || activity.startedAt != nil {
                        TemplateClock(activity: activity) { now in
                            Text(activity.trailingText(now: now) ?? "")
                                .font(.system(size: 9.5, weight: .medium, design: .rounded)).monospacedDigit()
                                .foregroundStyle(Color.islandSecondary)
                        }
                    }
                }
                .lineLimit(1)
                .fixedSize()
                HStack(spacing: 6) {
                    RollingNumber(text: teams[1].score ?? "0", size: score, animation: motion.value)
                    TeamBadge(team: teams[1], height: badge, round: round)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

/// Up to three live values: "5.2 km   5:31 /km   148 bpm".
struct MetricsLine: View {
    let metrics: [ActivityMetric]
    var size: CGFloat
    var motion: TemplateMotion

    var body: some View {
        HStack(spacing: 9) {
            ForEach(Array(metrics.prefix(TemplateLimits.metrics).enumerated()), id: \.offset) { _, m in
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    RollingNumber(text: m.value, size: size, weight: .semibold, animation: motion.value)
                    if let unit = m.unit ?? m.label {
                        Text(unit).font(.system(size: size * 0.72, weight: .medium)).foregroundStyle(Color.islandTertiary).lineLimit(1)
                    }
                }
                .fixedSize()
            }
        }
    }
}

// MARK: - Expanded row

/// A row in the expanded island drawn with the activity's template; the generic row otherwise.
struct TemplateRow: View {
    let activity: Activity
    let model: AppModel
    @ViewState private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let t = model.visualTemplate(for: activity), t != .media, t != .agent, hasData(t) {
            let tint = model.tint(for: activity)
            HStack(spacing: 10) {
                card(t, tint: tint, motion: TemplateMotion(model, systemReduceMotion: reduceMotion))
                ForEach(Array(activity.actions.prefix(2).enumerated()), id: \.offset) { _, action in
                    Button(action.title) { model.perform(action, activityID: activity.id) }
                        .buttonStyle(CapsuleButtonStyle(tint: tint))
                }
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
        } else {
            ActivityRow(activity: activity, model: model)
        }
    }

    /// The richer row needs the template's own data; without it the generic row reads better.
    private func hasData(_ t: ActivityTemplate) -> Bool {
        switch t {
        case .flight: return activity.flight != nil
        case .route: return activity.route != nil
        case .score: return activity.teams?.count == 2
        case .stages: return activity.stageCount != nil
        case .workout: return activity.metrics != nil || activity.startedAt != nil
        case .gauge: return activity.clampedProgress != nil
        default: return true
        }
    }

    @ViewBuilder
    private func card(_ t: ActivityTemplate, tint: Color, motion: TemplateMotion) -> some View {
        let a = activity
        switch t {
        case .flight:
            FlightBoard(activity: a, tint: tint, size: 14)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .score:
            ScoreLine(activity: a, badge: 24, score: 19, round: true, motion: motion)
        case .timer:
            HStack(spacing: 10) {
                ZStack {
                    TimerRing(activity: a, tint: tint, size: 28, lineWidth: 2.5, motion: motion)
                    IconView(icon: model.icon(for: a), size: 13, tint: tint)
                }
                titles(a.title, a.subtitle ?? timeLine(a))
                Spacer(minLength: 4)
                TemplateValueText(activity: a, model: model, size: 17, tint: tint)
            }
        case .gauge:
            HStack(spacing: 10) {
                GaugeRing(level: a.clampedProgress, tint: tint, size: 30, lineWidth: 3, animation: motion.value)
                TemplateClock(activity: a) { now in
                    titles(a.title, a.subtitle ?? a.endsAt.map { "Full in " + TemplateFormat.minutes(until: $0, now: now) })
                }
                Spacer(minLength: 4)
                if let metrics = a.metrics {
                    VStack(alignment: .trailing, spacing: 1) {
                        ForEach(Array(metrics.prefix(2).enumerated()), id: \.offset) { _, m in
                            RollingNumber(text: m.text, size: 11.5, weight: .semibold, animation: motion.value)
                        }
                    }
                    .fixedSize()
                } else {
                    TemplateValueText(activity: a, model: model, size: 13, tint: tint)
                }
            }
        default:
            HStack(spacing: 10) {
                leadingMark(t, tint: tint)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(rowTitle(t)).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        if t == .stages, let label = activity.currentStageLabel {
                            Text(label).font(.system(size: 11)).foregroundStyle(Color.islandSecondary).lineLimit(1).layoutPriority(1)
                        }
                    }
                    secondLine(t, tint: tint, motion: motion)
                }
                Spacer(minLength: 4)
                trailing(t, tint: tint, motion: motion).fixedSize().layoutPriority(1)
            }
        }
    }

    private func titles(_ title: String, _ subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            if let subtitle {
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Color.islandSecondary).lineLimit(1)
            }
        }
    }

    private func rowTitle(_ t: ActivityTemplate) -> String {
        t == .route ? activity.route?.instruction ?? activity.title : activity.title
    }

    @ViewBuilder
    private func leadingMark(_ t: ActivityTemplate, tint: Color) -> some View {
        switch t {
        case .stages: IconView(icon: activity.currentStageSymbol ?? model.icon(for: activity), size: 18, tint: tint)
        case .route: RouteMark(route: activity.route ?? ActivityRoute(), height: 18, tint: tint)
        default: IconView(icon: model.icon(for: activity), size: 18, tint: tint)
        }
    }

    @ViewBuilder
    private func secondLine(_ t: ActivityTemplate, tint: Color, motion: TemplateMotion) -> some View {
        let a = activity
        switch t {
        case .eta:
            TemplateClock(activity: a) { now in
                if let p = a.trackProgress(now: now) {
                    EtaTrack(progress: p, tint: tint, tracker: a.trackerIcon ?? model.icon(for: a), glyph: 10, animation: motion.value)
                } else if let sub = a.subtitle {
                    Text(sub).font(.system(size: 11)).foregroundStyle(Color.islandSecondary).lineLimit(1)
                }
            }
        case .stages:
            MilestoneBar(count: a.stageCount ?? 1, current: a.currentStage ?? 1, tint: tint, dot: 6, animate: motion.perpetual)
        case .workout:
            if let metrics = a.metrics {
                ViewThatFits(in: .horizontal) {
                    ForEach((1...min(metrics.count, TemplateLimits.metrics)).reversed(), id: \.self) { n in
                        MetricsLine(metrics: Array(metrics.prefix(n)), size: 11.5, motion: motion)
                    }
                }
            } else if let sub = a.subtitle {
                Text(sub).font(.system(size: 11)).foregroundStyle(Color.islandSecondary).lineLimit(1)
            }
        case .route:
            let line = [a.subtitle, a.route?.instruction != nil ? a.title : nil].compactMap { $0 }.first
            if let line { Text(line).font(.system(size: 11)).foregroundStyle(Color.islandSecondary).lineLimit(1) }
        default:
            if let sub = a.subtitle {
                Text(sub).font(.system(size: 11)).foregroundStyle(Color.islandSecondary).lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func trailing(_ t: ActivityTemplate, tint: Color, motion: TemplateMotion) -> some View {
        switch t {
        case .liveAudio:
            HStack(spacing: 7) {
                VoiceWave(tint: tint, active: activity.state == .running && motion.perpetual, width: 22, height: 14)
                if activity.templateTrailing(now: Date()) != nil { TemplateValueText(activity: activity, model: model, size: 12.5, tint: tint) }
            }
        case .eta where activity.trailing == nil && activity.phase == "arrived":
            TemplateTrailing(activity: activity, model: model, tint: tint)
        case .eta where activity.subtitle != nil && activity.trackProgress(now: Date()) != nil:
            VStack(alignment: .trailing, spacing: 1) {
                TemplateValueText(activity: activity, model: model, size: 13, tint: tint)
                Text(activity.subtitle ?? "").font(.system(size: 10.5)).foregroundStyle(Color.islandSecondary).lineLimit(1)
            }
        default:
            TemplateValueText(activity: activity, model: model, size: 13, tint: tint)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
