import CoreGraphics

/// Screen facts needed to place the island. Filled from `NSScreen` in the app,
/// constructed directly in tests.
public struct ScreenDescriptor: Equatable, Sendable {
    public var id: UInt32
    public var name: String
    /// Full screen frame in global AppKit coordinates (origin bottom-left).
    public var frame: CGRect
    /// `NSScreen.safeAreaInsets.top`; non-zero only on displays with a camera housing.
    public var safeAreaTop: CGFloat
    /// Width of `NSScreen.auxiliaryTopLeftArea`, if any.
    public var auxiliaryLeftWidth: CGFloat?
    /// Width of `NSScreen.auxiliaryTopRightArea`, if any.
    public var auxiliaryRightWidth: CGFloat?
    /// Height of the menu bar on this screen (frame.maxY - visibleFrame.maxY), 0 when hidden.
    public var menuBarHeight: CGFloat
    public var isBuiltIn: Bool

    public init(
        id: UInt32,
        name: String,
        frame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryLeftWidth: CGFloat? = nil,
        auxiliaryRightWidth: CGFloat? = nil,
        menuBarHeight: CGFloat = 24,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.frame = frame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryLeftWidth = auxiliaryLeftWidth
        self.auxiliaryRightWidth = auxiliaryRightWidth
        self.menuBarHeight = menuBarHeight
        self.isBuiltIn = isBuiltIn
    }

    public var hasNotch: Bool { safeAreaTop > 0 }
}

/// Size of each island state. All values are in points.
public struct IslandMetrics: Equatable, Sendable {
    /// The hardware notch (or the synthetic pill on notchless displays).
    public var notch: CGSize
    /// How far compact "wings" extend on each side of the notch.
    public var wingWidth: CGFloat
    /// Size of the fully expanded panel.
    public var expanded: CGSize
    /// Whether the notch is real hardware or a drawn pill.
    public var isSynthetic: Bool
    /// The closed island floats as a pill inside the menu bar instead of hanging from the top
    /// edge (a display without a notch, "Floating pill" or "Only on hover").
    public var floats: Bool = false

    public var compact: CGSize {
        CGSize(width: notch.width + wingWidth * 2, height: notch.height)
    }
}

public enum NotchGeometry {
    /// Fallback notch size (14"/16" MacBook Pro) when auxiliary areas are unavailable.
    public static let fallbackNotchWidth: CGFloat = 185
    /// Height of the synthetic pill on displays without a notch.
    public static let syntheticHeight: CGFloat = 24
    public static let syntheticWidth: CGFloat = 180

    /// How far a floating pill sits inside the menu bar, top and bottom.
    public static let pillInset: CGFloat = 1.5

    /// The narrowest and shortest notch an adjustment can leave.
    public static let minimumNotch = CGSize(width: 40, height: 12)

    /// Derive island metrics for a screen.
    /// - Parameters:
    ///   - expandedSize: requested expanded panel size (clamped to fit the screen).
    ///   - wingWidth: compact wing width on each side.
    ///   - adjust: points added to the notch's width and height ("Fit to the notch"), so the
    ///     closed island lines up with the hardware. Everything placed from the notch follows:
    ///     the wings, hit-testing, the hover zone and the trigger window.
    ///   - notchless: how the island looks on a display without a notch.
    public static func metrics(
        for screen: ScreenDescriptor,
        expandedSize: CGSize = CGSize(width: 640, height: 200),
        wingWidth: CGFloat = 84,
        adjust: CGSize = .zero,
        notchless: NotchlessStyle = .notch
    ) -> IslandMetrics {
        var notch: CGSize
        let synthetic: Bool
        if screen.hasNotch {
            let width: CGFloat
            if let left = screen.auxiliaryLeftWidth, let right = screen.auxiliaryRightWidth {
                width = max(0, screen.frame.width - left - right)
            } else {
                width = fallbackNotchWidth
            }
            // Guard against nonsense values from odd display modes.
            notch = CGSize(width: width > 40 ? width : fallbackNotchWidth, height: screen.safeAreaTop)
            synthetic = false
        } else {
            let height = screen.menuBarHeight > 0 ? min(screen.menuBarHeight, 32) : syntheticHeight
            notch = CGSize(width: syntheticWidth, height: height)
            synthetic = true
        }
        // Never below the minimum (or the notch itself, if that is smaller still).
        if adjust.width.isFinite, adjust.width != 0 {
            notch.width = max(min(notch.width, minimumNotch.width), notch.width + adjust.width)
        }
        if adjust.height.isFinite, adjust.height != 0 {
            notch.height = max(min(notch.height, minimumNotch.height), notch.height + adjust.height)
        }

        let maxWidth = max(notch.width, screen.frame.width - 40)
        let maxHeight = max(notch.height, screen.frame.height / 2)
        let expanded = CGSize(
            width: min(max(expandedSize.width, notch.width + 2 * wingWidth), maxWidth),
            height: min(max(expandedSize.height, notch.height * 2), maxHeight)
        )
        let clampedWing = max(0, min(wingWidth, (maxWidth - notch.width) / 2))
        return IslandMetrics(notch: notch, wingWidth: clampedWing, expanded: expanded, isSynthetic: synthetic,
                             floats: synthetic && notchless.floats)
    }

    /// Frame (global AppKit coordinates) of the transparent host window. The window is
    /// sized for the largest state so SwiftUI can animate inside it without resizing the window.
    public static func windowFrame(for screen: ScreenDescriptor, metrics: IslandMetrics, shadowPadding: CGFloat = 24) -> CGRect {
        let width = max(metrics.expanded.width, metrics.compact.width) + shadowPadding * 2
        let height = metrics.expanded.height + shadowPadding
        return CGRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    /// The rectangle currently occupied by the visible island in global coordinates,
    /// used for hit-testing so everything outside it stays click-through.
    public static func visibleRect(for screen: ScreenDescriptor, size: CGSize) -> CGRect {
        CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// The zone that arms hover-to-open. Slightly wider than the notch so it's easy to hit,
    /// but only a few points tall so it doesn't eat menu-bar clicks next to the notch.
    public static func hoverZone(for screen: ScreenDescriptor, metrics: IslandMetrics, slop: CGFloat = 8) -> CGRect {
        let w = metrics.notch.width + slop * 2
        let h = max(metrics.notch.height, 6)
        return CGRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h)
    }

    /// The pointer location to hit-test against rectangles anchored to the top of `frame`.
    /// A pointer pushed against the top edge reports `y == frame.maxY`, which `CGRect.contains`
    /// treats as outside, so the notch would never arm on the most natural movement.
    public static func hitPoint(_ p: CGPoint, in frame: CGRect) -> CGPoint {
        p.y >= frame.maxY ? CGPoint(x: p.x, y: frame.maxY - 0.5) : p
    }
}
