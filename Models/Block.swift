import Foundation

enum BlockKind: String, CaseIterable, Identifiable, Codable {
    case paragraph
    case heading1
    case heading2
    case heading3
    case bullet
    case numbered
    case quote
    case code
    case divider

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .paragraph: "Text"
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .heading3: "Heading 3"
        case .bullet: "Bulleted list"
        case .numbered: "Numbered list"
        case .quote: "Quote"
        case .code: "Code"
        case .divider: "Divider"
        }
    }

    var menuKeywords: [String] {
        switch self {
        case .paragraph: ["text", "paragraph", "p"]
        case .heading1: ["h1", "heading1", "heading", "title"]
        case .heading2: ["h2", "heading2"]
        case .heading3: ["h3", "heading3"]
        case .bullet: ["bullet", "ul", "list"]
        case .numbered: ["numbered", "ol", "1"]
        case .quote: ["quote", "blockquote"]
        case .code: ["code", "snippet"]
        case .divider: ["divider", "line", "hr", "---"]
        }
    }

    var systemImage: String {
        switch self {
        case .paragraph: "text.alignleft"
        case .heading1: "textformat.size.larger"
        case .heading2: "textformat.size"
        case .heading3: "textformat.size.smaller"
        case .bullet: "list.bullet"
        case .numbered: "list.number"
        case .quote: "text.quote"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .divider: "minus"
        }
    }
}

struct Block: Identifiable, Equatable, Codable {
    let id: UUID
    var kind: BlockKind
    var text: String

    init(id: UUID = UUID(), kind: BlockKind = .paragraph, text: String = "") {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

struct SlashCommandState: Equatable {
    var filter: String
    /// Number of characters to remove from the end of `text` (includes `/` and filter).
    var suffixLength: Int
}

enum SlashCommandParser {
    /// Notion-style: `/` at the end of the block text opens the menu; characters after `/` filter it.
    static func activeCommand(in text: String) -> SlashCommandState? {
        guard let slashIndex = text.lastIndex(of: "/") else { return nil }
        let afterSlash = text[text.index(after: slashIndex)...]
        if afterSlash.contains("\n") { return nil }
        let filter = String(afterSlash)
        if filter.contains(" ") { return nil }
        let suffixLength = text.distance(from: slashIndex, to: text.endIndex)
        return SlashCommandState(filter: filter, suffixLength: suffixLength)
    }
}
