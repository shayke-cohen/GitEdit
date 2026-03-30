import Foundation

/// Represents a file or directory in the workspace file tree.
@MainActor
public final class WorkspaceItem: Identifiable, ObservableObject, @unchecked Sendable {
    nonisolated public let id: UUID
    nonisolated public let url: URL
    nonisolated public let name: String
    nonisolated public let isDirectory: Bool
    nonisolated public let fileType: FileType?
    nonisolated public let depth: Int

    @Published public var children: [WorkspaceItem]?
    @Published public var isExpanded: Bool
    @Published public var gitStatus: GitFileStatus

    public init(
        url: URL,
        isDirectory: Bool,
        depth: Int = 0,
        children: [WorkspaceItem]? = nil
    ) {
        self.id = UUID()
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
        self.fileType = isDirectory ? nil : FileType.detect(from: url)
        self.depth = depth
        self._children = Published(initialValue: children)
        self._isExpanded = Published(initialValue: isDirectory && depth == 0)
        self._gitStatus = Published(initialValue: .unmodified)
    }

    /// SF Symbol name for the file tree row.
    public var iconName: String {
        if isDirectory {
            return "folder.fill"
        }
        return fileType?.iconName ?? "doc"
    }
}

/// Git status for a single file, mapped from libgit2 status flags.
public enum GitFileStatus: String, Sendable {
    case unmodified
    case modified
    case added
    case deleted
    case renamed
    case untracked
    case ignored

    /// Color name for the git decoration dot in the sidebar.
    public var decorationColorName: String? {
        switch self {
        case .unmodified, .ignored: return nil
        case .modified: return "systemOrange"
        case .added, .untracked: return "systemGreen"
        case .deleted: return "systemRed"
        case .renamed: return "systemBlue"
        }
    }

    /// Shape + color decoration for accessibility (DES-001: not color-only).
    public var decoration: (shape: String, color: String)? {
        switch self {
        case .unmodified, .ignored: return nil
        case .modified: return ("circle.fill", "systemOrange")
        case .added, .untracked: return ("plus.circle.fill", "systemGreen")
        case .deleted: return ("minus.circle", "systemRed")
        case .renamed: return ("arrow.right.circle.fill", "systemBlue")
        }
    }
}
