import Foundation
import Testing
@testable import IsletCore

/// The title beside Now Playing's artwork keeps its room: at the compact size the player chip
/// and the volume button used to cut "Midnight City" to "Midnight…".
@Suite struct NowPlayingTitleRowTests {
    /// The row's spacing on either side of the gap between title and buttons (two of `Space.m`).
    static let spacing = 24.0

    /// The width beside the artwork for a card `hero` points wide with `art`-point artwork.
    static func width(hero: Double, art: Double) -> Double { hero - art - 12 }

    typealias Layout = NowPlayingTitleRow.Layout

    @Test(arguments: [
        // (others, expected): the compact size beside the glances, 200 points with 40-point artwork.
        (0, Layout(chips: 0, showsVolume: true)),
        // Room for the title takes the volume button away, not the chip.
        (1, Layout(chips: 1, showsVolume: false)),
        // Several other players: one chip, so another player can still be picked.
        (3, Layout(chips: 1, showsVolume: false)),
        (5, Layout(chips: 1, showsVolume: false)),
    ])
    func compactBesideTheGlances(others: Int, expected: Layout) {
        let row = NowPlayingTitleRow.layout(width: Self.width(hero: 200, art: 40), spacing: Self.spacing, otherPlayers: others,
                                            volumeRow: false)
        #expect(row == expected)
        #expect(Self.width(hero: 200, art: 40) - Self.spacing - NowPlayingTitleRow.beside(row) >= NowPlayingTitleRow.titleRoom)
    }

    @Test func theStandardSizeKeepsEverything() {
        let width = Self.width(hero: 290, art: 56)
        #expect(NowPlayingTitleRow.layout(width: width, spacing: Self.spacing, otherPlayers: 1, volumeRow: false)
                == Layout(chips: 1, showsVolume: true))
        #expect(NowPlayingTitleRow.layout(width: width, spacing: Self.spacing, otherPlayers: 3, volumeRow: false)
                == Layout(chips: 3, showsVolume: true))
        // Never more than three chips.
        #expect(NowPlayingTitleRow.layout(width: width, spacing: Self.spacing, otherPlayers: 7, volumeRow: false).chips == 3)
    }

    @Test func compactWithTheWholeWidth() {
        // Nothing beside the music: the card has the island's width, and everything fits.
        #expect(NowPlayingTitleRow.layout(width: Self.width(hero: 426, art: 40), spacing: Self.spacing, otherPlayers: 2,
                                          volumeRow: false) == Layout(chips: 2, showsVolume: true))
    }

    @Test func aTallCardHasTheVolumeRowInstead() {
        let row = NowPlayingTitleRow.layout(width: Self.width(hero: 290, art: 72), spacing: Self.spacing, otherPlayers: 1,
                                            volumeRow: true)
        #expect(row == Layout(chips: 1, showsVolume: false))
        #expect(NowPlayingTitleRow.layout(width: 300, spacing: Self.spacing, otherPlayers: 0, volumeRow: true).isEmpty)
    }

    @Test func aVeryNarrowCardStillOffersAnotherPlayer() {
        #expect(NowPlayingTitleRow.layout(width: 90, spacing: Self.spacing, otherPlayers: 2, volumeRow: false)
                == Layout(chips: 1, showsVolume: false))
        #expect(NowPlayingTitleRow.layout(width: 90, spacing: Self.spacing, otherPlayers: 0, volumeRow: false).isEmpty)
        #expect(NowPlayingTitleRow.layout(width: 300, spacing: Self.spacing, otherPlayers: -1, volumeRow: false)
                == Layout(chips: 0, showsVolume: true))
    }
}
