import AppKit
import IsletCore
import IsletSystem
import SwiftUI

extension Snapshots {
    static let teleprompterDemo = """
    Good morning, everyone, and thank you for joining.
    Today I want to show you three things we shipped this month, and one we didn't.
    First, the new island pages. Each one starts switched off and waits under More until you turn it on.
    Second, the teleprompter you're reading right now. It moves just under the camera, so you look into the lens.
    Third, sales and stocks at a glance, without opening a browser tab.
    """

    /// The tools under "More" (mirror, teleprompter, stocks, sales) and the AI usage lines on
    /// Home, at the compact and standard sizes. Leaves the model as it found it.
    static func renderTools(model: AppModel, now: Date, shoot: (String) -> Void, size: (SizePreset) -> Void) {
        let saved = model.settings
        model.settings.mirror.enabled = true
        model.settings.teleprompter.enabled = true
        model.settings.stocks.enabled = true
        model.settings.sales = SalesSettings(enabled: true, stores: [.stripe, .shopify, .gumroad], shopifyStore: "example")
        model.forcedPresentation = .expanded

        for preset in [SizePreset.compact, .standard] {
            size(preset)
            let suffix = preset.rawValue
            model.tab = .mirror
            model.mirror.showDemo(.running, access: .granted)
            shoot("90-mirror-\(suffix)")
            model.tab = .teleprompter
            model.teleprompter.showDemo(teleprompterDemo, at: 18)
            shoot("91-teleprompter-\(suffix)")
            model.tab = .stocks
            model.stocks.showDemo(now: now)
            shoot("92-stocks-\(suffix)")
            model.tab = .sales
            model.sales.showDemo(now: now)
            shoot("93-sales-\(suffix)")
        }
        size(.compact)

        // Asking for the camera, and none connected.
        model.tab = .mirror
        model.mirror.showDemo(.needsAccess, access: .notDetermined)
        shoot("90b-mirror-allow")
        model.mirror.showDemo(.needsAccess, access: .denied)
        shoot("90c-mirror-not-allowed")
        model.mirror.showDemo(.noCamera, access: .granted)
        shoot("90d-mirror-no-camera")
        model.mirror.showDemo(.off, access: .notDetermined)

        // See-through while reading, on the Black theme too; and with no script yet.
        model.tab = .teleprompter
        model.settings.teleprompter.seeThrough = true
        model.teleprompter.showDemo(teleprompterDemo, at: 40)
        shoot("91b-teleprompter-see-through")
        model.settings.theme = .black
        shoot("91c-teleprompter-see-through-black")
        model.settings.theme = saved.theme
        model.settings.teleprompter.seeThrough = false
        model.settings.teleprompter.textSize = 28
        shoot("91d-teleprompter-large-text")
        model.settings.teleprompter.textSize = saved.teleprompter.textSize
        model.teleprompter.showDemo("", at: 0)
        shoot("91e-teleprompter-empty")

        // A symbol Yahoo doesn't know, one with no connection and no price yet, and one whose
        // earlier price stays while the new one can't be read.
        model.tab = .stocks
        model.stocks.showDemo(now: now)
        model.stocks.showDemoProblems(["NVDA": .message("No data found"), "^GSPC": .unreachable, "MSFT": .unreachable],
                                      stale: ["MSFT"])
        size(.standard)
        shoot("92b-stocks-problems-standard")
        size(.compact)

        // Every store connected: the list scrolls rather than running off the page.
        model.tab = .sales
        model.settings.sales.stores = SalesStore.allCases
        model.sales.showDemo(now: now, stores: SalesStore.allCases)
        shoot("93c-sales-every-store-compact")

        // Sales with no store connected yet.
        model.tab = .sales
        model.settings.sales.stores = []
        shoot("93b-sales-none-connected")

        // AI usage on Home: OpenRouter, Copilot and Ollama, then beside Claude and Codex.
        model.tab = .home
        model.toolUsage.showDemo(now: now)
        model.agentUsage.clearForSnapshot()
        size(.standard)
        shoot("94-home-ai-usage-standard")
        size(.compact)
        shoot("94b-home-ai-usage-compact")
        model.agentUsage.showDemo(now: now)
        size(.large)
        shoot("94c-home-ai-usage-with-agents-large")
        size(.compact)

        model.settings = saved
        model.tab = .home
    }
}
