import AppKit
import IsletCore
import SwiftUI

/// The Weather page (under More once turned on): the weather now on the left, the week ahead
/// on the right. The forecast is fetched when the page opens, at most every half hour.
struct WeatherTab: View {
    let model: AppModel
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        let w = model.tools.weather
        Group {
            if !model.settings.weatherEnabled {
                EmptyHint(symbol: "cloud.sun",
                          text: "The weather now and for the week ahead, for a city you choose or where you are.") {
                    Button("Turn on") {
                        model.setTool(\.weatherEnabled, true)
                        if model.settings.weatherPlace == nil && !model.settings.weatherUsesLocation {
                            AppActions.openSettings(.tools, at: "tools.weatherLocation")
                        }
                    }
                    .buttonStyle(CapsuleButtonStyle(tint: .blue, filled: true))
                }
            } else if let report = w.report {
                WeatherReportView(report: report, place: w.placeName, unit: w.unit)
            } else {
                status(w.status)
            }
        }
        // On opening the page, and again when it is turned on or the place changes.
        .task(id: Self.refreshKey(model.settings)) { if !snapshotMode { w.refreshIfDue() } }
    }

    static func refreshKey(_ s: IsletSettings) -> String {
        "\(s.weatherEnabled) \(s.weatherUsesLocation) \(s.weatherPlace?.latitude ?? 0) \(s.weatherPlace?.longitude ?? 0)"
    }

    @ViewBuilder
    private func status(_ status: WeatherController.Status) -> some View {
        switch status {
        case .needsPlace:
            EmptyHint(symbol: "mappin.and.ellipse", text: "Choose a city for the weather, or use where you are.") {
                Button("Choose…") { AppActions.openSettings(.tools, at: "tools.weatherLocation") }
                    .buttonStyle(CapsuleButtonStyle(tint: .blue, filled: true))
            }
        case .locationDenied:
            EmptyHint(symbol: "location.slash", text: "Islet isn't allowed to know where this Mac is. Allow Location, or choose a city instead.") {
                Button("Open System Settings") { NSWorkspace.shared.open(PermissionKind.location.settingsURL) }
                    .buttonStyle(CapsuleButtonStyle(tint: .blue, filled: true))
                Button("Choose a city…") { AppActions.openSettings(.tools, at: "tools.weatherLocation") }
                    .buttonStyle(CapsuleButtonStyle())
            }
        case .failed:
            EmptyHint(symbol: "cloud", text: "The weather couldn't be reached.") {
                Button("Try again") { model.tools.weather.retry() }.buttonStyle(CapsuleButtonStyle())
            }
        case .loading, .idle:
            HStack(spacing: Space.s) {
                SpinnerArc(tint: Ink.tertiary, lineWidth: 1.5).frame(width: 10, height: 10)
                Text("Getting the weather").textStyle(.body).foregroundStyle(Ink.tertiary)
            }
        }
    }
}

/// Now on the left (the symbol, the temperature, the sky in words and the place), and one
/// column per day on the right.
struct WeatherReportView: View {
    let report: WeatherReport
    let place: String?
    let unit: TemperatureUnit

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            now
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            ColumnRule().padding(.horizontal, Space.l)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(report.days.prefix(OpenMeteo.days).enumerated()), id: \.element.id) { i, day in
                    DayColumn(day: day, title: i == 0 ? "Today" : day.weekday(), unit: unit)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: 252)
            .frame(maxHeight: .infinity)
        }
    }

    private var now: some View {
        let c = report.current
        return HStack(alignment: .center, spacing: Space.m) {
            Image(systemName: WeatherCode.symbol(c.code, isDay: c.isDay))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 28))
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(unit.format(c.temperature))
                    .textStyle(.display)
                    .foregroundStyle(Ink.primary)
                Text(WeatherCode.text(c.code))
                    .textStyle(.body)
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
                // The place and how it feels, or just the place when that is all that fits.
                ViewThatFits(in: .horizontal) {
                    Text(detail).lineLimit(1).fixedSize()
                    Text(place ?? detail).lineLimit(1)
                }
                .textStyle(.caption)
                .foregroundStyle(Ink.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "London · feels like 13°", or the day's high and low when it feels as it is.
    private var detail: String {
        var parts: [String] = []
        if let place { parts.append(place) }
        if let feels = report.current.feelsLike, unit.format(feels) != unit.format(report.current.temperature) {
            parts.append("feels like \(unit.format(feels))")
        } else if let today = report.today {
            parts.append("\(unit.format(today.high)) / \(unit.format(today.low))")
        }
        return parts.joined(separator: " · ")
    }
}

/// One day of the forecast: its name, the sky, the high and the low.
private struct DayColumn: View {
    let day: WeatherReport.Day
    let title: String
    let unit: TemperatureUnit

    var body: some View {
        VStack(spacing: Space.xs) {
            Text(title)
                .textStyle(.caption, emphasized: true)
                .foregroundStyle(Ink.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Image(systemName: WeatherCode.symbol(day.code))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 15))
                .frame(height: 18)
            Text(unit.format(day.high))
                .textStyle(.body, emphasized: true, numeric: true)
                .foregroundStyle(Ink.primary)
            Text(unit.format(day.low))
                .textStyle(.caption, numeric: true)
                .foregroundStyle(Ink.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(WeatherCode.text(day.code)), \(unit.format(day.high)) and \(unit.format(day.low))")
    }
}
