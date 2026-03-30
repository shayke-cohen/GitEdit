import SwiftUI
import GitEditCore

/// Floating palette for quick file access (Cmd+P).
/// Fuzzy search with keyboard navigation.
struct QuickOpenView: View {
    @EnvironmentObject var appState: AppState
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var selectedIndex = 0

    private let fuzzySearch = FuzzySearch()

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Quick Open…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .testID("quick-open-search")
                    .onSubmit { openSelected() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Results
            if results.isEmpty && !query.isEmpty {
                Text("No matches")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                                QuickOpenRow(
                                    result: result,
                                    isSelected: index == selectedIndex,
                                    workspaceURL: appState.workspaceURL
                                )
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedIndex = index
                                    openSelected()
                                }
                            }
                        }
                    }
                    .onChange(of: selectedIndex) { _, newIndex in
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                    .frame(maxHeight: 300)
                }
            }
        }
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .onAppear {
            query = ""
            updateResults()
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
            updateResults()
        }
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(results.count - 1, selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.escape) {
            appState.showQuickOpen = false
            return .handled
        }
    }

    private func updateResults() {
        let allPaths = collectFilePaths(from: appState.fileTree)

        if query.isEmpty {
            // Show all files when query is empty (most recently opened first)
            results = allPaths.prefix(20).map { SearchResult(path: $0, score: 0) }
        } else {
            results = fuzzySearch.search(query: query, candidates: allPaths)
        }
    }

    private func openSelected() {
        guard selectedIndex < results.count else { return }
        let path = results[selectedIndex].path
        if let root = appState.workspaceURL {
            let url = root.appendingPathComponent(path)
            appState.openFile(url: url)
        }
        appState.showQuickOpen = false
    }

    private func collectFilePaths(from items: [WorkspaceItem]) -> [String] {
        var paths: [String] = []
        for item in items {
            if !item.isDirectory {
                if let root = appState.workspaceURL {
                    let relative = item.url.path.replacingOccurrences(of: root.path + "/", with: "")
                    paths.append(relative)
                }
            }
            if let children = item.children {
                paths.append(contentsOf: collectFilePaths(from: children))
            }
        }
        return paths
    }
}

struct QuickOpenRow: View {
    let result: SearchResult
    let isSelected: Bool
    let workspaceURL: URL?

    var body: some View {
        HStack(spacing: 8) {
            // File type icon
            let fileType = FileType.detect(from: URL(fileURLWithPath: result.path))
            Image(systemName: fileType.iconName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            // Filename (bold) + relative path (muted)
            VStack(alignment: .leading, spacing: 1) {
                Text(URL(fileURLWithPath: result.path).lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(result.path)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : .clear)
    }
}
