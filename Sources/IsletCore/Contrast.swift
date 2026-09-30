import Foundation

/// Keeps tints legible on the island's black: brand colours such as Uber's black or JetBlue's
/// navy are lifted in OKLCH lightness (hue kept) until they reach 3:1 contrast.
extension RGBA {
    /// WCAG relative luminance (0 black … 1 white).
    public var luminance: Double {
        0.2126 * Self.linear(r) + 0.7152 * Self.linear(g) + 0.0722 * Self.linear(b)
    }

    /// WCAG contrast ratio against black.
    public var contrastOnBlack: Double { (luminance + 0.05) / 0.05 }

    /// This colour, or a lighter one of the same hue with at least `minContrast` against black.
    /// Near-greys (no usable hue) become white.
    public func readableOnBlack(minContrast: Double = 3) -> RGBA {
        guard contrastOnBlack < minContrast else { return self }
        let lab = Self.oklab(self)
        let chroma = (lab.a * lab.a + lab.b * lab.b).squareRoot()
        guard chroma >= 0.03 else { return RGBA(r: 1, g: 1, b: 1, a: a) }
        let hue = atan2(lab.b, lab.a)
        var lo = lab.l, hi = 1.0
        var best = RGBA(r: 1, g: 1, b: 1, a: a)
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            let candidate = Self.inGamut(l: mid, chroma: chroma, hue: hue, alpha: a)
            // A little headroom so rounding to 8-bit hex stays above the target.
            if candidate.contrastOnBlack >= minContrast + 0.02 {
                best = candidate
                hi = mid
            } else {
                lo = mid
            }
        }
        return best
    }

    /// `#RRGGBB`, ignoring alpha.
    public var hex: String {
        func byte(_ v: Double) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    static func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    static func gamma(_ c: Double) -> Double { c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055 }

    static func oklab(_ c: RGBA) -> (l: Double, a: Double, b: Double) {
        let r = linear(c.r), g = linear(c.g), b = linear(c.b)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    /// Linear sRGB for an OKLab colour (may fall outside 0...1).
    static func linearRGB(l: Double, a: Double, b: Double) -> (Double, Double, Double) {
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let L = l_ * l_ * l_, M = m_ * m_ * m_, S = s_ * s_ * s_
        return (4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S,
                -1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S,
                -0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S)
    }

    /// The OKLCH colour, with chroma reduced until it fits in sRGB.
    static func inGamut(l: Double, chroma: Double, hue: Double, alpha: Double) -> RGBA {
        var c = chroma
        while true {
            let (r, g, b) = linearRGB(l: l, a: c * cos(hue), b: c * sin(hue))
            let fits = [r, g, b].allSatisfy { $0 >= -0.0001 && $0 <= 1.0001 }
            if fits || c < 0.001 {
                return RGBA(r: gamma(min(1, max(0, r))), g: gamma(min(1, max(0, g))), b: gamma(min(1, max(0, b))), a: alpha)
            }
            c *= 0.94
        }
    }
}
