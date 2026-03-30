import SwiftUI
import GitEditCore

/// Clean text editing surface.
/// Plain text mode: centered prose, no line numbers (720px max-width).
/// Source mode: monospace, line numbers, full width.
struct PlainTextEditor: View {
    @ObservedObject var tab: EditorTab
    let showLineNumbers: Bool
    let monoFont: Bool

    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            if showLineNumbers {
                lineNumberGutter
                    .testID("line-number-gutter")
            }

            textEditor
                .testID("text-editor")
        }
    }

    private var textEditor: some View {
        ScrollView {
            if monoFont {
                TextEditor(text: $tab.content)
                    .font(.system(size: 14, design: .monospaced))
                    .scrollDisabled(true)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Prose mode: centered, max-width for readability
                TextEditor(text: $tab.content)
                    .font(.system(size: 16))
                    .lineSpacing(6)
                    .scrollDisabled(true)
                    .padding(.horizontal, 48)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
            }
        }
        .onChange(of: tab.content) { _, _ in
            tab.isModified = true
        }
    }

    private var lineNumberGutter: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: 0) {
                let lines = tab.content.components(separatedBy: .newlines)
                ForEach(Array(lines.enumerated()), id: \.offset) { index, _ in
                    Text("\(index + 1)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(height: 20)
                }
            }
            .padding(.horizontal, 8)
            .frame(width: 48)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .trailing) {
            Divider()
        }
    }
}
