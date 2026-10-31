import Foundation

@MainActor
@Observable
final class NoteStore {
    private(set) var notes: [Note] = []
    var selectedNoteID: String?
    var editorText = ""
    private(set) var isLoading = false
    var errorMessage: String?

    private var vault: VaultService?
    private var saveTask: Task<Void, Never>?
    private var loadedFileURL: URL?

    var selectedNote: Note? {
        guard let id = selectedNoteID else { return nil }
        return notes.first { $0.id == id }
    }

    func bind(vault: VaultService) {
        self.vault = vault
    }

    func reload() {
        guard let root = vault?.startAccessingVault() else {
            notes = []
            selectedNoteID = nil
            editorText = ""
            return
        }
        defer { vault?.stopAccessingVault() }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            errorMessage = "Could not read notes in this folder."
            return
        }

        var found: [Note] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            let modified = values?.contentModificationDate ?? .distantPast
            let name = fileURL.deletingPathExtension().lastPathComponent
            found.append(Note(title: name, fileURL: fileURL, modifiedAt: modified))
        }
        found.sort { $0.modifiedAt > $1.modifiedAt }
        notes = found

        if let selected = selectedNoteID, !notes.contains(where: { $0.id == selected }) {
            selectedNoteID = notes.first?.id
        } else if selectedNoteID == nil {
            selectedNoteID = notes.first?.id
        }
        loadSelectedNoteContent()
    }

    func select(_ note: Note) {
        flushSave()
        selectedNoteID = note.id
        loadSelectedNoteContent()
    }

    func createNote() {
        guard let root = vault?.startAccessingVault() else { return }
        defer { vault?.stopAccessingVault() }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let base = "Note \(formatter.string(from: Date()))"
        var url = root.appendingPathComponent("\(base).md", isDirectory: false)
        var index = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = root.appendingPathComponent("\(base) \(index).md", isDirectory: false)
            index += 1
        }

        let initial = "# \(base)\n\n"
        do {
            try initial.write(to: url, atomically: true, encoding: .utf8)
            reload()
            if let created = notes.first(where: { $0.fileURL == url }) {
                select(created)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSelectedNote() {
        guard let note = selectedNote else { return }
        guard vault?.startAccessingVault() != nil else { return }
        defer { vault?.stopAccessingVault() }

        do {
            try FileManager.default.removeItem(at: note.fileURL)
            selectedNoteID = nil
            editorText = ""
            loadedFileURL = nil
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateEditorText(_ text: String) {
        editorText = text
        scheduleSave()
    }

    private func loadSelectedNoteContent() {
        guard let note = selectedNote else {
            editorText = ""
            loadedFileURL = nil
            return
        }
        guard vault?.startAccessingVault() != nil else { return }
        defer { vault?.stopAccessingVault() }

        do {
            editorText = try String(contentsOf: note.fileURL, encoding: .utf8)
            loadedFileURL = note.fileURL
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await saveEditorIfNeeded()
        }
    }

    private func flushSave() {
        saveTask?.cancel()
        Task { await saveEditorIfNeeded() }
    }

    private func saveEditorIfNeeded() async {
        guard let fileURL = loadedFileURL, let note = selectedNote else { return }
        guard vault?.startAccessingVault() != nil else { return }
        defer { vault?.stopAccessingVault() }

        do {
            try editorText.write(to: fileURL, atomically: true, encoding: .utf8)
            let filename = fileURL.deletingPathExtension().lastPathComponent
            let title = Note.title(from: editorText, fallback: filename)
            if let idx = notes.firstIndex(where: { $0.id == note.id }) {
                notes[idx].title = title
                notes[idx].modifiedAt = Date()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
