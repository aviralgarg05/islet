import CoreGraphics
import Foundation

/// How the closed island uses the space around the notch.
public enum ClosedLayoutPreference: String, Codable, Sendable, CaseIterable {
    /// Beside the notch, sized to the free space in the menu bar; below it only when there's
    /// no room at all.
    case auto
    /// Always beside the notch, in the menu bar row (may cover menu bar icons).
    case wings
    /// Always below the notch, leaving the menu bar row untouched.
    case drop
}

/// The layout the closed island actually uses right now.
public enum ClosedLayout: Equatable, Sendable {
    /// Content in the menu bar row, beside the notch, with a wing on each side.
    case wings(left: CGFloat, right: CGFloat)
    /// Content in a pill hanging below the notch; the menu bar row is left alone.
    case drop
}

/// What is in the menu bar next to the notch, measured on one display.
public struct MenuBarOccupancy: Equatable, Sendable {
    /// Right edge of the rightmost app menu that ends left of the notch (global x).
    public var leftObstacleMaxX: CGFloat?
    /// Left edge of the leftmost status item that starts right of the notch (global x).
    public var rightObstacleMinX: CGFloat?

    public init(leftObstacleMaxX: CGFloat? = nil, rightObstacleMinX: CGFloat? = nil) {
        self.leftObstacleMaxX = leftObstacleMaxX
        self.rightObstacleMinX = rightObstacleMinX
    }

    /// Build from item frames in global coordinates: menu titles and status items, anywhere in the bar.
    /// - Parameter chevron: macOS 26+ "Show Hidden Menu Bar Items" button. Items it has collapsed
    ///   still report frames stacked on it; they aren't drawn, so they don't count. The chevron
    ///   itself is always an obstacle: covering it would hide those items for good.
    public static func from(menuFrames: [CGRect], statusFrames: [CGRect], chevron: CGRect? = nil, notch: CGRect) -> MenuBarOccupancy {
        var status = statusFrames.filter { $0.width > 0 }
        if let chevron, chevron.width > 0 {
            let zone = chevron.insetBy(dx: -2, dy: 0)
            status = status.filter { !$0.intersects(zone) } + [chevron]
        }
        let items = menuFrames.filter { $0.width > 0 } + status
        let left = items.filter { $0.midX < notch.midX }.map(\.maxX).max()
        let right = items.filter { $0.midX >= notch.midX }.map(\.minX).min()
        return MenuBarOccupancy(leftObstacleMaxX: left, rightObstacleMinX: right)
    }
}

public enum MenuBarLayoutEngine {
    /// Space kept clear between a wing and the nearest menu bar item.
    public static let clearance: CGFloat = 6
    /// Narrowest wing that can still show an icon and a short value.
    public static let minimumWing: CGFloat = 34
    /// Narrowest wing at all: room for an icon only. Less than this and the island drops.
    public static let iconOnlyWing: CGFloat = 26
    /// Wing width when the menu bar can't be measured (no Accessibility). Narrow enough to clear
    /// the menus of most apps and the status items on a 14" MacBook Pro.
    public static let unmeasuredWing: CGFloat = 36

    /// Pick the closed layout.
    /// - Parameters:
    ///   - notch: the notch (or synthetic pill) rect in global coordinates.
    ///   - preferredWing: wing width from settings.
    ///   - occupancy: measured menu bar items; nil when they can't be measured (no Accessibility).
    ///   - hasMenuBar: false when the display has no menu bar row (auto-hidden, or a secondary
    ///     display without its own menu bar), in which case nothing can be covered.
    public static func decide(
        preference: ClosedLayoutPreference,
        notch: CGRect,
        preferredWing: CGFloat,
        occupancy: MenuBarOccupancy?,
        hasMenuBar: Bool
    ) -> ClosedLayout {
        switch preference {
        case .wings:
            return .wings(left: preferredWing, right: preferredWing)
        case .drop:
            return .drop
        case .auto:
            // Like the iPhone (and other notch apps), the closed island stays in the top row.
            guard hasMenuBar else { return .wings(left: preferredWing, right: preferredWing) }
            guard let occupancy else {
                let w = min(preferredWing, unmeasuredWing)
                return .wings(left: w, right: w)
            }
            let leftRoom = occupancy.leftObstacleMaxX.map { notch.minX - $0 - clearance } ?? preferredWing
            let rightRoom = occupancy.rightObstacleMinX.map { $0 - notch.maxX - clearance } ?? preferredWing
            // Keep the island symmetric around the notch: both wings take the narrower width.
            let width = min(preferredWing, leftRoom, rightRoom)
            if width >= minimumWing { return .wings(left: width, right: width) }
            if width >= iconOnlyWing { return .wings(left: iconOnlyWing, right: iconOnlyWing) }
            // Not even an icon fits without covering something: hang below the notch instead.
            return .drop
        }
    }

    /// Free menu bar room left beyond each wing (for bubbles), given the chosen wing width.
    /// Infinity when nothing was measured on that side.
    public static func slack(notch: CGRect, occupancy: MenuBarOccupancy, wing: CGFloat) -> (left: CGFloat, right: CGFloat) {
        let left = occupancy.leftObstacleMaxX.map { notch.minX - $0 - clearance - wing } ?? .infinity
        let right = occupancy.rightObstacleMinX.map { $0 - notch.maxX - clearance - wing } ?? .infinity
        return (max(0, left), max(0, right))
    }

    /// Height of the dropped pill below the notch.
    public static let dropHeight: CGFloat = 26

    /// Width changes smaller than this are ignored, so a status item that retitles every few
    /// seconds doesn't make the wings twitch.
    public static let widthHysteresis: CGFloat = 4
    /// Switching between wings and the dropped pill happens at most this often.
    public static let minimumSwitchInterval: TimeInterval = 1

    /// Whether a new measurement should replace the layout in use.
    /// - Returns: `.apply`, `.keep` (change too small), or `.defer` (a wings/drop switch came too
    ///   soon after the last one; measure again later).
    public static func stabilise(current: ClosedLayout?, next: ClosedLayout, lastSwitch: Date?, now: Date) -> Stabilised {
        guard let current else { return .apply }
        switch (current, next) {
        case (.drop, .drop):
            return .keep
        case (.wings(let a, let b), .wings(let c, let d)):
            return abs(a - c) < widthHysteresis && abs(b - d) < widthHysteresis ? .keep : .apply
        default:
            if let lastSwitch, now.timeIntervalSince(lastSwitch) < minimumSwitchInterval { return .defer }
            return .apply
        }
    }

    public enum Stabilised: Equatable, Sendable { case apply, keep, `defer` }
}
