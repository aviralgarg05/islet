import Foundation

// MARK: - Clipboard history

public struct ClipboardEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    /// The text copied; for files, their names; for an image, a description ("Image 1440 × 900").
    public var text: String
    public var date: Date
    public var sourceBundleID: String?
    public var pinned: Bool
    /// What it is, so the Clipboard page can show it as itself.
    public var kind: ClipKind
    /// Files copied in Finder (or anywhere that copies files): their paths, in order.
    public var paths: [String]
    /// An image copied on its own: a screenshot, a picture from a web page.
    public var image: ClipImage?

    public init(id: String = UUID().uuidString, text: String, date: Date, sourceBundleID: String? = nil, pinned: Bool = false,
                kind: ClipKind? = nil, paths: [String] = [], image: ClipImage? = nil) {
        self.id = id; self.text = text; self.date = date; self.sourceBundleID = sourceBundleID; self.pinned = pinned
        self.kind = kind ?? ClipKind.classify(text)
        self.paths = paths
        self.image = image
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        date = try c.decode(Date.self, forKey: .date)
        sourceBundleID = try c.decodeIfPresent(String.self, forKey: .sourceBundleID)
        pinned = (try? c.decodeIfPresent(Bool.self, forKey: .pinned)) ?? false
        paths = (try? c.decodeIfPresent([String].self, forKey: .paths)) ?? []
        image = try? c.decodeIfPresent(ClipImage.self, forKey: .image)
        kind = (try? c.decodeIfPresent(ClipKind.self, forKey: .kind)) ?? ClipKind.classify(text)
    }

    /// The colour a colour clip names.
    public var colour: RGBA? { kind == .colour ? ClipColour.parse(text) : nil }

    /// Bytes it holds: its text, or its image.
    var bytes: Int { image?.data.count ?? text.utf8.count }

    /// Whether every word of a search is in it: its text, its file names and paths, its kind.
    public func matches(_ query: String) -> Bool {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let haystack = ([text, kind.title] + paths).joined(separator: "\n").lowercased()
        return words.allSatisfy { haystack.contains($0) }
    }
}

/// What a clip is.
public enum ClipKind: String, Codable, Sendable, CaseIterable {
    case text, link, colour, image, files

    public var title: String {
        switch self {
        case .text: return "Text"
        case .link: return "Links"
        case .colour: return "Colours"
        case .image: return "Images"
        case .files: return "Files"
        }
    }

    /// A web address on its own is a link, and a colour written as CSS writes it ("#0A84FF",
    /// "rgb(10, 132, 255)", "hsl(211 100% 52%)") is a colour. Anything else is text.
    public static func classify(_ text: String) -> ClipKind {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count <= 2048, !s.contains(where: \.isNewline) else { return .text }
        if ClipLink.parts(s) != nil { return .link }
        if ClipColour.parse(s) != nil, !ClipColour.isNumberedReference(s) { return .colour }
        return .text
    }
}

/// An image as it was copied, kept only in memory with the rest of clipboard history.
public struct ClipImage: Codable, Equatable, Sendable {
    public var data: Data
    /// The pasteboard type it came as ("public.png", "public.tiff").
    public var type: String
    /// Its size in pixels.
    public var width: Int
    public var height: Int

    public init(data: Data, type: String, width: Int, height: Int) {
        self.data = data; self.type = type; self.width = width; self.height = height
    }

    /// "1440 × 900 PNG".
    public var summary: String {
        let format = type.split(separator: ".").last.map { $0.uppercased() } ?? "image"
        return "\(width) × \(height) \(format)"
    }
}

/// A link: where it goes, written plainly.
public enum ClipLink {
    /// ("example.com", "/casement/releases") for a web address on its own, or nil.
    public static func parts(_ text: String) -> (host: String, rest: String)? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.contains(where: \.isWhitespace) else { return nil }
        let lower = s.lowercased()
        let withScheme = lower.hasPrefix("http://") || lower.hasPrefix("https://") ? s : lower.hasPrefix("www.") ? "https://" + s : nil
        guard let withScheme, let url = URL(string: withScheme), let host = url.host, host.contains("."), !host.hasPrefix("."),
              !host.hasSuffix(".") else { return nil }
        var rest = url.path
        if let q = url.query { rest += "?" + q }
        if rest == "/" { rest = "" }
        return (host.hasPrefix("www.") ? String(host.dropFirst(4)) : host, rest)
    }

    /// The address to open: as copied, or with https:// in front of a bare "www." one.
    public static func url(_ text: String) -> URL? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard parts(s) != nil else { return nil }
        return URL(string: s.lowercased().hasPrefix("www.") ? "https://" + s : s)
    }
}

/// A colour written as CSS writes it.
public enum ClipColour {
    /// "#0A84FF", "#fff", "#0A84FF80", "rgb(10, 132, 255)", "rgba(10 132 255 / 50%)",
    /// "hsl(211, 100%, 52%)". A bare "fff" or a colour's name is text.
    public static func parse(_ text: String) -> RGBA? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasPrefix("#") {
            let hex = s.dropFirst()
            guard [3, 4, 6, 8].contains(hex.count), hex.allSatisfy(\.isHexDigit) else { return nil }
            // #RGBA is #RRGGBBAA written short.
            if hex.count == 4 { return RGBA.parse(hex.map { "\($0)\($0)" }.joined()) }
            return RGBA.parse(String(hex))
        }
        for (prefix, isHSL) in [("rgba(", false), ("rgb(", false), ("hsla(", true), ("hsl(", true)] where s.hasPrefix(prefix) {
            guard s.hasSuffix(")") else { return nil }
            let inner = s.dropFirst(prefix.count).dropLast()
            let parts = inner.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" }).map(String.init)
            guard parts.count == 3 || parts.count == 4 else { return nil }
            let alpha = parts.count == 4 ? component(parts[3], scale: 1) : 1
            if isHSL {
                guard let h = Double(parts[0].replacingOccurrences(of: "deg", with: "")), h.isFinite,
                      let sat = percent(parts[1]), let light = percent(parts[2]), let alpha else { return nil }
                return hsl(h, sat, light, alpha)
            }
            guard let r = component(parts[0], scale: 255), let g = component(parts[1], scale: 255),
                  let b = component(parts[2], scale: 255), let alpha else { return nil }
            return RGBA(r: r, g: g, b: b, a: alpha)
        }
        return nil
    }

    /// "#123" or "#4021" copied is far more often an issue or a pull request than a colour, so
    /// three or four digits with no letter count as a colour only when they are one grey
    /// ("#000", "#999"). Six or eight digits ("#336699") are a colour.
    public static func isNumberedReference(_ text: String) -> Bool {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("#") else { return false }
        let digits = s.dropFirst()
        guard (3...4).contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        return Set(digits).count > 1
    }

    /// 0...1 from "128" (out of `scale`) or "50%".
    static func component(_ raw: String, scale: Double) -> Double? {
        if raw.hasSuffix("%") { return percent(raw) }
        guard let v = Double(raw), v >= 0, v <= scale else { return nil }
        return v / scale
    }

    static func percent(_ raw: String) -> Double? {
        guard raw.hasSuffix("%"), let v = Double(raw.dropLast()), (0...100).contains(v) else { return nil }
        return v / 100
    }

    static func hsl(_ hue: Double, _ s: Double, _ l: Double, _ a: Double) -> RGBA {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 30
        func f(_ n: Double) -> Double {
            let k = (n + h).truncatingRemainder(dividingBy: 12)
            return l - s * min(l, 1 - l) * max(-1, min(k - 3, 9 - k, 1))
        }
        return RGBA(r: f(0), g: f(8), b: f(4), a: a)
    }

    /// "#0A84FF", for showing beside the swatch.
    public static func hex(_ c: RGBA) -> String {
        func byte(_ v: Double) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        let base = String(format: "#%02X%02X%02X", byte(c.r), byte(c.g), byte(c.b))
        return c.a < 1 ? base + String(format: "%02X", byte(c.a)) : base
    }
}

/// What was on the pasteboard, as the clipboard monitor read it.
public enum ClipboardContent: Equatable, Sendable {
    case text(String)
    case files([String])
    case image(ClipImage)
}

/// The Clipboard page's filter.
public enum ClipFilter: Hashable, Sendable {
    case all
    case pinned
    case kind(ClipKind)

    public var title: String {
        switch self {
        case .all: return "All"
        case .pinned: return "Pinned"
        case .kind(let k): return k.title
        }
    }

    public func includes(_ e: ClipboardEntry) -> Bool {
        switch self {
        case .all: return true
        case .pinned: return e.pinned
        case .kind(let k): return e.kind == k
        }
    }
}

/// Clipboard history that respects the nspasteboard.org privacy conventions, so passwords
/// copied from password managers are never recorded: text, links, colours, images and files,
/// kept in memory only.
public struct ClipboardHistory: Codable, Equatable, Sendable {
    public private(set) var entries: [ClipboardEntry] = []
    /// Lowering it drops the oldest unpinned entries straight away, not at the next copy.
    public var limit: Int {
        didSet {
            if limit < 1 { limit = 1 }
            trim()
        }
    }
    /// Apps the user chose to ignore (Settings → Shelf & Clipboard). Adding one also forgets
    /// what was already kept from it, pinned or not.
    public var ignoredApps: Set<String> = [] {
        didSet { entries.removeAll { $0.sourceBundleID.map(ignoredApps.contains) ?? false } }
    }
    /// Skip what looks like a password copied in a browser, where password manager extensions
    /// copy as the browser itself: text shaped like a generated password from a web page
    /// (`looksLikeGeneratedPassword`), anything shaped like a password from an extension's own
    /// page (`looksLikePassword`).
    public var skipsSecrets = true

    enum CodingKeys: String, CodingKey { case entries, limit }

    /// Pasteboard types that mark content as secret or throwaway (nspasteboard.org).
    public static let ignoredTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword",
        "de.petermaurer.TransientPasteboardType",
        "com.typeit4me.clipping",
        "Pasteboard generator type",
    ]

    /// Apps whose copies are never recorded, regardless of types.
    /// Bundle identifiers of password managers (identifiers, not credentials).
    public static let ignoredApps: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.apple.Passwords.MenuBarExtra",
        "org.keepassxc.keepassxc",
        "com.lastpass.LastPass",
        "com.dashlane.Dashlane",
    ]

    /// Browsers, whose password manager extensions copy passwords as the browser.
    public static var browsers: Set<String> { Browsers.bundleIDs }

    /// The pasteboard type where Chrome, Edge, Brave, Arc and other Chromium browsers put the
    /// address of the page or extension a copy came from. Casement reads it to decide, never keeps it.
    public static let sourceURLType = "org.chromium.source-url"

    /// Chrome Web Store ids of password manager extensions (identifiers, not credentials). A
    /// copy from one of their pages is never kept, like a copy from their apps.
    public static let passwordManagerExtensions: Set<String> = [
        "aeblfdkhhhdcdjpifhhbdiojplfjncoa", // 1Password
        "nngceckbapebfimnlniiiahkandclblb", // Bitwarden
        "hdokiejnpimakedhajhdlcegeplioahd", // LastPass
        "fdjamakpfbbddfjaooikfcpapjohcfmg", // Dashlane
        "pejdijmoenmkgeppbflobdenhhabjlaj", // iCloud Passwords
        "ghmbeldphafepmbegfdlkpapadhbakde", // Proton Pass
        "bfogiafebfohielmmehodmfbbebbbpei", // Keeper
        "oboonakemofpalcgghocfoadofidjkkk", // KeePassXC-Browser
        "fooolghllnmhmmndgjiamiiodkpenpbb", // NordPass
        "pnlccmojcmeohlpggmfnbbiapkmbliob", // RoboForm
    ]

    public static let maxTextLength = 100_000
    /// The most text kept in all (bytes of UTF-8), whatever the count: 500 long copies would
    /// otherwise hold 50 MB. The oldest unpinned entries go first.
    public static let maxTotalBytes = 4_000_000
    /// The largest image kept (a full-screen Retina screenshot is 2 to 8 MB), and all images
    /// together: past that, the oldest unpinned images go first.
    public static let maxImageBytes = 12_000_000
    public static let maxTotalImageBytes = 36_000_000
    /// More files than this copied at once aren't kept (a whole folder selected in Finder).
    public static let maxFiles = 100

    public init(limit: Int = 30) { self.limit = max(1, limit) }

    public enum Outcome: Equatable, Sendable { case added, moved, ignored }

    /// - Parameter sourceURL: the page or extension a browser says the copy came from
    ///   (`sourceURLType`), used for the decision only.
    @discardableResult
    public mutating func add(_ text: String, types: [String], sourceBundleID: String?, sourceURL: String? = nil,
                             now: Date) -> Outcome {
        guard shouldKeep(text, types: types, sourceBundleID: sourceBundleID, sourceURL: sourceURL) else { return .ignored }
        if let i = entries.firstIndex(where: { $0.paths.isEmpty && $0.image == nil && $0.text == text }) {
            moveToFront(i, now: now, sourceBundleID: sourceBundleID)
            return .moved
        }
        entries.insert(ClipboardEntry(text: text, date: now, sourceBundleID: sourceBundleID), at: 0)
        trim()
        return .added
    }

    /// Whatever the monitor read: text, files or an image.
    @discardableResult
    public mutating func add(_ content: ClipboardContent, types: [String], sourceBundleID: String?, sourceURL: String? = nil,
                             now: Date) -> Outcome {
        switch content {
        case .text(let text):
            return add(text, types: types, sourceBundleID: sourceBundleID, sourceURL: sourceURL, now: now)
        case .files(let paths):
            guard !paths.isEmpty, paths.count <= Self.maxFiles, isAllowed(types: types, sourceBundleID: sourceBundleID) else {
                return .ignored
            }
            if let i = entries.firstIndex(where: { $0.kind == .files && $0.paths == paths }) {
                moveToFront(i, now: now, sourceBundleID: sourceBundleID)
                return .moved
            }
            let names = paths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
            entries.insert(ClipboardEntry(text: names, date: now, sourceBundleID: sourceBundleID, kind: .files, paths: paths), at: 0)
            trim()
            return .added
        case .image(let image):
            guard !image.data.isEmpty, image.data.count <= Self.maxImageBytes, isAllowed(types: types, sourceBundleID: sourceBundleID)
            else { return .ignored }
            if let i = entries.firstIndex(where: { $0.image?.data.count == image.data.count && $0.image?.data == image.data }) {
                moveToFront(i, now: now, sourceBundleID: sourceBundleID)
                return .moved
            }
            entries.insert(ClipboardEntry(text: "Image " + image.summary, date: now, sourceBundleID: sourceBundleID, kind: .image,
                                          image: image), at: 0)
            trim()
            return .added
        }
    }

    /// Copied again from the Clipboard page: it goes back to the top.
    public mutating func touch(id: String, now: Date) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        moveToFront(i, now: now, sourceBundleID: nil)
    }

    private mutating func moveToFront(_ i: Int, now: Date, sourceBundleID: String?) {
        var e = entries.remove(at: i)
        e.date = now
        e.sourceBundleID = sourceBundleID ?? e.sourceBundleID
        entries.insert(e, at: 0)
    }

    /// What the Clipboard page lists for a search and a filter, newest first.
    public func filtered(_ query: String, filter: ClipFilter = .all) -> [ClipboardEntry] {
        entries.filter { filter.includes($0) && $0.matches(query) }
    }

    /// The filters worth offering: All, Pinned when something is pinned, and each kind there is.
    public var filters: [ClipFilter] {
        var out: [ClipFilter] = [.all]
        if entries.contains(where: \.pinned) { out.append(.pinned) }
        let kinds = Set(entries.map(\.kind))
        out += ClipKind.allCases.filter(kinds.contains).map(ClipFilter.kind)
        return out
    }

    /// The filter a choice comes to: the choice while the bar offers it, All once it doesn't
    /// (the last pinned clip unpinned, the last picture removed). The page forgets a choice it
    /// no longer offers, so a later copy doesn't switch the list back to it unasked.
    public func resolved(_ filter: ClipFilter) -> ClipFilter {
        filters.contains(filter) ? filter : .all
    }

    public mutating func togglePin(id: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].pinned.toggle()
    }

    /// Whether a copy is kept: never secret or throwaway types (nspasteboard.org), password
    /// managers' apps and extensions, apps the user ignored, likely passwords from a browser,
    /// blank text or text over `maxTextLength`.
    public func shouldKeep(_ text: String, types: [String], sourceBundleID: String?, sourceURL: String? = nil) -> Bool {
        guard isAllowed(types: types, sourceBundleID: sourceBundleID) else { return false }
        if let id = sourceURL.flatMap(Self.extensionID), Self.passwordManagerExtensions.contains(id) { return false }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= Self.maxTextLength else { return false }
        if skipsSecrets, let b = sourceBundleID, Browsers.browser(for: b) != nil {
            // An extension's own page copies little but what it holds; a web page copies all sorts.
            let fromExtension = sourceURL.map(Self.isExtensionPage) ?? false
            if fromExtension ? Self.looksLikePassword(text) : Self.looksLikeGeneratedPassword(text) { return false }
        }
        return true
    }

    /// Not secret or throwaway (nspasteboard.org), and not from a password manager or an app
    /// the user ignored. Images and files are held to this; text to `shouldKeep`.
    public func isAllowed(types: [String], sourceBundleID: String?) -> Bool {
        if types.contains(where: Self.ignoredTypes.contains) { return false }
        if let b = sourceBundleID, Self.ignoredApps.contains(b) || ignoredApps.contains(b) { return false }
        return true
    }

    // MARK: What a password looks like

    /// The extension a browser's source address names (`chrome-extension://<id>/…`), if any.
    static func extensionID(_ sourceURL: String) -> String? {
        let prefix = "chrome-extension://"
        guard sourceURL.lowercased().hasPrefix(prefix) else { return nil }
        let id = sourceURL.dropFirst(prefix.count).prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        return id.isEmpty ? nil : id.lowercased()
    }

    /// Whether a browser's source address is one of its extensions' own pages.
    static func isExtensionPage(_ sourceURL: String) -> Bool {
        let s = sourceURL.lowercased()
        return ["chrome-extension://", "moz-extension://", "safari-web-extension://", "extension://"].contains { s.hasPrefix($0) }
    }

    /// Safari's (and the Passwords app's) strong password: three groups of six letters and
    /// digits joined by hyphens, with a capital and a digit ("fujvy7-Bezkah-doqnij").
    static func isSafariStrongPassword(_ text: String) -> Bool {
        let groups = text.split(separator: "-", omittingEmptySubsequences: false)
        guard groups.count == 3,
              groups.allSatisfy({ $0.count == 6 && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } }) else { return false }
        return text.contains(where: \.isUppercase) && text.contains(where: \.isLowercase) && text.contains(where: \.isNumber)
    }

    /// How a generated password looks, which text copied from a web page almost never does:
    /// Safari's strong passwords, or plain ASCII mixing both cases with digits or symbols where
    /// the letters don't make words. "xT3!kP9#qr" falls apart into x, T, k, P and qr, while
    /// "Windows11", "COVID-19", "iPhone15Pro", "Report_Q3-2026.pdf" and UUIDs keep their words
    /// (or use one case) and are kept. Some generated passwords read wordy enough to be kept:
    /// the rule would rather keep a password on this Mac than lose ordinary text.
    public static func looksLikeGeneratedPassword(_ text: String) -> Bool {
        guard looksLikePassword(text), text.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }) else { return false }
        if isSafariStrongPassword(text) { return true }
        let letters = text.filter(\.isLetter)
        guard letters.contains(where: \.isLowercase), letters.contains(where: \.isUppercase) else { return false }
        // Hexadecimal: hashes, colours, UUIDs.
        if letters.allSatisfy({ "abcdefABCDEF".contains($0) }) { return false }
        let all = words(in: text)
        let scraps = all.filter(isScrap).count
        return scraps >= 3 && scraps * 2 >= all.count
    }

    /// Units written in mixed case, each a word of its own ("3.2GHz", "5000mAh").
    static let units: Set<String> = [
        "Hz", "kHz", "MHz", "GHz", "THz", "Wh", "kWh", "MWh", "Ah", "mAh", "dB", "dBm", "kB", "KiB", "MiB", "GiB", "TiB",
        "kbps", "Mbps", "Gbps", "MBps", "GBps", "mL", "mW", "kW", "MW",
    ]

    /// The words in a text's letters, split the way names and code are written: "getHUDValue"
    /// is get, HUD and Value; "iOS" is i and OS. Digits and symbols separate words.
    static func words(in text: String) -> [String] {
        var out: [String] = []
        for run in text.split(whereSeparator: { !($0.isASCII && $0.isLetter) }) {
            if units.contains(String(run)) {
                out.append(String(run))
                continue
            }
            let c = Array(run)
            var i = 0
            while i < c.count {
                var j = i
                if c[i].isUppercase {
                    while j < c.count, c[j].isUppercase { j += 1 }
                    if j - i == 1 {
                        // A capital and the lower case after it: a capitalised word.
                        while j < c.count, c[j].isLowercase { j += 1 }
                    } else if j < c.count {
                        // Capitals, then lower case ("HTTPServer"): the last capital starts the next word.
                        j -= 1
                    }
                } else {
                    while j < c.count, c[j].isLowercase { j += 1 }
                }
                out.append(String(c[i..<j]))
                i = j
            }
        }
        return out
    }

    /// A scrap rather than a word: a lone letter, or letters without a vowel that aren't all
    /// capitals ("Hv", "qr", "Bzk"). Capitals alone ("HUD", "OS") read as an abbreviation.
    static func isScrap(_ word: String) -> Bool {
        if word.count == 1 { return true }
        if units.contains(word) || word.allSatisfy(\.isUppercase) { return false }
        return !word.contains { "aeiouyAEIOUY".contains($0) }
    }

    /// One line with no spaces, 8 to 128 characters, mixing at least three of lower case,
    /// upper case, digits and symbols. Links, paths, email addresses and domain names don't
    /// count, however mixed. Broad on purpose: only a copy from a browser extension's own page
    /// is held to it.
    public static func looksLikePassword(_ text: String) -> Bool {
        guard (8...128).contains(text.count), !text.contains(where: { $0.isWhitespace }) else { return false }
        if text.contains("://") || text.hasPrefix("www.") || text.hasPrefix("/") || text.hasPrefix("~/") { return false }
        if text.range(of: #"^[^@]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[a-z]{2,24}$"#, options: .regularExpression) != nil { return false }
        if text.range(of: #"^([A-Za-z0-9-]+\.)+[a-z]{2,24}(/\S*)?$"#, options: .regularExpression) != nil { return false }
        var lower = false, upper = false, digit = false, symbol = false
        for c in text.unicodeScalars {
            switch c.properties.generalCategory {
            case .lowercaseLetter: lower = true
            case .uppercaseLetter: upper = true
            case .decimalNumber: digit = true
            default: symbol = true
            }
        }
        return [lower, upper, digit, symbol].filter { $0 }.count >= 3
    }

    public mutating func remove(id: String) { entries.removeAll { $0.id == id } }

    /// Clears everything except pinned entries ("Clear unpinned").
    public mutating func clear() { entries.removeAll { !$0.pinned } }

    /// Forgets everything, pinned entries too: clipboard history was switched off.
    public mutating func removeAll() { entries.removeAll() }

    public var hasUnpinned: Bool { entries.contains { !$0.pinned } }

    mutating func trim() {
        while entries.count > limit, let i = entries.lastIndex(where: { !$0.pinned }) {
            entries.remove(at: i)
        }
        var total = entries.filter { $0.image == nil }.reduce(0) { $0 + $1.bytes }
        while total > Self.maxTotalBytes, let i = entries.lastIndex(where: { !$0.pinned && $0.image == nil }) {
            total -= entries[i].bytes
            entries.remove(at: i)
        }
        var images = entries.compactMap(\.image).reduce(0) { $0 + $1.data.count }
        while images > Self.maxTotalImageBytes, let i = entries.lastIndex(where: { !$0.pinned && $0.image != nil }) {
            images -= entries[i].bytes
            entries.remove(at: i)
        }
    }
}

// MARK: - File shelf

public struct ShelfItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var path: String
    public var addedAt: Date
    /// Security-scoped / regular bookmark so items survive renames and moves.
    public var bookmark: Data?

    public init(id: String = UUID().uuidString, path: String, addedAt: Date, bookmark: Data? = nil) {
        self.id = id; self.path = path; self.addedAt = addedAt; self.bookmark = bookmark
    }

    public var name: String { (path as NSString).lastPathComponent }
    public var fileExtension: String { (path as NSString).pathExtension.lowercased() }
}

/// Temporary holding area for files dragged onto the island.
public struct Shelf: Codable, Equatable, Sendable {
    public private(set) var items: [ShelfItem] = []
    public var limit: Int

    public init(limit: Int = 40) { self.limit = max(1, limit) }

    /// Add paths (deduplicated, newest first). A file already on the shelf moves to the front
    /// and its time on the shelf starts again. Returns the paths that were new.
    @discardableResult
    public mutating func add(paths: [String], now: Date, bookmark: (String) -> Data? = { _ in nil }) -> [String] {
        var added: [String] = []
        for p in paths.reversed() where !p.isEmpty {
            let std = (p as NSString).standardizingPath
            if let i = items.firstIndex(where: { $0.path == std }) {
                var existing = items.remove(at: i)
                existing.addedAt = now
                items.insert(existing, at: 0)
                continue
            }
            items.insert(ShelfItem(path: std, addedAt: now, bookmark: bookmark(std)), at: 0)
            added.append(std)
        }
        if items.count > limit { items.removeLast(items.count - limit) }
        return added.reversed()
    }

    public mutating func remove(id: String) { items.removeAll { $0.id == id } }
    public mutating func removeAll() { items.removeAll() }

    // MARK: How long files stay

    /// Takes off the shelf what has been there longer than `keepFor` seconds (0 keeps
    /// everything). Only the shelf forgets them: the files themselves stay where they are.
    /// Returns what was taken off.
    @discardableResult
    public mutating func expire(now: Date, keepFor: TimeInterval) -> [ShelfItem] {
        guard keepFor > 0 else { return [] }
        let gone = items.filter { now.timeIntervalSince($0.addedAt) >= keepFor }
        guard !gone.isEmpty else { return [] }
        let ids = Set(gone.map(\.id))
        items.removeAll { ids.contains($0.id) }
        return gone
    }

    /// When the next file is due to come off the shelf, for the one deadline timer.
    public func nextExpiry(keepFor: TimeInterval) -> Date? {
        guard keepFor > 0 else { return nil }
        return items.map { $0.addedAt.addingTimeInterval(keepFor) }.min()
    }

    /// How long, as said in a sentence: "an hour", "a day", "a week", "3 days". Nil when files
    /// are kept until they are removed.
    public static func keepPhrase(_ seconds: TimeInterval) -> String? {
        guard seconds > 0 else { return nil }
        let title = keepTitle(seconds)
        for (one, phrase) in [("1 minute", "a minute"), ("1 hour", "an hour"), ("1 day", "a day"), ("1 week", "a week")] where title == one {
            return phrase
        }
        return title
    }

    /// "Until I remove them", "1 hour", "1 day", "1 week" (and "10 minutes" for a shorter
    /// time set in config.json).
    public static func keepTitle(_ seconds: TimeInterval) -> String {
        if seconds <= 0 { return "Until I remove them" }
        if seconds < 3600 {
            let minutes = max(1, Int((seconds / 60).rounded()))
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
        let hours = Int((seconds / 3600).rounded())
        if hours < 24 { return hours <= 1 ? "1 hour" : "\(hours) hours" }
        let days = Int((seconds / 86400).rounded())
        if days % 7 == 0 { return days == 7 ? "1 week" : "\(days / 7) weeks" }
        return days == 1 ? "1 day" : "\(days) days"
    }

    /// Drop entries whose file no longer exists. Files on a disk or share that isn't mounted
    /// right now stay (`isAvailable` dims them) until it comes back.
    public mutating func prune(exists: (String) -> Bool) {
        items.removeAll { item in
            guard !exists(item.path) else { return false }
            if let volume = Self.volume(of: item.path), !exists(volume) { return false }
            return true
        }
    }

    /// The external volume a path is on ("/Volumes/Backup"), or nil for the startup disk.
    public static func volume(of path: String) -> String? {
        let parts = (path as NSString).standardizingPath.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 3, parts[0] == "Volumes" else { return nil }
        return "/Volumes/" + parts[1]
    }

    /// Whether an item can be opened now: false while the volume it is on isn't mounted.
    public static func isAvailable(_ item: ShelfItem, exists: (String) -> Bool) -> Bool {
        guard let volume = volume(of: item.path) else { return true }
        return exists(volume)
    }

    public mutating func updatePath(id: String, to path: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].path = path
    }

    /// The bookmark for an item, made after it was added (away from the main thread).
    public mutating func setBookmark(_ data: Data?, forPath path: String) {
        guard let i = items.firstIndex(where: { $0.path == path }) else { return }
        items[i].bookmark = data
    }

    /// Items on the startup disk are quick to check, so they are checked at once. Ones on
    /// another volume (an external disk, or a network share that may not answer) are checked
    /// away from the main thread (`ShelfCheck`).
    public static func isOnStartupDisk(_ item: ShelfItem) -> Bool { volume(of: item.path) == nil }
}

/// What a look at a shelf file on another volume found.
public enum ShelfCheck: Equatable, Sendable {
    /// The file is there.
    case present
    /// Its volume is there and the file isn't: it leaves the shelf.
    case gone
    /// Its volume isn't mounted (or didn't answer in time): it stays, dimmed, until it is back.
    case unreachable

    public static func check(path: String, exists: (String) -> Bool) -> ShelfCheck {
        if exists(path) { return .present }
        if let volume = Shelf.volume(of: path), !exists(volume) { return .unreachable }
        return .gone
    }
}

// MARK: - System stats

public struct CPUTicks: Equatable, Sendable {
    public var user: UInt64, system: UInt64, idle: UInt64, nice: UInt64
    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }
}

public struct SystemStats: Equatable, Sendable {
    /// 0...1
    public var cpu: Double
    public var memoryUsed: UInt64
    public var memoryTotal: UInt64

    public init(cpu: Double, memoryUsed: UInt64, memoryTotal: UInt64) {
        self.cpu = cpu; self.memoryUsed = memoryUsed; self.memoryTotal = memoryTotal
    }

    public var memoryFraction: Double { memoryTotal == 0 ? 0 : Double(memoryUsed) / Double(memoryTotal) }

    /// CPU usage between two samples summed over all cores.
    public static func cpuUsage(previous: [CPUTicks], current: [CPUTicks]) -> Double {
        guard previous.count == current.count, !current.isEmpty else { return 0 }
        var busy: UInt64 = 0, total: UInt64 = 0
        for (a, b) in zip(previous, current) {
            let du = b.user &- a.user, ds = b.system &- a.system, dn = b.nice &- a.nice, di = b.idle &- a.idle
            // Counter wrap or reset: skip this core.
            guard b.user >= a.user, b.system >= a.system, b.idle >= a.idle, b.nice >= a.nice else { continue }
            busy += du + ds + dn
            total += du + ds + dn + di
        }
        return total == 0 ? 0 : Double(busy) / Double(total)
    }
}
