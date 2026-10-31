import SwiftUI
import UniformTypeIdentifiers

struct VaultSetupView: View {
    @Environment(VaultService.self) private var vault
    @State private var showFolderPicker = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Open a vault")
                .font(.title.bold())

            Text("Poka works like Obsidian: choose a folder on your Mac or in iCloud Drive. Your notes stay as plain Markdown files you own.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

            if let path = vault.displayPath {
                Label(path, systemImage: "folder")
                    .font(.callout)
                    .lineLimit(3)
                    .frame(maxWidth: 520)
            }

            Button("Choose folder…") {
                #if os(macOS)
                pickFolderMac()
                #else
                showFolderPicker = true
                #endif
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if let error = vault.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                vault.adoptURL(url)
            case .failure(let error):
                vault.errorMessage = error.localizedDescription
            }
        }
        #endif
    }

    #if os(macOS)
    private func pickFolderMac() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Open Vault"
        panel.message = "Select the folder that contains (or will contain) your Markdown notes"
        if panel.runModal() == .OK, let url = panel.url {
            vault.adoptURL(url)
        }
    }
    #endif
}

#if os(macOS)
import AppKit
#endif
