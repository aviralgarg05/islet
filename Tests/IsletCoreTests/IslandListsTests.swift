import Foundation
import Testing
@testable import IsletCore

/// Lists on the open island say how many rows they leave out, as the closed island's "+2" does.
@Suite struct ListFitTests {
    @Test func everythingThatFitsIsShownWithoutALine() {
        #expect(ListFit.fit([32, 32], spacing: 12, in: 90) == .init(shown: 2, more: 0))
        #expect(ListFit.fit([], spacing: 12, in: 90) == .init(shown: 0, more: 0))
        // Heights are estimates: a row a point or two past the edge still counts as fitting.
        #expect(ListFit.fit([30, 30, 30], spacing: 8, in: 104) == .init(shown: 3, more: 0))
    }

    /// Home's column at the compact size: two glances and "+3 more" under them.
    @Test func homeAtTheCompactSize() {
        let fit = ListFit.fit(Array(repeating: 32, count: 5), spacing: 12, in: 90)
        #expect(fit == .init(shown: 2, more: 3))
        #expect(ListFit.moreText(fit.more) == "+3 more")
    }

    /// Today's reminders at the compact size (70 points under the label): the line takes the
    /// second row's place rather than cutting it off.
    @Test func theLineTakesTheLastRowsPlaceWhenItMustFit() {
        #expect(ListFit.fit([30, 30, 30], spacing: 8, in: 70) == .init(shown: 1, more: 2))
        // With the all-day line above, 48 points: one event and the line.
        #expect(ListFit.fit([30, 30], spacing: 8, in: 48) == .init(shown: 1, more: 1))
    }

    @Test func theCountAlwaysAddsUp() {
        for count in 0...8 {
            for room in stride(from: 0.0, through: 240, by: 10) {
                let fit = ListFit.fit(Array(repeating: 30, count: count), spacing: 8, in: room)
                #expect(fit.shown + fit.more == count)
                #expect(fit.more == 0 || fit.more >= 1 && fit.shown < count)
            }
        }
    }
}

@Suite struct GlanceTitleTests {
    @Test func theShortPartAfterTheLastDotStaysWhole() {
        #expect(GlanceTitle.split("Grey Prius · 7ABC123") == ("Grey Prius", " · 7ABC123"))
        #expect(GlanceTitle.split("Claude · islet · tests") == ("Claude · islet", " · tests"))
    }

    @Test func otherTitlesTruncateAsAWhole() {
        #expect(GlanceTitle.split("Design review") == ("Design review", nil))
        #expect(GlanceTitle.split(" · leading") == (" · leading", nil))
        #expect(GlanceTitle.split("Trailing · ") == ("Trailing · ", nil))
        // A long tail would push the rest out: the title truncates as one.
        let long = "Deploy · production-eu-west-2-canary"
        #expect(GlanceTitle.split(long) == (long, nil))
    }
}
