import SwiftUI

@main
struct GitEditApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(appState)
                .frame(minWidth: 960, minHeight: 600)
                .overlay {
                    if appState.showQuickOpen {
                        Color.black.opacity(0.2)
                            .ignoresSafeArea()
                            .onTapGesture { appState.showQuickOpen = false }
                        QuickOpenView()
                            .environmentObject(appState)
                            .padding(.top, 80)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    guard let provider = providers.first else { return false }
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                        guard let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil),
                              url.hasDirectoryPath else { return }
                        Task { @MainActor in
                            appState.openWorkspace(url: url)
                        }
                    }
                    return true
                }
                .onOpenURL { url in
                    appState.openWorkspace(url: url)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Folder...") {
                    appState.showOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button("Quick Open") {
                    appState.showQuickOpen = true
                }
                .keyboardShortcut("p", modifiers: .command)
            }

            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    appState.showSidebar.toggle()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Toggle Git Panel") {
                    appState.showGitPanel.toggle()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .textEditing) {
                Button("Toggle Diff") {
                    appState.showDiff.toggle()
                    if appState.showDiff {
                        appState.showGitPanel = true
                        appState.showHistory = false
                        appState.showBlame = false
                    }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("File History") {
                    appState.showHistory.toggle()
                    if appState.showHistory {
                        appState.showGitPanel = true
                        appState.showDiff = false
                        appState.showBlame = false
                    }
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Button("Toggle Blame") {
                    appState.showBlame.toggle()
                    if appState.showBlame {
                        appState.showGitPanel = true
                        appState.showDiff = false
                        appState.showHistory = false
                    }
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            }
        }
    }
}
