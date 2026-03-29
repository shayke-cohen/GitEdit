import SwiftUI
import GitEditCore

/// File tree sidebar — shows workspace contents with file-type icons and git decorations.
struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var filterText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Filter field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter files…", text: $filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !filterText.isEmpty {
                    Button {
                        filterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // File tree
            if appState.fileTree.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filteredItems) { item in
                        FileTreeRow(item: item)
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var filteredItems: [WorkspaceItem] {
        guard !filterText.isEmpty else { return appState.fileTree }
        return appState.fileTree.flatFilter { item in
            item.name.localizedCaseInsensitiveContains(filterText)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.largeTitle)
                .foregroundStyle(.quaternary)
            Text("No files")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A single row in the file tree.
struct FileTreeRow: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var item: WorkspaceItem

    var body: some View {
        if item.isDirectory {
            DisclosureGroup(isExpanded: $item.isExpanded) {
                if let children = item.children {
                    ForEach(children) { child in
                        FileTreeRow(item: child)
                    }
                }
            } label: {
                rowLabel
            }
        } else {
            Button {
                appState.openFile(url: item.url)
            } label: {
                rowLabel
            }
            .buttonStyle(.plain)
        }
    }

    private var rowLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: item.iconName)
                .foregroundStyle(iconColor)
                .frame(width: 16)
                .accessibilityLabel(item.isDirectory ? "Folder" : (item.fileType?.displayName ?? "File"))

            Text(item.name)
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer()

            // Git status decoration
            if let colorName = item.gitStatus.decorationColorName {
                Circle()
                    .fill(Color(colorName))
                    .frame(width: 6, height: 6)
                    .accessibilityLabel("Git status: \(item.gitStatus.rawValue)")
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Button("Copy Relative Path") {
                if let root = appState.workspaceURL {
                    let relativePath = item.url.path.replacingOccurrences(of: root.path + "/", with: "")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(relativePath, forType: .string)
                }
            }
        }
    }

    private var iconColor: Color {
        guard let fileType = item.fileType else { return .secondary }
        switch fileType {
        case .markdown: return .blue
        case .csv, .tsv: return .green
        case .json: return .orange
        case .yaml, .toml: return .orange
        case .env: return .yellow
        case .plainText: return .secondary
        }
    }
}

// MARK: - Tree filtering helper

extension Array where Element == WorkspaceItem {
    /// Recursively filter a tree, keeping parents that have matching children.
    @MainActor
    func flatFilter(_ predicate: (WorkspaceItem) -> Bool) -> [WorkspaceItem] {
        compactMap { item in
            if predicate(item) { return item }
            if item.isDirectory, let children = item.children {
                let filtered = children.flatFilter(predicate)
                if !filtered.isEmpty { return item }
            }
            return nil
        }
    }
}
