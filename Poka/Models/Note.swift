import Foundation

struct Note: Identifiable, Hashable, Sendable {
    var title: String
    var fileURL: URL
    var modifiedAt: Date

    /// Stable identity across folder scans (same path → same note).
    var id: String { fileURL.path }

    init(title: String, fileURL: URL, modifiedAt: Date) {
        self.title = title
        self.fileURL = fileURL
        self.modifiedAt = modifiedAt
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
