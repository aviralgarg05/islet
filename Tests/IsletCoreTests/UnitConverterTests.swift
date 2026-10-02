import Foundation
import Testing
@testable import IsletCore

/// The converter reads what people type ("5 ft in cm", "100f to c") and answers with
/// Foundation's sums, written the way the Mac's region writes numbers.
@Suite struct UnitConverterTests {
    let gb = Locale(identifier: "en_GB")

    func answer(_ text: String, imperial: Bool = false) -> String? {
        UnitConverter.convert(text, imperialVolumes: imperial, locale: gb)?.results.first?.text
    }

    @Test(arguments: [
        ("5 ft in cm", "152.4 cm"),
        ("5ft in cm", "152.4 cm"),
        ("5 feet to centimetres", "152.4 cm"),
        ("5 ft = cm", "152.4 cm"),
        ("5ft=cm", "152.4 cm"),
        ("5 ft -> cm", "152.4 cm"),
        ("1 mi in km", "1.60934 km"),
        ("10 km to miles", "6.21371 mi"),
        ("70 kg in lb", "154.324 lb"),
        ("70 kg in stone", "11.0231 st"),
        ("100 °F in °C", "37.7778 °C"),
        ("100f to c", "37.7778 °C"),
        ("-40 c in f", "-40 °F"),
        ("0 c in kelvin", "273.15 K"),
        ("2 cups in ml", "473.176 ml"),
        ("1 tbsp in tsp", "3 tsp"),
        ("60 mph in km/h", "96.5606 km/h"),
        ("100 kph in mph", "62.1371 mph"),
        ("10 knots in km/h", "18.52 km/h"),
        ("1,000 m in km", "1 km"),
        ("1.5 l in ml", "1,500 ml"),
        (".5 kg in g", "500 g"),
    ])
    func readsTheWaysPeopleType(text: String, expected: String) {
        #expect(answer(text) == expected, "\(text)")
    }

    @Test func inchesAndTheWordInAreToldApart() {
        #expect(answer("5 in in cm") == "12.7 cm")
        #expect(answer("5 in cm") == "12.7 cm")
        #expect(answer("5 m in ft") == "16.4042 ft")
    }

    @Test func withoutATargetTheUsualOnesAnswer() throws {
        let c = try #require(UnitConverter.convert("5 ft", locale: gb))
        #expect(!c.asked)
        #expect(c.results.map(\.unit.id) == ["m", "cm"])
        #expect(c.sentence == "5 ft = 1.524 m")
        let speed = try #require(UnitConverter.convert("60 miles per hour", locale: gb))
        #expect(speed.results.map(\.unit.id) == ["kmh"])
    }

    @Test func pintsAndGallonsFollowTheRegion() {
        #expect(answer("1 pint in ml") == "473.176 ml")
        #expect(answer("1 pint in ml", imperial: true) == "568.261 ml")
        #expect(answer("1 gallon in l", imperial: true) == "4.54609 l")
        // Said outright, the other one is still there.
        #expect(answer("1 us gallon in l", imperial: true) == "3.78541 l")
        #expect(UnitConverter.usesImperialVolumes(Locale(identifier: "en_GB")))
        #expect(!UnitConverter.usesImperialVolumes(Locale(identifier: "en_US")))
    }

    @Test(arguments: ["", "hello", "5", "five ft in cm", "5 ft in kg", "5 apples in pears", "ft in cm",
                      "1e400 m in km", "1,00,0 m in km"])
    func nonsenseIsNotAnAnswer(text: String) {
        #expect(UnitConverter.convert(text, locale: gb) == nil, "\(text)")
    }

    @Test func aCommaCanBeTheDecimalPoint() {
        #expect(answer("5,5 kg in g") == "5,500 g")
        #expect(answer("12,000 g in kg") == "12 kg")
    }

    @Test func numbersAreWrittenTheRegionsWay() {
        #expect(UnitConverter.format(1500.25, locale: gb) == "1,500.25")
        #expect(UnitConverter.format(1500.25, locale: Locale(identifier: "de_DE")) == "1.500,25")
        #expect(UnitConverter.format(0.000000000001, locale: gb) == "0")
        #expect(UnitConverter.format(1.0 / 3.0, locale: gb) == "0.333333")
    }

    @Test func longWholeNumbersAreNotRoundedOff() {
        #expect(answer("1 mi in mm") == "1,609,344 mm")
        #expect(answer("1000 mi in m") == "1,609,344 m")
        #expect(UnitConverter.format(123_456_789.4, locale: gb) == "123,456,789")
        #expect(UnitConverter.format(999_999.6, locale: gb) == "1,000,000")
        // Below a million, six significant figures as before.
        #expect(answer("100 mi in m") == "160,934 m")
    }

    @Test func theNumberCopiedHasNoThousandsSeparators() throws {
        let r = try #require(UnitConverter.convert("1 mi in mm", locale: gb)?.results.first)
        #expect(r.number == "1,609,344")
        #expect(r.plainNumber == "1609344")
        let de = try #require(UnitConverter.convert("1.5 l in ml", locale: Locale(identifier: "de_DE"))?.results.first)
        #expect(de.number == "1.500")
        #expect(de.plainNumber == "1500")
        let small = try #require(UnitConverter.convert("5 ft in cm", locale: gb)?.results.first)
        #expect(small.plainNumber == "152.4")
        #expect(UnitConverter.format(-1234.5, locale: gb, grouped: false) == "-1234.5")
    }

    @Test func everyUnitHasItsOwnNamesAndAFoundationUnit() {
        var seen: [String: String] = [:]
        for unit in UnitConverter.units {
            for name in unit.names {
                #expect(seen[name] == nil, "\(name) is \(seen[name] ?? "") and \(unit.id)")
                seen[name] = unit.id
            }
            // Each converts to the others of its kind and back.
            let back = Measurement(value: 3, unit: unit.foundation).converted(to: unit.foundation).value
            #expect(abs(back - 3) < 1e-9)
            #expect(!UnitConverter.defaultTargets(for: unit, imperialVolumes: false).isEmpty, "\(unit.id)")
            #expect(UnitConverter.defaultTargets(for: unit, imperialVolumes: false).allSatisfy { $0.dimension == unit.dimension })
        }
        #expect(Set(UnitConverter.units.map(\.dimension)) == Set(ConverterDimension.allCases))
    }

    @Test func theExamplesAllAnswer() {
        for example in UnitConverter.examples {
            #expect(UnitConverter.convert(example, locale: gb)?.asked == true, "\(example)")
        }
    }
}
