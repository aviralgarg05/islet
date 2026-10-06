import AppKit
import CasementCore
import SwiftUI

@MainActor
extension Snapshots {
    /// `<dir>/60-*.png` and `61-*.png` at each size: the open Glass island's stem-and-body shape
    /// (Black beside it for comparison), and the closed island growing while the pointer rests
    /// on it, empty and with music.
    static func renderShapes(to dir: URL, model: AppModel) {
        let saved = model.settings
        let savedTab = model.tab
        defer {
            model.settings = saved
            model.tab = savedTab
            model.setHover(nil)
            model.closedPlacements[1] = nil
        }
        model.tab = .home
        for preset in [SizePreset.compact, .standard, .large] {
            model.settings.sizePreset = preset
            let s = model.settings
            let metrics = NotchGeometry.metrics(for: screen, expandedSize: CGSize(width: s.expandedSize.width, height: s.expandedSize.height),
                                                wingWidth: s.effectiveWingWidth, adjust: s.notchAdjust)
            model.closedPlacements[1] = ClosedPlacement(wing: metrics.wingWidth, slack: .infinity)
            func shoot(_ name: String, height: CGFloat) {
                let view = IslandView(model: model, display: 1, metrics: metrics)
                    .frame(width: 760, height: height)
                    .background(backdrop(metrics: metrics))
                write(view, to: dir.appendingPathComponent("\(name)-\(preset.rawValue).png"))
            }
            let open = metrics.expanded.height + 30 + PageSwitcher.band
            model.forcedPresentation = .expanded
            model.settings.theme = .glass
            shoot("60-expanded-glass-stem", height: open)
            model.settings.glassLevel = 0
            shoot("60-expanded-glass-stem-level-black", height: open)
            model.settings.glassLevel = 1
            shoot("60-expanded-glass-stem-level-glass", height: open)
            model.settings.glassLevel = saved.glassLevel
            model.settings.theme = .black
            shoot("60-expanded-black", height: open)
            model.settings.theme = saved.theme

            // The island answers the pointer only with motion on (with animation Off it would
            // jump): these shots show the response, so they draw it as the default style does.
            model.settings.animationStyle = .fluid
            model.setHover(1)
            model.forcedPresentation = .idle
            shoot("61-hover-idle", height: 60)
            model.forcedPresentation = .compact(.nowPlaying(model.nowPlaying!))
            shoot("61-hover-compact-media", height: 60)
            model.setHover(nil)
            shoot("61-rest-compact-media", height: 60)
            model.settings.animationStyle = saved.animationStyle
        }
    }
}
