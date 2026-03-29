import SwiftUI

/// Root view — three-column layout per design spec.
/// Col 1: Sidebar (file tree), Col 2: Editor area, Col 3: Git panel (contextual).
struct MainWindow: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            Group {
                if appState.workspaceURL == nil {
                    WelcomeView()
                } else {
                    workspaceView
                }
            }

            // Quick Open overlay
            if appState.showQuickOpen {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture { appState.showQuickOpen = false }

                VStack {
                    QuickOpenView()
                        .padding(.top, 80)
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private var workspaceView: some View {
        NavigationSplitView(
            columnVisibility: sidebarBinding,
            sidebar: {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 160, ideal: 220, max: 400)
            },
            detail: {
                HSplitView {
                    editorArea

                    if appState.showGitPanel {
                        GitPanelView()
                            .frame(minWidth: 240, idealWidth: 300, maxWidth: 480)
                    }
                }
            }
        )
        .toolbar {
            toolbarItems
        }
    }

    @ViewBuilder
    private var editorArea: some View {
        VStack(spacing: 0) {
            if !appState.openTabs.isEmpty {
                TabBarView()
            }

            EditorArea()

            StatusBarView()
        }
    }

    private var sidebarBinding: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { appState.showSidebar ? .all : .detailOnly },
            set: { appState.showSidebar = ($0 != .detailOnly) }
        )
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            if appState.isGitRepo {
                GitBranchBadge()
            }

            Spacer()

            // View mode picker for active tab
            if let tab = appState.activeTab {
                ViewModePicker(tab: tab)
            }

            Button {
                appState.showGitPanel.toggle()
            } label: {
                Label("Git Panel", systemImage: "arrow.triangle.branch")
            }
            .help("Toggle Git Panel (⇧⌘G)")
        }
    }
}

/// Placeholder for the git branch badge in the toolbar.
struct GitBranchBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.secondary)
            Text("main")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Segmented control to switch between Source / Split / Rendered views.
struct ViewModePicker: View {
    @ObservedObject var tab: EditorTab

    var body: some View {
        Picker("View Mode", selection: $tab.viewMode) {
            Text("Source").tag(ViewMode.source)
            if tab.fileType == .markdown {
                Text("Split").tag(ViewMode.split)
            }
            Text("Rendered").tag(ViewMode.rendered)
        }
        .pickerStyle(.segmented)
        .frame(width: tab.fileType == .markdown ? 200 : 140)
    }
}
