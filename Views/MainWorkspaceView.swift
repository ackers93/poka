import SwiftUI
import UniformTypeIdentifiers

struct MainWorkspaceView: View {
    @Environment(VaultService.self) private var vault
    @Bindable var noteStore: NoteStore

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var selectedFolderURL: URL?
    @State private var folderToRename: NoteFolder?
    @State private var renamedFolderName = ""

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $noteStore.selectedNoteID) {
                if !noteStore.folders.isEmpty {
                    Section("Folders") {
                        ForEach(noteStore.folders) { folder in
                            Label(folder.relativePath, systemImage: "folder")
                                .contentShape(Rectangle())
                                .background(selectedFolderURL == folder.url ? Color.accentColor.opacity(0.16) : .clear)
                                .onTapGesture {
                                    selectedFolderURL = folder.url
                                    noteStore.selectedNoteID = nil
                                }
                                .onDrop(of: [.text], delegate: FolderDropDelegate(folder: folder, noteStore: noteStore))
                                .contextMenu {
                                    Button {
                                        noteStore.createNote(in: folder.url)
                                    } label: {
                                        Label("New Note", systemImage: "square.and.pencil")
                                    }
                                    Button {
                                        selectedFolderURL = folder.url
                                        newFolderName = ""
                                        isCreatingFolder = true
                                    } label: {
                                        Label("New Folder", systemImage: "folder.badge.plus")
                                    }
                                    Divider()
                                    Button("Rename Folder") {
                                        folderToRename = folder
                                        renamedFolderName = folder.name
                                    }
                                }
                        }
                    }
                }

                ForEach(noteStore.notes) { note in
                    Text(note.title)
                        .tag(note.id)
                        .onDrag {
                            NSItemProvider(object: note.id as NSString)
                        }
                }
            }
            .navigationTitle(vaultTitle)
            .contextMenu {
                Button {
                    noteStore.createNote(in: selectedFolderURL)
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
                Button {
                    newFolderName = ""
                    isCreatingFolder = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        noteStore.createNote(in: selectedFolderURL)
                    } label: {
                        Label("New note", systemImage: "square.and.pencil")
                    }
                    Button {
                        newFolderName = ""
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
                    noteStore.createFolder(named: newFolderName, in: selectedFolderURL)
                    newFolderName = ""
                }
                Button("Cancel", role: .cancel) {
                    newFolderName = ""
                }
            } message: {
                Text("The folder will be created in the selected folder.")
            }
            .alert("Rename Folder", isPresented: Binding(
                get: { folderToRename != nil },
                set: { if !$0 { folderToRename = nil } }
            )) {
                TextField("Folder name", text: $renamedFolderName)
                Button("Rename") {
                    if let folder = folderToRename {
                        noteStore.renameFolder(at: folder.url, to: renamedFolderName)
                    }
                    folderToRename = nil
                }
                Button("Cancel", role: .cancel) {
                    folderToRename = nil
                }
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
            noteStore.createNote(in: selectedFolderURL)
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

private struct FolderDropDelegate: DropDelegate {
    let folder: NoteFolder
    let noteStore: NoteStore

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { identifier, _ in
            guard let identifier = identifier as? NSString else { return }
            let noteID = identifier as String
            Task { @MainActor in
                noteStore.moveNote(id: noteID, to: folder.url)
            }
        }
        return true
    }
}

#if os(macOS)
import AppKit
#endif
