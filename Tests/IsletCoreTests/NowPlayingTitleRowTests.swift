import Foundation
import Testing
@testable import IsletCore

/// The title beside Now Playing's artwork keeps its room: at the compact size the player chip
/// and the volume button used to cut "Midnight City" to "Midnight…". Other players fold into
/// one chip that counts them before the volume button goes.
@Suite struct NowPlayingTitleRowTests {
    /// The row's spacing between the title and what sits beside it (`Space.m`).
    static let spacing = 12.0

    /// The width beside the artwork for a card `hero` points wide with `art`-point artwork.
    static func width(hero: Double, art: Double) -> Double { hero - art - 12 }

    typealias Layout = NowPlayingTitleRow.Layout

    @Test(arguments: [
        // (others, expected): the compact size beside the glances, 200 points with 40-point artwork.
        (0, Layout(chips: 0, showsVolume: true)),
        // Room for the title takes the volume button away, not the chip.
        (1, Layout(chips: 1, showsVolume: false)),
        // Several other players: one chip that counts them, so any of them can still be picked.
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
        // Never more than three chips: the third stands for the other five.
        let seven = NowPlayingTitleRow.layout(width: width, spacing: Self.spacing, otherPlayers: 7, volumeRow: false)
        #expect(seven.chips == 3)
        #expect(seven.folded(otherPlayers: 7) == 5)
    }

    @Test func aFoldedChipCountsThePlayersItStandsFor() {
        #expect(Layout(chips: 1, showsVolume: true).folded(otherPlayers: 1) == 1)
        #expect(Layout(chips: 1, showsVolume: true).folded(otherPlayers: 3) == 3)
        #expect(Layout(chips: 2, showsVolume: true).folded(otherPlayers: 2) == 1)
        #expect(Layout(chips: 0, showsVolume: true).folded(otherPlayers: 0) == 0)
    }

    /// Players fold into one chip before the volume button goes: on a card with room for one
    /// chip and the button, both stay.
    @Test func playersFoldBeforeTheVolumeButtonGoes() {
        let width = Self.width(hero: 200, art: 40) + 22
        #expect(NowPlayingTitleRow.layout(width: width, spacing: Self.spacing, otherPlayers: 3, volumeRow: false)
                == Layout(chips: 1, showsVolume: true))
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

/// The lyrics button on the Now Playing card fits at every size without cutting the title: in
/// the row where there is room, under the other buttons where there isn't.
@Suite struct NowPlayingLyricsButtonTests {
    typealias Layout = NowPlayingTitleRow.Layout
    static let spacing = 12.0

    @Test func compactBesideTheGlancesPutsItUnderTheVolumeButton() {
        let width = NowPlayingTitleRowTests.width(hero: 201, art: 40)
        let row = NowPlayingTitleRow.layout(width: width, spacing: Self.spacing, otherPlayers: 0, volumeRow: false, lyrics: true)
        #expect(row == Layout(chips: 0, showsVolume: true, lyrics: .below))
        #expect(width - Self.spacing - NowPlayingTitleRow.beside(row) >= NowPlayingTitleRow.titleRoom)
        // With another player, under its chip.
        #expect(NowPlayingTitleRow.layout(width: width, spacing: Self.spacing, otherPlayers: 2, volumeRow: false, lyrics: true)
                == Layout(chips: 1, showsVolume: false, lyrics: .below))
    }

    @Test func roomyCardsKeepItInTheRow() {
        // Compact with the whole width, standard, and large (with its volume row).
        #expect(NowPlayingTitleRow.layout(width: NowPlayingTitleRowTests.width(hero: 428, art: 40), spacing: Self.spacing,
                                          otherPlayers: 0, volumeRow: false, lyrics: true)
                == Layout(chips: 0, showsVolume: true, lyrics: .beside))
        #expect(NowPlayingTitleRow.layout(width: NowPlayingTitleRowTests.width(hero: 291, art: 56), spacing: Self.spacing,
                                          otherPlayers: 1, volumeRow: false, lyrics: true)
                == Layout(chips: 1, showsVolume: true, lyrics: .beside))
        #expect(NowPlayingTitleRow.layout(width: NowPlayingTitleRowTests.width(hero: 347, art: 72), spacing: Self.spacing,
                                          otherPlayers: 0, volumeRow: true, lyrics: true)
                == Layout(chips: 0, showsVolume: false, lyrics: .beside))
    }

    @Test func itMovesUnderBeforePlayersFold() {
        let width = NowPlayingTitleRowTests.width(hero: 291, art: 56)
        #expect(NowPlayingTitleRow.layout(width: width, spacing: Self.spacing, otherPlayers: 3, volumeRow: false, lyrics: true)
                == Layout(chips: 3, showsVolume: true, lyrics: .below))
    }

    @Test func noButtonWithoutASongOrRoom() {
        #expect(NowPlayingTitleRow.layout(width: 300, spacing: Self.spacing, otherPlayers: 0, volumeRow: false)
                == Layout(chips: 0, showsVolume: true, lyrics: .none))
        #expect(NowPlayingTitleRow.layout(width: 100, spacing: Self.spacing, otherPlayers: 0, volumeRow: true, lyrics: true).isEmpty)
        #expect(!Layout(chips: 0, showsVolume: false, lyrics: .beside).isEmpty)
    }
}
