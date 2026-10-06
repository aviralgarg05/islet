import Foundation
import Testing
@testable import CasementCore

/// Opened straight from Downloads, macOS runs Casement from a temporary copy that moves at every
/// launch, so hooks and Login Items lose it. Casement asks, in plain words, to move to Applications.
@Suite struct MoveToApplicationsTests {
    static let home = "/Users/a"
    static let translocated = "/private/var/folders/xy/abc/T/AppTranslocation/1F2E3D4C-5B6A-4798-8A7B-6C5D4E3F2A1B/d/Casement.app"
    static let downloads = "/Users/a/Downloads/Casement.app"

    @Test func aTemporaryCopyIsTranslocated() {
        #expect(AppLocation.isTranslocated(bundlePath: Self.translocated))
        #expect(!AppLocation.isTranslocated(bundlePath: Self.downloads))
        #expect(!AppLocation.isTranslocated(bundlePath: "/Applications/Casement.app"))
    }

    @Test(arguments: [
        // (where Casement runs, the moment, whether it offers)
        (translocated, AppLocation.MoveMoment.launch, true),
        (translocated, .connecting("Claude Code"), true),
        (translocated, .asked, true),
        // Moved out of Downloads by hand, say to the Desktop: it keeps working, so only Settings offers.
        (downloads, .launch, false),
        (downloads, .connecting("Codex"), false),
        (downloads, .asked, true),
        ("/Applications/Casement.app", .launch, false),
        ("/Applications/Casement.app", .asked, false),
        ("/Users/a/Applications/Casement.app", .connecting("Cursor"), false),
        ("/Users/a/Applications/Casement.app", .asked, false),
    ])
    func whenCasementOffersToMove(path: String, moment: AppLocation.MoveMoment, offers: Bool) {
        #expect(AppLocation.offersMove(bundlePath: path, home: Self.home, isAppBundle: true, moment: moment) == offers)
    }

    @Test func aBuildRunFromTheCommandLineNeverOffers() {
        for moment in [AppLocation.MoveMoment.launch, .connecting("Claude Code"), .asked] {
            #expect(!AppLocation.offersMove(bundlePath: Self.translocated, home: Self.home, isAppBundle: false, moment: moment))
        }
    }

    @Test func itGoesToApplicationsOrTheHomeFoldersOwn() {
        #expect(AppLocation.destination(appName: "Casement.app", home: Self.home, canWriteSharedApplications: true)
                == "/Applications/Casement.app")
        #expect(AppLocation.destination(appName: "Casement.app", home: Self.home, canWriteSharedApplications: false)
                == "/Users/a/Applications/Casement.app")
    }

    @Test func atLaunchItSaysWhyAndOffersToMove() {
        let p = AppLocation.prompt(for: .launch, folder: "Downloads", translocated: true, destination: "/Applications/Casement.app",
                                   home: Self.home, replacing: false)
        #expect(p.title == "Move Casement to Applications?")
        #expect(p.message == "Casement is still in Downloads, so it may not open at login and coding agents can lose track of it."
                + " Casement can move itself to Applications and reopen.")
        #expect(p.confirm == "Move to Applications")
        #expect(p.cancel == "Not now")
        #expect(!p.message.contains("Bin"))
    }

    @Test func beforeConnectingItNamesTheAgent() {
        let p = AppLocation.prompt(for: .connecting("Claude Code"), folder: "Downloads", translocated: true,
                                   destination: "/Applications/Casement.app", home: Self.home, replacing: false)
        #expect(p.title == "Move Casement to Applications first?")
        #expect(p.message.contains("Claude Code would lose track of it the next time Casement opens."))
        #expect(p.message.hasSuffix("and reopen, then you can connect."))
        #expect(p.cancel == "Cancel")
    }

    @Test func askedInSettingsFromAnotherFolder() {
        let p = AppLocation.prompt(for: .asked, folder: "Desktop", translocated: false, destination: "/Users/a/Applications/Casement.app",
                                   home: Self.home, replacing: true)
        #expect(p.message.hasPrefix("Casement runs from Desktop."))
        #expect(p.message.contains("move itself to Applications in your home folder"))
        #expect(p.message.hasSuffix("The copy of Casement already there goes to the Bin."))
        #expect(p.cancel == "Cancel")
        // macOS didn't say where the download is.
        let unknown = AppLocation.prompt(for: .launch, folder: nil, translocated: true, destination: "/Applications/Casement.app",
                                         home: Self.home, replacing: false)
        #expect(unknown.message.hasPrefix("Casement hasn\u{2019}t been moved to Applications, so it may not open at login"))
    }

    /// The owner's rules for words people read: plain, British, no em dashes, nothing technical.
    @Test func theWordsArePlain() {
        let moments: [AppLocation.MoveMoment] = [.launch, .connecting("Codex"), .asked]
        for moment in moments {
            for translocated in [true, false] {
                let p = AppLocation.prompt(for: moment, folder: "Downloads", translocated: translocated,
                                           destination: "/Applications/Casement.app", home: Self.home, replacing: true)
                let all = [p.title, p.message, p.confirm, p.cancel].joined(separator: " ")
                for word in ["\u{2014}", "translocat", "quarantine", "bundle", "hook", "/", "Trash"] {
                    #expect(!all.contains(word), "\(moment) \(translocated): \(word)")
                }
            }
        }
    }

    /// The offer is short: what goes wrong, and what Casement can do, in two sentences.
    @Test func theOfferIsTwoSentences() {
        let moments: [AppLocation.MoveMoment] = [.launch, .connecting("Codex"), .asked]
        for moment in moments {
            for folder in ["Downloads", nil] {
                let p = AppLocation.prompt(for: moment, folder: folder, translocated: true, destination: "/Applications/Casement.app",
                                           home: Self.home, replacing: false)
                let sentences = p.message.split(separator: ".", omittingEmptySubsequences: true)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                #expect(sentences.count == 2, "\(moment): \(p.message)")
                #expect(!p.message.contains("'"), "straight apostrophe in \(p.message)")
            }
        }
    }

    /// The new copy opens once this one has quit. The path is an argument of its own, so a
    /// folder name with quotes or a `$` can't change the command.
    @Test func reopeningWaitsForThisCopyToQuit() {
        let path = "/Users/a/Applications/Casement \"$(x)\".app"
        let args = AppLocation.reopenArguments(pid: 4242, appPath: path)
        #expect(args.count == 4)
        #expect(args[0] == "/bin/sh")
        #expect(args[1] == "-c")
        #expect(args[2].contains("kill -0 4242"))
        #expect(args[2].hasSuffix("/usr/bin/open \"$0\""))
        #expect(!args[2].contains(path))
        #expect(args[3] == path)
    }
}
