import SwiftUI
import GitEditCore

/// Blame view — per-line author+date gutter with commit tooltip on hover.
/// Lines grouped by commit with subtle color banding.
struct BlamePanelView: View {
    @EnvironmentObject var appState: AppState
    @State private var blameLines: [BlameLine] = []
    @State private var hoveredLine: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let tab = appState.activeTab {
                HStack {
                    Text("Blame: \(tab.name)")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()
            }

            if blameLines.isEmpty {
                emptyState
            } else {
                blameContent
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 24))
                .foregroundStyle(.quaternary)
            Text("No blame data available")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Blame annotations will appear here\nfor files in a git repository.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var blameContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(blameLines) { line in
                    BlameLineRow(
                        line: line,
                        isHovered: hoveredLine == line.id,
                        showAnnotation: shouldShowAnnotation(for: line)
                    )
                    .onHover { isHovered in
                        hoveredLine = isHovered ? line.id : nil
                    }
                }
            }
        }
    }

    /// Only show annotation on first line of each commit group.
    private func shouldShowAnnotation(for line: BlameLine) -> Bool {
        guard line.id > 0 else { return true }
        let prevIndex = line.id - 1
        guard prevIndex < blameLines.count else { return true }
        return blameLines[prevIndex].commitHash != line.commitHash
    }
}

struct BlameLineRow: View {
    let line: BlameLine
    let isHovered: Bool
    let showAnnotation: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Blame annotation gutter
            HStack(spacing: 4) {
                if showAnnotation {
                    Text(String(line.author.split(separator: " ").first ?? ""))
                        .lineLimit(1)
                    Text(relativeDate)
                        .foregroundStyle(.tertiary)
                } else {
                    Spacer()
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: 140, alignment: .trailing)
            .padding(.trailing, 8)

            // Line number
            Text("\(line.id + 1)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 8)
        }
        .padding(.vertical, 1)
        .background(isHovered ? Color.accentColor.opacity(0.05) : .clear)
        .popover(isPresented: .constant(isHovered)) {
            VStack(alignment: .leading, spacing: 4) {
                Text(line.commitHash.prefix(7))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                Text(line.message)
                    .font(.system(size: 12))
                    .lineLimit(3)
                HStack {
                    Text(line.author)
                    Spacer()
                    Text(line.date, style: .date)
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(width: 280)
        }
    }

    private var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: line.date, relativeTo: .now)
    }
}
