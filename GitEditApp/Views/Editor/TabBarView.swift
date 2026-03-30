import SwiftUI
import GitEditCore

/// Scrollable tab bar showing open files — macOS native style.
struct TabBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(appState.openTabs) { tab in
                    TabItem(tab: tab, isActive: tab.id == appState.activeTabID)
                }
            }
        }
        .frame(height: 32)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .testID("tab-bar")
    }
}

struct TabItem: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var tab: EditorTab
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            // File type icon
            Image(systemName: tab.fileType.iconName)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            // Modified indicator + filename
            HStack(spacing: 2) {
                if tab.isModified {
                    Circle()
                        .fill(.primary)
                        .frame(width: 5, height: 5)
                        .accessibilityLabel("Unsaved changes")
                }
                Text(tab.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
            }

            // Close button
            Button {
                appState.closeTab(id: tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close tab")
            .opacity(isActive ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isActive ? Color(nsColor: .controlBackgroundColor) : .clear)
        .testID("tab-\(tab.name)")
        .contentShape(Rectangle())
        .onTapGesture {
            appState.activeTabID = tab.id
        }
        .contextMenu {
            Button("Close") { appState.closeTab(id: tab.id) }
            Button("Close Others") {
                let id = tab.id
                appState.openTabs.removeAll { $0.id != id }
                appState.activeTabID = id
            }
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([tab.url])
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(tab.url.path, forType: .string)
            }
        }
    }
}
