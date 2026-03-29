import Foundation

/// Parses CSV/TSV content into structured rows and columns.
public struct CSVParser: Sendable {

    public init() {}

    /// Parse CSV content into a 2D array of strings.
    public func parse(_ content: String, delimiter: Character = ",") -> CSVDocument {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false
        var i = content.startIndex

        while i < content.endIndex {
            let char = content[i]

            if insideQuotes {
                if char == "\"" {
                    let next = content.index(after: i)
                    if next < content.endIndex && content[next] == "\"" {
                        // Escaped quote
                        currentField.append("\"")
                        i = content.index(after: next)
                        continue
                    } else {
                        insideQuotes = false
                    }
                } else {
                    currentField.append(char)
                }
            } else {
                if char == "\"" {
                    insideQuotes = true
                } else if char == delimiter {
                    currentRow.append(currentField)
                    currentField = ""
                } else if char.isNewline {
                    // Note: Swift treats \r\n as a single Character (grapheme cluster),
                    // so .isNewline handles \n, \r, and \r\n uniformly.
                    currentRow.append(currentField)
                    currentField = ""
                    if !currentRow.isEmpty {
                        rows.append(currentRow)
                    }
                    currentRow = []
                } else {
                    currentField.append(char)
                }
            }

            i = content.index(after: i)
        }

        // Final field and row
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }

        guard let headerRow = rows.first, !headerRow.isEmpty else {
            return CSVDocument(headers: [], rows: [], columnTypes: [])
        }

        let dataRows = Array(rows.dropFirst())
        let columnTypes = inferColumnTypes(headers: headerRow, rows: dataRows)

        return CSVDocument(headers: headerRow, rows: dataRows, columnTypes: columnTypes)
    }

    /// Infer column types by sampling data.
    private func inferColumnTypes(headers: [String], rows: [[String]]) -> [ColumnType] {
        let sampleSize = min(rows.count, 100)
        let sample = rows.prefix(sampleSize)

        return headers.indices.map { colIndex in
            var numberCount = 0
            var dateCount = 0
            var boolCount = 0
            var nonEmpty = 0

            for row in sample {
                guard colIndex < row.count else { continue }
                let value = row[colIndex].trimmingCharacters(in: .whitespaces)
                if value.isEmpty { continue }
                nonEmpty += 1

                if Double(value) != nil || Int(value) != nil {
                    numberCount += 1
                } else if isBooleanValue(value) {
                    boolCount += 1
                } else if isDateValue(value) {
                    dateCount += 1
                }
            }

            guard nonEmpty > 0 else { return .text }
            let threshold = Double(nonEmpty) * 0.8

            if Double(numberCount) >= threshold { return .number }
            if Double(boolCount) >= threshold { return .boolean }
            if Double(dateCount) >= threshold { return .date }
            return .text
        }
    }

    private func isBooleanValue(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower == "true" || lower == "false" || lower == "yes" || lower == "no" || lower == "1" || lower == "0"
    }

    private func isDateValue(_ value: String) -> Bool {
        // Simple heuristic: matches common date patterns
        let datePatterns = [
            #"^\d{4}-\d{2}-\d{2}$"#,           // 2024-01-15
            #"^\d{2}/\d{2}/\d{4}$"#,            // 01/15/2024
            #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}"#  // ISO 8601
        ]
        return datePatterns.contains { value.range(of: $0, options: .regularExpression) != nil }
    }
}

/// A parsed CSV document.
public struct CSVDocument: Sendable {
    public let headers: [String]
    public let rows: [[String]]
    public let columnTypes: [ColumnType]

    public var rowCount: Int { rows.count }
    public var columnCount: Int { headers.count }
}

/// Inferred column data type for display badges.
public enum ColumnType: String, Sendable {
    case text = "Text"
    case number = "Num"
    case date = "Date"
    case boolean = "Bool"
}
