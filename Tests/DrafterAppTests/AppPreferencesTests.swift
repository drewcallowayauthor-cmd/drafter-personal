import Foundation
import Testing
@testable import DrafterApp

@MainActor
@Suite("AppPreferences")
struct AppPreferencesTests {
    @Test("defaults match the documented fallback values")
    func defaultsMatchFallbacks() {
        let prefs = makePreferences()

        #expect(prefs.projectsDirectoryPath == nil)
        #expect(prefs.defaultAuthorName == "")
        #expect(prefs.reopenLastProjectOnLaunch == false)
        #expect(prefs.lastOpenedProjectPath == nil)

        #expect(prefs.editorFontSize == 15)
        #expect(prefs.editorLineHeightMultiple == 1.0)
        #expect(prefs.measuredWidthInCharacters == 68)
        #expect(prefs.isTypewriterScrollingEnabled == true)
        #expect(prefs.typewriterCaretFraction == 0.45)

        #expect(prefs.autosaveDelaySeconds == 2)
        #expect(prefs.autocommitDebounceSeconds == 90)
        #expect(prefs.syncFetchIntervalSeconds == 180)
        #expect(prefs.syncPushDebounceSeconds == 30)

        #expect(prefs.gitPathOverride == nil)
        #expect(prefs.pandocPathOverride == nil)
        #expect(prefs.typstPathOverride == nil)
        #expect(prefs.epubcheckPathOverride == nil)

        #expect(prefs.hasCompletedOnboarding == false)
        #expect(prefs.lastPickedVersionControlMode == nil)
    }

    @Test("writes round-trip through the backing UserDefaults suite")
    func writesRoundTrip() {
        let suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = AppPreferences(defaults: defaults)
        prefs.projectsDirectoryPath = "/tmp/Projects"
        prefs.defaultAuthorName = "Josiah"
        prefs.reopenLastProjectOnLaunch = true
        prefs.editorFontSize = 18
        prefs.measuredWidthInCharacters = 72
        prefs.autocommitDebounceSeconds = 45
        prefs.gitPathOverride = "/opt/homebrew/bin/git"
        prefs.hasCompletedOnboarding = true
        prefs.lastPickedVersionControlMode = "localFile"

        let reloaded = AppPreferences(defaults: defaults)
        #expect(reloaded.projectsDirectoryPath == "/tmp/Projects")
        #expect(reloaded.defaultAuthorName == "Josiah")
        #expect(reloaded.reopenLastProjectOnLaunch == true)
        #expect(reloaded.editorFontSize == 18)
        #expect(reloaded.measuredWidthInCharacters == 72)
        #expect(reloaded.autocommitDebounceSeconds == 45)
        #expect(reloaded.gitPathOverride == "/opt/homebrew/bin/git")
        #expect(reloaded.hasCompletedOnboarding == true)
        #expect(reloaded.lastPickedVersionControlMode == "localFile")
    }

    private func makePreferences() -> AppPreferences {
        let suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return AppPreferences(defaults: defaults)
    }
}
