import Foundation

/// `Bundle.module` only exists when this file is compiled as part of an SwiftPM target
/// (`swift build`/`swift test`, and the CI/`swift run` path). The Xcode app target
/// (`Drafter.xcodeproj`, used for the packaged `.app`) compiles these same source files
/// directly rather than through SwiftPM, so `Bundle.module` doesn't exist there — but
/// `Bundle.main` resolves to the same place, since the Xcode target copies
/// `Resources/Fonts`/`Resources/DOCX`/`Resources/Binaries` into `Contents/Resources`
/// the same way SwiftPM's `.copy()` resources land in the `.module` bundle.
enum ResourceBundle {
    static var current: Bundle {
        #if SWIFT_PACKAGE
        .module
        #else
        .main
        #endif
    }
}
