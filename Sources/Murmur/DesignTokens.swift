import AppKit
import CoreText
import SwiftUI

// MARK: - Manrope

/// Registers the bundled Manrope static-weight fonts (extracted from the
/// variable font used in the design mockup) so `Font.manrope` resolves.
/// Must run once, before any view renders — called from
/// `AppDelegate.applicationDidFinishLaunching`.
enum FontLoader {
    private static let weights = [
        "ExtraLight", "Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold",
    ]

    static func registerManrope() {
        for weight in weights {
            let name = "Manrope-\(weight)"
            // Packaged .app: files live under Contents/Resources/Fonts —
            // Bundle.main resolves that correctly. SwiftPM's Bundle.module
            // accessor instead looks for a `Murmur_Murmur.bundle` at the
            // app's top level, which trips codesign's resource sealing, so
            // the shipped app doesn't use it. `swift run` during
            // development has no such Resources folder, so it falls back
            // to Bundle.module there.
            let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
            guard let url else { continue }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }
}

enum ManropeWeight {
    case extraLight, light, regular, medium, semibold, bold, extraBold

    fileprivate var postScriptName: String {
        switch self {
        case .extraLight: return "Manrope-ExtraLight"
        case .light: return "Manrope-Light"
        case .regular: return "Manrope-Regular"
        case .medium: return "Manrope-Medium"
        case .semibold: return "Manrope-SemiBold"
        case .bold: return "Manrope-Bold"
        case .extraBold: return "Manrope-ExtraBold"
        }
    }
}

extension Font {
    /// Manrope at the given size/weight. Falls back to the system font
    /// automatically if registration ever fails — `Font.custom` degrades
    /// gracefully rather than crashing on a missing PostScript name.
    static func manrope(_ size: CGFloat, _ weight: ManropeWeight = .regular) -> Font {
        .custom(weight.postScriptName, size: size)
    }
}

// MARK: - Palette (Murmur: black/cream/lime, sampled from the approved design)

enum Palette {
    private static func dynamic(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? dark : light
        })
    }

    // Surfaces
    static let shell = dynamic(
        NSColor(red: 0.953, green: 0.953, blue: 0.953, alpha: 1),
        NSColor(red: 0.055, green: 0.059, blue: 0.071, alpha: 1))
    static let panel = dynamic(
        .white,
        NSColor(red: 0.090, green: 0.094, blue: 0.110, alpha: 1))
    static let card = dynamic(
        NSColor(red: 0.918, green: 0.933, blue: 0.922, alpha: 1),
        NSColor(red: 0.157, green: 0.149, blue: 0.133, alpha: 1))
    static let cardHover = dynamic(
        NSColor(red: 0.871, green: 0.886, blue: 0.867, alpha: 1),
        NSColor(red: 0.196, green: 0.184, blue: 0.161, alpha: 1))

    // Text
    static let ink = dynamic(.black, NSColor(red: 0.961, green: 0.961, blue: 0.961, alpha: 1))
    static let inkSoft = dynamic(
        NSColor(red: 0.416, green: 0.416, blue: 0.424, alpha: 1),
        NSColor(red: 0.659, green: 0.671, blue: 0.651, alpha: 1))
    static let inkFaint = dynamic(
        NSColor(red: 0.604, green: 0.620, blue: 0.608, alpha: 1),
        NSColor(red: 0.431, green: 0.443, blue: 0.424, alpha: 1))
    static let onInk = dynamic(.white, NSColor(red: 0.090, green: 0.094, blue: 0.110, alpha: 1))

    static let border = dynamic(
        NSColor(red: 0.871, green: 0.886, blue: 0.867, alpha: 1),
        NSColor.white.withAlphaComponent(0.1))

    // Accent (lime) — the fill itself doesn't shift between modes, only
    // the "text version" (accentText) and its soft wash do, so it keeps
    // reading as accent-colored text against either surface.
    //
    // This is deliberately the palest of the brand's three limes, not a
    // drift from the other two:
    //   - #F0FAA1 (here) — in-app UI fills: toggles, pills, highlighted
    //     nav text. Sits behind and beside body text constantly, so it
    //     has to stay calm; the saturated brand lime below reads as
    //     neon the moment it's a solid filled capsule next to prose.
    //   - #C8F137 — Resources/Murmur.svg's accent dots (the app icon).
    //     Icons are small, isolated, and looked at for a second, not
    //     read past — they can afford (and need) more punch to register
    //     at 16px in a menu bar.
    //   - #EAFF58 — murmurmac.com's --lime. A marketing page sells the
    //     brand itself, so its accent is the boldest of the three.
    // Each shade is scoped to a different kind of surface on purpose;
    // this isn't the one to converge on the other two.
    static let accent = Color(red: 0.941, green: 0.980, blue: 0.631)
    static let accentInk = Color.black
    static let accentText = dynamic(
        NSColor(red: 0.373, green: 0.431, blue: 0.157, alpha: 1),
        NSColor(red: 0.941, green: 0.980, blue: 0.631, alpha: 1))
    static let accentSoft = dynamic(
        NSColor(red: 190.0 / 255, green: 205.0 / 255, blue: 60.0 / 255, alpha: 0.22),
        NSColor(red: 0.941, green: 0.980, blue: 0.631, alpha: 0.16))

    static let danger = dynamic(
        NSColor(red: 0.678, green: 0.235, blue: 0.165, alpha: 1),
        NSColor(red: 0.878, green: 0.478, blue: 0.373, alpha: 1))
    // `--shadow` is two layers, and far stronger in dark mode (0.35/0.40)
    // than light (0.04/0.07) — a single faint shadow reads as flat on a
    // dark surface, which is what a naive port produces.
    static let shadowNear = dynamic(
        NSColor(srgbRed: 20 / 255, green: 19 / 255, blue: 17 / 255, alpha: 0.04),
        NSColor.black.withAlphaComponent(0.35))
    static let shadowFar = dynamic(
        NSColor(srgbRed: 20 / 255, green: 19 / 255, blue: 17 / 255, alpha: 0.07),
        NSColor.black.withAlphaComponent(0.40))

    /// `.stat-card-trend` — its own green, distinct from the chart mark.
    static let trendUp = dynamic(
        NSColor(red: 0.286, green: 0.443, blue: 0.224, alpha: 1),
        NSColor(red: 0.659, green: 0.851, blue: 0.494, alpha: 1))
    static let chartMark = dynamic(
        NSColor(red: 0.404, green: 0.463, blue: 0.165, alpha: 1),
        NSColor(red: 0.541, green: 0.600, blue: 0.220, alpha: 1))

    /// Toggle "on" track. The design's own CSS fills this with the raw
    /// `--accent` pastel, which reads fine as a thin text color or a small
    /// dot but turns neon as a solid filled capsule — and worse in dark
    /// mode, where that same light pastel sits directly on a near-black
    /// panel instead of a white one. Reuses `chartMark`'s already-toned,
    /// same-hue step instead of inventing a third green.
    static let toggleOn = chartMark

    // Rail — always dark, in both light and dark app appearance (matches
    // the mockup: the nav rail never changes with system theme).
    static let rail = Color(red: 0.090, green: 0.094, blue: 0.110)

    /// Home's capture zone: a deliberately dark "hero" card in light mode
    /// (same fixed near-black as `rail`, for brand consistency — this part
    /// isn't changing), but NOT pinned to that exact value in dark mode
    /// too. A shadow is how *light* mode communicates elevation, and it
    /// stops working the moment the page around it is already near-black —
    /// there's no room to read as "darker than its surroundings" when nothing
    /// nearby is lighter to begin with. Dark-mode UI elevates surfaces by
    /// making them *lighter*, the same lightness-step idea `card`/`cardHover`
    /// already use one step up from `panel`/`shell` — this is that same
    /// step, scoped to this one surface (roughly a 10% white overlay over
    /// `rail`'s own value) rather than borrowing `card`'s separately-scoped
    /// warm tone. Confirmed against Material Design's dark theme guidance:
    /// elevated dark surfaces use overlay tints, not shadows.
    static let heroSurface = dynamic(
        NSColor(red: 0.090, green: 0.094, blue: 0.110, alpha: 1),
        NSColor(red: 0.181, green: 0.185, blue: 0.199, alpha: 1))
    static let railItem = Color(red: 0.773, green: 0.769, blue: 0.780)
    static let railActive = Color(red: 0.271, green: 0.275, blue: 0.282)

    static let banner = Color(red: 0.090, green: 0.094, blue: 0.110)
    /// The banner is a subtle two-stop gradient, not a flat fill.
    static let banner2 = Color(red: 0.157, green: 0.149, blue: 0.133)

    /// Alias kept for pages not yet ported to the new design — the mockup
    /// uses the plain card surface for callouts (`.page-tip`, availability
    /// banners) rather than a separate tinted color.
    static let tint = card
}

// MARK: - Radii & motion

enum Radius {
    static let sm: CGFloat = 9
    static let md: CGFloat = 12
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
}

extension Animation {
    /// Matches the mockup's cubic-bezier(0.4, 0, 0.2, 1) easing.
    static func murmurEase(_ duration: Double = 0.2) -> Animation {
        .timingCurve(0.4, 0, 0.2, 1, duration: duration)
    }
}
