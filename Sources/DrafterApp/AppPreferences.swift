import Foundation
import Observation

/// Central app-wide preferences, backing the Settings window's five panes and onboarding.
/// UserDefaults-backed like `RecentProjects`, but as a single `@Observable` object rather than
/// per-view `@AppStorage`, since several consumers (schedulers, `BinaryResolver` call sites,
/// `ProjectViewModel`) are plain objects rather than SwiftUI views and need imperative reads.
@MainActor
@Observable
public final class AppPreferences {
    public static let shared = AppPreferences()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - General

    public var projectsDirectoryPath: String? {
        get { defaults.string(forKey: Key.projectsDirectoryPath) }
        set { defaults.set(newValue, forKey: Key.projectsDirectoryPath) }
    }

    public var defaultAuthorName: String {
        get { defaults.string(forKey: Key.defaultAuthorName) ?? "" }
        set { defaults.set(newValue, forKey: Key.defaultAuthorName) }
    }

    public var reopenLastProjectOnLaunch: Bool {
        get { defaults.bool(forKey: Key.reopenLastProjectOnLaunch) }
        set { defaults.set(newValue, forKey: Key.reopenLastProjectOnLaunch) }
    }

    public var lastOpenedProjectPath: String? {
        get { defaults.string(forKey: Key.lastOpenedProjectPath) }
        set { defaults.set(newValue, forKey: Key.lastOpenedProjectPath) }
    }

    // MARK: - Editor

    public var editorFontSize: Double {
        get { defaults.object(forKey: Key.editorFontSize) as? Double ?? 15 }
        set { defaults.set(newValue, forKey: Key.editorFontSize) }
    }

    public var editorLineHeightMultiple: Double {
        get { defaults.object(forKey: Key.editorLineHeightMultiple) as? Double ?? 1.0 }
        set { defaults.set(newValue, forKey: Key.editorLineHeightMultiple) }
    }

    public var measuredWidthInCharacters: Int {
        get { defaults.object(forKey: Key.measuredWidthInCharacters) as? Int ?? 68 }
        set { defaults.set(newValue, forKey: Key.measuredWidthInCharacters) }
    }

    public var isTypewriterScrollingEnabled: Bool {
        get { defaults.object(forKey: Key.isTypewriterScrollingEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.isTypewriterScrollingEnabled) }
    }

    public var typewriterCaretFraction: Double {
        get { defaults.object(forKey: Key.typewriterCaretFraction) as? Double ?? 0.45 }
        set { defaults.set(newValue, forKey: Key.typewriterCaretFraction) }
    }

    // MARK: - Versioning

    public var autosaveDelaySeconds: Double {
        get { defaults.object(forKey: Key.autosaveDelaySeconds) as? Double ?? 2 }
        set { defaults.set(newValue, forKey: Key.autosaveDelaySeconds) }
    }

    public var autocommitDebounceSeconds: Double {
        get { defaults.object(forKey: Key.autocommitDebounceSeconds) as? Double ?? 90 }
        set { defaults.set(newValue, forKey: Key.autocommitDebounceSeconds) }
    }

    public var syncFetchIntervalSeconds: Double {
        get { defaults.object(forKey: Key.syncFetchIntervalSeconds) as? Double ?? 180 }
        set { defaults.set(newValue, forKey: Key.syncFetchIntervalSeconds) }
    }

    public var syncPushDebounceSeconds: Double {
        get { defaults.object(forKey: Key.syncPushDebounceSeconds) as? Double ?? 30 }
        set { defaults.set(newValue, forKey: Key.syncPushDebounceSeconds) }
    }

    // MARK: - Tools

    public var gitPathOverride: String? {
        get { defaults.string(forKey: Key.gitPathOverride) }
        set { defaults.set(newValue, forKey: Key.gitPathOverride) }
    }

    public var pandocPathOverride: String? {
        get { defaults.string(forKey: Key.pandocPathOverride) }
        set { defaults.set(newValue, forKey: Key.pandocPathOverride) }
    }

    public var typstPathOverride: String? {
        get { defaults.string(forKey: Key.typstPathOverride) }
        set { defaults.set(newValue, forKey: Key.typstPathOverride) }
    }

    public var epubcheckPathOverride: String? {
        get { defaults.string(forKey: Key.epubcheckPathOverride) }
        set { defaults.set(newValue, forKey: Key.epubcheckPathOverride) }
    }

    // MARK: - Onboarding

    public var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    public var lastPickedVersionControlMode: String? {
        get { defaults.string(forKey: Key.lastPickedVersionControlMode) }
        set { defaults.set(newValue, forKey: Key.lastPickedVersionControlMode) }
    }

    private enum Key {
        static let projectsDirectoryPath = "DrafterPref.projectsDirectoryPath"
        static let defaultAuthorName = "DrafterPref.defaultAuthorName"
        static let reopenLastProjectOnLaunch = "DrafterPref.reopenLastProjectOnLaunch"
        static let lastOpenedProjectPath = "DrafterPref.lastOpenedProjectPath"

        static let editorFontSize = "DrafterPref.editorFontSize"
        static let editorLineHeightMultiple = "DrafterPref.editorLineHeightMultiple"
        static let measuredWidthInCharacters = "DrafterPref.measuredWidthInCharacters"
        static let isTypewriterScrollingEnabled = "DrafterPref.isTypewriterScrollingEnabled"
        static let typewriterCaretFraction = "DrafterPref.typewriterCaretFraction"

        static let autosaveDelaySeconds = "DrafterPref.autosaveDelaySeconds"
        static let autocommitDebounceSeconds = "DrafterPref.autocommitDebounceSeconds"
        static let syncFetchIntervalSeconds = "DrafterPref.syncFetchIntervalSeconds"
        static let syncPushDebounceSeconds = "DrafterPref.syncPushDebounceSeconds"

        static let gitPathOverride = "DrafterPref.gitPathOverride"
        static let pandocPathOverride = "DrafterPref.pandocPathOverride"
        static let typstPathOverride = "DrafterPref.typstPathOverride"
        static let epubcheckPathOverride = "DrafterPref.epubcheckPathOverride"

        static let hasCompletedOnboarding = "DrafterPref.hasCompletedOnboarding"
        static let lastPickedVersionControlMode = "DrafterPref.lastPickedVersionControlMode"
    }
}
