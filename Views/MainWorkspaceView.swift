import SwiftUI

struct MainWorkspaceView: View {
    @Environment(VaultService.self) private var vault
    @Bindable var noteStore: NoteStore

    @State private var showPreview = true
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $noteStore.selectedNoteID) {
                ForEach(noteStore.notes) { note in
                    Text(note.title)
                        .tag(note.id)
                }
            }
            .navigationTitle(vaultTitle)
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        noteStore.createNote()
                    } label: {
                        Label("New note", systemImage: "square.and.pencil")
                    }
                    Button {
                        noteStore.reload()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) {
                        noteStore.deleteSelectedNote()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(noteStore.selectedNote == nil)
                }
            }
            .onChange(of: noteStore.selectedNoteID) { _, newID in
                guard let id = newID, let note = noteStore.notes.first(where: { $0.id == id }) else { return }
                noteStore.select(note)
            }
        } detail: {
            if noteStore.selectedNote != nil {
                NoteEditorView(noteStore: noteStore, showPreview: $showPreview)
            } else {
                ContentUnavailableView(
                    "No note selected",
                    systemImage: "doc.text",
                    description: Text("Create a note or pick one from the sidebar.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    if let path = vault.displayPath {
                        Text(path)
                            .font(.caption)
                    }
                    Button("Open different folder…") {
                        vault.clearVault()
                    }
                    Divider()
                    Button("Reveal vault in Finder") {
                        revealVaultInFinder()
                    }
                } label: {
                    Label("Vault", systemImage: "folder")
                }
            }
            ToolbarItem(placement: .automatic) {
                Toggle(isOn: $showPreview) {
                    Label("Preview", systemImage: "eye")
                }
            }
        }
        .overlay {
            if noteStore.isLoading {
                ProgressView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pokaCreateNote)) { _ in
            noteStore.createNote()
        }
    }

    private var vaultTitle: String {
        guard let path = vault.displayPath else { return "Notes" }
        return (path as NSString).lastPathComponent
    }

    #if os(macOS)
    private func revealVaultInFinder() {
        guard let url = vault.startAccessingVault() else { return }
        defer { vault.stopAccessingVault() }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    #else
    private func revealVaultInFinder() {}
    #endif
}

#if os(macOS)
import AppKit
#endif
