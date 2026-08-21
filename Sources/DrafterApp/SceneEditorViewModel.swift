import CompileService
import DrafterCore
import Foundation
import Observation
import ProjectStore

/// Owns the currently open scene in the editor pane. Loading is separate from
/// `ProjectViewModel`'s project-level state since which scene is open changes far more
/// often than which project is.
///
/// Autosave (§8.3 point 9): a disk write 2 s after the last keystroke, and immediately
/// on blur (switching scenes, or the app losing focus). No save button, ever.
@MainActor
@Observable
final class SceneEditorViewModel {
    private(set) var document: SceneDocument?
    private(set) var errorMessage: String?

    private let fileWriter: AtomicFileWriting
    /// `var`, not `let`: re-read on every autosave debounce so a Settings change to
    /// the autosave interval takes effect immediately rather than only after the app
    /// (and this view model, which lives for the app's lifetime) restarts.
    var autosaveDelay: Duration
    private var autosaveTask: Task<Void, Never>?
    private var wordCountBaseline = 0

    /// Called after every successful disk write with the word delta since the previous
    /// one — the signal `AutocommitScheduler` uses to know a commit is owed (§5.4).
    var onSaved: ((Int) -> Void)?

    init(fileWriter: AtomicFileWriting = LiveAtomicFileWriter(), autosaveDelay: Duration = .seconds(2)) {
        self.fileWriter = fileWriter
        self.autosaveDelay = autosaveDelay
    }

    func open(url: URL) {
        autosaveTask?.cancel()
        errorMessage = nil
        do {
            document = try SceneDocument.load(from: url)
            wordCountBaseline = WordCounter.count(document?.body ?? "")
        } catch {
            document = nil
            errorMessage = error.localizedDescription
        }
    }

    /// Call on blur: switching scenes or the app losing focus. Flushes any pending edit
    /// immediately rather than waiting out the debounce.
    func close() {
        autosaveTask?.cancel()
        saveNow()
        document = nil
        errorMessage = nil
    }

    func updateBody(_ body: String) {
        document?.body = body
        scheduleAutosave()
    }

    /// Writes the current document to disk immediately if it has unsaved changes.
    /// Idempotent — safe to call speculatively (e.g. on every blur event).
    func saveNow() {
        guard let document, document.isDirty else { return }
        do {
            try fileWriter.write(Data(document.serializedContents().utf8), to: document.url)
            self.document = document.markedSaved()
            let newWordCount = WordCounter.count(document.body)
            onSaved?(newWordCount - wordCountBaseline)
            wordCountBaseline = newWordCount
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let delay = autosaveDelay
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }
}
