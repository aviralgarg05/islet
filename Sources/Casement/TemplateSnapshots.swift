import AppKit
import CasementCore
import SwiftUI

/// One snapshot sheet per Live Activity template and size preset: the closed island with full,
/// narrow and icon-only wings, the sneak peek with full and icon-only wings, the bubble at each
/// diameter and the expanded row. Rendered by `Casement --snapshot <dir>` into `<dir>/templates/`.
@MainActor
enum TemplateSnapshots {
    /// A realistic activity per template, with the moment it was first sent.
    static func demos(now: Date) -> [(name: String, spec: ActivitySpec, sentAt: Date)] {
        func spec(_ id: String, _ source: String, _ title: String, _ subtitle: String?, _ icon: String, _ tint: String,
                  _ template: ActivityTemplate, edit: (inout ActivitySpec) -> Void = { _ in }) -> ActivitySpec {
            var s = ActivitySpec(id: "tpl-" + id, source: source, title: title, subtitle: subtitle, icon: .symbol(icon),
                                 state: .running, tint: tint, sneak: false)
            s.template = template.rawValue
            edit(&s)
            return s
        }
        return [
            ("eta", spec("eta", "com.zimride.instant", "Grey Prius · 7ABC123", "Arriving", "car.fill", "#FF00BF", .eta) {
                $0.trackerIcon = .symbol("car.fill")
                $0.phase = "enroute"
                $0.endsAt = now.addingTimeInterval(250)
            }, now.addingTimeInterval(-360)),
            ("stages", spec("stages", "bundl.swiggy", "Swiggy", "Your order is being prepared", "takeoutbag.and.cup.and.straw.fill", "#FC8019", .stages) {
                $0.stageLabels = ["Placed", "Preparing", "On the way", "Delivered"]
                $0.stageSymbols = [.symbol("checkmark.circle.fill"), .symbol("frying.pan.fill"), .symbol("bicycle"), .symbol("house.fill")]
                $0.steps = 4
                $0.step = 2
                $0.endsAt = now.addingTimeInterval(18 * 60)
            }, now),
            ("flight", spec("flight", "com.united.UnitedCustomerFacingIPhone", "UA 1234 to New York", "Boarding starts at 08:35",
                            "airplane", "#005DAA", .flight) {
                $0.flight = ActivityFlight(number: "UA 1234", from: "SFO", to: "JFK", departs: now.addingTimeInterval(42 * 60),
                                           arrives: now.addingTimeInterval(6 * 3600), gate: "B22", terminal: "3", seat: "14C", status: "On time")
            }, now),
            ("route", spec("route", "com.samvermette.Transit", "N Judah to Ocean Beach", nil, "tram.fill", "#30B566", .route) {
                $0.route = ActivityRoute(mode: "tram", line: "N", lineTint: "#0A84FF", stopsLeft: 3, instruction: "Get off at Carl & Cole")
                $0.endsAt = now.addingTimeInterval(7 * 60)
            }, now),
            ("score", spec("score", "com.espn.ScoreCenter", "Lakers at Celtics", "Tatum makes 3-pt jump shot", "sportscourt.fill", "#CC0000", .score) {
                $0.teams = [ActivityTeam(abbr: "LAL", name: "Lakers", score: "102", tint: "#FDB927"),
                            ActivityTeam(abbr: "BOS", name: "Celtics", score: "98", tint: "#007A33")]
                $0.period = "Q4"
                $0.endsAt = now.addingTimeInterval(151)
            }, now),
            ("timer", spec("timer", "timer", "Tea", "Green tea, 80 °C", "cup.and.saucer.fill", "orange", .timer) {
                $0.endsAt = now.addingTimeInterval(272)
            }, now.addingTimeInterval(-28)),
            ("workout", spec("workout", "com.strava.stravaride", "Morning run", nil, "figure.run", "#FC4C02", .workout) {
                $0.startedAt = now.addingTimeInterval(-1454)
                $0.metrics = [ActivityMetric(label: "distance", value: "5.2", unit: "km"),
                              ActivityMetric(label: "pace", value: "5:31", unit: "/km"),
                              ActivityMetric(label: "heart", value: "148", unit: "bpm")]
            }, now),
            ("gauge", spec("gauge", "com.teslamotors.TeslaApp", "Supercharging", nil, "bolt.car.fill", "#E82127", .gauge) {
                $0.progress = 0.72
                $0.endsAt = now.addingTimeInterval(32 * 60)
                $0.metrics = [ActivityMetric(value: "150", unit: "kW"), ActivityMetric(value: "$7.40")]
            }, now),
            ("live-audio", spec("audio", "com.apple.FaceTime", "FaceTime", "Mum", "video.fill", "green", .liveAudio) {
                $0.startedAt = now.addingTimeInterval(-754)
            }, now),
            ("media", spec("media", "iphone", "Midnight City", "M83", "music.note", "#FA2D48", .media), now),
            ("agent", spec("agent", "com.github.stormbreaker.prod", "Fix login flow", nil, "arrow.triangle.pull", "#24292F", .agent) {
                $0.phase = "Testing"
                $0.steps = 7
                $0.step = 3
            }, now),
            ("progress", spec("progress", "ci", "Release build", "Compiling 142/310", "hammer.fill", "orange", .progress) {
                $0.progress = 0.46
            }, now),
            // Later phases of the same kinds.
            ("eta-arrived", spec("eta2", "com.zimride.instant", "Grey Prius · 7ABC123", "Your driver is here", "car.fill", "#FF00BF", .eta) {
                $0.trackerIcon = .symbol("car.fill")
                $0.phase = "arrived"
                $0.progress = 1
            }, now),
            ("flight-airborne", spec("flight2", "com.flightyapp.flighty", "BA 287 to San Francisco", nil, "airplane", "#0A84FF", .flight) {
                $0.flight = ActivityFlight(number: "BA 287", from: "LHR", to: "SFO", departs: now.addingTimeInterval(-4 * 3600),
                                           arrives: now.addingTimeInterval(72 * 60), status: "Delayed 25 min", carousel: "7")
            }, now),
            // Mirrored from the menu bar: a template from the catalogue, but only text to fill it.
            ("mirrored-uber", mirrored("Uber", "Arriving · 4 min"), now),
            ("mirrored-espn", mirrored("ESPN", "IND 245/3 · AUS 198"), now),
        ]
    }

    private static func mirrored(_ app: String, _ detail: String) -> ActivitySpec {
        let m = MirroredLiveActivity(key: "snapshot-" + app, appName: app, detail: detail)
        return MenuBarLiveActivities.activity(for: m, look: LiveActivityCatalog.look(for: app).map { ($0.symbol, $0.tint) }, isNew: false)
    }

    static func render(to dir: URL, model: AppModel) {
        let out = dir.appendingPathComponent("templates")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let now = Date()
        var center = ActivityCenter()
        let activities = demos(now: now).map { d in (d.name, try! center.apply(d.spec, now: d.sentAt)) }
        let savedPreset = model.settings.sizePreset
        model.settings.maxConcurrent = 3

        for preset in [SizePreset.compact, .standard] {
            model.settings.sizePreset = preset
            let size = CGSize(width: model.settings.expandedSize.width, height: model.settings.expandedSize.height)
            let metrics = NotchGeometry.metrics(for: Snapshots.screen, expandedSize: size, wingWidth: model.settings.effectiveWingWidth)
            let full = ClosedPlacement(wing: metrics.wingWidth, slack: .infinity)
            let narrow = ClosedPlacement.unmeasured(.auto, wing: metrics.wingWidth, hasMenuBar: true)
            let iconOnly = ClosedPlacement(wing: MenuBarLayoutEngine.iconOnlyWing, slack: 0)
            let rowWidth = min(260, (metrics.expanded.width - 36 - 16) * 0.5)

            for (name, a) in activities {
                var parts: [(String, NSImage)] = []
                func island(_ label: String, _ p: IslandPresentation, _ placement: ClosedPlacement, height: CGFloat) {
                    model.forcedPresentation = p
                    model.closedPlacements[1] = placement
                    let view = IslandView(model: model, display: 1, metrics: metrics)
                        .frame(width: 760, height: height)
                        .background(Snapshots.backdrop(metrics: metrics))
                    if let img = image(view) { parts.append((label, img)) }
                }
                let closed = IslandPresentation.compact(.activity(a, others: 0))
                island("wings, \(Int(full.wing)) pt", closed, full, height: 44)
                island("wings, \(Int(narrow.wing)) pt (menu bar not measured)", closed, narrow, height: 44)
                island("wings, \(Int(iconOnly.wing)) pt (crowded menu bar)", closed, iconOnly, height: 44)
                island("sneak peek", .sneak(a), full, height: 84)
                island("sneak peek, \(Int(iconOnly.wing)) pt wings", .sneak(a), iconOnly, height: 84)
                let extras = HStack(alignment: .center, spacing: 14) {
                    ForEach([32, 28, 24] as [CGFloat], id: \.self) { d in
                        BubbleView(bubble: .activity(a), model: model, diameter: d)
                    }
                    TemplateRow(activity: a, model: model)
                        .frame(width: rowWidth)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black))
                }
                .padding(12)
                .frame(width: 760, alignment: .leading)
                .background(LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.62), Color(red: 0.62, green: 0.45, blue: 0.55)],
                                           startPoint: .leading, endPoint: .trailing))
                if let img = image(extras) { parts.append(("bubbles and row", img)) }

                let sheet = VStack(alignment: .leading, spacing: 4) {
                    Text("\(name) · \(Int(metrics.expanded.width)) pt")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.white).padding(.leading, 8)
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(part.0).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.6)).padding(.leading, 8)
                            Image(nsImage: part.1)
                        }
                    }
                }
                .padding(.vertical, 8)
                .background(Color(white: 0.16))
                Snapshots.write(sheet, to: out.appendingPathComponent("\(name)-\(Int(metrics.expanded.width)).png"))
            }
        }
        // The expanded island with template rows among the others.
        for d in demos(now: now) where ["flight", "score", "eta"].contains(d.name) {
            var spec = d.spec
            spec.priority = .high
            _ = try? model.applyLocal(spec)
        }
        model.forcedPresentation = .expanded
        model.tab = .home
        model.closedPlacements[1] = nil
        for preset in [SizePreset.compact, .standard] {
            model.settings.sizePreset = preset
            let size = CGSize(width: model.settings.expandedSize.width, height: model.settings.expandedSize.height)
            let metrics = NotchGeometry.metrics(for: Snapshots.screen, expandedSize: size, wingWidth: model.settings.effectiveWingWidth)
            let view = IslandView(model: model, display: 1, metrics: metrics)
                .frame(width: 760, height: metrics.expanded.height + 30)
                .background(Snapshots.backdrop(metrics: metrics))
            Snapshots.write(view, to: out.appendingPathComponent("expanded-home-\(Int(metrics.expanded.width)).png"))
        }
        model.forcedPresentation = nil
        model.settings.sizePreset = savedPreset
    }

    private static func image<V: View>(_ view: V) -> NSImage? {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark).environment(\.snapshotMode, true))
        renderer.scale = 2
        return renderer.nsImage
    }
}
