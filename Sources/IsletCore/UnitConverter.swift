import Foundation

/// What the converter measures.
public enum ConverterDimension: String, CaseIterable, Sendable {
    case length, mass, temperature, volume, speed

    public var title: String {
        switch self {
        case .length: return "Length"
        case .mass: return "Weight"
        case .temperature: return "Temperature"
        case .volume: return "Volume"
        case .speed: return "Speed"
        }
    }
}

/// A unit the converter knows, by the names people type for it.
public struct ConverterUnit: Sendable, Hashable, Identifiable {
    public let id: String
    /// How it is written in an answer: "cm", "°F", "fl oz".
    public let symbol: String
    public let dimension: ConverterDimension
    /// Lower-case names and abbreviations it is typed as.
    let names: [String]

    /// The Foundation unit the sums are done in. Imperial and US units use their exact
    /// definitions (an inch is 25.4 mm, a pound 0.45359237 kg), so a tablespoon is 3 teaspoons
    /// to the last digit.
    var foundation: Dimension {
        func length(_ metres: Double) -> UnitLength { UnitLength(symbol: symbol, converter: UnitConverterLinear(coefficient: metres)) }
        func mass(_ kilograms: Double) -> UnitMass { UnitMass(symbol: symbol, converter: UnitConverterLinear(coefficient: kilograms)) }
        func volume(_ litres: Double) -> UnitVolume { UnitVolume(symbol: symbol, converter: UnitConverterLinear(coefficient: litres)) }
        func speed(_ metresPerSecond: Double) -> UnitSpeed {
            UnitSpeed(symbol: symbol, converter: UnitConverterLinear(coefficient: metresPerSecond))
        }
        switch id {
        case "mm": return UnitLength.millimeters
        case "cm": return UnitLength.centimeters
        case "m": return UnitLength.meters
        case "km": return UnitLength.kilometers
        case "in": return length(0.0254)
        case "ft": return length(0.3048)
        case "yd": return length(0.9144)
        case "mi": return length(1609.344)
        case "nmi": return length(1852)
        case "mg": return UnitMass.milligrams
        case "g": return UnitMass.grams
        case "kg": return UnitMass.kilograms
        case "t": return UnitMass.metricTons
        case "oz": return mass(0.028349523125)
        case "lb": return mass(0.45359237)
        case "st": return mass(6.35029318)
        case "c": return UnitTemperature.celsius
        case "f": return UnitTemperature.fahrenheit
        case "k": return UnitTemperature.kelvin
        case "ml": return UnitVolume.milliliters
        case "l": return UnitVolume.liters
        case "m3": return UnitVolume.cubicMeters
        case "tsp": return volume(0.00492892159375)
        case "tbsp": return volume(0.01478676478125)
        case "floz": return volume(0.0295735295625)
        case "cup": return volume(0.2365882365)
        case "pt": return volume(0.473176473)
        case "qt": return volume(0.946352946)
        case "gal": return volume(3.785411784)
        case "ukfloz": return volume(0.0284130625)
        case "ukpt": return volume(0.56826125)
        case "ukgal": return volume(4.54609)
        case "mps": return UnitSpeed.metersPerSecond
        case "kmh": return speed(1000.0 / 3600.0)
        case "mph": return speed(0.44704)
        default: return speed(1852.0 / 3600.0)
        }
    }
}

/// One answer: "152.4 cm".
public struct ConverterResult: Sendable, Equatable, Identifiable {
    public let unit: ConverterUnit
    public let value: Double
    /// The value as shown, "152.4" or "1,609,344".
    public let number: String
    /// The value as copied, without thousands separators so it pastes into a sum or a form:
    /// "1609344".
    public let plainNumber: String
    public var id: String { unit.id }
    /// "152.4 cm".
    public var text: String { UnitConverter.joined(number, unit) }
}

/// What was typed, read: an amount in a unit, and its value in one or more others.
public struct Conversion: Sendable, Equatable {
    public let amount: Double
    public let unit: ConverterUnit
    /// The amount as shown, "5".
    public let number: String
    /// The unit asked for, or a couple of the usual ones when none was.
    public let results: [ConverterResult]
    /// Whether a unit to convert to was typed.
    public let asked: Bool

    /// "5 ft".
    public var source: String { UnitConverter.joined(number, unit) }
    /// "5 ft = 152.4 cm".
    public var sentence: String { results.first.map { "\(source) = \($0.text)" } ?? source }
}

/// Reads conversions typed the way people say them: "5 ft in cm", "100f to c", "3.5 kg",
/// "60 mph in km/h", "2 cups = ml". Lengths, weights, temperatures, volumes and speeds, with the
/// sums done by Foundation's `Measurement`. Nothing leaves the Mac.
public enum UnitConverter {
    /// Every unit, in the order Settings and the page list them.
    public static let units: [ConverterUnit] = [
        ConverterUnit(id: "mm", symbol: "mm", dimension: .length, names: ["mm", "millimetre", "millimetres", "millimeter", "millimeters"]),
        ConverterUnit(id: "cm", symbol: "cm", dimension: .length, names: ["cm", "centimetre", "centimetres", "centimeter", "centimeters", "cms"]),
        ConverterUnit(id: "m", symbol: "m", dimension: .length, names: ["m", "metre", "metres", "meter", "meters"]),
        ConverterUnit(id: "km", symbol: "km", dimension: .length, names: ["km", "kms", "kilometre", "kilometres", "kilometer", "kilometers", "k"]),
        ConverterUnit(id: "in", symbol: "in", dimension: .length, names: ["in", "inch", "inches", "\"", "″"]),
        ConverterUnit(id: "ft", symbol: "ft", dimension: .length, names: ["ft", "foot", "feet", "'", "′"]),
        ConverterUnit(id: "yd", symbol: "yd", dimension: .length, names: ["yd", "yds", "yard", "yards"]),
        ConverterUnit(id: "mi", symbol: "mi", dimension: .length, names: ["mi", "mile", "miles"]),
        ConverterUnit(id: "nmi", symbol: "nmi", dimension: .length, names: ["nmi", "nautical mile", "nautical miles"]),
        ConverterUnit(id: "mg", symbol: "mg", dimension: .mass, names: ["mg", "milligram", "milligrams", "milligramme", "milligrammes"]),
        ConverterUnit(id: "g", symbol: "g", dimension: .mass, names: ["g", "gram", "grams", "gramme", "grammes", "gr"]),
        ConverterUnit(id: "kg", symbol: "kg", dimension: .mass, names: ["kg", "kgs", "kilo", "kilos", "kilogram", "kilograms", "kilogramme", "kilogrammes"]),
        ConverterUnit(id: "t", symbol: "t", dimension: .mass, names: ["t", "tonne", "tonnes", "metric ton", "metric tons"]),
        ConverterUnit(id: "oz", symbol: "oz", dimension: .mass, names: ["oz", "ounce", "ounces"]),
        ConverterUnit(id: "lb", symbol: "lb", dimension: .mass, names: ["lb", "lbs", "pound", "pounds"]),
        ConverterUnit(id: "st", symbol: "st", dimension: .mass, names: ["st", "stone", "stones"]),
        ConverterUnit(id: "c", symbol: "°C", dimension: .temperature, names: ["c", "°c", "°", "celsius", "centigrade", "degc", "deg c", "degrees c", "degrees celsius"]),
        ConverterUnit(id: "f", symbol: "°F", dimension: .temperature, names: ["f", "°f", "fahrenheit", "degf", "deg f", "degrees f", "degrees fahrenheit"]),
        ConverterUnit(id: "k", symbol: "K", dimension: .temperature, names: ["kelvin", "kelvins"]),
        ConverterUnit(id: "ml", symbol: "ml", dimension: .volume, names: ["ml", "millilitre", "millilitres", "milliliter", "milliliters", "cc"]),
        ConverterUnit(id: "l", symbol: "l", dimension: .volume, names: ["l", "litre", "litres", "liter", "liters", "ltr"]),
        ConverterUnit(id: "m3", symbol: "m³", dimension: .volume, names: ["m3", "m³", "cubic metre", "cubic metres", "cubic meter", "cubic meters"]),
        ConverterUnit(id: "tsp", symbol: "tsp", dimension: .volume, names: ["tsp", "teaspoon", "teaspoons"]),
        ConverterUnit(id: "tbsp", symbol: "tbsp", dimension: .volume, names: ["tbsp", "tablespoon", "tablespoons"]),
        ConverterUnit(id: "floz", symbol: "fl oz", dimension: .volume, names: ["fl oz", "floz", "fluid ounce", "fluid ounces", "us fl oz"]),
        ConverterUnit(id: "cup", symbol: "cups", dimension: .volume, names: ["cup", "cups"]),
        ConverterUnit(id: "pt", symbol: "US pt", dimension: .volume, names: ["us pt", "us pint", "us pints", "pt", "pint", "pints"]),
        ConverterUnit(id: "qt", symbol: "qt", dimension: .volume, names: ["qt", "quart", "quarts"]),
        ConverterUnit(id: "gal", symbol: "US gal", dimension: .volume, names: ["us gal", "us gallon", "us gallons", "gal", "gallon", "gallons"]),
        ConverterUnit(id: "ukfloz", symbol: "UK fl oz", dimension: .volume, names: ["uk fl oz", "imperial fl oz", "imperial fluid ounce", "imperial fluid ounces"]),
        ConverterUnit(id: "ukpt", symbol: "UK pt", dimension: .volume, names: ["uk pt", "uk pint", "uk pints", "imperial pint", "imperial pints"]),
        ConverterUnit(id: "ukgal", symbol: "UK gal", dimension: .volume, names: ["uk gal", "uk gallon", "uk gallons", "imperial gallon", "imperial gallons"]),
        ConverterUnit(id: "mps", symbol: "m/s", dimension: .speed, names: ["m/s", "mps", "metres per second", "meters per second", "metre per second", "meter per second"]),
        ConverterUnit(id: "kmh", symbol: "km/h", dimension: .speed, names: ["km/h", "kmh", "kph", "km/hr", "kmph", "kilometres per hour", "kilometers per hour", "kilometre per hour", "kilometer per hour"]),
        ConverterUnit(id: "mph", symbol: "mph", dimension: .speed, names: ["mph", "mi/h", "miles per hour", "mile per hour"]),
        ConverterUnit(id: "kn", symbol: "kn", dimension: .speed, names: ["kn", "kt", "kts", "knot", "knots"]),
    ]

    /// Words between the amount and the unit wanted.
    static let connectors: Set<String> = ["in", "to", "into", "as", "=", "->", "→"]

    /// Examples for the page's empty state, one per dimension.
    public static let examples = ["5 ft in cm", "70 kg in lb", "100 °F in °C", "2 cups in ml", "60 mph in km/h"]

    /// - Parameter imperialVolumes: a plain "pint" or "gallon" means the British one (the
    ///   Mac's region is the United Kingdom); otherwise the US one.
    public static func unit(named raw: String, imperialVolumes: Bool = false) -> ConverterUnit? {
        let name = normalisedName(raw)
        guard !name.isEmpty else { return nil }
        if imperialVolumes {
            switch name {
            case "pt", "pint", "pints": return unit(id: "ukpt")
            case "gal", "gallon", "gallons": return unit(id: "ukgal")
            case "fl oz", "floz", "fluid ounce", "fluid ounces": return unit(id: "ukfloz")
            default: break
            }
        }
        if let u = units.first(where: { $0.names.contains(name) }) { return u }
        // "kgs", "metres" already listed; a stray plural otherwise.
        if name.count > 2, name.hasSuffix("s"), let u = units.first(where: { $0.names.contains(String(name.dropLast())) }) { return u }
        return nil
    }

    static func unit(id: String) -> ConverterUnit? { units.first { $0.id == id } }

    static func normalisedName(_ raw: String) -> String {
        var s = raw.lowercased().replacingOccurrences(of: "º", with: "°").replacingOccurrences(of: "° ", with: "°")
        s = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if s.hasSuffix("."), s.count > 1 { s.removeLast() }
        return s
    }

    /// Reads "5 ft in cm" (or "5ft", "5 feet to centimetres", "-40 c = f"). Without a unit to
    /// convert to, the answer is in the usual ones for it ("5 ft" gives metres and centimetres).
    public static func convert(_ text: String, imperialVolumes: Bool = false, locale: Locale = .current) -> Conversion? {
        guard let (amount, rest) = splitAmount(text), !rest.isEmpty else { return nil }
        let tokens = tokenise(rest)
        guard !tokens.isEmpty, tokens.count <= 8 else { return nil }
        // The whole rest is one unit: "5 ft", "60 miles per hour".
        if let from = unit(named: tokens.joined(separator: " "), imperialVolumes: imperialVolumes) {
            let targets = defaultTargets(for: from, imperialVolumes: imperialVolumes)
            return make(amount, from, targets, asked: false, locale: locale)
        }
        // A unit, perhaps a word like "in" or "to", then the unit wanted. A connector is
        // preferred where there is one, so "5 in in cm" is inches to centimetres.
        var plain: Conversion?
        for i in 1..<tokens.count {
            guard let from = unit(named: tokens[..<i].joined(separator: " "), imperialVolumes: imperialVolumes) else { continue }
            var right = Array(tokens[i...])
            var connected = false
            if right.count > 1, connectors.contains(right[0]) {
                right.removeFirst()
                connected = true
            }
            guard let to = unit(named: right.joined(separator: " "), imperialVolumes: imperialVolumes), to.dimension == from.dimension
            else { continue }
            let c = make(amount, from, [to], asked: true, locale: locale)
            if connected { return c }
            if plain == nil { plain = c }
        }
        return plain
    }

    /// The number at the start and the rest: "5ft in cm" is (5, "ft in cm").
    static func splitAmount(_ text: String) -> (Double, String)? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = s.range(of: #"^[-−+]?(\d[\d,]*(\.\d+)?|\.\d+)"#, options: .regularExpression) else { return nil }
        var number = String(s[match]).replacingOccurrences(of: "−", with: "-")
        // "1,000" groups thousands; "5,5" is five and a half (a comma for a decimal point).
        if number.contains(","), !number.contains(".") {
            let parts = number.split(separator: ",", omittingEmptySubsequences: false)
            if parts.count == 2, parts[1].count != 3 {
                number = number.replacingOccurrences(of: ",", with: ".")
            } else {
                guard parts.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
                number = number.replacingOccurrences(of: ",", with: "")
            }
        } else {
            number = number.replacingOccurrences(of: ",", with: "")
        }
        guard let value = Double(number), value.isFinite, abs(value) < 1e15 else { return nil }
        return (value, String(s[match.upperBound...]).trimmingCharacters(in: .whitespaces))
    }

    /// Words, with "=", "->" and "→" apart even when written against a unit ("ft=cm").
    static func tokenise(_ text: String) -> [String] {
        var s = normalisedName(text)
        for sep in ["->", "→", "="] { s = s.replacingOccurrences(of: sep, with: " \(sep) ") }
        return s.split(separator: " ").map(String.init)
    }

    /// The units an amount is usually wanted in, from metric to imperial and back.
    static func defaultTargets(for unit: ConverterUnit, imperialVolumes: Bool) -> [ConverterUnit] {
        let ids: [String]
        switch unit.id {
        case "mm": ids = ["in"]
        case "cm": ids = ["in", "ft"]
        case "m": ids = ["ft", "yd"]
        case "km": ids = ["mi"]
        case "in": ids = ["cm"]
        case "ft": ids = ["m", "cm"]
        case "yd": ids = ["m"]
        case "mi": ids = ["km"]
        case "nmi": ids = ["km", "mi"]
        case "mg": ids = ["g"]
        case "g": ids = ["oz"]
        case "kg": ids = ["lb", "st"]
        case "t": ids = ["kg", "lb"]
        case "oz": ids = ["g"]
        case "lb": ids = ["kg"]
        case "st": ids = ["kg", "lb"]
        case "c": ids = ["f"]
        case "f": ids = ["c"]
        case "k": ids = ["c", "f"]
        case "ml": ids = [imperialVolumes ? "ukfloz" : "floz", "tsp"]
        case "l": ids = imperialVolumes ? ["ukpt", "ukgal"] : ["pt", "gal"]
        case "m3": ids = ["l"]
        case "tsp", "tbsp", "floz", "cup", "ukfloz": ids = ["ml"]
        case "pt", "qt", "ukpt": ids = ["l", "ml"]
        case "gal", "ukgal": ids = ["l"]
        case "mps": ids = ["kmh", "mph"]
        case "kmh": ids = ["mph"]
        case "mph": ids = ["kmh"]
        default: ids = ["kmh", "mph"]
        }
        return ids.compactMap { self.unit(id: $0) }
    }

    static func make(_ amount: Double, _ from: ConverterUnit, _ targets: [ConverterUnit], asked: Bool, locale: Locale) -> Conversion? {
        let m = Measurement(value: amount, unit: from.foundation)
        let results = targets.map { to -> ConverterResult in
            let v = m.converted(to: to.foundation).value
            return ConverterResult(unit: to, value: v, number: format(v, locale: locale),
                                   plainNumber: format(v, locale: locale, grouped: false))
        }
        guard results.allSatisfy({ $0.value.isFinite }) else { return nil }
        return Conversion(amount: amount, unit: from, number: format(amount, locale: locale), results: results, asked: asked)
    }

    /// Six significant figures, grouped thousands, no trailing zeros: 152.4, 1.60934, 37.7778.
    /// A whole part longer than that is never rounded off: a mile is 1,609,344 mm, not
    /// 1,609,340.
    public static func format(_ value: Double, locale: Locale = .current, grouped: Bool = true) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.usesGroupingSeparator = grouped
        let clean = abs(value) < 1e-9 ? 0 : value
        if abs(clean) >= 1e6 {
            f.maximumFractionDigits = 0
        } else {
            f.usesSignificantDigits = true
            f.maximumSignificantDigits = 6
            f.minimumSignificantDigits = 1
        }
        return f.string(from: NSNumber(value: clean)) ?? String(clean)
    }

    /// "152.4 cm", or "37.8 °C" with a space before a degree sign too, as SI writes it.
    static func joined(_ number: String, _ unit: ConverterUnit) -> String {
        "\(number) \(unit.symbol)"
    }

    /// Whether the Mac's region writes pints and gallons the British way.
    public static func usesImperialVolumes(_ locale: Locale = .current) -> Bool {
        locale.region?.identifier == "GB"
    }
}
