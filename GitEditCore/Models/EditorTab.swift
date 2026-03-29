import Foundation

/// Represents an open file tab in the editor area.
public final class EditorTab: Identifiable, ObservableObject {
    public let id: UUID
    public let url: URL
    public let fileType: FileType

    @Published public var content: String
    @Published public var isModified: Bool
    @Published public var viewMode: ViewMode

    public var name: String { url.lastPathComponent }

    public init(url: URL, content: String = "") {
        self.id = UUID()
        self.url = url
        self.fileType = FileType.detect(from: url)
        self.content = content
        self.isModified = false
        // Default view mode based on file type
        self.viewMode = fileType.renderingMode == .splitPreview ? .split : .rendered
    }
}

/// View mode for the editor — controls source vs rendered display.
public enum ViewMode: String, CaseIterable, Sendable {
    case source    // Raw text with syntax highlighting
    case split     // Side-by-side source + preview (markdown)
    case rendered  // Full rendered view (preview, table, tree, key-value)
}
