import SwiftUI
import GitEditCore

/// Unified diff view — shows current file vs HEAD.
/// Added lines green bg, removed lines red bg, line numbers both sides.
struct DiffPanelView: View {
    @EnvironmentObject var appState: AppState
    @State private var hunks: [DiffHunk] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            if let tab = appState.activeTab {
                HStack {
                    Text(tab.name)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                    Text("vs HEAD")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()
            }

            if hunks.isEmpty {
                noChanges
            } else {
                diffContent
            }
        }
    }

    private var noChanges: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 24))
                .foregroundStyle(.green)
            Text("No changes")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var diffContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(hunks) { hunk in
                    // Hunk header
                    Text("@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary)

                    // Diff lines
                    ForEach(hunk.lines) { line in
                        DiffLineRow(line: line)
                    }
                }
            }
        }
    }
}

struct DiffLineRow: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            // Line prefix
            Text(prefix)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(prefixColor)
                .frame(width: 16)

            Text(line.content)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 1)
        .background(backgroundColor)
    }

    private var prefix: String {
        switch line.kind {
        case .added: return "+"
        case .removed: return "-"
        case .context: return " "
        }
    }

    private var prefixColor: Color {
        switch line.kind {
        case .added: return Color(red: 0.11, green: 0.48, blue: 0.21)
        case .removed: return Color(red: 0.75, green: 0.22, blue: 0.17)
        case .context: return .secondary
        }
    }

    private var backgroundColor: Color {
        switch line.kind {
        case .added: return Color.green.opacity(0.12)
        case .removed: return Color.red.opacity(0.12)
        case .context: return .clear
        }
    }
}
