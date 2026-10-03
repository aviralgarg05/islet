import Foundation
import Testing
@testable import IsletCore

@Suite struct WeatherTests {
    static let forecast = #"""
    {"latitude":51.5,"longitude":-0.12,"timezone":"Europe/London",
     "current":{"time":"2026-10-01T10:15","interval":900,"temperature_2m":14.2,"apparent_temperature":12.6,
                "weather_code":61,"is_day":1,"wind_speed_10m":11.4},
     "daily":{"time":["2026-10-01","2026-10-02","2026-10-03"],
              "weather_code":[61,3,null],
              "temperature_2m_max":[16.1,17.4,15.0],
              "temperature_2m_min":[9.8,10.2,8.0],
              "precipitation_probability_max":[80,null,10]}}
    """#

    @Test func decodesCurrentConditionsAndTheDaysAhead() throws {
        let t = Date(timeIntervalSince1970: 5_000)
        let r = try OpenMeteo.decodeForecast(Data(Self.forecast.utf8), fetchedAt: t)
        #expect(r.current.temperature == 14.2)
        #expect(r.current.feelsLike == 12.6)
        #expect(r.current.code == 61)
        #expect(r.current.isDay)
        #expect(r.fetchedAt == t)
        // The third day has no code, so it is left out rather than guessed.
        #expect(r.days.map(\.date) == ["2026-10-01", "2026-10-02"])
        #expect(r.days[0].rainChance == 80)
        #expect(r.days[1].rainChance == nil)
        #expect(r.days.first?.high == 16.1)
    }

    @Test func aForecastWithoutCurrentConditionsIsAnError() {
        #expect(throws: OpenMeteo.DecodeError.noCurrentConditions) {
            try OpenMeteo.decodeForecast(Data(#"{"daily":{}}"#.utf8), fetchedAt: Date())
        }
        #expect(throws: (any Error).self) { try OpenMeteo.decodeForecast(Data("not json".utf8), fetchedAt: Date()) }
    }

    @Test func sendsOnlyARoundedPosition() throws {
        let url = OpenMeteo.forecastURL(latitude: 51.507351, longitude: -0.127758)
        #expect(url.host == "api.open-meteo.com")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "latitude" }?.value == "51.51")
        #expect(items.first { $0.name == "longitude" }?.value == "-0.13")
        #expect(items.first { $0.name == "forecast_days" }?.value == "7")
        #expect(OpenMeteo.rounded(48.85341) == 48.85)
    }

    @Test func searchesPlacesByName() throws {
        let url = try #require(OpenMeteo.geocodingURL("  Paris ", language: "fr"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(url.host == "geocoding-api.open-meteo.com")
        #expect(items.first { $0.name == "name" }?.value == "Paris")
        #expect(items.first { $0.name == "language" }?.value == "fr")
        #expect(OpenMeteo.geocodingURL("   ") == nil)
        let json = #"""
        {"results":[{"id":1,"name":"Paris","latitude":48.85341,"longitude":2.3488,"country":"France","admin1":"Île-de-France"},
                    {"id":2,"name":"Paris","latitude":33.66,"longitude":-95.55,"country":"United States","admin1":"Texas"},
                    {"id":3,"name":"Nowhere"}]}
        """#
        let places = try OpenMeteo.decodePlaces(Data(json.utf8))
        #expect(places.map(\.label) == ["Paris, Île-de-France, France", "Paris, Texas, United States"])
        #expect(try OpenMeteo.decodePlaces(Data(#"{"generationtime_ms":0.5}"#.utf8)).isEmpty)
    }

    @Test func placeLabelsSkipRepeats() {
        #expect(WeatherPlace(name: "Singapore", region: "Singapore", country: "Singapore", latitude: 1.3, longitude: 103.8).label == "Singapore")
        #expect(WeatherPlace(name: "Leeds", region: "", country: "United Kingdom", latitude: 53.8, longitude: -1.5).label == "Leeds, United Kingdom")
    }

    @Test func temperaturesInEitherUnit() {
        #expect(TemperatureUnit.celsius.format(14.4) == "14°")
        #expect(TemperatureUnit.celsius.format(-0.4) == "0°", "never minus zero")
        #expect(TemperatureUnit.fahrenheit.format(14.4) == "58°")
        #expect(TemperatureUnit.fahrenheit.format(-40) == "-40°")
        #expect(TemperatureUnit.automatic.resolved(usesUSMeasures: true) == .fahrenheit)
        #expect(TemperatureUnit.automatic.resolved(usesUSMeasures: false) == .celsius)
        #expect(TemperatureUnit.celsius.resolved(usesUSMeasures: true) == .celsius)
        // The reading comes from the service: `Int(_:)` traps beyond its range, and a figure no
        // weather service could mean is not drawn as though it were the weather.
        #expect(TemperatureUnit.celsius.format(1e300) == "–")
        #expect(TemperatureUnit.fahrenheit.format(-1e300) == "–")
        #expect(TemperatureUnit.celsius.format(.nan) == "–")
        #expect(TemperatureUnit.celsius.format(.infinity) == "–")
        // The hottest and coldest it has ever been here still show.
        #expect(TemperatureUnit.celsius.format(56.7) == "57\u{00B0}")
        #expect(TemperatureUnit.celsius.format(-89.2) == "-89\u{00B0}")
    }

    @Test func codesHaveWordsAndSymbols() {
        #expect(WeatherCode.text(0) == "Clear")
        #expect(WeatherCode.text(63) == "Rain")
        #expect(WeatherCode.text(1234) == "Unknown")
        #expect(WeatherCode.symbol(0, isDay: true) == "sun.max.fill")
        #expect(WeatherCode.symbol(0, isDay: false) == "moon.stars.fill")
        #expect(WeatherCode.symbol(95) == "cloud.bolt.rain.fill")
        for code in [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99] {
            #expect(WeatherCode.text(code) != "Unknown", "\(code)")
            #expect(!WeatherCode.symbol(code).isEmpty)
        }
    }

    @Test func weekdaysComeFromTheDateItself() {
        let day = WeatherReport.Day(date: "2026-10-01", code: 0, high: 1, low: 0)
        #expect(day.weekday(locale: Locale(identifier: "en_GB")) == "Thu")
        #expect(WeatherReport.Day(date: "garbage", code: 0, high: 1, low: 0).weekday() == "")
    }

    @Test func refreshesAtMostEveryHalfHour() {
        let t = Date(timeIntervalSince1970: 10_000)
        #expect(WeatherRefresh.isDue(lastAttempt: nil, lastSuccess: nil, now: t))
        #expect(!WeatherRefresh.isDue(lastAttempt: t, lastSuccess: t, now: t.addingTimeInterval(29 * 60)))
        #expect(WeatherRefresh.isDue(lastAttempt: t, lastSuccess: t, now: t.addingTimeInterval(30 * 60)))
        // A request that failed is tried again after a minute, not half an hour.
        let failed = t.addingTimeInterval(40 * 60)
        #expect(!WeatherRefresh.isDue(lastAttempt: failed, lastSuccess: t, now: failed.addingTimeInterval(30)))
        #expect(WeatherRefresh.isDue(lastAttempt: failed, lastSuccess: t, now: failed.addingTimeInterval(61)))
    }

    @Test func weatherSettingsStartOffAndLoadLeniently() {
        let d = IsletSettings()
        #expect(!d.weatherEnabled && !d.weatherUsesLocation && d.weatherPlace == nil && d.temperatureUnit == .automatic)
        let s = IsletSettings.decodeLenient(Data(#"""
        {"weatherEnabled": true, "weatherPlace": {"name": "Oslo", "latitude": 59.91, "longitude": 10.75},
         "temperatureUnit": "kelvin"}
        """#.utf8))
        #expect(s.weatherEnabled)
        #expect(s.weatherPlace?.name == "Oslo")
        #expect(s.temperatureUnit == .automatic, "an unknown unit falls back")
        let off = IsletSettings.decodeLenient(Data(#"{"weatherPlace": {"name": "X", "latitude": 400, "longitude": 0}}"#.utf8))
        #expect(off.weatherPlace == nil, "a place off the globe is dropped")
    }

    @Test func readsThePlacesOffsetFromUTC() throws {
        let json = #"{"utc_offset_seconds":32400,"current":{"temperature_2m":20,"weather_code":0},"daily":{"time":["2026-10-02"],"weather_code":[0],"temperature_2m_max":[22],"temperature_2m_min":[15]}}"#
        let r = try OpenMeteo.decodeForecast(Data(json.utf8), fetchedAt: Date(timeIntervalSince1970: 0))
        #expect(r.utcOffset == 32_400)
    }

    @Test func aKeptReportShowsTheDaysFromThePlacesToday() {
        let days = ["2026-10-01", "2026-10-02", "2026-10-03"].map { WeatherReport.Day(date: $0, code: 0, high: 20, low: 10) }
        // 1 October, 23:30 UTC: still the 1st for a place on UTC, already the 2nd in Tokyo.
        let now = Date(timeIntervalSince1970: 1_790_897_400)
        let utc = WeatherReport(current: .init(temperature: 15, code: 0), days: days, fetchedAt: now, utcOffset: 0)
        #expect(utc.placeDate(now) == "2026-10-01")
        #expect(utc.upcoming(now: now).map(\.date) == ["2026-10-01", "2026-10-02", "2026-10-03"])
        let tokyo = WeatherReport(current: .init(temperature: 15, code: 0), days: days, fetchedAt: now, utcOffset: 9 * 3600)
        #expect(tokyo.placeDate(now) == "2026-10-02")
        #expect(tokyo.upcoming(now: now).map(\.date) == ["2026-10-02", "2026-10-03"])
        #expect(tokyo.today(now: now)?.date == "2026-10-02")
        // Two days later the kept report has only its last day left, and no today.
        let later = now.addingTimeInterval(2 * 86_400)
        #expect(utc.upcoming(now: later).map(\.date) == ["2026-10-03"])
        #expect(utc.today(now: later.addingTimeInterval(86_400)) == nil)
    }

    @Test func anOldReportSaysWhenItIsFrom() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        let fetched = c.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9, minute: 12))!
        let r = WeatherReport(current: .init(temperature: 15, code: 0), days: [], fetchedAt: fetched, utcOffset: 0)
        let gb = Locale(identifier: "en_GB")
        #expect(r.updatedText(now: fetched.addingTimeInterval(59 * 60), calendar: c, locale: gb) == nil)
        #expect(r.updatedText(now: fetched.addingTimeInterval(60 * 60), calendar: c, locale: gb) == "As of 09:12")
        #expect(r.updatedText(now: fetched.addingTimeInterval(86_400), calendar: c, locale: gb) == "As of yesterday")
        #expect(r.updatedText(now: fetched.addingTimeInterval(3 * 86_400), calendar: c, locale: gb) == "As of Thu")
        // After the place, mid-line, as "feels like" reads: "London · as of 09:12".
        #expect(r.updatedText(now: fetched.addingTimeInterval(60 * 60), afterPlace: true, calendar: c, locale: gb) == "as of 09:12")
        #expect(r.updatedText(now: fetched.addingTimeInterval(59 * 60), afterPlace: true, calendar: c, locale: gb) == nil)
        // In a word, to follow the place when the line is short.
        #expect(r.age(now: fetched.addingTimeInterval(59 * 60), calendar: c, locale: gb) == nil)
        #expect(r.age(now: fetched.addingTimeInterval(86_400), calendar: c, locale: gb) == "yesterday")
    }

    @Test func aKeptReportShowsTodaysSky() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        let fetched = c.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9, minute: 12))!
        let days = [WeatherReport.Day(date: "2026-10-01", code: 61, high: 16, low: 10),
                    WeatherReport.Day(date: "2026-10-02", code: 3, high: 17, low: 10)]
        let r = WeatherReport(current: .init(temperature: 14, code: 61, isDay: true), days: days, fetchedAt: fetched, utcOffset: 0)
        // The same day, a reading from this morning still stands.
        #expect(r.sky(now: fetched.addingTimeInterval(3 * 3600)).code == 61)
        // The next day, today's forecast replaces yesterday's rain.
        #expect(r.sky(now: fetched.addingTimeInterval(86_400)).code == 3)
        // With no today left in it, the reading is all there is.
        #expect(r.sky(now: fetched.addingTimeInterval(3 * 86_400)).code == 61)
        #expect(WeatherCode.symbol(1) == WeatherCode.symbol(0))
    }
}
