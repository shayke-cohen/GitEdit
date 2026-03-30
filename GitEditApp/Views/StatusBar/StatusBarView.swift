import SwiftUI
import GitEditCore

/// Bottom status bar — file path (left), word/position count (center), file type + git info (right).
struct StatusBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            Divider().frame(height: 0)

            if let tab = appState.activeTab {
                // Left: file path
                Text(relativePath(for: tab))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .testID("status-bar-path")

                Spacer()

                // Center: word count or cursor position
                centerInfo(for: tab)
                    .testID("status-bar-center-info")

                Spacer()

                // Right: file type | encoding | git modified count
                HStack(spacing: 8) {
                    Text(tab.fileType.displayName)
                        .testID("status-bar-filetype")
                    Text("UTF-8")
                        .foregroundStyle(.tertiary)
                }
            } else {
                Spacer()
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .testID("status-bar")
    }

    private func relativePath(for tab: EditorTab) -> String {
        guard let root = appState.workspaceURL else { return tab.url.path }
        return tab.url.path.replacingOccurrences(of: root.path + "/", with: "")
    }

    @ViewBuilder
    private func centerInfo(for tab: EditorTab) -> some View {
        let content = tab.content
        switch tab.fileType.renderingMode {
        case .prose, .splitPreview:
            // Word count for prose/markdown
            let words = content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            let chars = content.count
            Text("\(words) words · \(chars) chars")
        case .table:
            // Row count for CSV — use CSVParser for accurate count (fixes trailing newline bug)
            let rows = CSVParser().parse(content).rowCount
            Text("\(rows) rows")
        default:
            // Line count for everything else
            let lines = content.components(separatedBy: .newlines).count
            Text("\(lines) lines")
        }
    }
}
