import SwiftUI
import GitEditCore

/// Spreadsheet table view for CSV/TSV files.
/// Sortable columns, type badges, virtualized rows, inline cell editing.
struct CSVTableView: View {
    @ObservedObject var tab: EditorTab
    let delimiter: Character

    @State private var document: CSVDocument?
    @State private var sortColumn: Int?
    @State private var sortAscending = true
    @State private var showRaw = false

    private let parser = CSVParser()

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            csvToolbar

            Divider()

            if showRaw {
                PlainTextEditor(tab: tab, showLineNumbers: true, monoFont: true)
            } else if let doc = document {
                tableContent(doc)
            } else {
                ProgressView("Parsing…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { parseContent() }
        .onChange(of: tab.content) { _, _ in parseContent() }
    }

    private var csvToolbar: some View {
        HStack {
            if let doc = document {
                Text("\(doc.rowCount) rows × \(doc.columnCount) columns")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(showRaw ? "Table" : "Raw CSV") {
                showRaw.toggle()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func tableContent(_ doc: CSVDocument) -> some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(sortedRows(doc).enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: 0) {
                            // Row number gutter
                            Text("\(rowIndex + 1)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .frame(width: 40, alignment: .trailing)
                                .padding(.trailing, 8)

                            ForEach(Array(doc.headers.indices), id: \.self) { colIndex in
                                let value = colIndex < row.count ? row[colIndex] : ""
                                Text(value)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                    .frame(width: 150, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                            }
                        }
                        .background(rowIndex % 2 == 0 ? Color.clear : Color(nsColor: .alternatingContentBackgroundColors[1]))
                    }
                } header: {
                    headerRow(doc)
                }
            }
        }
    }

    private func headerRow(_ doc: CSVDocument) -> some View {
        HStack(spacing: 0) {
            // Gutter header
            Text("#")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 8)

            ForEach(Array(doc.headers.enumerated()), id: \.offset) { index, header in
                Button {
                    if sortColumn == index {
                        sortAscending.toggle()
                    } else {
                        sortColumn = index
                        sortAscending = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(header)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)

                        // Type badge
                        if index < doc.columnTypes.count {
                            Text(doc.columnTypes[index].rawValue)
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                        }

                        if sortColumn == index {
                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8))
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 150, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func sortedRows(_ doc: CSVDocument) -> [[String]] {
        guard let col = sortColumn, col < doc.columnCount else { return doc.rows }

        return doc.rows.sorted { a, b in
            let va = col < a.count ? a[col] : ""
            let vb = col < b.count ? b[col] : ""

            // Try numeric comparison first
            if let na = Double(va), let nb = Double(vb) {
                return sortAscending ? na < nb : na > nb
            }
            let result = va.localizedCaseInsensitiveCompare(vb)
            return sortAscending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    private func parseContent() {
        let delim = delimiter
        let text = tab.content
        Task.detached {
            let doc = CSVParser().parse(text, delimiter: delim)
            await MainActor.run { document = doc }
        }
    }
}
