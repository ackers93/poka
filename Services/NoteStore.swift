import Foundation

@MainActor
@Observable
final class NoteStore {
    private(set) var notes: [Note] = []
    private(set) var folders: [NoteFolder] = []
    var selectedNoteID: String?
    var editorBlocks: [Block] = [Block()]
    private(set) var isLoading = false
    var errorMessage: String?

    private var vault: VaultService?
    private var saveTask: Task<Void, Never>?
    private var loadedFileURL: URL?
    private var loadedFrontmatter: NoteFrontmatter = .empty

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
            folders = []
            selectedNoteID = nil
            editorBlocks = [Block()]
            return
        }
        defer { vault?.stopAccessingVault() }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            errorMessage = "Could not read notes in this folder."
            return
        }

        var found: [Note] = []
        var foundFolders: [NoteFolder] = []
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            if values?.isDirectory == true {
                let relativePath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
                foundFolders.append(NoteFolder(url: fileURL, relativePath: relativePath))
                continue
            }
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            let modified = values?.contentModificationDate ?? .distantPast
            let name = fileURL.deletingPathExtension().lastPathComponent
            let document = (try? String(contentsOf: fileURL, encoding: .utf8)).map(MarkdownDocument.parse)
            let title = document?.frontmatter.name ?? Note.title(from: document?.body ?? "", fallback: name)
            found.append(Note(title: title, fileURL: fileURL, modifiedAt: modified, frontmatter: document?.frontmatter ?? .empty))
        }
        found.sort { $0.modifiedAt > $1.modifiedAt }
        notes = found
        folders = foundFolders.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }

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

    func createNote(in folder: URL? = nil) {
        guard let root = vault?.startAccessingVault() else { return }
        defer { vault?.stopAccessingVault() }

        let parent = folder ?? root

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let base = "Note \(formatter.string(from: Date()))"
        var url = parent.appendingPathComponent("\(base).md", isDirectory: false)
        var index = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = parent.appendingPathComponent("\(base) \(index).md", isDirectory: false)
            index += 1
        }

        let date = Self.metadataDate()
        let frontmatter = NoteFrontmatter.empty.updating(name: base, created: date, updated: date)
        let initial = frontmatter.rendered(with: MarkdownCodec.serialize([Block(kind: .heading1, text: base)]))
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

    func createFolder(named name: String, in folder: URL? = nil) {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return }
        guard !cleanedName.contains("/"), !cleanedName.contains(":") else {
            errorMessage = "Folder names cannot contain / or :."
            return
        }
        guard let root = vault?.startAccessingVault() else { return }
        defer { vault?.stopAccessingVault() }

        let parent = folder ?? root
        let folderURL = parent.appendingPathComponent(cleanedName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveNote(id: String, to folder: URL) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        guard vault?.startAccessingVault() != nil else { return }
        defer { vault?.stopAccessingVault() }

        let destination = folder.appendingPathComponent(note.fileURL.lastPathComponent, isDirectory: false)
        guard destination != note.fileURL else { return }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            errorMessage = "A note named \(note.fileURL.lastPathComponent) already exists in this folder."
            return
        }

        do {
            try FileManager.default.moveItem(at: note.fileURL, to: destination)
            reload()
            if let moved = notes.first(where: { $0.fileURL == destination }) {
                select(moved)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameFolder(at folder: URL, to name: String) {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return }
        guard !cleanedName.contains("/"), !cleanedName.contains(":") else {
            errorMessage = "Folder names cannot contain / or :."
            return
        }
        guard vault?.startAccessingVault() != nil else { return }
        defer { vault?.stopAccessingVault() }

        let destination = folder.deletingLastPathComponent().appendingPathComponent(cleanedName, isDirectory: true)
        guard destination != folder else { return }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            errorMessage = "A folder named \(cleanedName) already exists here."
            return
        }

        do {
            try FileManager.default.moveItem(at: folder, to: destination)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameNote(_ note: Note, to name: String) {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return }
        guard !cleanedName.contains("/"), !cleanedName.contains(":") else {
            errorMessage = "Note names cannot contain / or :."
            return
        }
        guard vault?.startAccessingVault() != nil else { return }
        defer { vault?.stopAccessingVault() }

        let destination = note.fileURL
            .deletingLastPathComponent()
            .appendingPathComponent(cleanedName)
            .appendingPathExtension("md")
        guard destination == note.fileURL || !FileManager.default.fileExists(atPath: destination.path) else {
            errorMessage = "A note named \(cleanedName) already exists in this folder."
            return
        }

        do {
            saveTask?.cancel()
            let source = try String(contentsOf: note.fileURL, encoding: .utf8)
            let document = MarkdownDocument.parse(source)
            let updatedBody = Self.updatingDocumentTitle(in: document.body, to: cleanedName)
            let updatedFrontmatter = document.frontmatter.updating(name: cleanedName, updated: Self.metadataDate())
            try updatedFrontmatter.rendered(with: updatedBody).write(to: note.fileURL, atomically: true, encoding: .utf8)
            if destination != note.fileURL {
                try FileManager.default.moveItem(at: note.fileURL, to: destination)
            }
            selectedNoteID = nil
            reload()
            if let renamed = notes.first(where: { $0.fileURL == destination }) {
                select(renamed)
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
            editorBlocks = [Block()]
            loadedFileURL = nil
            loadedFrontmatter = .empty
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func commitEditorBlocks(_ blocks: [Block]) {
        editorBlocks = blocks
        scheduleSave()
    }

    private func loadSelectedNoteContent() {
        guard let note = selectedNote else {
            editorBlocks = [Block()]
            loadedFileURL = nil
            loadedFrontmatter = .empty
            return
        }
        guard vault?.startAccessingVault() != nil else { return }
        defer { vault?.stopAccessingVault() }

        do {
            let text = try String(contentsOf: note.fileURL, encoding: .utf8)
            let document = MarkdownDocument.parse(text)
            editorBlocks = MarkdownCodec.parse(document.body)
            loadedFileURL = note.fileURL
            loadedFrontmatter = document.frontmatter
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

        let markdown = MarkdownCodec.serialize(editorBlocks)
        let frontmatter = loadedFrontmatter.updating(updated: Self.metadataDate())
        do {
            try frontmatter.rendered(with: markdown).write(to: fileURL, atomically: true, encoding: .utf8)
            let filename = fileURL.deletingPathExtension().lastPathComponent
            let title = frontmatter.name ?? Note.title(from: markdown, fallback: filename)
            if let idx = notes.firstIndex(where: { $0.id == note.id }) {
                notes[idx].title = title
                notes[idx].modifiedAt = Date()
                notes[idx].frontmatter = frontmatter
            }
            loadedFrontmatter = frontmatter
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func metadataDate() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func updatingDocumentTitle(in body: String, to title: String) -> String {
        var lines = body.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        if let index = lines.firstIndex(where: { $0.hasPrefix("# ") }) {
            lines[index] = "# \(title)"
        } else {
            lines.insert("# \(title)", at: 0)
        }
        return lines.joined(separator: "\n")
    }
}
