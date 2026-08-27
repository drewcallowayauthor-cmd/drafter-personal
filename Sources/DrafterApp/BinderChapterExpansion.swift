import SwiftUI

/// Tracks which Manuscript chapters are expanded in the binder.
///
/// This lives outside `ContentView`'s reactive path on purpose. macOS `List` has a
/// long-standing bug where a screenful of `DisclosureGroup`s driven by a single
/// programmatic `isExpanded` binding rooted in a view that the `List` itself
/// observes will start to overlap and stop toggling once the list gets long
/// (30–50 chapters). Every toggle invalidates the owning view, the whole `List`
/// re-evaluates, and the disclosure animations trip over each other.
///
/// The fix: each chapter row (`ChapterDisclosure`) owns a local `@State` for its
/// own expansion, so toggling one row never re-evaluates the `List`. This class is
/// only a side store — `ContentView` writes to it (seed-on-open, reveal-on-search)
/// but never reads it in `body`, so mutating `expanded` invalidates nothing.
/// Programmatic changes reach the rows through `revealTick`, which the rows observe
/// individually.
@Observable
final class BinderChapterExpansion {
    /// The set of expanded chapter directory URLs. Authoritative, but read only at
    /// row-init time and inside event closures — never during a `body` evaluation.
    private(set) var expanded: Set<URL> = []

    /// Bumped whenever `expanded` is changed programmatically (not by a user toggle),
    /// so already-mounted rows can pick up the new desired state. Rows observe this;
    /// they do not observe `expanded`.
    private(set) var revealTick = 0

    func isExpanded(_ chapterURL: URL) -> Bool {
        expanded.contains(chapterURL)
    }

    /// Records a user's manual toggle. Deliberately does *not* bump `revealTick` —
    /// the row that toggled already has the right local state, and the others should
    /// not be disturbed.
    func userSet(_ chapterURL: URL, expanded isExpanded: Bool) {
        if isExpanded {
            expanded.insert(chapterURL)
        } else {
            expanded.remove(chapterURL)
        }
    }

    /// Expand a single chapter and notify mounted rows (used by reveal-on-search and
    /// after creating a chapter).
    func reveal(_ chapterURL: URL) {
        expanded.insert(chapterURL)
        revealTick += 1
    }

    /// Replace the whole set (used when a project opens: every chapter starts
    /// expanded) and notify mounted rows.
    func replaceAll(with chapterURLs: some Sequence<URL>) {
        expanded = Set(chapterURLs)
        revealTick += 1
    }
}

/// A `DisclosureGroup` whose expansion is held in local `@State`, synced to a shared
/// ``BinderChapterExpansion`` store only through events. See that type's docs for why
/// the indirection matters on macOS `List`.
struct ChapterDisclosure<Label: View, Content: View>: View {
    let chapterURL: URL
    let expansion: BinderChapterExpansion
    @ViewBuilder let content: () -> Content
    @ViewBuilder let label: () -> Label

    @State private var isExpanded: Bool

    init(
        chapterURL: URL,
        expansion: BinderChapterExpansion,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.chapterURL = chapterURL
        self.expansion = expansion
        self.content = content
        self.label = label
        _isExpanded = State(initialValue: expansion.isExpanded(chapterURL))
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded, content: content, label: label)
            .onChange(of: isExpanded) { _, newValue in
                expansion.userSet(chapterURL, expanded: newValue)
            }
            .onChange(of: expansion.revealTick) { _, _ in
                let desired = expansion.isExpanded(chapterURL)
                if desired != isExpanded {
                    isExpanded = desired
                }
            }
    }
}
