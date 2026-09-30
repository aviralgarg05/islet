import AppKit
import IsletCore
import IsletSystem
import SwiftUI

/// Borderless, non-activating panel that sits above the menu bar on every Space.
final class IslandPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        // 27: above the menu bar (24) and status items (25), below pop-up menus (101).
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        // Transient, not stationary: stationary windows stay drawn over Mission Control's Spaces bar.
        collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// One island on one display.
@MainActor
final class IslandWindowController {
    let display: CGDirectDisplayID
    private(set) var screen: NSScreen
    private(set) var descriptor: ScreenDescriptor
    private(set) var metrics: IslandMetrics
    let panel: IslandPanel
    let trigger = TriggerPanel()
    private let model: AppModel

    init(model: AppModel, screen: NSScreen) {
        self.model = model
        self.screen = screen
        self.display = screen.displayID ?? 0
        self.descriptor = Self.describe(screen)
        let size = model.settings.expandedSize
        self.metrics = NotchGeometry.metrics(
            for: descriptor,
            expandedSize: CGSize(width: size.width, height: size.height),
            wingWidth: model.settings.effectiveWingWidth
        )
        panel = IslandPanel(frame: NotchGeometry.windowFrame(for: descriptor, metrics: metrics))
        panel.sharingType = model.settings.hideFromScreenCapture ? .none : .readOnly
        let host = IslandHostingView(rootView: IslandView(model: model, display: display, metrics: metrics))
        host.sizingOptions = []
        let id = display
        host.onSwipe = { [weak model] direction in model?.handleSwipe(direction, display: id) }
        panel.contentView = host
        panel.orderFrontRegardless()
    }

    static func describe(_ s: NSScreen) -> ScreenDescriptor {
        ScreenDescriptor(
            id: s.displayID ?? 0,
            name: s.localizedName,
            frame: s.frame,
            safeAreaTop: s.safeAreaInsets.top,
            auxiliaryLeftWidth: s.auxiliaryTopLeftArea?.width,
            auxiliaryRightWidth: s.auxiliaryTopRightArea?.width,
            menuBarHeight: s.frame.maxY - s.visibleFrame.maxY,
            isBuiltIn: CGDisplayIsBuiltin(s.displayID ?? 0) != 0
        )
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
        trigger.orderOut(nil)
        trigger.close()
    }

    /// Where the trigger window sits: the visible island, or just the notch area when idle.
    /// On displays without a notch, only a thin strip at the top edge, so menu-bar clicks
    /// next to the centre are unaffected.
    func updateTrigger() {
        let p = model.presentation(for: display)
        if p == .hidden {
            trigger.orderOut(nil)
            return
        }
        // Idle: exactly the notch, never the menu bar beside it. On displays without a notch,
        // a thin strip at the very top edge.
        var zones = [notchRect]
        if metrics.isSynthetic, !IslandLayout.isVisible(p) {
            zones = [CGRect(x: notchRect.minX, y: descriptor.frame.maxY - 4, width: notchRect.width, height: 4)]
        }
        zones += hitRects
        let frame = zones.reduce(CGRect.null) { $0.union($1) }.integral
        if trigger.frame != frame { trigger.setFrame(frame, display: false) }
        trigger.view.setActiveRegions(zones.map { $0.offsetBy(dx: -frame.minX, dy: -frame.minY) })
        if !trigger.isVisible { trigger.orderFrontRegardless() }
    }

    /// The notch (or synthetic pill) in global coordinates.
    var notchRect: CGRect { NotchGeometry.visibleRect(for: descriptor, size: metrics.notch) }

    /// Regions the island actually occupies right now, in global coordinates: the part in the
    /// menu bar row, the body (below the row when dropped) and any bubbles. Everything else
    /// on the panel is transparent and passes clicks through.
    var hitRects: [CGRect] {
        let p = model.presentation(for: display)
        guard IslandLayout.isVisible(p) else { return [] }
        let placement = model.placement(for: display, metrics: metrics)
        let g = IslandLayout.geometry(for: p, metrics: metrics, layout: placement.layout)
        let top = descriptor.frame.maxY
        let midX = descriptor.frame.midX
        var rects: [CGRect] = []
        if g.stemWidth > 0 {
            let stem = g.stemWidth + 2 * g.top
            rects.append(CGRect(x: midX - stem / 2, y: top - g.stemHeight, width: stem, height: g.stemHeight))
            rects.append(CGRect(x: midX - g.size.width / 2, y: top - g.size.height, width: g.size.width, height: g.size.height - g.stemHeight))
        } else {
            rects.append(CGRect(x: midX - g.outerWidth / 2, y: top - g.size.height, width: g.outerWidth, height: g.size.height))
        }
        let bubbles = model.bubbles(for: p)
        if !bubbles.items.isEmpty {
            let left = model.settings.bubblePlacement == .left
            let bp = IslandLayout.bubblePlacement(geometry: g, metrics: metrics, placement: placement, count: bubbles.items.count, left: left)
            let span = CGFloat(bubbles.items.count) * (bp.diameter + IslandLayout.bubbleGap)
            let x = left ? midX - g.outerWidth / 2 - span : midX + g.outerWidth / 2
            rects.append(CGRect(x: x, y: top - bp.top - bp.diameter, width: span, height: bp.diameter))
        }
        return rects
    }

    /// Bounding box of `hitRects` (empty when nothing is drawn).
    var islandRect: CGRect { hitRects.reduce(CGRect.null) { $0.union($1) } }

    /// Something in the menu bar may have changed since the last measurement.
    private var menuBarStale = true
    private var lastLayoutSwitch: Date?
    private var deferredMeasure: DispatchWorkItem?

    /// Measure the menu bar beside the notch and store the automatic placement.
    /// While nothing is drawn on this display it only notes that a measurement is due, so an
    /// idle island never reads the menu bar; `measureIfStale` catches up when it appears.
    func measureMenuBar(force: Bool = false) {
        guard model.settings.closedLayout == .auto else { return }
        guard force || IslandLayout.isVisible(model.presentation(for: display)) else {
            menuBarStale = true
            return
        }
        menuBarStale = false
        let wing = metrics.wingWidth
        let notch = notchRect
        let display = display
        guard descriptor.menuBarHeight > 0 else {
            model.closedPlacements[display] = .unmeasured(.auto, wing: wing, hasMenuBar: false)
            return
        }
        MenuBarInspector.measure(notch: notch, screenFrame: descriptor.frame) { [weak self] occupancy in
            guard let self else { return }
            let layout = MenuBarLayoutEngine.decide(preference: .auto, notch: notch, preferredWing: wing, occupancy: occupancy, hasMenuBar: true)
            let current = self.model.closedPlacements[display]
            switch MenuBarLayoutEngine.stabilise(current: current?.layout, next: layout, lastSwitch: self.lastLayoutSwitch, now: Date()) {
            case .keep: return
            case .defer:
                self.deferredMeasure?.cancel()
                let work = DispatchWorkItem { [weak self] in self?.measureMenuBar(force: true) }
                self.deferredMeasure = work
                DispatchQueue.main.asyncAfter(deadline: .now() + MenuBarLayoutEngine.minimumSwitchInterval, execute: work)
                return
            case .apply: break
            }
            var placement = ClosedPlacement(layout: layout, leftSlack: 0, rightSlack: 0)
            if case .wings(let l, _) = layout, let occupancy {
                let slack = MenuBarLayoutEngine.slack(notch: notch, occupancy: occupancy, wing: l)
                placement.leftSlack = slack.left
                placement.rightSlack = slack.right
            }
            if current?.layout != layout { self.lastLayoutSwitch = Date() }
            if current != placement { self.model.closedPlacements[display] = placement }
        }
    }

    /// Called when the silhouette changes: measure if the island just appeared after a change.
    func measureIfStale() {
        if menuBarStale, IslandLayout.isVisible(model.presentation(for: display)) { measureMenuBar() }
    }

    private var lastPointerMeasure = Date.distantPast

    /// The pointer reached the island. Hidden menu bar items may have been revealed next to it
    /// since the last measurement (macOS doesn't always announce that), so check again.
    func pointerEntered() {
        let now = Date()
        guard now.timeIntervalSince(lastPointerMeasure) > 2 else { return }
        lastPointerMeasure = now
        measureMenuBar()
    }

    /// Hovering here arms the island: the notch itself, nothing beside it.
    var hoverZone: CGRect { NotchGeometry.hoverZone(for: descriptor, metrics: metrics, slop: 0) }

    var expandedRect: CGRect {
        NotchGeometry.visibleRect(for: descriptor, size: CGSize(width: metrics.expanded.width + 20, height: metrics.expanded.height))
    }

    func setInteractive(_ interactive: Bool) {
        if panel.ignoresMouseEvents == interactive { panel.ignoresMouseEvents = !interactive }
    }
}

/// Invisible window over the notch (and the visible island). Its tracking area wakes the
/// pointer logic only when the pointer is actually there, so moving the mouse elsewhere costs
/// Islet nothing. It is also the drop target that pulls files onto the shelf.
final class TriggerPanel: NSPanel {
    let view = TriggerView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        // Just below the island panel (27), above the menu bar.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class TriggerView: NSView {
    var onEnter: (() -> Void)?
    var onClick: (() -> Void)?
    var onDragEnter: (() -> Void)?
    var onDragExit: (() -> Void)?
    var onDrop: (([URL]) -> Void)?
    var onSwipe: ((SwipeDirection) -> Void)?
    private var area: NSTrackingArea?
    private var swipes = SwipeRecognizer()

    private let fill = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // A nearly transparent fill marks where the window takes clicks. Fully transparent
        // pixels pass clicks through to the menu bar, so only the active regions are filled.
        fill.fillColor = NSColor(white: 0, alpha: 0.004).cgColor
        layer?.addSublayer(fill)
        registerForDraggedTypes([.fileURL])
    }

    /// Regions (in view coordinates) that should receive the pointer.
    func setActiveRegions(_ rects: [CGRect]) {
        let path = CGMutablePath()
        rects.forEach { path.addRect($0) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = bounds
        fill.path = path
        CATransaction.commit()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(a)
        area = a
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func scrollWheel(with event: NSEvent) {
        if let direction = swipes.feed(ScrollSample(event)) { onSwipe?(direction) }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEnter?()
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { onDragExit?() }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        onDrop?(urls)
        return !urls.isEmpty
    }
}

/// Hover-to-open, click-through and drag-to-shelf. Idle: no event monitors at all, just the
/// trigger windows. Active (pointer at the island, or island open): global/local monitors.
@MainActor
final class PointerCoordinator {
    private let model: AppModel
    var controllers: [IslandWindowController] = [] {
        didSet { refreshTriggers() }
    }
    private var monitors: [Any] = []
    private var intent = HoverIntent()
    private var restTimer: Timer?
    private var activeDisplay: CGDirectDisplayID?
    private var layoutObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
    }

    var isActive: Bool { !monitors.isEmpty }

    func start() {
        applySettings()
        layoutObserver = NotificationCenter.default.addObserver(forName: .isletLayoutChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layoutChanged() }
        }
        refreshTriggers()
    }

    func stop() {
        deactivate()
        if let o = layoutObserver { NotificationCenter.default.removeObserver(o) }
    }

    func applySettings() {
        intent.openDelay = model.settings.openDelay
        intent.closeDelay = model.settings.closeDelay
    }

    // MARK: Triggers

    private func refreshTriggers() {
        for c in controllers {
            c.updateTrigger()
            let display = c.display
            c.trigger.view.onEnter = { [weak self] in self?.activate(from: display) }
            c.trigger.view.onClick = { [weak self] in self?.clicked(display) }
            c.trigger.view.onSwipe = { [weak self] direction in self?.model.handleSwipe(direction, display: display) }
            c.trigger.view.onDragEnter = { [weak self] in self?.dragEntered(display) }
            c.trigger.view.onDragExit = { [weak self] in self?.model.setDraggingFile(false) }
            c.trigger.view.onDrop = { [weak self] urls in
                self?.model.setDraggingFile(false)
                if !urls.isEmpty { self?.model.addToShelf(urls) }
            }
        }
    }

    private func layoutChanged() {
        controllers.forEach {
            $0.updateTrigger()
            $0.measureIfStale()
        }
        // Opened by the API, a hotkey or the menu: start tracking so it can close on leave.
        if model.expandedScreen != nil, !isActive { activate(from: model.expandedScreen) }
    }

    private func clicked(_ display: CGDirectDisplayID) {
        let p = model.presentation(for: display)
        Haptics.play(.tap)
        if let a = model.focusedActivity(for: p), model.canOpen(a) {
            model.openActivity(a)
        } else {
            model.setExpanded(display)
        }
    }

    private func dragEntered(_ display: CGDirectDisplayID) {
        guard model.settings.shelfEnabled else { return }
        model.setDraggingFile(true)
        model.select(tab: .shelf)
        model.setExpanded(display)
        controllers.first { $0.display == display }?.setInteractive(true)
        activate(from: display)
    }

    // MARK: Active tracking

    private func activate(from display: CGDirectDisplayID?) {
        activeDisplay = display ?? activeDisplay
        if let display { controllers.first { $0.display == display }?.pointerEntered() }
        if monitors.isEmpty {
            let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp]
            if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] e in
                MainActor.assumeIsolated { self?.handle(e) }
            }) { monitors.append(g) }
            if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in
                MainActor.assumeIsolated { self?.handle(e) }
                return e
            }) { monitors.append(l) }
        }
        evaluate(at: NSEvent.mouseLocation, now: Date())
    }

    private func deactivate() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        restTimer?.invalidate()
        restTimer = nil
        intent.reset()
        controllers.forEach { $0.setInteractive(false) }
    }

    private func controller(at p: CGPoint) -> IslandWindowController? {
        controllers.first { $0.screen.frame.insetBy(dx: -1, dy: -1).contains(p) }
    }

    private func handle(_ event: NSEvent) {
        if event.type == .leftMouseUp, model.isDraggingFile { model.setDraggingFile(false) }
        evaluate(at: NSEvent.mouseLocation, now: Date())
    }

    private func evaluate(at p: CGPoint, now: Date) {
        guard let c = controller(at: p) else {
            // On a display without an island: that's leaving, so a pending open is cancelled and
            // an open island starts its close grace period instead of waiting for the pointer.
            if let display = activeDisplay {
                let decision = intent.sample(point: p, now: now, inTrigger: false, inExpanded: false,
                                             isOpen: model.expandedScreen == display)
                apply(decision, display: display)
                armRestTimerIfNeeded()
            }
            maybeDeactivate(pointerNearIsland: false)
            return
        }
        let expandedHere = model.expandedScreen == c.display
        let inIsland = c.hitRects.contains { $0.contains(p) }
        c.setInteractive(inIsland || expandedHere && c.expandedRect.contains(p) || model.isDraggingFile)
        for other in controllers where other !== c { other.setInteractive(model.isDraggingFile && model.expandedScreen == other.display) }

        let inTrigger = c.hoverZone.contains(p) || (inIsland && !expandedHere)
        if !inTrigger { model.controls.hoverOpenBlocked = false }
        if model.settings.hoverToOpen || expandedHere {
            let decision = intent.sample(point: p, now: now, inTrigger: inTrigger,
                                         inExpanded: expandedHere && c.expandedRect.insetBy(dx: -6, dy: -6).contains(p), isOpen: expandedHere)
            activeDisplay = c.display
            apply(decision, display: c.display)
            armRestTimerIfNeeded()
        }
        maybeDeactivate(pointerNearIsland: inTrigger || inIsland || (expandedHere && c.expandedRect.contains(p)))
    }

    /// Stop listening once the island is closed and the pointer has moved away.
    private func maybeDeactivate(pointerNearIsland: Bool) {
        guard isActive, model.expandedScreen == nil, !model.isDraggingFile, !pointerNearIsland,
              intent.enteredAt == nil, intent.exitedAt == nil else { return }
        deactivate()
    }

    private func apply(_ d: HoverIntent.Decision, display: CGDirectDisplayID) {
        switch d {
        case .open:
            if model.settings.hoverToOpen, !model.controls.hoverOpenBlocked { model.setExpanded(display) }
        case .close:
            if !model.pinned, !model.isDraggingFile, !model.controls.holdsOpen { model.setExpanded(nil) }
            intent.reset()
        case .none:
            break
        }
    }

    /// While the pointer rests (no events), keep evaluating dwell/grace timers.
    private func armRestTimerIfNeeded() {
        let pending = intent.enteredAt != nil || intent.exitedAt != nil
        if pending, restTimer == nil {
            let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.restTick() }
            }
            RunLoop.main.add(t, forMode: .common)
            restTimer = t
        } else if !pending {
            restTimer?.invalidate()
            restTimer = nil
        }
    }

    private func restTick() {
        guard let display = activeDisplay else { return }
        let decision = intent.tick(now: Date(), isOpen: model.expandedScreen == display)
        apply(decision, display: display)
        if intent.enteredAt == nil && intent.exitedAt == nil || decision != .none {
            restTimer?.invalidate()
            restTimer = nil
            maybeDeactivate(pointerNearIsland: controller(at: NSEvent.mouseLocation)?.hoverZone.contains(NSEvent.mouseLocation) ?? false)
        }
    }
}

extension Notification.Name {
    /// Posted by the island view when its silhouette changes (trigger windows follow it).
    static let isletLayoutChanged = Notification.Name("IsletLayoutChanged")
    /// Posted when items in the menu bar appear, disappear or move.
    static let isletMenuBarChanged = Notification.Name("IsletMenuBarChanged")
}
