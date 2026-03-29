import SwiftUI

/// Empty state — shown when no folder is open.
/// Centered card with open folder CTA and recent folders.
struct WelcomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 32) {
            // Logo and tagline
            VStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)

                Text("GitEdit")
                    .font(.system(size: 36, weight: .bold, design: .default))

                Text("Every file rendered beautifully.\nGit history always one keystroke away.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Primary CTA
            Button(action: appState.showOpenPanel) {
                Label("Open Folder…", systemImage: "folder")
                    .font(.headline)
                    .frame(width: 200, height: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("o", modifiers: .command)

            // Drop zone hint
            Text("or drop a folder here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
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
}
