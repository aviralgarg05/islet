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
        #expect(r.today?.high == 16.1)
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
}
