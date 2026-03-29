import Foundation

/// A line-level git change indicator for the editor gutter.
public struct GutterIndicator: Identifiable, Sendable {
    public let id: UUID
    public let lineRange: Range<Int>
    public let kind: GutterKind

    public init(lineRange: Range<Int>, kind: GutterKind) {
        self.id = UUID()
        self.lineRange = lineRange
        self.kind = kind
    }
}

public enum GutterKind: String, Sendable {
    case added
    case modified
    case deleted

    /// SF Symbol for accessibility (not color-only).
    public var shapeName: String {
        switch self {
        case .added: return "plus"
        case .modified: return "circle.fill"
        case .deleted: return "minus"
        }
    }

    public var colorName: String {
        switch self {
        case .added: return "systemGreen"
        case .modified: return "systemOrange"
        case .deleted: return "systemRed"
        }
    }
}

/// A single commit in the file history panel.
public struct FileCommit: Identifiable, Sendable {
    public let id: String  // commit hash
    public let shortHash: String
    public let author: String
    public let email: String
    public let message: String
    public let date: Date

    public init(id: String, author: String, email: String, message: String, date: Date) {
        self.id = id
        self.shortHash = String(id.prefix(7))
        self.author = author
        self.email = email
        self.message = message
        self.date = date
    }

    public var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

/// Blame information for a single line.
public struct BlameLine: Identifiable, Sendable {
    public let id: Int  // line number
    public let commitHash: String
    public let author: String
    public let date: Date
    public let message: String

    public init(lineNumber: Int, commitHash: String, author: String, date: Date, message: String) {
        self.id = lineNumber
        self.commitHash = commitHash
        self.author = author
        self.date = date
        self.message = message
    }

    public var shortHash: String { String(commitHash.prefix(7)) }
}

/// A single diff hunk for the diff overlay.
public struct DiffHunk: Identifiable, Sendable {
    public let id: UUID
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    public let lines: [DiffLine]

    public init(oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, lines: [DiffLine]) {
        self.id = UUID()
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.lines = lines
    }
}

public struct DiffLine: Identifiable, Sendable {
    public let id: UUID
    public let content: String
    public let kind: DiffLineKind

    public init(content: String, kind: DiffLineKind) {
        self.id = UUID()
        self.content = content
        self.kind = kind
    }
}

public enum DiffLineKind: Sendable {
    case context
    case added
    case removed
}
