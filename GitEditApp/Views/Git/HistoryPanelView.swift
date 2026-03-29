import SwiftUI
import GitEditCore

/// File history panel — list of commits touching the current file.
/// Click one commit to see file state; Cmd+click two to compare.
struct HistoryPanelView: View {
    @EnvironmentObject var appState: AppState
    @State private var commits: [FileCommit] = []
    @State private var selectedCommitID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let tab = appState.activeTab {
                HStack {
                    Text("History: \(tab.name)")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(commits.count) commits")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()
            }

            if commits.isEmpty {
                emptyState
            } else {
                commitList
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 24))
                .foregroundStyle(.quaternary)
            Text("No history available")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Commit history will appear here\nfor files in a git repository.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var commitList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(commits) { commit in
                    CommitRow(commit: commit, isSelected: selectedCommitID == commit.id)
                        .onTapGesture {
                            selectedCommitID = commit.id
                        }
                }
            }
        }
    }
}

struct CommitRow: View {
    let commit: FileCommit
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Author avatar placeholder
            Circle()
                .fill(.quaternary)
                .frame(width: 24, height: 24)
                .overlay {
                    Text(String(commit.author.prefix(1)).uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(commit.message)
                    .font(.system(size: 12))
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
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : .clear)
        .contentShape(Rectangle())
    }
}
