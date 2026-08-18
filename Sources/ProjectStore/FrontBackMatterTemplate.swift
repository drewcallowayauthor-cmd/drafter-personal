import Foundation

/// Which section of the binder a generated file belongs in (§4.2).
public enum MatterSection: Sendable, Equatable {
    case front
    case back
}

/// The six standard front/back matter files (§9.2), generated from `project.json` at
/// project creation as editable markdown — never regenerated at compile time, so hand
/// edits are permanent. `content(for:)` is what "Regenerate from template" writes back.
public enum FrontBackMatterTemplate: String, CaseIterable, Sendable {
    case alsoBy
    case titlePage
    case copyright
    case dedication
    case aboutTheAuthor
    case newsletter

    public var section: MatterSection {
        switch self {
        case .alsoBy, .titlePage, .copyright, .dedication: return .front
        case .aboutTheAuthor, .newsletter: return .back
        }
    }

    /// Filename with its ordering prefix (§4.3), matching the design doc's example
    /// layout exactly.
    public var filename: String {
        switch self {
        case .alsoBy: return "01 Also By.md"
        case .titlePage: return "02 Title Page.md"
        case .copyright: return "03 Copyright.md"
        case .dedication: return "04 Dedication.md"
        case .aboutTheAuthor: return "01 About the Author.md"
        case .newsletter: return "02 Newsletter.md"
        }
    }

    /// Looks up which template (if any) a binder file corresponds to, by filename —
    /// used to decide whether a given front/back matter scene can offer "Regenerate
    /// from Template" at all.
    public static func matching(filename: String) -> FrontBackMatterTemplate? {
        allCases.first { $0.filename == filename }
    }

    public func content(for metadata: ProjectMetadata) -> String {
        switch self {
        case .titlePage:
            let subtitleLine = metadata.subtitle.isEmpty ? "" : "\n\(metadata.subtitle)"
            return "# \(metadata.title)\(subtitleLine)\n\n\(metadata.author)"

        case .copyright:
            let isbnLine = metadata.isbn.isEmpty ? "" : "\nISBN: \(metadata.isbn)"
            return """
                Copyright © \(metadata.copyrightYear) by \(metadata.author)

                All rights reserved. No part of this book may be reproduced in any
                form without written permission from the author, except brief
                quotations used in a book review.

                This is a work of fiction. Names, characters, places, and incidents
                are products of the author's imagination or are used fictitiously.
                Any resemblance to actual persons, living or dead, events, or
                locales is entirely coincidental.
                \(isbnLine)
                """

        case .alsoBy:
            return "# Also by \(metadata.author)\n\n*Title of Another Book*"

        case .dedication:
            return "# Dedication\n\nFor —"

        case .aboutTheAuthor:
            return "# About the Author\n\n\(metadata.author) lives and writes. Learn more at [website]."

        case .newsletter:
            return "# Join the Newsletter\n\nSign up at [link] for updates on new releases."
        }
    }
}
