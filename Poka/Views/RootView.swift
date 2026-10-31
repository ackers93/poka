import SwiftUI

struct RootView: View {
    @Environment(VaultService.self) private var vault
    @State private var noteStore = NoteStore()

    var body: some View {
        Group {
            if !vault.hasVault {
                VaultSetupView()
            } else {
                MainWorkspaceView(noteStore: noteStore)
            }
        }
        .onChange(of: vault.hasVault) { _, hasVault in
            if hasVault { noteStore.reload() }
        }
        .onAppear {
            noteStore.bind(vault: vault)
            if vault.hasVault { noteStore.reload() }
        }
    }
}
