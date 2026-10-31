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
                Label(vaultTitle, systemImage: "externaldrive")
                    .contentShape(Rectangle())
                    .background(selectedFolderURL == nil ? Color.accentColor.opacity(0.16) : .clear)
                    .onTapGesture {
                        selectedFolderURL = nil
                        noteStore.selectedNoteID = nil
                    }

                ForEach(folderTree) { node in
                    FolderTreeRow(
                        node: node,
                        noteStore: noteStore,
                        selectedFolderURL: $selectedFolderURL,
                        isCreatingFolder: $isCreatingFolder,
                        newFolderName: $newFolderName,
                        folderToRename: $folderToRename,
                        renamedFolderName: $renamedFolderName
                    )
                }
                ForEach(rootNotes) { note in
                    NoteSidebarRow(
                        note: note,
                        noteStore: noteStore,
                        selectedFolderURL: $selectedFolderURL
                    )
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

    private var folderTree: [FolderTreeNode] {
        folders(in: vault.rootURL)
    }

    private var rootNotes: [Note] {
        guard let root = vault.rootURL else { return noteStore.notes }
        return noteStore.notes.filter { $0.fileURL.deletingLastPathComponent() == root }
    }

    private func folders(in parent: URL?) -> [FolderTreeNode] {
        noteStore.folders
            .filter { $0.url.deletingLastPathComponent() == parent }
            .map { folder in
                FolderTreeNode(
                    folder: folder,
                    children: folders(in: folder.url),
                    notes: noteStore.notes.filter { $0.fileURL.deletingLastPathComponent() == folder.url }
                )
            }
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

private struct FolderTreeNode: Identifiable {
    let folder: NoteFolder
    let children: [FolderTreeNode]
    let notes: [Note]

    var id: String { folder.id }
}

private struct FolderTreeRow: View {
    let node: FolderTreeNode
    let noteStore: NoteStore
    @Binding var selectedFolderURL: URL?
    @Binding var isCreatingFolder: Bool
    @Binding var newFolderName: String
    @Binding var folderToRename: NoteFolder?
    @Binding var renamedFolderName: String

    var body: some View {
        if node.children.isEmpty && node.notes.isEmpty {
            folderLabel
        } else {
            DisclosureGroup {
                ForEach(node.children) { child in
                    FolderTreeRow(
                        node: child,
                        noteStore: noteStore,
                        selectedFolderURL: $selectedFolderURL,
                        isCreatingFolder: $isCreatingFolder,
                        newFolderName: $newFolderName,
                        folderToRename: $folderToRename,
                        renamedFolderName: $renamedFolderName
                    )
                }
                ForEach(node.notes) { note in
                    NoteSidebarRow(
                        note: note,
                        noteStore: noteStore,
                        selectedFolderURL: $selectedFolderURL
                    )
                }
            } label: {
                folderLabel
            }
        }
    }

    private var folderLabel: some View {
        Label(node.folder.name, systemImage: "folder")
            .contentShape(Rectangle())
            .background(selectedFolderURL == node.folder.url ? Color.accentColor.opacity(0.16) : .clear)
            .onTapGesture {
                selectedFolderURL = node.folder.url
                noteStore.selectedNoteID = nil
            }
            .onDrop(of: [.text], delegate: FolderDropDelegate(folder: node.folder, noteStore: noteStore))
            .contextMenu {
                Button {
                    noteStore.createNote(in: node.folder.url)
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
                Button {
                    selectedFolderURL = node.folder.url
                    newFolderName = ""
                    isCreatingFolder = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                Divider()
                Button("Rename Folder") {
                    folderToRename = node.folder
                    renamedFolderName = node.folder.name
                }
            }
    }
}

private struct NoteSidebarRow: View {
    let note: Note
    let noteStore: NoteStore
    @Binding var selectedFolderURL: URL?

    var body: some View {
        Text(note.title)
            .tag(note.id)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedFolderURL = note.fileURL.deletingLastPathComponent()
                noteStore.select(note)
            }
            .onDrag {
                NSItemProvider(object: note.id as NSString)
            }
    }
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
