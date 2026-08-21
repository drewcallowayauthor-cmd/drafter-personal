import CoreServices
import Foundation

/// §6.3: watches a working tree for changes that came from outside the app — git
/// operations (fetch/merge/checkout), not a sync client, but the reload rules are the
/// same either way. `FSEventStreamCreate`'s own `latency` parameter provides the
/// design doc's "debounced 500ms": a burst of file writes from a `git merge` coalesces
/// into one callback instead of one per file.
///
/// Reports the specific paths that changed (`kFSEventStreamCreateFlagFileEvents`)
/// rather than just "something in this tree changed" — callers need that to tell
/// whether the currently-open scene was actually touched, as opposed to some unrelated
/// file elsewhere in the project (a new chapter being created, front/back matter being
/// regenerated, …). `.git/` is filtered out entirely: the app's own commits (autosave,
/// checkpoint, sync) constantly write inside it, and none of that is ever "an external
/// change to a scene" in §6.3's sense.
final class FileSystemWatcher {
    private var stream: FSEventStreamRef?
    private let path: String
    private let onChange: (Set<URL>) -> Void

    init(path: URL, onChange: @escaping (Set<URL>) -> Void) {
        self.path = path.resolvingSymlinksInPath().path
        self.onChange = onChange
    }

    func start() {
        stop()

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let pathsToWatch = [path] as CFArray

        guard
            let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                Self.callback,
                &context,
                pathsToWatch,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.5,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
            )
        else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }

    private static let callback: FSEventStreamCallback = { _, clientCallBackInfo, numEvents, eventPaths, _, _ in
        guard let clientCallBackInfo else { return }
        let watcher = Unmanaged<FileSystemWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()

        let cPaths = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
        var changedURLs: Set<URL> = []
        for index in 0..<numEvents {
            let path = String(cString: cPaths[index])
            guard !path.contains("/.git/"), !path.hasSuffix("/.git") else { continue }
            changedURLs.insert(URL(fileURLWithPath: path).resolvingSymlinksInPath())
        }

        guard !changedURLs.isEmpty else { return }
        watcher.onChange(changedURLs)
    }
}
