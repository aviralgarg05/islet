import AppKit
import CasementCore
import SwiftUI

extension Snapshots {
    /// Meeting reminders (counting down, started, the sneak peek and Home leading with Join),
    /// the Today page when calendar access is missing, and two players at once. Leaves the
    /// model as it found it.
    static func renderCalendarAndPlayers(model: AppModel, now: Date, shoot: (String) -> Void,
                                         size: (SizePreset) -> Void, placement: (ClosedPlacement?) -> Void) {
        let demoAgenda = model.agenda
        let song = model.nowPlaying

        // A FaceTime call in eight and a half minutes (FaceTime's own icon), and a Google Meet
        // that started three minutes ago (no Mac app: a video glyph).
        let soon = AgendaItem(id: "snap-soon", title: "Design review", start: now.addingTimeInterval(8.5 * 60),
                              end: now.addingTimeInterval(38.5 * 60), calendarColor: "#FF9F0A",
                              meetingURL: URL(string: "https://facetime.apple.com/join#v=1&p=abc"))
        let started = AgendaItem(id: "snap-now", title: "Weekly planning", start: now.addingTimeInterval(-3 * 60),
                                 end: now.addingTimeInterval(27 * 60), calendarColor: "#0A84FF",
                                 meetingURL: URL(string: "https://meet.google.com/abc-defg-hij"))
        func reminder(_ id: String) -> Activity? {
            model.activities.first { MeetingReminders.isReminder($0) && $0.title == id }
        }

        model.showMeetingsForSnapshot([soon], now: now)
        if let a = reminder("Design review") {
            model.forcedPresentation = .compact(.activity(a, others: 0))
            shoot("70-compact-meeting-soon")
            placement(ClosedPlacement(wing: MenuBarLayoutEngine.iconOnlyWing, slack: 0))
            shoot("i70-compact-meeting-soon")
            // Full width with room beside it, as the other "w" shots: the wing width set, which a
            // measured menu bar never exceeds.
            placement(ClosedPlacement(wing: CGFloat(model.settings.effectiveWingWidth), slack: .infinity))
            shoot("w70-compact-meeting-soon")
            placement(nil)
            model.forcedPresentation = .sneak(a)
            shoot("71-sneak-meeting-soon")
            model.forcedPresentation = .expanded
            model.tab = .home
            shoot("72-expanded-home-meeting-soon")
        }
        model.showMeetingsForSnapshot([started], now: now)
        if let a = reminder("Weekly planning") {
            model.forcedPresentation = .compact(.activity(a, others: 0))
            shoot("73-compact-meeting-now")
            // "Now" stays a word even in the narrowest wing.
            placement(ClosedPlacement(wing: MenuBarLayoutEngine.iconOnlyWing, slack: 0))
            shoot("i73-compact-meeting-now")
            placement(nil)
            model.forcedPresentation = .sneak(a)
            shoot("74-sneak-meeting-now")
            model.forcedPresentation = .expanded
            model.tab = .home
            shoot("75-expanded-home-meeting-now")
            size(.standard)
            shoot("75b-expanded-home-meeting-now-standard")
            size(.compact)
        }
        model.showMeetingsForSnapshot(demoAgenda, now: now)

        // Today without calendar access: "Add events only" for the calendar, reminders turned
        // off in System Settings; then neither asked yet.
        model.forcedPresentation = .expanded
        model.tab = .today
        model.setCalendarAccessForSnapshot(events: .writeOnly, reminders: .denied)
        shoot("76-expanded-today-write-only")
        model.tab = .home
        // Without access there is nothing to read, so no next event beside the line saying why.
        model.showMeetingsForSnapshot([], now: now)
        shoot("76d-expanded-home-calendar-blocked")
        model.showMeetingsForSnapshot(demoAgenda, now: now)
        model.tab = .today
        model.setCalendarAccessForSnapshot(events: .notDetermined, reminders: .notDetermined)
        shoot("76b-expanded-today-not-asked")
        model.setCalendarAccessForSnapshot(events: .notDetermined, reminders: .notDetermined, refused: [.calendars])
        shoot("76c-expanded-today-refused")
        model.setCalendarAccessForSnapshot(events: .fullAccess, reminders: .fullAccess)

        // A video paused in Chrome and a song playing in Spotify: Spotify leads, with Chrome as
        // a chip beside the title; picked, Chrome leads and Spotify is the chip.
        let spotify = NowPlaying(source: .spotify, bundleID: "com.spotify.client", appName: "Spotify", title: "Midnight City",
                                 artist: "M83", album: "Hurry Up, We're Dreaming", isPlaying: true, duration: 243, elapsed: 71,
                                 timestamp: now, shuffle: true, repeatMode: .off)
        let chrome = NowPlaying(source: .browser, bundleID: "com.google.Chrome", appName: "Google Chrome",
                                title: "Keynote highlights", artist: "YouTube", isPlaying: false, duration: 1260, elapsed: 312,
                                timestamp: now.addingTimeInterval(-90))
        model.loadPlayersForSnapshot([spotify], bridge: chrome, now: now)
        model.tab = .home
        shoot("77-expanded-two-players")
        size(.standard)
        shoot("77b-expanded-two-players-standard")
        size(.compact)
        model.pickPlayer(chrome)
        shoot("78-expanded-picked-player")
        // Closed, the island shows what plays: Spotify's song, not the paused video picked.
        if let np = model.closedNowPlaying {
            model.forcedPresentation = .compact(.nowPlaying(np))
            shoot("79-compact-picked-player")
        }

        // Every player macOS lists: a live video playing in Chrome, which has the controls, a song
        // paused in Spotify an hour ago and a Safari tab. Both are chips; closed, the video shows.
        // The video, outside a playlist, has no next or previous track: those buttons are faint.
        let stream = NowPlaying(source: .browser, bundleID: "com.google.Chrome", appName: "Google Chrome",
                                title: "Harbour lights, live", artist: "Slow TV", isPlaying: true, elapsed: 0, timestamp: now,
                                commands: [.play, .pause, .togglePlayPause, .seek])
        let pausedSong = NowPlaying(source: .system, bundleID: "com.spotify.client", appName: "Spotify", title: "Midnight City",
                                    artist: "M83", album: "Hurry Up, We're Dreaming", isPlaying: false, duration: 243, elapsed: 71,
                                    timestamp: now.addingTimeInterval(-3600))
        let tab = NowPlaying(source: .browser, bundleID: "com.apple.Safari", appName: "Safari", title: "Bread at home",
                             artist: "Kitchen notes", isPlaying: false, duration: 840, elapsed: 125, timestamp: now.addingTimeInterval(-600))
        model.loadPlayersForSnapshot([], bridge: BridgeReport(players: [stream, pausedSong, tab], current: "com.google.Chrome"), now: now)
        model.forcedPresentation = .expanded
        model.tab = .home
        shoot("79b-expanded-every-player")
        if let np = model.closedNowPlaying {
            model.forcedPresentation = .compact(.nowPlaying(np))
            shoot("79c-compact-every-player")
        }
        model.forcedPresentation = .expanded
        // The song paused an hour ago, picked: it shows, and Spotify's own controls take it.
        model.pickPlayer(pausedSong)
        shoot("79d-expanded-picked-long-paused")
        // The Safari tab, picked: Chrome has the controls, so a press says so and offers Safari.
        model.pickPlayer(tab)
        model.setControlHintForSnapshot(.otherApp(OtherAppHint(app: "Safari", bundleID: "com.apple.Safari", holder: "Google Chrome")))
        shoot("79e-expanded-other-app-hint")
        size(.standard)
        shoot("79f-expanded-other-app-hint-standard")
        size(.compact)
        // The live video on show while Spotify, paused, has the controls: "Open Google Chrome" is
        // long, and the words beside it keep their room. Then with nobody holding the controls.
        model.loadPlayersForSnapshot([], bridge: BridgeReport(players: [stream, pausedSong], current: "com.spotify.client"), now: now)
        model.forcedPresentation = .expanded
        model.tab = .home
        model.setControlHintForSnapshot(.otherApp(OtherAppHint(app: "Google Chrome", bundleID: "com.google.Chrome", holder: "Spotify")))
        shoot("79g-expanded-other-app-hint-long-name")
        size(.standard)
        shoot("79h-expanded-other-app-hint-long-name-standard")
        size(.compact)
        model.setControlHintForSnapshot(.otherApp(OtherAppHint(app: "Google Chrome", bundleID: "com.google.Chrome", holder: nil)))
        shoot("79i-expanded-other-app-hint-no-holder")
        model.setControlHintForSnapshot(nil)
        model.loadPlayersForSnapshot([], bridge: nil, now: now, song: song)
        model.forcedPresentation = .expanded
        model.tab = .home
    }
}
