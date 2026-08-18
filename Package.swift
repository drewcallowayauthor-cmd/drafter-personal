// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Drafter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DrafterApp", targets: ["DrafterApp"]),
        .library(name: "DrafterCore", targets: ["DrafterCore"]),
        .library(name: "DrafterTestSupport", targets: ["DrafterTestSupport"]),
        .library(name: "GitService", targets: ["GitService"]),
        .library(name: "CompileService", targets: ["CompileService"]),
        .library(name: "BackupService", targets: ["BackupService"]),
        .library(name: "ProjectStore", targets: ["ProjectStore"])
    ],
    targets: [
        // MARK: - Core (shared protocols and types; no I/O of its own)
        .target(
            name: "DrafterCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DrafterCoreTests",
            dependencies: ["DrafterCore", "DrafterTestSupport"]
        ),

        // MARK: - Test support (fakes shared across test targets; not shipped in the app)
        .target(
            name: "DrafterTestSupport",
            dependencies: ["DrafterCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // MARK: - GitService (subprocess wrapper: commit, fetch, merge, push, log, diff)
        .target(
            name: "GitService",
            dependencies: ["DrafterCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "GitServiceTests",
            dependencies: ["GitService", "DrafterTestSupport"]
        ),

        // MARK: - CompileService (assembly -> pandoc -> EPUB / typst -> PDF)
        .target(
            name: "CompileService",
            dependencies: ["DrafterCore", "ProjectStore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CompileServiceTests",
            dependencies: ["CompileService"]
        ),

        // MARK: - BackupService (Box mirror + git bundle scheduling)
        .target(
            name: "BackupService",
            dependencies: ["DrafterCore", "GitService"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "BackupServiceTests",
            dependencies: ["BackupService"]
        ),

        // MARK: - ProjectStore (owns the open project; file I/O; FSEvents; in-memory tree)
        .target(
            name: "ProjectStore",
            dependencies: ["DrafterCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ProjectStoreTests",
            dependencies: ["ProjectStore", "DrafterTestSupport"]
        ),

        // MARK: - App (SwiftUI shell; wires the services together)
        .executableTarget(
            name: "DrafterApp",
            dependencies: ["DrafterCore", "GitService", "CompileService", "BackupService", "ProjectStore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DrafterAppTests",
            dependencies: ["DrafterApp", "DrafterTestSupport"]
        )
    ]
)
