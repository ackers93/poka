import Foundation
import UniformTypeIdentifiers

struct NoteMedia {
    let url: URL
    let isVideo: Bool

    // Only recognize standalone links into the vault's shared media directory.
    init?(markdown: String, note: URL, vault: URL) {
        let depth = note.deletingLastPathComponent().standardizedFileURL.pathComponents.count - vault.standardizedFileURL.pathComponents.count
        guard depth >= 0, markdown.hasSuffix(")"),
              let separator = markdown.range(of: "]("),
              markdown.hasPrefix("![") || markdown.hasPrefix("[") else { return nil }
        let prefix = String(repeating: "../", count: depth) + "media/"
        let target = markdown[separator.upperBound...].dropLast()
        guard target.hasPrefix(prefix),
              let name = target.dropFirst(prefix.count).removingPercentEncoding,
              !name.contains("/"), !name.contains("\0"),
              let type = UTType(filenameExtension: (name as NSString).pathExtension) else { return nil }
        isVideo = type.conforms(to: .movie)
        guard isVideo ? markdown.hasPrefix("[") : (type.conforms(to: .image) && markdown.hasPrefix("![")) else { return nil }
        url = vault.appendingPathComponent("media").appendingPathComponent(name)
    }

    static func markdown(for file: URL, note: URL, vault: URL) -> String {
        let name = file.lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
        let depth = note.deletingLastPathComponent().standardizedFileURL.pathComponents.count - vault.standardizedFileURL.pathComponents.count
        let path = String(repeating: "../", count: max(0, depth)) + "media/" + encoded
        let label = name.components(separatedBy: CharacterSet(charactersIn: "[]\\").union(.newlines)).joined(separator: " ")
        let image = UTType(filenameExtension: file.pathExtension)?.conforms(to: .image) == true
        return "\(image ? "!" : "")[\(label)](\(path))"
    }

    static func rebaseLinks(in markdown: String, from source: URL, to destination: URL, vault: URL) -> String {
        let newline = markdown.contains("\r\n") ? "\r\n" : "\n"
        var fenced = false
        var frontmatter = markdown.hasPrefix("---" + newline)
        return markdown.components(separatedBy: newline).enumerated().map { index, line in
            if frontmatter {
                if index > 0 && line == "---" { frontmatter = false }
                return line
            }
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { fenced.toggle() }
            guard !fenced, let media = NoteMedia(markdown: line, note: source, vault: vault),
                  let split = line.range(of: "](") else { return line }
            let newLink = Self.markdown(for: media.url, note: destination, vault: vault)
            guard let target = newLink.range(of: "](") else { return line }
            return String(line[..<split.upperBound]) + newLink[target.upperBound...]
        }.joined(separator: newline)
    }

    static func copy(from source: URL, suggestedName: String?, type: UTType?, vault: URL) throws -> URL {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        guard try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let fm = FileManager.default
        let folder = vault.appendingPathComponent("media", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var name = (suggestedName as NSString?)?.lastPathComponent ?? source.lastPathComponent
        if name.isEmpty || name.hasPrefix(".") { name = "Attachment" }
        let ext = (name as NSString).pathExtension
        if let type, UTType(filenameExtension: ext)?.conforms(to: type) != true,
           let suffix = type.preferredFilenameExtension {
            name += "." + suffix
        }
        guard let actual = UTType(filenameExtension: (name as NSString).pathExtension),
              actual.conforms(to: .image) || actual.conforms(to: .movie) else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "Choose an image or video file."])
        }
        let original = folder.appendingPathComponent(name)
        var destination = original
        var number = 2
        while true {
            do {
                try fm.copyItem(at: source, to: destination)
                return destination
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                destination = folder.appendingPathComponent("\(original.deletingPathExtension().lastPathComponent)-\(number)").appendingPathExtension(original.pathExtension)
                number += 1
            }
        }
    }
}

extension NoteMedia {
    static func importItem(_ provider: NSItemProvider, vault: URL,
                           completion: @escaping @MainActor @Sendable (Result<URL, Error>) -> Void) {
        let finish: @Sendable (Result<URL, Error>) -> Void = { result in
            Task { @MainActor in completion(result) }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                finish(Result {
                    guard let data, let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL else {
                        throw error ?? CocoaError(.fileReadUnknown)
                    }
                    return try copy(from: url, suggestedName: nil, type: nil, vault: vault)
                })
            }
        } else if let type = provider.registeredTypeIdentifiers.compactMap({ UTType($0) }).first(where: {
            $0.conforms(to: .image) || $0.conforms(to: .movie)
        }) {
            let name = provider.suggestedName
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                finish(Result {
                    guard let url else { throw error ?? CocoaError(.fileReadUnknown) }
                    return try copy(from: url, suggestedName: name, type: type, vault: vault)
                })
            }
        } else {
            finish(.failure(CocoaError(.fileReadUnknown)))
        }
    }
}
