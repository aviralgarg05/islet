import CoreGraphics
import Foundation

/// How wide the closed island's wings are. The closed island always sits in the menu bar row,
/// with a wing either side of the notch; this only decides their width.
public enum ClosedLayoutPreference: String, Codable, Sendable, CaseIterable {
    /// Fit the wings to the free space in the menu bar, down to icon-only wings.
    case auto
    /// Always the wing width from Settings (may cover menu bar icons).
    case wings
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
    ///   itself is an obstacle, so the wings keep clear of it whenever there's room.
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
    /// Narrowest wing at all: room for an icon only. Used whenever less than `minimumWing` is free,
    /// even if it then covers the edge of the nearest menu bar item.
    public static let iconOnlyWing: CGFloat = 26
    /// Wing width when the menu bar can't be measured (no Accessibility). Narrow enough to clear
    /// the menus of most apps and the status items on a 14" MacBook Pro.
    public static let unmeasuredWing: CGFloat = 36

    /// Width of each wing of the closed island. Both wings get the same width, so the island
    /// stays centred on the notch.
    /// - Parameters:
    ///   - notch: the notch (or synthetic pill) rect in global coordinates.
    ///   - preferredWing: wing width from settings.
    ///   - occupancy: measured menu bar items; nil when they can't be measured (no Accessibility).
    ///   - hasMenuBar: false when the display has no menu bar row (auto-hidden, or a secondary
    ///     display without its own menu bar), in which case nothing can be covered.
    public static func wingWidth(
        preference: ClosedLayoutPreference,
        notch: CGRect,
        preferredWing: CGFloat,
        occupancy: MenuBarOccupancy?,
        hasMenuBar: Bool
    ) -> CGFloat {
        guard preference == .auto, hasMenuBar else { return preferredWing }
        guard let occupancy else { return min(preferredWing, unmeasuredWing) }
        let leftRoom = occupancy.leftObstacleMaxX.map { notch.minX - $0 - clearance } ?? preferredWing
        let rightRoom = occupancy.rightObstacleMinX.map { $0 - notch.maxX - clearance } ?? preferredWing
        // The narrower side decides, so the island stays symmetric around the notch.
        let room = min(preferredWing, leftRoom, rightRoom)
        // Too little room for an icon and a value: icon-only wings, still in the menu bar row.
        return room >= minimumWing ? room : iconOnlyWing
    }

    /// Free menu bar room left beyond each wing (for bubbles), given the chosen wing width.
    /// Infinity when nothing was measured on that side.
    public static func slack(notch: CGRect, occupancy: MenuBarOccupancy, wing: CGFloat) -> (left: CGFloat, right: CGFloat) {
        let left = occupancy.leftObstacleMaxX.map { notch.minX - $0 - clearance - wing } ?? .infinity
        let right = occupancy.rightObstacleMinX.map { $0 - notch.maxX - clearance - wing } ?? .infinity
        return (max(0, left), max(0, right))
    }

    /// Width changes smaller than this are ignored, so a status item that retitles every few
    /// seconds doesn't make the wings twitch.
    public static let widthHysteresis: CGFloat = 4

    /// Whether a newly measured wing width should replace the one in use (always, when none is).
    public static func shouldReplace(_ current: CGFloat?, with next: CGFloat) -> Bool {
        guard let current else { return true }
        return abs(current - next) >= widthHysteresis
    }
}
