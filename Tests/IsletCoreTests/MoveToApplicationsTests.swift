import Foundation
import Testing
@testable import IsletCore

/// Opened straight from Downloads, macOS runs Islet from a temporary copy that moves at every
/// launch, so hooks and Login Items lose it. Islet asks, in plain words, to move to Applications.
@Suite struct MoveToApplicationsTests {
    static let home = "/Users/a"
    static let translocated = "/private/var/folders/xy/abc/T/AppTranslocation/1F2E3D4C-5B6A-4798-8A7B-6C5D4E3F2A1B/d/Islet.app"
    static let downloads = "/Users/a/Downloads/Islet.app"

    @Test func aTemporaryCopyIsTranslocated() {
        #expect(AppLocation.isTranslocated(bundlePath: Self.translocated))
        #expect(!AppLocation.isTranslocated(bundlePath: Self.downloads))
        #expect(!AppLocation.isTranslocated(bundlePath: "/Applications/Islet.app"))
    }

    @Test(arguments: [
        // (where Islet runs, the moment, whether it offers)
        (translocated, AppLocation.MoveMoment.launch, true),
        (translocated, .connecting("Claude Code"), true),
        (translocated, .asked, true),
        // Moved out of Downloads by hand, say to the Desktop: it keeps working, so only Settings offers.
        (downloads, .launch, false),
        (downloads, .connecting("Codex"), false),
        (downloads, .asked, true),
        ("/Applications/Islet.app", .launch, false),
        ("/Applications/Islet.app", .asked, false),
        ("/Users/a/Applications/Islet.app", .connecting("Cursor"), false),
        ("/Users/a/Applications/Islet.app", .asked, false),
    ])
    func whenIsletOffersToMove(path: String, moment: AppLocation.MoveMoment, offers: Bool) {
        #expect(AppLocation.offersMove(bundlePath: path, home: Self.home, isAppBundle: true, moment: moment) == offers)
    }

    @Test func aBuildRunFromTheCommandLineNeverOffers() {
        for moment in [AppLocation.MoveMoment.launch, .connecting("Claude Code"), .asked] {
            #expect(!AppLocation.offersMove(bundlePath: Self.translocated, home: Self.home, isAppBundle: false, moment: moment))
        }
    }

    @Test func itGoesToApplicationsOrTheHomeFoldersOwn() {
        #expect(AppLocation.destination(appName: "Islet.app", home: Self.home, canWriteSharedApplications: true)
                == "/Applications/Islet.app")
        #expect(AppLocation.destination(appName: "Islet.app", home: Self.home, canWriteSharedApplications: false)
                == "/Users/a/Applications/Islet.app")
    }

    @Test func atLaunchItSaysWhyAndOffersToMove() {
        let p = AppLocation.prompt(for: .launch, folder: "Downloads", translocated: true, destination: "/Applications/Islet.app",
                                   home: Self.home, replacing: false)
        #expect(p.title == "Move Islet to Applications?")
        #expect(p.message.hasPrefix("Islet is still in Downloads, so macOS runs it from a temporary copy"))
        #expect(p.message.contains("Connected coding agents would lose track of it"))
        #expect(p.message.hasSuffix("Islet can move itself to Applications and open again from there."))
        #expect(p.confirm == "Move to Applications")
        #expect(p.cancel == "Not now")
        #expect(!p.message.contains("Bin"))
    }

    @Test func beforeConnectingItNamesTheAgent() {
        let p = AppLocation.prompt(for: .connecting("Claude Code"), folder: "Downloads", translocated: true,
                                   destination: "/Applications/Islet.app", home: Self.home, replacing: false)
        #expect(p.title == "Move Islet to Applications first?")
        #expect(p.message.contains("If you connect Claude Code now, it loses track of Islet the next time Islet opens."))
        #expect(p.message.contains("and then you can connect"))
        #expect(p.cancel == "Cancel")
    }

    @Test func askedInSettingsFromAnotherFolder() {
        let p = AppLocation.prompt(for: .asked, folder: "Desktop", translocated: false, destination: "/Users/a/Applications/Islet.app",
                                   home: Self.home, replacing: true)
        #expect(p.message.hasPrefix("Islet runs from Desktop."))
        #expect(p.message.contains("move itself to Applications in your home folder"))
        #expect(p.message.hasSuffix("The copy of Islet already there goes to the Bin."))
        #expect(p.cancel == "Cancel")
        // macOS didn't say where the download is.
        let unknown = AppLocation.prompt(for: .launch, folder: nil, translocated: true, destination: "/Applications/Islet.app",
                                         home: Self.home, replacing: false)
        #expect(unknown.message.hasPrefix("Islet hasn't been moved to Applications, so macOS runs it"))
    }

    /// The owner's rules for words people read: plain, British, no em dashes, nothing technical.
    @Test func theWordsArePlain() {
        let moments: [AppLocation.MoveMoment] = [.launch, .connecting("Codex"), .asked]
        for moment in moments {
            for translocated in [true, false] {
                let p = AppLocation.prompt(for: moment, folder: "Downloads", translocated: translocated,
                                           destination: "/Applications/Islet.app", home: Self.home, replacing: true)
                let all = [p.title, p.message, p.confirm, p.cancel].joined(separator: " ")
                for word in ["\u{2014}", "translocat", "quarantine", "bundle", "hook", "/", "Trash"] {
                    #expect(!all.contains(word), "\(moment) \(translocated): \(word)")
                }
            }
        }
    }

    /// The new copy opens once this one has quit. The path is an argument of its own, so a
    /// folder name with quotes or a `$` can't change the command.
    @Test func reopeningWaitsForThisCopyToQuit() {
        let path = "/Users/a/Applications/Islet \"$(x)\".app"
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
