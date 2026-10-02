import AppKit
import CoreLocation
import IsletCore
import IsletSystem
import Observation

/// The tools that start off: lyrics, shortcuts, weather, the month calendar, the stopwatch and
/// focus sounds. Each keeps its own state; `AppModel.applyEverydayTools()` follows their switches.
@MainActor
final class Tools {
    let lyrics: LyricsController
    let shortcuts: ShortcutsController
    let weather: WeatherController
    let month = MonthCalendarController()
    let stopwatch: StopwatchController
    let focus: FocusSoundController
    /// To-dos, the quick note, the converter and emoji (NoteTools.swift).
    let todos = TodoController()
    let note = NoteController()
    let converter = ConverterController()
    let emoji = EmojiController()
    let clipboardPage = ClipboardPage()

    init(model: AppModel) {
        lyrics = LyricsController(model: model)
        shortcuts = ShortcutsController(model: model)
        weather = WeatherController(model: model)
        stopwatch = StopwatchController(model: model)
        focus = FocusSoundController(model: model)
    }
}

extension AppModel {
    /// Follow these tools' switches: whatever was turned off stops and forgets what it had.
    /// Called from `applyTools()` (AppModel+Tools.swift) with the tools under More.
    func applyEverydayTools() {
        let s = settings
        tools.lyrics.settingsChanged()
        if !s.stopwatchEnabled { tools.stopwatch.reset() }
        tools.weather.settingsChanged()
        tools.focus.update()
        if tab == .shortcuts && !s.shortcutsEnabled || tab == .weather && !s.weatherEnabled { select(tab: .home) }
        applyNoteTools()
    }

    /// Turns a tool on or off from the island (its page's "Turn on").
    func setTool(_ key: WritableKeyPath<IsletSettings, Bool>, _ on: Bool) {
        settings[keyPath: key] = on
        saveAndApplySettings()
    }
}

// MARK: - Lyrics

/// Lyrics for the song on show. Looked up only while lyrics are on and Now Playing is in the
/// open island, once per song (`LyricsService` keeps each answer). The lyrics button on the card
/// shows or hides them; with lyrics off it opens an offer that says what turning them on sends,
/// and nothing is sent before **Show lyrics** is clicked.
@MainActor
@Observable
final class LyricsController {
    typealias State = LyricsState

    /// What Home's column shows for the song instead of the glances.
    enum Column: Equatable {
        case lyrics(SongLyrics)
        /// Turning lyrics on, and what that sends. `browser`: the song plays in a web browser,
        /// so **Show lyrics** turns that switch on too.
        case offer(browser: Bool)
        /// Asked for with the button and not back yet.
        case lookingUp
        /// Asked for with the button, and none came: said for a moment, then the glances return.
        case note(String)
    }

    private(set) var state: State = .idle
    /// The song `state` is about.
    private(set) var trackKey: String?
    /// The song whose lyrics were hidden with the button or the "x" on them (the next song shows
    /// its own).
    private(set) var hiddenTrack: String?
    /// The song whose lyrics button was clicked while lyrics were off for it: Home offers them.
    private(set) var offerTrack: String?
    /// The song asked for with the button: while it is looked up Home shows a spinner, and
    /// "No lyrics for this song" for a moment when there are none. Lookups on their own (a new
    /// song) stay quiet and leave the glances until lyrics are found.
    private(set) var askedTrack: String?
    /// Bumped when the switches in Settings ask for the song on show to be looked up again
    /// (lyrics turned on, or browsers switched while on). Home's card looks it up then, without
    /// waiting for the next song.
    private(set) var resets = 0

    @ObservationIgnored private unowned let model: AppModel
    @ObservationIgnored private lazy var service = LyricsService(
        cache: LyricsCache(directory: IsletPaths.supportDirectory.appendingPathComponent("lyrics")), version: AppModel.version)
    @ObservationIgnored private var failedAt: Date?
    /// The switches in Settings as last applied (`settingsChanged`), nil before the first look.
    @ObservationIgnored private var switches: LyricsSwitches?
    /// How long "No lyrics for this song" stays before the glances come back.
    static let noteSeconds: Double = 4

    init(model: AppModel) {
        self.model = model
    }

    /// The lyrics for `np`, once found.
    func lyrics(for np: NowPlaying) -> SongLyrics? {
        guard np.trackKey == trackKey, case .found(let lyrics) = state else { return nil }
        return lyrics
    }

    func state(for np: NowPlaying) -> State {
        np.trackKey == trackKey ? state : .idle
    }

    func isHidden(_ np: NowPlaying) -> Bool { hiddenTrack == np.trackKey }

    /// Lyrics are on for `np`: on, and on for browsers too when it plays in one.
    func isOn(for np: NowPlaying) -> Bool {
        let s = model.settings
        return s.lyricsEnabled && (s.lyricsIncludeBrowsers || LyricsQuery.origin(of: np) != .browser)
    }

    /// The lyrics are in Home's column for `np` (or on their way, asked for): the button is lit.
    func isShowing(_ np: NowPlaying) -> Bool {
        guard isOn(for: np) else { return offerTrack == np.trackKey }
        switch column(for: np) {
        case .lyrics, .lookingUp: return true
        default: return false
        }
    }

    /// What Home's column shows for `np`, or nil for the glances.
    func column(for np: NowPlaying) -> Column? {
        guard isOn(for: np) else {
            return offerTrack == np.trackKey ? .offer(browser: LyricsQuery.origin(of: np) == .browser) : nil
        }
        guard !isHidden(np) else { return nil }
        let asked = askedTrack == np.trackKey
        switch state(for: np) {
        case .found(let lyrics): return .lyrics(lyrics)
        case .idle, .loading: return asked ? .lookingUp : nil
        case .missing: return asked ? .note("No lyrics for this song") : nil
        case .failed: return asked ? .note("Lyrics can\u{2019}t be reached just now") : nil
        }
    }

    /// The lyrics button: the offer while lyrics are off for the song, otherwise show or hide.
    func toggle(_ np: NowPlaying) {
        guard isOn(for: np) else {
            offerTrack = offerTrack == np.trackKey ? nil : np.trackKey
            return
        }
        offerTrack = nil
        if isShowing(np) {
            hide(np)
            return
        }
        hiddenTrack = nil
        if lyrics(for: np) != nil { return }
        askedTrack = np.trackKey
        want(np, force: true)
    }

    /// **Show lyrics** in the offer: lyrics on (for browsers too when the song plays in one),
    /// and this song looked up at once.
    func accept(_ np: NowPlaying) {
        model.settings.lyricsEnabled = true
        if LyricsQuery.origin(of: np) == .browser { model.settings.lyricsIncludeBrowsers = true }
        model.saveAndApplySettings()
        offerTrack = nil
        hiddenTrack = nil
        askedTrack = np.trackKey
        want(np, force: true)
    }

    /// **Not now**: the offer closes, and nothing else changes.
    func decline() {
        offerTrack = nil
    }

    /// Hide the lyrics for this song; Home shows its glances again.
    func hide(_ np: NowPlaying) {
        hiddenTrack = np.trackKey
        if askedTrack == np.trackKey { askedTrack = nil }
    }

    /// Now Playing is on show with `np`: look its lyrics up if they aren't known yet. `force`
    /// (the button) asks again for a song already settled, from the cache when it is there.
    func want(_ np: NowPlaying, force: Bool = false) {
        let s = model.settings
        guard s.lyricsEnabled,
              state.needsLookUp(sameSong: np.trackKey == trackKey, force: force,
                                sinceFailure: Date().timeIntervalSince(failedAt ?? .distantPast)) else { return }
        if askedTrack != np.trackKey { askedTrack = nil }
        if offerTrack != np.trackKey { offerTrack = nil }
        trackKey = np.trackKey
        guard let query = LyricsQuery(np, includeBrowsers: s.lyricsIncludeBrowsers) else {
            state = .missing
            settled(np.trackKey)
            return
        }
        if let saved = service.cached(query) {
            apply(saved)
            settled(np.trackKey)
            return
        }
        state = .loading
        let key = np.trackKey
        service.lookUp(query) { [weak self] result in
            guard let self, self.trackKey == key else { return }
            switch result {
            case .success(let lookup): self.apply(lookup)
            case .failure:
                self.state = .failed
                self.failedAt = Date()
            }
            self.settled(key)
        }
    }

    private func apply(_ lookup: LyricsLookup) {
        switch lookup {
        case .found(let lyrics): state = .found(lyrics)
        case .missing: state = .missing
        }
    }

    /// A lookup the button asked for ended without lyrics: its note shows for a moment, then
    /// the glances come back.
    private func settled(_ key: String) {
        guard askedTrack == key, lyrics(forKey: key) == nil else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.noteSeconds))
            guard let self, self.askedTrack == key, self.lyrics(forKey: key) == nil else { return }
            self.askedTrack = nil
        }
    }

    private func lyrics(forKey key: String) -> SongLyrics? {
        guard key == trackKey, case .found(let lyrics) = state else { return nil }
        return lyrics
    }

    /// Settings changed: lyrics turned off forget what they had. Turned on, or with browsers
    /// switched while on, the song on show is looked up again at once (`resets`). Either way,
    /// lyrics hidden with × show again, and an open offer closes.
    func settingsChanged() {
        let s = model.settings
        let now = LyricsSwitches(enabled: s.lyricsEnabled, browsers: s.lyricsIncludeBrowsers)
        let change = LyricsSwitches.change(from: switches, to: now)
        switches = now
        guard change != .none else { return }
        clear()
        hiddenTrack = nil
        offerTrack = nil
        if change == .lookAgain { resets &+= 1 }
    }

    func clear() {
        state = .idle
        trackKey = nil
        askedTrack = nil
    }

    func showForSnapshot(_ lyrics: SongLyrics?, for np: NowPlaying, hidden: Bool = false) {
        trackKey = np.trackKey
        state = lyrics.map(State.found) ?? .idle
        hiddenTrack = hidden ? np.trackKey : nil
        offerTrack = nil
        askedTrack = nil
        switches = LyricsSwitches(enabled: model.settings.lyricsEnabled, browsers: model.settings.lyricsIncludeBrowsers)
    }

    /// The offer, a lookup under way or its note, for snapshots.
    func showForSnapshot(offer: Bool = false, state: State, asked: Bool, for np: NowPlaying) {
        trackKey = np.trackKey
        self.state = state
        hiddenTrack = nil
        offerTrack = offer ? np.trackKey : nil
        askedTrack = asked ? np.trackKey : nil
        switches = LyricsSwitches(enabled: model.settings.lyricsEnabled, browsers: model.settings.lyricsIncludeBrowsers)
    }
}

// MARK: - Shortcuts

/// The user's shortcuts: read when the Shortcuts page (or the Ask box) opens, at most every half
/// minute, and run one at a time per shortcut.
@MainActor
@Observable
final class ShortcutsController {
    private(set) var items: [ShortcutItem] = []
    private(set) var loaded = false
    private(set) var unavailable = false
    var query = ""
    private(set) var runs: [String: ShortcutRunState] = [:]
    /// Shortcuts run this session, most recent first.
    private(set) var recent: [String] = []

    @ObservationIgnored private unowned let model: AppModel
    @ObservationIgnored private let runner = ShortcutsRunner()
    @ObservationIgnored private var listedAt: Date?
    @ObservationIgnored private var listing = false

    init(model: AppModel) {
        self.model = model
    }

    var results: [ShortcutItem] { ShortcutsCatalog.search(query, in: items, recent: recent) }
    /// What Return runs: nothing until something is typed.
    var returnTarget: ShortcutItem? { ShortcutsCatalog.returnTarget(query, in: items, recent: recent) }

    /// Read the list again, unless it was read in the last 30 seconds.
    func refresh() {
        guard model.settings.shortcutsEnabled, !listing,
              Date().timeIntervalSince(listedAt ?? .distantPast) > 30 else { return }
        listing = true
        runner.list { [weak self] result in
            guard let self else { return }
            self.listing = false
            self.listedAt = Date()
            self.loaded = true
            switch result {
            case .success(let items):
                self.items = items
                self.unavailable = false
            case .failure(.unavailable):
                self.unavailable = true
            case .failure:
                break
            }
        }
    }

    func run(_ item: ShortcutItem) {
        guard runs[item.id] != .running else { return }
        Haptics.play(.tap)
        runs[item.id] = .running
        recent.removeAll { $0 == item.id }
        recent.insert(item.id, at: 0)
        runner.run(item) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.runs[item.id] = .done
            case .failure(.unavailable):
                self.runs[item.id] = .failed(nil)
            case .failure(.failed(let reason)):
                self.runs[item.id] = .failed(reason)
            }
            self.announce(item)
            // "Done" shows for a moment, then the row goes back to rest.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                if self?.runs[item.id] == .done { self?.runs[item.id] = nil }
            }
        }
    }

    /// With the island closed, a quick word when the shortcut has finished.
    private func announce(_ item: ShortcutItem) {
        guard model.expandedScreen == nil, let state = runs[item.id] else { return }
        let ok = state == .done
        var failure: String?
        if case .failed(let reason) = state { failure = reason }
        _ = try? model.applyLocal(ActivitySpec(
            id: "shortcut-run", source: "shortcuts", title: item.name, subtitle: ok ? "Done" : failure ?? "Didn\u{2019}t finish",
            icon: .symbol(ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"), state: ok ? .success : .warning,
            tint: ok ? "green" : "orange", priority: .low, ttl: 3, sneak: true
        ))
    }

    func showForSnapshot(_ items: [ShortcutItem], runs: [String: ShortcutRunState] = [:], query: String = "") {
        self.items = items
        self.runs = runs
        self.query = query
        loaded = true
        unavailable = false
    }
}

// MARK: - Weather

/// The forecast for the chosen place, or for where the Mac is. Fetched when the Weather page
/// opens and the last one is half an hour old, never in the background.
@MainActor
@Observable
final class WeatherController {
    enum Status: Equatable {
        case idle
        case loading
        /// Neither a city nor "where I am" is chosen.
        case needsPlace
        case locationDenied
        case failed
    }

    private(set) var report: WeatherReport?
    private(set) var status: Status = .idle
    /// A city search in Settings.
    private(set) var places: [WeatherPlace] = []
    private(set) var searching = false
    private(set) var searchFailed = false

    @ObservationIgnored private unowned let model: AppModel
    @ObservationIgnored private lazy var service = WeatherService(version: AppModel.version)
    @ObservationIgnored private var location: LocationProvider?
    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private var lastSuccess: Date?
    /// Which place the report is for, and the last request was for, so another place starts afresh.
    @ObservationIgnored private var reportKey: String?
    @ObservationIgnored private var attemptKey: String?

    init(model: AppModel) {
        self.model = model
    }

    /// "My location", or the city's name.
    var placeName: String? {
        let s = model.settings
        return s.weatherUsesLocation ? "My location" : s.weatherPlace?.name
    }

    /// The unit from Settings, with Automatic following the region.
    var unit: TemperatureUnit {
        model.settings.temperatureUnit.resolved(usesUSMeasures: Locale.current.measurementSystem == .us)
    }

    private var key: String? {
        let s = model.settings
        guard s.weatherEnabled else { return nil }
        if s.weatherUsesLocation { return "here" }
        return s.weatherPlace.map { "\(OpenMeteo.rounded($0.latitude)),\(OpenMeteo.rounded($0.longitude))" }
    }

    /// The place or the switch changed: forget a report for somewhere else.
    func settingsChanged() {
        guard key != reportKey, report != nil else { return }
        report = nil
        reportKey = nil
    }

    /// The Weather page is on show: fetch if the last forecast is due for a refresh, or was for
    /// another place.
    func refreshIfDue() {
        let s = model.settings
        guard s.weatherEnabled else { return }
        guard let key else {
            status = .needsPlace
            return
        }
        settingsChanged()
        let samePlace = key == attemptKey
        if samePlace {
            guard status != .loading, WeatherRefresh.isDue(lastAttempt: lastAttempt, lastSuccess: lastSuccess, now: Date()) else { return }
        }
        attemptKey = key
        lastAttempt = Date()
        status = .loading
        if s.weatherUsesLocation {
            let provider = location ?? LocationProvider()
            location = provider
            provider.requestLocation { [weak self] result in
                guard let self, self.key == key else { return }
                switch result {
                case .success(let c): self.fetch(latitude: c.latitude, longitude: c.longitude, key: key)
                case .failure(.denied): self.status = .locationDenied
                case .failure: self.status = .failed
                }
            }
        } else if let place = s.weatherPlace {
            fetch(latitude: place.latitude, longitude: place.longitude, key: key)
        }
    }

    /// Try again now (the page's button after a failure).
    func retry() {
        attemptKey = nil
        status = .idle
        refreshIfDue()
    }

    private func fetch(latitude: Double, longitude: Double, key: String) {
        service.forecast(latitude: latitude, longitude: longitude) { [weak self] result in
            guard let self, self.key == key else { return }
            switch result {
            case .success(let report):
                self.report = report
                self.reportKey = key
                self.lastSuccess = Date()
                self.status = .idle
            case .failure:
                self.status = .failed
            }
        }
    }

    /// Settings: find places by name (a user action, so it goes online).
    func search(_ name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        searching = true
        searchFailed = false
        service.places(named: name) { [weak self] result in
            guard let self else { return }
            self.searching = false
            switch result {
            case .success(let places): self.places = places
            case .failure:
                self.places = []
                self.searchFailed = true
            }
        }
    }

    func clearSearch() {
        places = []
        searchFailed = false
    }

    func showForSnapshot(_ report: WeatherReport?, status: Status = .idle) {
        self.report = report
        self.status = status
        reportKey = key
    }
}

// MARK: - Month calendar

/// The month shown on Today, the day picked in it (`MonthCalendarState`), and that month's
/// events, read when the month calendar is on screen and again when the calendars change.
@MainActor
@Observable
final class MonthCalendarController {
    private(set) var state = MonthCalendarState(now: Date())
    private(set) var events: [AgendaItem] = []
    @ObservationIgnored private var loadedMonth: Date?

    var month: Date { state.month }
    var selected: Date? { state.selected }

    /// Today has opened: start from this month and today again, and read its events.
    func appeared(_ model: AppModel) {
        state.reset(now: Date())
        load(model, force: true)
    }

    /// Read the shown month's events (only once per month unless `force`).
    func load(_ model: AppModel, force: Bool = false) {
        guard force || loadedMonth != month else { return }
        loadedMonth = month
        let range = MonthGrid.interval(of: month)
        events = model.settings.calendarEnabled ? model.calendar.events(from: range.start, to: range.end) : []
    }

    func grid(_ model: AppModel, now: Date = Date()) -> MonthGrid {
        let visible = Agenda.visible(events, hiding: Set(model.settings.hiddenCalendars))
        let days = MonthGrid.eventDays(visible, in: MonthGrid.interval(of: month))
        return MonthGrid.make(containing: month, today: now, selected: selected, eventDays: days)
    }

    func show(monthsFrom delta: Int, _ model: AppModel) {
        state.shift(by: delta)
        load(model)
    }

    /// Back to this month and today.
    func today(_ model: AppModel) {
        state.reset(now: Date())
        load(model)
    }

    /// Pick a day; picking today or the picked day again goes back to today.
    func select(_ day: Date) {
        state.pick(day, now: Date())
    }

    func showForSnapshot(month: Date, selected: Date?, events: [AgendaItem]) {
        state.reset(now: month)
        if let selected { state.pick(selected, now: .distantPast) }
        self.events = events
        loadedMonth = self.month
    }
}

// MARK: - Stopwatch

/// The stopwatch: saved so it survives a relaunch, and shown beside the notch as a count-up
/// while it is running or paused, like the timers.
@MainActor
@Observable
final class StopwatchController {
    private(set) var stopwatch = Stopwatch()

    @ObservationIgnored private unowned let model: AppModel
    @ObservationIgnored private var storeURL: URL?
    @ObservationIgnored private var shown: ActivitySpec?
    @ObservationIgnored private var syncing = false

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        storeURL = IsletPaths.supportDirectory.appendingPathComponent("stopwatch.json")
        if model.settings.stopwatchEnabled, let url = storeURL, let saved = Stopwatch.load(from: url) { stopwatch = saved }
        sync()
    }

    /// Whether an activity is the stopwatch's (Home shows it itself).
    func owns(_ a: Activity) -> Bool { a.id == Stopwatch.activityID && a.source == Stopwatch.source }

    func toggle() {
        Haptics.play(.tap)
        stopwatch.toggle(now: Date())
        changed()
    }

    func lap() {
        Haptics.play(.tap)
        stopwatch.lap(now: Date())
        changed()
    }

    func reset() {
        guard stopwatch.isActive else { return }
        stopwatch.reset()
        changed()
    }

    /// Show its activity afresh: unmuted, a running stopwatch comes back at once.
    func resync() {
        shown = nil
        sync()
    }

    /// Its activity was dismissed (the island's close button, a script): that resets it.
    func activityRemoved(_ id: String) {
        guard !syncing, id == Stopwatch.activityID, shown != nil else { return }
        shown = nil
        stopwatch.reset()
        changed()
    }

    private func changed() {
        sync()
        if let storeURL { try? stopwatch.save(to: storeURL) }
    }

    /// A spec can't clear a count-up, so a change removes the activity and shows it again.
    private func sync() {
        let wanted = stopwatch.spec(now: Date())
        guard wanted != shown else { return }
        syncing = true
        defer { syncing = false }
        model.remove(activityID: Stopwatch.activityID)
        if let wanted { _ = try? model.applyLocal(wanted) }
        shown = wanted
    }

    func showForSnapshot(_ s: Stopwatch) {
        stopwatch = s
        sync()
    }
}

// MARK: - Focus sounds

/// Plays the focus sound during Pomodoro focus rounds and stops it for breaks. Called whenever
/// the timers or the settings change; nothing runs between those.
@MainActor
final class FocusSoundController {
    private unowned let model: AppModel
    private var director = FocusSoundDirector()
    private lazy var player = FocusSoundPlayer()
    /// The volume the sound plays at, so a change elsewhere in Settings doesn't fade it again.
    private var volume: Double?

    init(model: AppModel) {
        self.model = model
    }

    func update() {
        let s = model.settings
        let actions = director.update(sound: s.focusSound, focusing: model.timers.engine.isFocusing,
                                      musicPlaying: model.nowPlaying?.isPlaying == true)
        perform(actions)
        if director.noise == nil {
            volume = nil
        } else if volume != s.focusSoundVolume {
            if volume != nil { player.setVolume(s.focusSoundVolume) }
            volume = s.focusSoundVolume
        }
    }

    func stopAll() {
        perform(director.stopAll(musicPlaying: model.nowPlaying?.isPlaying == true))
    }

    private func perform(_ actions: [FocusSoundDirector.Action]) {
        for action in actions {
            switch action {
            case .startNoise(let sound): player.play(sound, volume: model.settings.focusSoundVolume)
            case .stopNoise: player.stop()
            case .playMusic: model.send(.play)
            case .pauseMusic: model.send(.pause)
            }
        }
    }
}
