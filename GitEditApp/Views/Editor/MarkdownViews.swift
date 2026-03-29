import SwiftUI
import GitEditCore

/// Side-by-side markdown editor: source (left) + live preview (right).
/// Scroll positions are independent for now; scroll sync is a v1.5 stretch goal.
struct MarkdownSplitView: View {
    @ObservedObject var tab: EditorTab

    var body: some View {
        HSplitView {
            // Source pane
            PlainTextEditor(tab: tab, showLineNumbers: true, monoFont: true)

            // Preview pane
            MarkdownPreview(content: tab.content)
                .frame(minWidth: 200)
        }
    }
}

/// Rendered markdown preview using AttributedString (CommonMark subset).
struct MarkdownPreview: View {
    let content: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let attributed = try? AttributedString(markdown: content, options: markdownOptions) {
                    Text(attributed)
                        .textSelection(.enabled)
                } else {
                    // Fallback: show raw text if parsing fails
                    Text(content)
                        .textSelection(.enabled)
                }
            }
            .padding(48)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var markdownOptions: AttributedString.MarkdownParsingOptions {
        .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    }
}
