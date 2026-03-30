import SwiftUI
import GitEditCore

/// Right panel for contextual git views: Diff, History, and Blame.
/// Default width 300px, slides in from right on toggle (Cmd+Shift+G).
struct GitPanelView: View {
    @EnvironmentObject var appState: AppState

    enum GitTab: String, CaseIterable {
        case diff = "Diff"
        case history = "History"
        case blame = "Blame"
    }

    @State private var selectedTab: GitTab = .diff

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("Git View", selection: $selectedTab) {
                ForEach(GitTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .testID("git-tab-picker")
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Content
            switch selectedTab {
            case .diff:
                DiffPanelContent()
            case .history:
                HistoryPanelContent()
            case .blame:
                BlamePanelContent()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .leading) { Divider() }
        .testID("git-panel-content")
    }
}

// MARK: - Diff Panel

struct DiffPanelContent: View {
    @EnvironmentObject var appState: AppState

    // Placeholder: will be populated by libgit2 integration
    @State private var hunks: [DiffHunk] = []

    var body: some View {
        if let tab = appState.activeTab {
            if hunks.isEmpty {
                emptyDiff(tab)
            } else {
                diffContent
            }
        } else {
            noFileSelected
        }
    }

    private var diffContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(hunks) { hunk in
                    HStack(spacing: 0) {
                        Text("@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                    }
                    .background(.quaternary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(hunk.lines) { line in
                        InlineDiffLineRow(line: line)
                    }
                }
            }
        }
    }

    private func emptyDiff(_ tab: EditorTab) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28))
                .foregroundStyle(.green)
            Text("No changes")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(tab.name)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noFileSelected: some View {
        Text("Open a file to see its diff")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct InlineDiffLineRow: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            Text(prefix)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 16)

            Text(line.content)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
    }

    private var prefix: String {
        switch line.kind {
        case .added: return "+"
        case .removed: return "-"
        case .context: return " "
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

// MARK: - History Panel

struct HistoryPanelContent: View {
    @EnvironmentObject var appState: AppState

    // Placeholder: will be populated by libgit2 integration
    @State private var commits: [FileCommit] = []
    @State private var selectedCommitID: String?

    var body: some View {
        if commits.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 28))
                    .foregroundStyle(.quaternary)
                Text("No history available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Open a file in a git repository")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(commits, selection: $selectedCommitID) { commit in
                InlineCommitRow(commit: commit)
            }
            .listStyle(.plain)
        }
    }
}

private struct InlineCommitRow: View {
    let commit: FileCommit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(commit.message)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)

            HStack(spacing: 6) {
                Text(commit.shortHash)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text(commit.author)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(commit.relativeDate)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .help(commit.date.formatted(date: .long, time: .shortened))
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Blame Panel

struct BlamePanelContent: View {
    @EnvironmentObject var appState: AppState

    // Placeholder: will be populated by libgit2 integration
    @State private var blameLines: [BlameLine] = []

    var body: some View {
        if blameLines.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "person.text.rectangle")
                    .font(.system(size: 28))
                    .foregroundStyle(.quaternary)
                Text("No blame data available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Open a file in a git repository")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(blameLines) { line in
                        InlineBlameLineRow(line: line)
                    }
                }
            }
        }
    }
}

private struct InlineBlameLineRow: View {
    let line: BlameLine
    @State private var showPopover = false

    var body: some View {
        HStack(spacing: 8) {
            Text("\(line.id)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 32, alignment: .trailing)

            HStack(spacing: 4) {
                Text(line.author.components(separatedBy: " ").first ?? line.author)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 80, alignment: .leading)

                Text(line.shortHash)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .onHover { hovering in
                showPopover = hovering
            }
            .popover(isPresented: $showPopover) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(line.author).font(.headline)
                    Text(line.commitHash)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(line.message).font(.caption)
                    Text(line.date.formatted(date: .long, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .frame(width: 280)
            }

            Spacer()
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 8)
    }
}
