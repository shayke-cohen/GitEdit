import Foundation

/// Represents a file or directory in the workspace file tree.
public final class WorkspaceItem: Identifiable, ObservableObject, Sendable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let fileType: FileType?
    public let depth: Int

    @MainActor @Published public var children: [WorkspaceItem]?
    @MainActor @Published public var isExpanded: Bool
    @MainActor @Published public var gitStatus: GitFileStatus

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
}
