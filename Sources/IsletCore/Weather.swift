import Foundation

/// How temperatures are shown.
public enum TemperatureUnit: String, Codable, Sendable, CaseIterable {
    /// Fahrenheit where the region uses US measures, Celsius elsewhere.
    case automatic
    case celsius
    case fahrenheit

    /// The unit to show: `automatic` follows the region.
    public func resolved(usesUSMeasures: Bool) -> TemperatureUnit {
        switch self {
        case .automatic: return usesUSMeasures ? .fahrenheit : .celsius
        case .celsius, .fahrenheit: return self
        }
    }

    /// A Celsius reading in this unit, rounded, with a degree sign: "18°". `automatic` reads as
    /// Celsius; resolve it first.
    public func format(_ celsius: Double) -> String {
        let value = self == .fahrenheit ? celsius * 9 / 5 + 32 : celsius
        // The reading comes from the weather service, so it is clamped: `Int(_:)` traps on
        // anything beyond its range, and on a reading that isn't a number at all.
        let whole = Int(ToolJSON.whole(value.rounded()))
        return "\(whole == 0 ? 0 : whole)°"
    }
}

/// A place the user chose for the weather, found by name.
public struct WeatherPlace: Codable, Equatable, Hashable, Sendable {
    public var name: String
    /// State, county or region, when known.
    public var region: String?
    public var country: String?
    public var latitude: Double
    public var longitude: Double

    public init(name: String, region: String? = nil, country: String? = nil, latitude: Double, longitude: Double) {
        self.name = name
        self.region = region
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
    }

    /// "Cambridge, England, United Kingdom", skipping parts that repeat or are missing.
    public var label: String {
        var parts = [name]
        for part in [region, country].compactMap({ $0 }) where !part.isEmpty && !parts.contains(part) {
            parts.append(part)
        }
        return parts.joined(separator: ", ")
    }
}

/// WMO weather codes, as Open-Meteo reports them, in words and as SF Symbols.
public enum WeatherCode {
    public static func text(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Cloudy"
        case 45: return "Fog"
        case 48: return "Freezing fog"
        case 51: return "Light drizzle"
        case 53: return "Drizzle"
        case 55: return "Heavy drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61: return "Light rain"
        case 63: return "Rain"
        case 65: return "Heavy rain"
        case 66, 67: return "Freezing rain"
        case 71: return "Light snow"
        case 73: return "Snow"
        case 75: return "Heavy snow"
        case 77: return "Snow grains"
        case 80: return "Light showers"
        case 81: return "Showers"
        case 82: return "Heavy showers"
        case 85: return "Snow showers"
        case 86: return "Heavy snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm with hail"
        default: return "Unknown"
        }
    }

    public static func symbol(_ code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        // The same sun as a clear sky: one forecast row shouldn't show two suns in two colours.
        case 1: return isDay ? "sun.max.fill" : "moon.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 56, 57, 66, 67: return "cloud.sleet.fill"
        case 61, 63: return "cloud.rain.fill"
        case 65, 82: return "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 80, 81: return isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

/// The weather now and for the days ahead, with temperatures in Celsius.
public struct WeatherReport: Codable, Equatable, Sendable {
    public struct Current: Codable, Equatable, Sendable {
        public var temperature: Double
        public var feelsLike: Double?
        public var code: Int
        public var isDay: Bool
        /// km/h.
        public var wind: Double?

        public init(temperature: Double, feelsLike: Double? = nil, code: Int, isDay: Bool = true, wind: Double? = nil) {
            self.temperature = temperature; self.feelsLike = feelsLike; self.code = code; self.isDay = isDay; self.wind = wind
        }
    }

    public struct Day: Codable, Equatable, Sendable, Identifiable {
        /// "2026-10-01", the day in the place's own time zone.
        public var date: String
        public var code: Int
        public var high: Double
        public var low: Double
        /// Percent.
        public var rainChance: Int?

        public var id: String { date }

        public init(date: String, code: Int, high: Double, low: Double, rainChance: Int? = nil) {
            self.date = date; self.code = code; self.high = high; self.low = low; self.rainChance = rainChance
        }

        /// The weekday, short ("Thu"), read from the date itself so the Mac's time zone can't
        /// move it to the day before.
        public func weekday(locale: Locale = .current) -> String {
            let parts = date.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return "" }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
            guard let day = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return "" }
            let f = DateFormatter()
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.locale = locale
            f.setLocalizedDateFormatFromTemplate("EEE")
            return f.string(from: day)
        }
    }

    public var current: Current
    /// Today first (the place's today when it was fetched).
    public var days: [Day]
    public var fetchedAt: Date
    /// The place's offset from UTC in seconds, which says when its days begin. Nil reads as the
    /// Mac's own time zone.
    public var utcOffset: Int?

    public init(current: Current, days: [Day], fetchedAt: Date, utcOffset: Int? = nil) {
        self.current = current
        self.days = days
        self.fetchedAt = fetchedAt
        self.utcOffset = utcOffset
    }

    /// A report this old came from an earlier visit, and the latest request didn't replace it:
    /// the page says when it is from.
    public static let staleAfter: TimeInterval = 60 * 60

    /// "2026-10-01" for `now` where the place is.
    public func placeDate(_ now: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        let offset = utcOffset ?? TimeZone.current.secondsFromGMT(for: now)
        calendar.timeZone = TimeZone(secondsFromGMT: offset) ?? .current
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The days from the place's today on: a report kept from yesterday doesn't show yesterday.
    public func upcoming(now: Date) -> [Day] {
        let today = placeDate(now)
        return days.filter { $0.date >= today }
    }

    /// Today's forecast where the place is, if the report still has it.
    public func today(now: Date) -> Day? {
        let today = placeDate(now)
        return days.first { $0.date == today }
    }

    public func isStale(now: Date) -> Bool {
        now.timeIntervalSince(fetchedAt) >= Self.staleAfter
    }

    /// When a stale report is from, short enough for the line under the sky: "As of 09:12"
    /// today, "As of yesterday", or "As of Mon" before that. After the place on the same line
    /// it goes on in lower case, as "feels like" does: "London · as of 09:12". Nil while it is fresh.
    public func updatedText(now: Date, afterPlace: Bool = false, calendar: Calendar = .current, locale: Locale = .current) -> String? {
        age(now: now, calendar: calendar, locale: locale).map { (afterPlace ? "as of " : "As of ") + $0 }
    }

    /// The same, in a word, to follow the place when the line is short: "09:12", "yesterday",
    /// "Mon". Nil while it is fresh.
    public func age(now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String? {
        guard isStale(now: now) else { return nil }
        if calendar.isDate(fetchedAt, inSameDayAs: now) {
            return UsageFormat.clockTime(fetchedAt, now: now, calendar: calendar, locale: locale)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(fetchedAt, inSameDayAs: yesterday) {
            return "yesterday"
        }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: fetchedAt)
    }

    /// The sky to draw beside the temperature: the reading itself, unless it was taken on an
    /// earlier day where the place is; then today's forecast, when the report still has it, so
    /// yesterday's rain doesn't sit beside today's cloud.
    public func sky(now: Date) -> (code: Int, isDay: Bool) {
        if placeDate(fetchedAt) != placeDate(now), let today = today(now: now) { return (today.code, true) }
        return (current.code, current.isDay)
    }
}

/// Open-Meteo: free forecasts with no account or key. Only a position (rounded to about a
/// kilometre) or a typed place name is sent.
public enum OpenMeteo {
    public static let forecastHost = "api.open-meteo.com"
    public static let geocodingHost = "geocoding-api.open-meteo.com"
    /// Days in the forecast, today included.
    public static let days = 7

    /// Two decimal places: about a kilometre, plenty for a forecast and no closer to the door.
    public static func rounded(_ degrees: Double) -> Double {
        (degrees * 100).rounded() / 100
    }

    public static func forecastURL(latitude: Double, longitude: Double) -> URL {
        var c = URLComponents()
        c.scheme = "https"
        c.host = forecastHost
        c.path = "/v1/forecast"
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", rounded(latitude))),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", rounded(longitude))),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: String(days)),
        ]
        return c.url!
    }

    /// Places matching a typed name, or nil for a blank one.
    public static func geocodingURL(_ name: String, language: String = "en") -> URL? {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        var c = URLComponents()
        c.scheme = "https"
        c.host = geocodingHost
        c.path = "/v1/search"
        c.queryItems = [
            URLQueryItem(name: "name", value: String(query.prefix(80))),
            URLQueryItem(name: "count", value: "6"),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "format", value: "json"),
        ]
        return c.url
    }

    public enum DecodeError: Error, Equatable {
        case noCurrentConditions
    }

    private struct ForecastJSON: Decodable {
        struct Current: Decodable {
            var temperature_2m: Double?
            var apparent_temperature: Double?
            var weather_code: Int?
            var is_day: Int?
            var wind_speed_10m: Double?
        }
        struct Daily: Decodable {
            var time: [String]?
            var weather_code: [Int?]?
            var temperature_2m_max: [Double?]?
            var temperature_2m_min: [Double?]?
            var precipitation_probability_max: [Int?]?
        }
        var current: Current?
        var daily: Daily?
        var utc_offset_seconds: Int?
    }

    /// Reads a forecast. Days with a missing temperature or code are left out.
    public static func decodeForecast(_ data: Data, fetchedAt: Date) throws -> WeatherReport {
        let json = try JSONDecoder().decode(ForecastJSON.self, from: data)
        guard let c = json.current, let temperature = c.temperature_2m, let code = c.weather_code else {
            throw DecodeError.noCurrentConditions
        }
        let current = WeatherReport.Current(temperature: temperature, feelsLike: c.apparent_temperature, code: code,
                                            isDay: (c.is_day ?? 1) != 0, wind: c.wind_speed_10m)
        var days: [WeatherReport.Day] = []
        if let d = json.daily, let times = d.time {
            for (i, date) in times.enumerated() {
                guard let code = d.weather_code?[safe: i] ?? nil,
                      let high = d.temperature_2m_max?[safe: i] ?? nil,
                      let low = d.temperature_2m_min?[safe: i] ?? nil else { continue }
                days.append(WeatherReport.Day(date: date, code: code, high: high, low: low,
                                              rainChance: d.precipitation_probability_max?[safe: i] ?? nil))
            }
        }
        return WeatherReport(current: current, days: days, fetchedAt: fetchedAt, utcOffset: json.utc_offset_seconds)
    }

    private struct PlacesJSON: Decodable {
        struct Result: Decodable {
            var name: String?
            var latitude: Double?
            var longitude: Double?
            var country: String?
            var admin1: String?
        }
        var results: [Result]?
    }

    /// Reads the places a search found (none is an empty list, not an error).
    public static func decodePlaces(_ data: Data) throws -> [WeatherPlace] {
        let json = try JSONDecoder().decode(PlacesJSON.self, from: data)
        return (json.results ?? []).compactMap { r in
            guard let name = r.name, let lat = r.latitude, let lon = r.longitude else { return nil }
            return WeatherPlace(name: name, region: r.admin1, country: r.country, latitude: lat, longitude: lon)
        }
    }
}

/// When the weather may be fetched again: at most every 30 minutes, sooner only after a failure
/// (then after a minute) or when the place changed.
public enum WeatherRefresh {
    public static let interval: TimeInterval = 30 * 60
    public static let retry: TimeInterval = 60

    /// `lastAttempt` is when the last request went out, `lastSuccess` when one last came back
    /// with a forecast.
    public static func isDue(lastAttempt: Date?, lastSuccess: Date?, now: Date) -> Bool {
        guard let attempt = lastAttempt else { return true }
        if let success = lastSuccess, success >= attempt { return now.timeIntervalSince(success) >= interval }
        return now.timeIntervalSince(attempt) >= retry
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
