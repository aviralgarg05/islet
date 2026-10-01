import AppKit
import IsletCore
import SwiftUI

extension Snapshots {
    /// 80 to 83: the island with Increase Contrast (84 and 85 are approvals, 86 is Ask). The ink
    /// and washes are firmer, controls and boxes get a clear edge, and so do the island, its
    /// bubbles and the page switcher. Without it nothing changes, so every other shot stands.
    static func renderIncreasedContrast(model: AppModel, waiting: Activity, metrics: IslandMetrics, shoot: (String) -> Void) {
        increasedContrast = true
        defer { increasedContrast = false }
        let presentation = model.forcedPresentation, tab = model.tab

        // Home with music and its glances, the page switcher under it, and Today.
        model.forcedPresentation = .expanded
        model.tab = .home
        shoot("80-contrast-expanded-home")
        model.tab = .today
        shoot("81-contrast-expanded-today")

        // The closed island with bubbles beside it, in a menu bar with room for them.
        model.closedPlacements[1] = ClosedPlacement(wing: metrics.wingWidth, slack: .infinity)
        model.forcedPresentation = .compact(.activity(waiting, others: 2))
        shoot("82-contrast-compact-bubbles")
        model.closedPlacements[1] = nil

        // The timer composer: a field and a row of capsules.
        model.forcedPresentation = .expanded
        model.tab = .home
        model.timers.isEntering = true
        shoot("83-contrast-timer-composer")
        model.timers.isEntering = false

        model.forcedPresentation = presentation
        model.tab = tab
    }
}
