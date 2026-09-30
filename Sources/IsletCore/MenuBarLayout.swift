import CoreGraphics

/// How the closed island uses the space around the notch.
public enum ClosedLayoutPreference: String, Codable, Sendable, CaseIterable {
    /// Wings beside the notch when the menu bar has room for them, otherwise drop below.
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
    public static func from(menuFrames: [CGRect], statusFrames: [CGRect], notch: CGRect) -> MenuBarOccupancy {
        let items = (menuFrames + statusFrames).filter { $0.width > 0 }
        let left = items.filter { $0.midX < notch.midX }.map(\.maxX).max()
        let right = items.filter { $0.midX >= notch.midX }.map(\.minX).min()
        return MenuBarOccupancy(leftObstacleMaxX: left, rightObstacleMinX: right)
    }
}

public enum MenuBarLayoutEngine {
    /// Space kept clear between a wing and the nearest menu bar item.
    public static let clearance: CGFloat = 6
    /// Narrowest wing that can still show an icon or a short value.
    public static let minimumWing: CGFloat = 34

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
            guard hasMenuBar else { return .wings(left: preferredWing, right: preferredWing) }
            guard let occupancy else { return .drop }
            let leftRoom = occupancy.leftObstacleMaxX.map { notch.minX - $0 - clearance } ?? preferredWing
            let rightRoom = occupancy.rightObstacleMinX.map { $0 - notch.maxX - clearance } ?? preferredWing
            let left = min(preferredWing, leftRoom)
            let right = min(preferredWing, rightRoom)
            guard left >= minimumWing, right >= minimumWing else { return .drop }
            // Keep the island symmetric around the notch: both wings take the narrower width.
            let width = min(left, right)
            return .wings(left: width, right: width)
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
}
