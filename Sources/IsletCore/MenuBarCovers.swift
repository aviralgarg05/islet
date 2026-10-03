import CoreGraphics
import Foundation

/// Where one of the menu bar's own Live Activity pills is, as Accessibility reports it: global
/// AX coordinates, whose origin is the top left of the display that carries the menu bar, with
/// y growing downwards.
public struct MenuBarActivityPill: Equatable, Sendable {
    /// The activity's key, the same one `MirroredLiveActivity` carries.
    public var key: String
    public var frame: CGRect
    /// Collapsed into the menu bar's overflow, so macOS doesn't draw it.
    public var hidden: Bool

    public init(key: String, frame: CGRect, hidden: Bool = false) {
        self.key = key
        self.frame = frame
        self.hidden = hidden
    }
}

/// "Hide the menu bar's own". macOS offers no way to hide a Live Activity pill, and Islet reads
/// that pill to mirror it, so it has to stay: Islet lays an opaque black rectangle over each
/// one instead, and the activity then shows in the island only.
///
/// Only the menu bar's Live Activity pills are ever covered, never another menu bar item, and
/// only while the island is there to show the activity instead.
public enum MenuBarCovers {
    /// What Islet knows when it works out where the covers go. Every part of it changes on an
    /// event, so nothing here is polled.
    public struct Input: Equatable, Sendable {
        /// "Hide the menu bar's own" (`hideMenuBarActivities`).
        public var hideOwn: Bool
        /// "Show Live Activities" (`mirrorMenuBarActivities`). With it off nothing is read or
        /// mirrored, so covering the pill would hide the activity altogether.
        public var mirroring: Bool
        /// This macOS puts Live Activities in the menu bar (`MenuBarLiveActivities.isSupported`).
        public var supported: Bool
        /// Islet has Accessibility. Without it the menu bar can't be read, so what Islet knows
        /// about the pills is stale.
        public var trusted: Bool
        /// This login session is the one in front (fast user switching).
        public var inFront: Bool
        /// The island shows on the display that carries the menu bar. False while a full screen
        /// app or an app rule hides it there, and when Islet has no island on that display.
        public var islandShows: Bool
        /// That display still draws a menu bar: nothing is in full screen over it and macOS
        /// isn't hiding it.
        public var menuBarShows: Bool
        /// Height of that display's menu bar, in points.
        public var menuBarHeight: CGFloat
        /// The AppKit y of the top of that display (its `frame.maxY`), where AX y is 0.
        public var menuBarTop: CGFloat

        public init(hideOwn: Bool, mirroring: Bool, supported: Bool, trusted: Bool, inFront: Bool,
                    islandShows: Bool, menuBarShows: Bool, menuBarHeight: CGFloat, menuBarTop: CGFloat) {
            self.hideOwn = hideOwn
            self.mirroring = mirroring
            self.supported = supported
            self.trusted = trusted
            self.inFront = inFront
            self.islandShows = islandShows
            self.menuBarShows = menuBarShows
            self.menuBarHeight = menuBarHeight
            self.menuBarTop = menuBarTop
        }
    }

    /// The rectangles to cover, as window frames (AppKit coordinates, origin bottom left), left
    /// to right. Empty whenever a cover would be wrong: the setting off, nothing mirrored,
    /// Accessibility gone, this session in the background, the island hidden on that display, or
    /// no menu bar to cover. A pill the notch has collapsed into the overflow isn't drawn, so it
    /// isn't covered either.
    public static func covers(pills: [MenuBarActivityPill], _ input: Input) -> [CGRect] {
        guard input.hideOwn, input.mirroring, input.supported, input.trusted, input.inFront,
              input.islandShows, input.menuBarShows, input.menuBarHeight > 0 else { return [] }
        return pills.filter { !$0.hidden }
            .sorted { $0.frame.minX < $1.frame.minX }
            .compactMap { windowFrame(pill: $0.frame, menuBarTop: input.menuBarTop, menuBarHeight: input.menuBarHeight) }
    }

    /// One pill's AX frame as a window frame. AX measures down from the top of the display that
    /// carries the menu bar; a window frame measures up from the bottom of that same display,
    /// whose AppKit origin is (0, 0). The result is kept inside the menu bar row, so a pill
    /// taller than the row never leaves a black edge hanging below it, and rounded outwards, so
    /// a fractional pill is covered whole.
    /// - Returns: nil when the pill has no size, or nothing of it falls in the row.
    public static func windowFrame(pill: CGRect, menuBarTop: CGFloat, menuBarHeight: CGFloat) -> CGRect? {
        guard pill.width > 0, pill.height > 0, menuBarHeight > 0,
              pill.minX.isFinite, pill.minY.isFinite, pill.width.isFinite, pill.height.isFinite else { return nil }
        let row = CGRect(x: pill.minX, y: 0, width: pill.width, height: menuBarHeight)
        let inRow = pill.intersection(row)
        guard !inRow.isNull, inRow.width > 0, inRow.height > 0 else { return nil }
        return CGRect(x: inRow.minX, y: menuBarTop - inRow.maxY, width: inRow.width, height: inRow.height).integral
    }

    /// Whether only the activities the notch hides are mirrored. "Hide the menu bar's own"
    /// covers the visible pills, which only makes sense when every activity is mirrored, so it
    /// overrides "Only when the notch hides them" (and dims it in Settings).
    public static func mirrorsOnlyHidden(onlyHidden: Bool, hideOwn: Bool) -> Bool {
        onlyHidden && !hideOwn
    }
}
