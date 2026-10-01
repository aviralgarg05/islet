import Foundation

/// Web browsers Islet knows: for Now Playing ("Web browsers" in Settings), calls held in a
/// browser tab, and passwords copied in one (clipboard history). A browser missing here still
/// plays, under "Other apps".
public enum Browsers {
    /// Bundle id → the name Islet shows.
    public static let names: [String: String] = [
        "com.apple.Safari": "Safari", "com.apple.SafariTechnologyPreview": "Safari Technology Preview",
        "com.google.Chrome": "Chrome", "com.google.Chrome.beta": "Chrome Beta", "com.google.Chrome.dev": "Chrome Dev",
        "com.google.Chrome.canary": "Chrome Canary", "org.chromium.Chromium": "Chromium",
        "company.thebrowser.Browser": "Arc", "company.thebrowser.dia": "Dia",
        "org.mozilla.firefox": "Firefox", "org.mozilla.firefoxdeveloperedition": "Firefox Developer Edition",
        "org.mozilla.nightly": "Firefox Nightly",
        "com.microsoft.edgemac": "Edge", "com.microsoft.edgemac.Beta": "Edge Beta", "com.microsoft.edgemac.Dev": "Edge Dev",
        "com.microsoft.edgemac.Canary": "Edge Canary",
        "com.brave.Browser": "Brave", "com.brave.Browser.beta": "Brave Beta", "com.brave.Browser.nightly": "Brave Nightly",
        "com.vivaldi.Vivaldi": "Vivaldi", "com.operasoftware.Opera": "Opera", "com.operasoftware.OperaGX": "Opera GX",
        "app.zen-browser.zen": "Zen", "com.kagi.kagimacOS": "Orion", "ai.perplexity.comet": "Comet", "com.openai.atlas": "Atlas",
        "com.duckduckgo.macos.browser": "DuckDuckGo",
    ]

    public static var bundleIDs: Set<String> { Set(names.keys) }

    /// The browser a bundle id belongs to, helper processes included ("com.google.Chrome.helper"
    /// is Chrome). The longest match wins, so Chrome Beta's helper is Chrome Beta's.
    public static func browser(for bundleID: String) -> (bundleID: String, name: String)? {
        names.filter { bundleID == $0.key || bundleID.hasPrefix($0.key + ".") }
            .max { $0.key.count < $1.key.count }
            .map { ($0.key, $0.value) }
    }
}
