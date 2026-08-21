import Foundation
import Observation
import SnapshotService

/// Backs §12's Local-file-mode "Version Control" panel — the local counterpart to the
/// Git-mode info already visible via the toolbar's sync status control and Settings'
/// GitHub Account section: detected cloud provider, `History/` size, last snapshot,
/// and the two actions (§12) that don't otherwise have a home.
@MainActor
@Observable
final class LocalFileVersionControlViewModel {
    private(set) var providerText: String
    private(set) var lastSnapshotText = "No snapshots yet"
    private(set) var snapshotCount = 0
    private(set) var historySizeText = "—"
    private(set) var isLoading = false

    private let snapshotService: SnapshotService
    private let workingTree: URL

    var historyFolderURL: URL { workingTree.appendingPathComponent("History") }

    init(snapshotService: SnapshotService, workingTree: URL) {
        self.snapshotService = snapshotService
        self.workingTree = workingTree
        providerText = SnapshotService.cloudProvider(for: workingTree).map { "Syncing via \($0)" } ?? "Not in a synced folder"
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let entries = (try? await snapshotService.log(for: nil, in: workingTree)) ?? []
        snapshotCount = entries.count
        if let latest = entries.first {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let machine = latest.machineName.isEmpty ? "this machine" : latest.machineName
            lastSnapshotText = "\(formatter.localizedString(for: latest.date, relativeTo: .now)) on \(machine)"
        } else {
            lastSnapshotText = "No snapshots yet"
        }

        historySizeText = Self.formattedSize(of: historyFolderURL)
    }

    private static func formattedSize(of url: URL) -> String {
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.fileAllocatedSizeKey]
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) {
            for case let fileURL as URL in enumerator {
                if let size = try? fileURL.resourceValues(forKeys: Set(keys)).fileAllocatedSize {
                    total += Int64(size)
                }
            }
        }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
}
