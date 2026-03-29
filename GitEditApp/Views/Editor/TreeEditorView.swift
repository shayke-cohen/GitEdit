import SwiftUI
import GitEditCore

/// Collapsible tree view for JSON, YAML, and TOML files.
/// Shows type-colored values, expand/collapse all, raw toggle.
struct TreeEditorView: View {
    @ObservedObject var tab: EditorTab
    @State private var rootNode: TreeNode?
    @State private var parseError: String?
    @State private var showRaw = false

    var body: some View {
        VStack(spacing: 0) {
            treeToolbar

            Divider()

            if let error = parseError {
                errorBanner(error)
            }

            if showRaw || parseError != nil {
                PlainTextEditor(tab: tab, showLineNumbers: true, monoFont: true)
            } else if let node = rootNode {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        TreeNodeRow(node: node, depth: 0)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ProgressView("Parsing…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { parseContent() }
        .onChange(of: tab.content) { _, _ in parseContent() }
    }

    private var treeToolbar: some View {
        HStack {
            Text(tab.fileType.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if rootNode != nil && parseError == nil {
                Button("Expand All") { rootNode?.expandAll() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Collapse All") { rootNode?.collapseAll() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Button(showRaw ? "Tree" : "Raw") {
                showRaw.toggle()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func errorBanner(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Parse error — \(error)")
                .font(.caption)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.orange.opacity(0.1))
    }

    private func parseContent() {
        do {
            let data = Data(tab.content.utf8)
            let json = try JSONSerialization.jsonObject(with: data)
            rootNode = TreeNode.from(key: "root", value: json)
            parseError = nil
        } catch {
            parseError = error.localizedDescription
            rootNode = nil
        }
    }
}

// MARK: - Tree node model

class TreeNode: Identifiable, ObservableObject {
    let id = UUID()
    let key: String
    let valueType: TreeValueType
    let displayValue: String?
    @Published var children: [TreeNode]
    @Published var isExpanded: Bool

    init(key: String, valueType: TreeValueType, displayValue: String? = nil, children: [TreeNode] = []) {
        self.key = key
        self.valueType = valueType
        self.displayValue = displayValue
        self.children = children
        self.isExpanded = children.isEmpty ? false : true
    }

    func expandAll() {
        isExpanded = true
        children.forEach { $0.expandAll() }
    }

    func collapseAll() {
        isExpanded = false
        children.forEach { $0.collapseAll() }
    }

    static func from(key: String, value: Any) -> TreeNode {
        switch value {
        case let dict as [String: Any]:
            let children = dict.sorted { $0.key < $1.key }.map { from(key: $0.key, value: $0.value) }
            return TreeNode(key: key, valueType: .object, displayValue: "{\(children.count)}", children: children)
        case let array as [Any]:
            let children = array.enumerated().map { from(key: "[\($0.offset)]", value: $0.element) }
            return TreeNode(key: key, valueType: .array, displayValue: "[\(children.count)]", children: children)
        case let str as String:
            return TreeNode(key: key, valueType: .string, displayValue: "\"\(str)\"")
        case let num as NSNumber:
            if num === kCFBooleanTrue || num === kCFBooleanFalse {
                return TreeNode(key: key, valueType: .boolean, displayValue: num.boolValue ? "true" : "false")
            }
            return TreeNode(key: key, valueType: .number, displayValue: "\(num)")
        case is NSNull:
            return TreeNode(key: key, valueType: .null, displayValue: "null")
        default:
            return TreeNode(key: key, valueType: .string, displayValue: "\(value)")
        }
    }
}

enum TreeValueType: String {
    case object = "Object"
    case array = "Array"
    case string = "Str"
    case number = "Num"
    case boolean = "Bool"
    case null = "Null"

    var color: Color {
        switch self {
        case .string: return .blue
        case .number: return .green
        case .boolean: return .orange
        case .null: return .gray
        case .object, .array: return .secondary
        }
    }
}

// MARK: - Tree node row view

struct TreeNodeRow: View {
    @ObservedObject var node: TreeNode
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                // Indentation
                Spacer()
                    .frame(width: CGFloat(depth) * 16)

                // Expand/collapse chevron
                if !node.children.isEmpty {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            node.isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 12)
                }

                // Key name
                Text(node.key)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.primary)

                // Type badge
                Text(node.valueType.rawValue)
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(node.valueType.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(node.valueType.color)

                // Value (for leaf nodes)
                if let value = node.displayValue, node.children.isEmpty {
                    Text(value)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(node.valueType.color)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())

            // Children
            if node.isExpanded {
                ForEach(node.children) { child in
                    TreeNodeRow(node: child, depth: depth + 1)
                }
            }
        }
    }
}
