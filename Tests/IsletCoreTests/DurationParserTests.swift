import Foundation
import Testing
@testable import IsletCore

@Suite struct DurationParserTests {
    /// Wednesday 30 September 2026, 17:45:10 UTC.
    let now: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 9; c.day = 30; c.hour = 17; c.minute = 45; c.second = 10
        return utc.date(from: c)!
    }()

    static var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    func parse(_ s: String, unit: TimeInterval = 60) throws -> DurationParser.Result {
        try DurationParser.parse(s, now: now, calendar: Self.utc, bareNumberUnit: unit)
    }

    func seconds(_ s: String) throws -> TimeInterval { try parse(s).seconds }

    @Test func compactUnits() throws {
        #expect(try seconds("20m") == 1200)
        #expect(try seconds("90s") == 90)
        #expect(try seconds("1h") == 3600)
        #expect(try seconds("1.5h") == 5400)
        #expect(try seconds("45sec") == 45)
        #expect(try seconds("2hrs") == 7200)
        #expect(try seconds("20M") == 1200)
    }

    @Test func compoundDurations() throws {
        #expect(try seconds("1h 30m") == 5400)
        #expect(try seconds("1h30m") == 5400)
        #expect(try seconds("1h30") == 5400)
        #expect(try seconds("5m30") == 330)
        #expect(try seconds("1 hour and 30 minutes") == 5400)
        #expect(try seconds("2 hours, 15 minutes") == 8100)
        #expect(try seconds("1h 5m 10s") == 3910)
    }

    @Test func wordsAndPhrases() throws {
        #expect(try seconds("25 min") == 1500)
        #expect(try seconds("25 minutes") == 1500)
        #expect(try seconds("half an hour") == 1800)
        #expect(try seconds("half a minute") == 30)
        #expect(try seconds("an hour") == 3600)
        #expect(try seconds("a minute") == 60)
        #expect(try seconds("an hour and a half") == 5400)
        #expect(try seconds("one and a half hours") == 5400)
        #expect(try seconds("a quarter of an hour") == 900)
        #expect(try seconds("a couple of minutes") == 120)
        #expect(try seconds("twenty five minutes") == 1500)
        #expect(try seconds("forty-five seconds") == 45)
        #expect(try seconds("ninety seconds") == 90)
        #expect(try seconds("ten minutes") == 600)
    }

    @Test func titleIsTheRemainingText() throws {
        #expect(try parse("in 20 minutes to take the pizza out") == .init(seconds: 1200, title: "Take the pizza out"))
        #expect(try parse("tea 4m") == .init(seconds: 240, title: "Tea"))
        #expect(try parse("Tea 4M") == .init(seconds: 240, title: "Tea"))
        #expect(try parse("pizza in 20 minutes") == .init(seconds: 1200, title: "Pizza"))
        #expect(try parse("for 10 min") == .init(seconds: 600, title: nil))
        #expect(try parse("in 20 minutes, check the oven.") == .init(seconds: 1200, title: "Check the oven"))
        #expect(try parse("remind me in 20 minutes to call Sam") == .init(seconds: 1200, title: "Call Sam"))
        #expect(try parse("set a timer for 10 minutes") == .init(seconds: 600, title: nil))
        #expect(try parse("10 minute tea timer") == .init(seconds: 600, title: "Tea"))
        #expect(try parse("5 minutes and then stretch") == .init(seconds: 300, title: "Stretch"))
        #expect(try parse("Laundry: 45m") == .init(seconds: 2700, title: "Laundry"))
        #expect(try parse("stand-up 15 min") == .init(seconds: 900, title: "Stand-up"))
    }

    @Test func clockTimesRollForward() throws {
        // 17:45:10 now.
        #expect(try seconds("at 18:30") == 44 * 60 + 50)
        #expect(try seconds("until 18:30") == 44 * 60 + 50)
        #expect(try seconds("at 6pm") == 14 * 60 + 50)
        #expect(try seconds("6pm") == 14 * 60 + 50)
        #expect(try seconds("at 6 p.m.") == 14 * 60 + 50)
        #expect(try seconds("at 6:15 pm") == 29 * 60 + 50)
        // Already past today: tomorrow.
        #expect(try seconds("at 17:00") == 23 * 3600 + 14 * 60 + 50)
        #expect(try seconds("at 5pm") == 23 * 3600 + 14 * 60 + 50)
        // "at 6" means whichever of 06:00 and 18:00 comes first; "06:30" is always morning.
        #expect(try seconds("at 6") == 14 * 60 + 50)
        #expect(try seconds("at 06:30") == 12 * 3600 + 44 * 60 + 50)
        #expect(try seconds("at 12am") == 6 * 3600 + 14 * 60 + 50)
        #expect(try seconds("at midnight") == 6 * 3600 + 14 * 60 + 50)
        #expect(try seconds("at noon") == 18 * 3600 + 14 * 60 + 50)
        #expect(try parse("at 6pm call mum") == .init(seconds: 14 * 60 + 50, title: "Call mum"))
        #expect(try parse("call mum at 6pm") == .init(seconds: 14 * 60 + 50, title: "Call mum"))
    }

    @Test func clockTimesJustPastRollToTomorrow() throws {
        let later = now.addingTimeInterval(30 * 60) // 18:15:10
        let r = try DurationParser.parse("at 6pm", now: later, calendar: Self.utc)
        #expect(r.seconds == 23 * 3600 + 44 * 60 + 50)
        #expect(r.seconds <= DurationParser.maxSeconds)
    }

    @Test func bareNumbers() throws {
        #expect(try seconds("25") == 1500)
        #expect(try parse("25", unit: 1).seconds == 25)
        #expect(try parse("300", unit: 1).seconds == 300)
        #expect(try parse("tea 4") == .init(seconds: 240, title: "Tea"))
        #expect(try parse("in 5") == .init(seconds: 300, title: nil))
    }

    @Test func rejectsNonsense() throws {
        #expect(throws: DurationParser.Failure.empty) { try parse("") }
        #expect(throws: DurationParser.Failure.empty) { try parse("   ") }
        #expect(throws: DurationParser.Failure.noDuration("hello")) { try parse("hello") }
        #expect(throws: DurationParser.Failure.noDuration("take 2 pills")) { try parse("take 2 pills") }
        #expect(throws: DurationParser.Failure.noDuration("m")) { try parse("m") }
        #expect(throws: DurationParser.Failure.noDuration("take a break")) { try parse("take a break") }
        #expect(throws: DurationParser.Failure.noDuration("at 25:00")) { try parse("at 25:00") }
        #expect(throws: DurationParser.Failure.noDuration("at 18:75")) { try parse("at 18:75") }
        #expect(throws: DurationParser.Failure.noDuration("13pm")) { try parse("13pm") }
        #expect(throws: DurationParser.Failure.tooShort) { try parse("0m") }
        #expect(throws: DurationParser.Failure.tooLong) { try parse("25 hours") }
        #expect(throws: DurationParser.Failure.tooLong) { try parse("24h 1m") }
        #expect(throws: DurationParser.Failure.tooLong) { try parse("99999999999999h") }
        #expect(try seconds("24h") == 86400)
    }

    @Test func messagesExplainTheFormat() {
        #expect(DurationParser.Failure.noDuration("x").description.contains("tea 4m"))
        #expect(DurationParser.Failure.tooLong.description.contains("24 hours"))
    }

    @Test func tokenizerSplitsNumbersAndLetters() {
        let t = DurationParser.tokenize(["1h30m", "6:15pm", "forty-five", "1.5h"]).map(\.text)
        #expect(t == ["1", "h", "30", "m", "6:15", "pm", "forty", "five", "1.5", "h"])
    }
}
