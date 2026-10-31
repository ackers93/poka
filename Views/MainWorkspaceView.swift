import SwiftUI

struct MainWorkspaceView: View {
    @Environment(VaultService.self) private var vault
    @Bindable var noteStore: NoteStore

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $noteStore.selectedNoteID) {
                if !noteStore.folders.isEmpty {
                    Section("Folders") {
                        ForEach(noteStore.folders) { folder in
                            Label(folder.relativePath, systemImage: "folder")
                        }
                    }
                }

                ForEach(noteStore.notes) { note in
                    Text(note.title)
                        .tag(note.id)
                }
            }
            .navigationTitle(vaultTitle)
            .contextMenu {
                Button {
                    noteStore.createNote()
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
                Button {
                    isCreatingFolder = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        noteStore.createNote()
                    } label: {
                        Label("New note", systemImage: "square.and.pencil")
                    }
                    Button {
                        isCreatingFolder = true
                    } label: {
                        Label("New folder", systemImage: "folder.badge.plus")
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
            .alert("New Folder", isPresented: $isCreatingFolder) {
                TextField("Folder name", text: $newFolderName)
                Button("Create") {
                    noteStore.createFolder(named: newFolderName)
                    newFolderName = ""
                }
                Button("Cancel", role: .cancel) {
                    newFolderName = ""
                }
            } message: {
                Text("The folder will be created at the top level of this vault.")
            }
        } detail: {
            if noteStore.selectedNote != nil {
                NoteEditorView(noteStore: noteStore)
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
