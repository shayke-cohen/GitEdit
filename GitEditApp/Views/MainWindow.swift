import SwiftUI
import GitEditCore

/// Root view — three-column layout per design spec.
/// Col 1: Sidebar (file tree), Col 2: Editor area, Col 3: Git panel (contextual).
struct MainWindow: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            Group {
                if appState.workspaceURL == nil {
                    WelcomeView()
                        .testID("welcome-view")
                } else {
                    workspaceView
                }
            }

            // Error banner overlay
            if let error = appState.lastError {
                VStack {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(error)
                            .lineLimit(2)
                        Spacer()
                        Button {
                            appState.lastError = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .testID("error-banner")

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.25), value: appState.lastError)
            }

            // Quick Open overlay
            if appState.showQuickOpen {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture { appState.showQuickOpen = false }

                VStack {
                    QuickOpenView()
                        .testID("quick-open-panel")
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
                    .testID("sidebar")
                    .navigationSplitViewColumnWidth(min: 160, ideal: 220, max: 400)
            },
            detail: {
                HSplitView {
                    editorArea
                        .testID("editor-area")

                    if appState.showGitPanel {
                        GitPanelView()
                            .testID("git-panel")
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
            .testID("toggle-git-panel")
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
        .testID("git-branch-badge")
    }
}

/// Segmented control to switch between Source / Split / Rendered views.
struct ViewModePicker: View {
    @ObservedObject var tab: EditorTab

    var body: some View {
        Picker("View Mode", selection: $tab.viewMode) {
            Text("Source").tag(ViewMode.source as ViewMode)
            Text("Split").tag(ViewMode.split as ViewMode)
            Text("Rendered").tag(ViewMode.rendered as ViewMode)
        }
        .pickerStyle(.segmented)
        .testID("view-mode-picker")
        .frame(width: tab.fileType == FileType.markdown ? 200 : 160)
    }
}
