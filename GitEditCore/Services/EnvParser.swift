import Foundation

/// Parses .env file content into structured key-value entries.
public struct EnvParser: Sendable {

    public init() {}

    /// Parse .env content into entries.
    public func parse(_ content: String) -> [EnvEntry] {
        var entries: [EnvEntry] = []

        for (index, line) in content.components(separatedBy: .newlines).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                entries.append(EnvEntry(lineNumber: index, kind: .blank))
                continue
            }

            if trimmed.hasPrefix("#") {
                entries.append(EnvEntry(lineNumber: index, kind: .comment(trimmed)))
                continue
            }

            // Split on first = only
            if let eqIndex = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[trimmed.startIndex..<eqIndex])
                    .trimmingCharacters(in: .whitespaces)
                var value = String(trimmed[trimmed.index(after: eqIndex)...])
                    .trimmingCharacters(in: .whitespaces)

                // Remove surrounding quotes
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                   (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }

                let isSensitive = Self.isSensitiveKey(key)
                entries.append(EnvEntry(
                    lineNumber: index,
                    kind: .keyValue(key: key, value: value, isSensitive: isSensitive)
                ))
            } else {
                // Malformed line — treat as comment
                entries.append(EnvEntry(lineNumber: index, kind: .comment(trimmed)))
            }
        }

        return entries
    }

    /// Check if a key name suggests it contains a secret value.
    /// Matches whole words separated by underscores: PASSWORD, SECRET, TOKEN, KEY, API_KEY, etc.
    /// Does NOT match substrings (MONKEY, TURKEY, AUTHOR are not sensitive).
    public static func isSensitiveKey(_ key: String) -> Bool {
        let upper = key.uppercased()
        let words = Set(upper.split(separator: "_").map(String.init))
        let sensitiveWords: Set<String> = ["PASSWORD", "SECRET", "TOKEN", "KEY", "PRIVATE", "CREDENTIAL", "AUTH"]
        return !words.isDisjoint(with: sensitiveWords)
    }
}

/// A single line in a .env file.
public struct EnvEntry: Identifiable, Sendable {
    public let id: Int  // line number
    public let lineNumber: Int
    public let kind: EnvEntryKind

    public init(lineNumber: Int, kind: EnvEntryKind) {
        self.id = lineNumber
        self.lineNumber = lineNumber
        self.kind = kind
    }
}

public enum EnvEntryKind: Sendable {
    case keyValue(key: String, value: String, isSensitive: Bool)
    case comment(String)
    case blank
}
