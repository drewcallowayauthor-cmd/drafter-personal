import DrafterCore
import Foundation

/// Records every write instead of touching disk, so callers that depend on
/// `AtomicFileWriting` can be unit tested without a temp directory.
public final class MockAtomicFileWriter: AtomicFileWriting, @unchecked Sendable {
    public struct Write: Sendable, Equatable {
        public let url: URL
        public let data: Data
    }

    private let lock = NSLock()
    private var _writes: [Write] = []

    public init() {}

    public var writes: [Write] {
        lock.lock(); defer { lock.unlock() }
        return _writes
    }

    public func write(_ data: Data, to url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        _writes.append(Write(url: url, data: data))
    }
}
