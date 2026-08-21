import Foundation

/// Fonts shipped inside the app bundle rather than relying on the Mac's installed
/// fonts. Palatino/Centaur/Hightower Text (KDP's other recommended body fonts) are
/// commercial typefaces whose licenses don't permit redistributing the font files —
/// only EB Garamond (SIL Open Font License, `Resources/Fonts/EBGaramond/OFL.txt`) can
/// legally be bundled, so it's the one font that's always available regardless of
/// what's installed on this Mac.
enum BundledFonts {
    static let ebGaramondFamily = "EB Garamond"

    /// The directory typst is pointed at via `--font-path` (`TypstService.compile`)
    /// so it can find the bundled `.ttf`s without them being installed anywhere.
    static var fontsDirectoryURL: URL? {
        Bundle.module.url(forResource: "Fonts", withExtension: nil)
    }
}
