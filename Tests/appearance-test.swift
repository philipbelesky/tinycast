import AppKit
import SwiftUI

/// Pins both branches of every `Theme.Colors` token to upstream's values, against the real `Theme`.
/// The fork adopted upstream's ramp wholesale (FORK.md divergence 2), so neither side is free to
/// drift: a retune here is a deliberate re-divergence, and this harness is where it has to be stated.
@main
@MainActor
struct AppearanceTests {
    static var failures = 0
    static var passes = 0

    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        if ok {
            passes += 1
        } else {
            failures += 1
            print("FAIL  \(label)\(detail.isEmpty ? "" : ": \(detail)")")
        }
    }

    /// Quantized to the 8 bits that reach the framebuffer: raw `CGFloat`s would fail on
    /// `Color(nsColor:).opacity(0.85)`, whose Float error a literal `Color.white.opacity` lacks.
    static func components(_ color: Color, _ name: NSAppearance.Name) -> [Int] {
        var out: [Int] = []
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            let ns = NSColor(color).usingColorSpace(.sRGB)!
            out = [ns.redComponent, ns.greenComponent, ns.blueComponent, ns.alphaComponent]
                .map { Int(($0 * 255).rounded()) }
        }
        return out
    }

    static func resolves(
        _ label: String, _ token: Color, _ name: NSAppearance.Name, is expected: Color
    ) {
        let actual = components(token, name)
        let wanted = components(expected, name)
        check(label, actual == wanted, "\(actual) != \(wanted)")
    }

    static func dark(_ label: String, _ token: Color, is expected: Color) {
        resolves("dark \(label)", token, .darkAqua, is: expected)
    }

    static func light(_ label: String, _ token: Color, is expected: Color) {
        resolves("light \(label)", token, .aqua, is: expected)
    }

    /// A token that resolves identically in both never adapted at all.
    static func adapts(_ label: String, _ token: Color) {
        check(
            "\(label) adapts", components(token, .darkAqua) != components(token, .aqua),
            "light resolves identically to dark")
    }

    static func main() {
        let c = Theme.Colors.self

        print("# dark branches")
        dark("panelScrim", c.panelScrim, is: Color.black.opacity(0.40))
        dark("selection", c.selection, is: Color.white.opacity(0.10))
        dark("rowHover", c.rowHover, is: Color.white.opacity(0.05))
        dark("menuHover", c.menuHover, is: Color.white.opacity(0.10))
        dark("separator", c.separator, is: Color.white.opacity(0.10))
        dark("controlSurface", c.controlSurface, is: Color.white.opacity(0.10))
        dark("border", c.border, is: Color.white.opacity(0.20))
        dark("textPrimary", c.textPrimary, is: Color.white)
        dark("textSecondary", c.textSecondary, is: Color.white.opacity(0.60))
        dark("textTertiary", c.textTertiary, is: Color.white.opacity(0.40))
        dark("iconPlaceholder", c.iconPlaceholder, is: Color.white.opacity(0.06))
        dark("sheen", c.sheen, is: Color.white.opacity(0.04))
        dark("cardFill", c.cardFill, is: Color.white.opacity(0.05))
        dark("cardStroke", c.cardStroke, is: Color.white.opacity(0.10))
        dark("glassFrost", c.glassFrost, is: Color.white.opacity(0.05))
        dark("dropGuide", c.dropGuide, is: Color.white.opacity(0.35))

        print("# light branches")
        light("panelScrim", c.panelScrim, is: Color.white.opacity(0.55))
        light("selection", c.selection, is: Color.black.opacity(0.09))
        light("rowHover", c.rowHover, is: Color.black.opacity(0.045))
        light("menuHover", c.menuHover, is: Color.black.opacity(0.09))
        light("separator", c.separator, is: Color.black.opacity(0.12))
        light("controlSurface", c.controlSurface, is: Color.black.opacity(0.08))
        light("border", c.border, is: Color.black.opacity(0.18))
        light("textPrimary", c.textPrimary, is: Color.black)
        light("textSecondary", c.textSecondary, is: Color.black.opacity(0.60))
        light("textTertiary", c.textTertiary, is: Color.black.opacity(0.42))
        light("iconPlaceholder", c.iconPlaceholder, is: Color.black.opacity(0.06))
        light("sheen", c.sheen, is: Color.black.opacity(0.04))
        light("cardFill", c.cardFill, is: Color.black.opacity(0.04))
        light("cardStroke", c.cardStroke, is: Color.black.opacity(0.10))
        light("glassFrost", c.glassFrost, is: Color.white.opacity(0.25))
        light("dropGuide", c.dropGuide, is: Color.black.opacity(0.35))

        // VolumeSlider drew a flat 0.85; textPrimary is alpha 1, so `.opacity` has to reproduce it.
        print("# textPrimary carries a call site's own opacity")
        dark("textPrimary at 0.85", c.textPrimary.opacity(0.85), is: Color.white.opacity(0.85))
        light("textPrimary at 0.85", c.textPrimary.opacity(0.85), is: Color.black.opacity(0.85))

        print("# every surface token resolves per appearance")
        for (label, token) in [
            ("panelScrim", c.panelScrim), ("selection", c.selection), ("rowHover", c.rowHover),
            ("menuHover", c.menuHover), ("separator", c.separator),
            ("controlSurface", c.controlSurface), ("border", c.border),
            ("textPrimary", c.textPrimary), ("textSecondary", c.textSecondary),
            ("textTertiary", c.textTertiary), ("cardFill", c.cardFill),
            ("cardStroke", c.cardStroke), ("glassFrost", c.glassFrost), ("dropGuide", c.dropGuide),
            ("iconPlaceholder", c.iconPlaceholder), ("sheen", c.sheen)
        ] {
            adapts(label, token)
        }

        print("# the scrim inverts rather than ramping: it lightens the light surface")
        check("light scrim is white", components(c.panelScrim, .aqua)[0] == 255)
        check("dark scrim is black", components(c.panelScrim, .darkAqua)[0] == 0)
        // Frost brightens glass in both, so it is the one token that stays white either side.
        check("frost stays white", components(c.glassFrost, .aqua)[0] == 255)

        print("# .system hands the choice back to AppKit")
        check("system is nil", AppAppearance.system.nsAppearance == nil)
        check("light is aqua", AppAppearance.light.nsAppearance?.isDark == false)
        check("dark is darkAqua", AppAppearance.dark.nsAppearance?.isDark == true)
        check("an unknown stored value is rejected", AppAppearance(rawValue: "sepia") == nil)

        print("\n\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
