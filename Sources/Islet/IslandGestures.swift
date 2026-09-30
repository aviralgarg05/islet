import AppKit
import IsletCore
import SwiftUI

/// The island's hosting view. It reads two-finger swipes from the scroll events the panel
/// already receives while the pointer is on the island: no event monitor, no permission.
final class IslandHostingView: NSHostingView<IslandView> {
    var onSwipe: ((SwipeDirection) -> Void)?
    private var swipes = SwipeRecognizer()

    override func scrollWheel(with event: NSEvent) {
        if let direction = swipes.feed(ScrollSample(event)) { onSwipe?(direction) }
        super.scrollWheel(with: event)
    }
}

extension ScrollSample {
    init(_ e: NSEvent) {
        self.init(
            dx: Double(e.scrollingDeltaX), dy: Double(e.scrollingDeltaY),
            phase: ScrollEventPhase(e.phase), momentum: ScrollEventPhase(e.momentumPhase),
            precise: e.hasPreciseScrollingDeltas, inverted: e.isDirectionInvertedFromDevice, time: e.timestamp
        )
    }
}

extension ScrollEventPhase {
    init(_ p: NSEvent.Phase) {
        if p.contains(.began) { self = .began }
        else if p.contains(.changed) { self = .changed }
        else if p.contains(.ended) { self = .ended }
        else if p.contains(.cancelled) { self = .cancelled }
        else if p.contains(.mayBegin) { self = .mayBegin }
        else if p.contains(.stationary) { self = .stationary }
        else { self = .none }
    }
}

/// A native pop-up menu at the pointer. The island stays open while it shows, even if the
/// menu reaches past the island's edge.
@MainActor
enum IslandMenu {
    struct Item {
        var title: String
        var symbol: String?
        var checked = false
        var enabled = true
        var action: (() -> Void)?

        static let separator = Item(title: "-")
    }

    static func show(_ items: [Item], model: AppModel) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in items {
            if item.title == "-" {
                menu.addItem(.separator())
                continue
            }
            let m = ClosureMenuItem(title: item.title, handler: item.action)
            m.isEnabled = item.enabled
            m.state = item.checked ? .on : .off
            if let symbol = item.symbol { m.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
            menu.addItem(m)
        }
        model.controls.holdsOpen = true
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        model.controls.holdsOpen = false
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: (() -> Void)?

    init(title: String, handler: (() -> Void)?) {
        self.handler = handler
        super.init(title: title, action: handler == nil ? nil : #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler?() }
}
