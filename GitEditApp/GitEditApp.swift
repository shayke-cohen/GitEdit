import SwiftUI
#if DEBUG
import AppXray
#endif

@main
struct GitEditApp: App {
    @StateObject private var appState = AppState()

    init() {
        #if DEBUG
        AppXray.shared.start(appName: "GitEdit")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(appState)
                .frame(minWidth: 960, minHeight: 600)
                .onAppear { Self.registerAppXray(appState) }
                .onAppear { Self.handleLaunchArgs(appState) }
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

    @MainActor
    private static func registerAppXray(_ appState: AppState) {
        #if DEBUG
        AppXray.shared.registerObservableObject(appState, name: "appState", setters: [
            "showSidebar": { [weak appState] val in
                DispatchQueue.main.async { appState?.showSidebar = val as! Bool }
            },
            "showGitPanel": { [weak appState] val in
                DispatchQueue.main.async { appState?.showGitPanel = val as! Bool }
            },
            "showQuickOpen": { [weak appState] val in
                DispatchQueue.main.async { appState?.showQuickOpen = val as! Bool }
            },
            "showDiff": { [weak appState] val in
                DispatchQueue.main.async { appState?.showDiff = val as! Bool }
            },
            "showHistory": { [weak appState] val in
                DispatchQueue.main.async { appState?.showHistory = val as! Bool }
            },
            "showBlame": { [weak appState] val in
                DispatchQueue.main.async { appState?.showBlame = val as! Bool }
            },
            "lastError": { [weak appState] val in
                DispatchQueue.main.async { appState?.lastError = val as? String }
            },
            "workspaceURL": { [weak appState] val in
                DispatchQueue.main.async {
                    if let path = val as? String {
                        appState?.openWorkspace(url: URL(fileURLWithPath: path))
                    }
                }
            },
        ])
        #endif
    }

    @MainActor
    private static func handleLaunchArgs(_ appState: AppState) {
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "--open-path"), idx + 1 < args.count {
            let path = args[idx + 1]
            let url = URL(fileURLWithPath: path)
            appState.openWorkspace(url: url)
        }
    }
}
