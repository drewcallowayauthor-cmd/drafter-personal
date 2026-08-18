import Foundation

/// Every file write in the app goes through this: write to a temp file in the same
/// directory, fsync, then atomically rename over the target (§6.5). Never truncate
/// an existing file in place. Abstracted behind a protocol so `ProjectStore` logic
/// can be unit tested without touching real disk.
public protocol AtomicFileWriting: Sendable {
    func write(_ data: Data, to url: URL) throws
}

public struct LiveAtomicFileWriter: AtomicFileWriting {
    public init() {}

    public func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let tempURL = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")

        try data.write(to: tempURL, options: .atomic)
        let handle = try FileHandle(forWritingTo: tempURL)
        try handle.synchronize()
        try handle.close()

        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
    }
}
