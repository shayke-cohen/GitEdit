import SwiftUI
import GitEditCore

/// Two-column key=value editor for .env files.
/// Secret masking for sensitive keys (PASSWORD, SECRET, TOKEN, KEY).
struct EnvEditorView: View {
    @ObservedObject var tab: EditorTab

    @State private var entries: [EnvEntry] = []
    @State private var revealedKeys: Set<Int> = []
    @State private var showAll = false
    @State private var showRaw = false

    private let parser = EnvParser()

    var body: some View {
        VStack(spacing: 0) {
            envToolbar

            Divider()

            if showRaw {
                PlainTextEditor(tab: tab, showLineNumbers: true, monoFont: true)
            } else {
                envTable
            }
        }
        .onAppear { entries = parser.parse(tab.content) }
        .onChange(of: tab.content) { _, _ in entries = parser.parse(tab.content) }
    }

    private var envToolbar: some View {
        HStack {
            Text("Environment")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button(showAll ? "Hide All" : "Show All") {
                showAll.toggle()
                if showAll {
                    revealedKeys = Set(entries.map(\.lineNumber))
                } else {
                    revealedKeys.removeAll()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(showRaw ? "Table" : "Raw") {
                showRaw.toggle()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var envTable: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(entries) { entry in
                    envRow(entry)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func envRow(_ entry: EnvEntry) -> some View {
        switch entry.kind {
        case .blank:
            Spacer().frame(height: 12)

        case .comment(let text):
            Text(text)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)

        case .keyValue(let key, let value, let isSensitive):
            HStack(spacing: 12) {
                // Key
                Text(key)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .frame(minWidth: 150, alignment: .trailing)

                Text("=")
                    .foregroundStyle(.tertiary)

                // Value (masked or revealed)
                let isRevealed = revealedKeys.contains(entry.lineNumber) || !isSensitive
                Text(isRevealed ? value : "••••••••")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(isSensitive && !isRevealed ? .secondary : .primary)
                    .textSelection(isRevealed ? .enabled : .disabled)
                    .accessibilityLabel(isSensitive && !isRevealed ? "masked value" : value)

                // Toggle visibility for sensitive values
                if isSensitive {
                    Button {
                        if revealedKeys.contains(entry.lineNumber) {
                            revealedKeys.remove(entry.lineNumber)
                        } else {
                            revealedKeys.insert(entry.lineNumber)
                        }
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isRevealed ? "Hide value" : "Show value")
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
    }
}
