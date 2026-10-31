import Foundation

struct Note: Identifiable, Hashable, Sendable {
    var title: String
    var fileURL: URL
    var modifiedAt: Date
    var frontmatter: NoteFrontmatter

    /// Stable identity across folder scans (same path → same note).
    var id: String { fileURL.path }

    init(title: String, fileURL: URL, modifiedAt: Date, frontmatter: NoteFrontmatter = .empty) {
        self.title = title
        self.fileURL = fileURL
        self.modifiedAt = modifiedAt
        self.frontmatter = frontmatter
    }

    static func title(from markdown: String, fallback filename: String) -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstLine = trimmed.split(separator: "\n", maxSplits: 1).first else {
            return filename
        }
        var line = String(firstLine)
        if line.hasPrefix("# ") {
            line = String(line.dropFirst(2))
        }
        let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? filename : cleaned
    }
}

struct NoteFolder: Identifiable, Hashable, Sendable {
    var url: URL
    var relativePath: String

    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var depth: Int { max(0, relativePath.split(separator: "/").count - 1) }
}

struct NoteFrontmatter: Hashable, Sendable {
    private(set) var lines: [String]
    private(set) var hasFrontmatter: Bool

    var name: String? { value(for: "name") }
    var icon: String? { value(for: "icon") }
    var tags: [String] {
        guard let raw = value(for: "tags") else { return [] }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return [] }
        return trimmed.dropFirst().dropLast().split(separator: ",").map {
            Self.unquote(String($0).trimmingCharacters(in: .whitespaces))
        }
    }
    var created: String? { value(for: "created") }
    var updated: String? { value(for: "updated") }

    static let empty = NoteFrontmatter(lines: [], hasFrontmatter: false)

    func updating(name: String? = nil, created: String? = nil, updated: String? = nil) -> NoteFrontmatter {
        var copy = self
        if let name { copy.set("name", value: Self.quote(name)) }
        if let created { copy.set("created", value: created) }
        if let updated { copy.set("updated", value: updated) }
        return copy
    }

    func rendered(with body: String) -> String {
        let normalizedBody = body.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let bodyWithNewline = normalizedBody.hasSuffix("\n") ? normalizedBody : normalizedBody + "\n"
        guard hasFrontmatter || !lines.isEmpty else { return bodyWithNewline }
        return "---\n" + lines.joined(separator: "\n") + "\n---\n" + bodyWithNewline
    }

    private func value(for key: String) -> String? {
        guard let line = lines.first(where: { $0.hasPrefix("\(key):") }) else { return nil }
        return Self.unquote(String(line.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces))
    }

    private mutating func set(_ key: String, value: String) {
        hasFrontmatter = true
        let replacement = "\(key): \(value)"
        if let index = lines.firstIndex(where: { $0.hasPrefix("\(key):") }) {
            lines[index] = replacement
        } else {
            lines.append(replacement)
        }
    }

    private static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func unquote(_ value: String) -> String {
        guard value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        return String(value.dropFirst().dropLast())
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}

struct MarkdownDocument: Sendable {
    var frontmatter: NoteFrontmatter
    var body: String

    static func parse(_ markdown: String) -> MarkdownDocument {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard normalized.hasPrefix("---\n"),
              let end = normalized.range(of: "\n---\n", range: normalized.index(normalized.startIndex, offsetBy: 4)..<normalized.endIndex)
        else {
            return MarkdownDocument(frontmatter: .empty, body: normalized)
        }
        let frontmatterStart = normalized.index(normalized.startIndex, offsetBy: 4)
        let lines = normalized[frontmatterStart..<end.lowerBound].split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return MarkdownDocument(
            frontmatter: NoteFrontmatter(lines: lines, hasFrontmatter: true),
            body: String(normalized[end.upperBound...])
        )
    }
}
