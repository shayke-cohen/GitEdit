import Foundation

/// Supported file types with their associated rendering modes.
/// File type determines the editor experience — this is GitEdit's core design principle.
public enum FileType: String, CaseIterable, Identifiable, Sendable {
    case markdown
    case csv
    case tsv
    case json
    case yaml
    case toml
    case env
    case plainText

    public var id: String { rawValue }

    /// Detect file type from a file URL's extension.
    public static func detect(from url: URL) -> FileType {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()

        // Name-based detection first (.env has no real extension)
        if name == ".env" || name.hasPrefix(".env.") {
            return .env
        }

        switch ext {
        case "md", "mdx", "markdown":
            return .markdown
        case "csv":
            return .csv
        case "tsv":
            return .tsv
        case "json":
            return .json
        case "yaml", "yml":
            return .yaml
        case "toml":
            return .toml
        case "env":
            return .env
        default:
            return .plainText
        }
    }

    /// The rendering mode this file type uses.
    public var renderingMode: RenderingMode {
        switch self {
        case .markdown: return .splitPreview
        case .csv, .tsv: return .table
        case .json, .yaml, .toml: return .tree
        case .env: return .keyValue
        case .plainText: return .prose
        }
    }

    /// Human-readable label for status bar display.
    public var displayName: String {
        switch self {
        case .markdown: return "Markdown"
        case .csv: return "CSV"
        case .tsv: return "TSV"
        case .json: return "JSON"
        case .yaml: return "YAML"
        case .toml: return "TOML"
        case .env: return "Environment"
        case .plainText: return "Plain Text"
        }
    }

    /// SF Symbol name for file tree icons.
    public var iconName: String {
        switch self {
        case .markdown: return "doc.richtext"
        case .csv, .tsv: return "tablecells"
        case .json: return "curlybraces"
        case .yaml, .toml: return "gearshape.2"
        case .env: return "lock.doc"
        case .plainText: return "doc.text"
        }
    }
}

/// How a file type should be rendered in the editor area.
public enum RenderingMode: String, Sendable {
    case splitPreview  // Markdown: source + live preview
    case table         // CSV/TSV: spreadsheet grid
    case tree          // JSON/YAML/TOML: collapsible tree
    case keyValue      // .env: key=value pairs
    case prose         // Plain text: clean writing surface
}
