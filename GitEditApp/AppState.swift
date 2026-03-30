import SwiftUI
import Combine
import GitEditCore

/// Global application state — owns the workspace, open tabs, and UI toggles.
@MainActor
final class AppState: ObservableObject {

    // MARK: - Workspace

    @Published var workspaceURL: URL?
    @Published var fileTree: [WorkspaceItem] = []
    @Published var isGitRepo: Bool = false

    // MARK: - Editor tabs

    @Published var openTabs: [EditorTab] = []
    @Published var activeTabID: UUID?

    var activeTab: EditorTab? {
        guard let id = activeTabID else { return nil }
        return openTabs.first { $0.id == id }
    }

    // MARK: - Error handling

    @Published var errorMessage: String?

    // MARK: - UI state

    @Published var showSidebar: Bool = true
    @Published var showGitPanel: Bool = false
    @Published var showQuickOpen: Bool = false
    @Published var showDiff: Bool = false
    @Published var showHistory: Bool = false
    @Published var showBlame: Bool = false
    @Published var lastError: String?

    // MARK: - File operations (DES-003)

    @Published var renameTarget: WorkspaceItem?
    @Published var deleteTarget: WorkspaceItem?

    // MARK: - Recent workspaces (persisted in UserDefaults)

    @Published var recentWorkspaces: [URL] = {
        let bookmarks = UserDefaults.standard.array(forKey: "recentWorkspaces") as? [Data] ?? []
        return bookmarks.compactMap { data in
            var stale = false
            return try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale)
        }
    }()

    // MARK: - Services

    let workspaceService = WorkspaceService()
    private var fileWatcher: FileWatcher?

    // MARK: - Workspace management

    func openWorkspace(url: URL) {
        workspaceURL = url
        isGitRepo = workspaceService.isInGitRepo(url: url)

        do {
            fileTree = try workspaceService.scanDirectory(at: url)
        } catch {
            fileTree = []
        }

        // Track recent workspaces
        addToRecent(url)

        // Start watching for file changes
        fileWatcher?.stop()
        fileWatcher = FileWatcher(path: url.path) { [weak self] changedPaths in
            Task { @MainActor in
                self?.handleFileChanges(changedPaths)
            }
        }
        fileWatcher?.start()
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to open in GitEdit"

        if panel.runModal() == .OK, let url = panel.url {
            openWorkspace(url: url)
        }
    }

    // MARK: - Tab management

    func openFile(url: URL) {
        // If already open, just switch to it
        if let existing = openTabs.first(where: { $0.url == url }) {
            activeTabID = existing.id
            return
        }

        // Check file size — warn over 10MB
        let size = (try? workspaceService.fileSize(at: url)) ?? 0
        let content: String
        do {
            content = try workspaceService.readFile(at: url)
        } catch {
            content = "Error reading file: \(error.localizedDescription)"
        }

        let tab = EditorTab(url: url, content: content)

        // Large file: force raw mode
        if size > 10_000_000 {
            tab.viewMode = .source
        }

        openTabs.append(tab)
        activeTabID = tab.id
    }

    func closeTab(id: UUID) {
        openTabs.removeAll { $0.id == id }
        if activeTabID == id {
            activeTabID = openTabs.last?.id
        }
    }

    func saveActiveTab() {
        guard let tab = activeTab else { return }
        do {
            try workspaceService.writeFile(content: tab.content, to: tab.url)
            tab.isModified = false
        } catch {
            lastError = "Save failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Recent workspace tracking

    private func addToRecent(_ url: URL) {
        recentWorkspaces.removeAll { $0 == url }
        recentWorkspaces.insert(url, at: 0)
        if recentWorkspaces.count > 5 { recentWorkspaces = Array(recentWorkspaces.prefix(5)) }

        let bookmarks = recentWorkspaces.compactMap { try? $0.bookmarkData(options: .withSecurityScope) }
        UserDefaults.standard.set(bookmarks, forKey: "recentWorkspaces")
    }

    // MARK: - File operations

    func renameFile(_ item: WorkspaceItem, to newName: String) {
        let newURL = item.url.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: item.url, to: newURL)
            // Close any open tab for the old URL
            openTabs.removeAll { $0.url == item.url }
            refreshFileTree()
        } catch {
            lastError = "Rename failed: \(error.localizedDescription)"
        }
    }

    func deleteFile(_ item: WorkspaceItem) {
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            openTabs.removeAll { $0.url == item.url }
            if let id = activeTabID, !openTabs.contains(where: { $0.id == id }) {
                activeTabID = openTabs.last?.id
            }
            refreshFileTree()
        } catch {
            lastError = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func refreshFileTree() {
        guard let root = workspaceURL else { return }
        do { fileTree = try workspaceService.scanDirectory(at: root) } catch {}
    }

    // MARK: - File watching

    private func handleFileChanges(_ paths: [String]) {
        // Refresh file tree on external changes
        guard let root = workspaceURL else { return }
        do {
            fileTree = try workspaceService.scanDirectory(at: root)
        } catch {
            // Silently ignore — tree stays as-is
        }
    }
}
