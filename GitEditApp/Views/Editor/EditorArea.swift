import SwiftUI
import GitEditCore

/// Routes the active tab to the appropriate file-type view.
/// File type determines the experience — this is GitEdit's core design principle.
struct EditorArea: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if let tab = appState.activeTab {
                editorView(for: tab)
                    .id(tab.id)  // Force fresh view per tab
            } else {
                noFileOpen
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func editorView(for tab: EditorTab) -> some View {
        switch tab.viewMode {
        case .source:
            // Raw text editor for any file type
            PlainTextEditor(tab: tab, showLineNumbers: true, monoFont: true)
        case .rendered, .split:
            // Rendered view based on file type
            renderedView(for: tab)
        }
    }

    @ViewBuilder
    private func renderedView(for tab: EditorTab) -> some View {
        switch tab.fileType {
        case .markdown:
            if tab.viewMode == .split {
                MarkdownSplitView(tab: tab)
            } else {
                MarkdownPreview(content: tab.content)
            }
        case .csv:
            CSVTableView(tab: tab, delimiter: ",")
        case .tsv:
            CSVTableView(tab: tab, delimiter: "\t")
        case .json, .yaml, .toml:
            TreeEditorView(tab: tab)
        case .env:
            EnvEditorView(tab: tab)
        case .plainText:
            PlainTextEditor(tab: tab, showLineNumbers: false, monoFont: false)
        }
    }

    private var noFileOpen: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
            Text("Open a file from the sidebar")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("⌘P to Quick Open")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
