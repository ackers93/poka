import Foundation

enum MarkdownCodec {
    static func parse(_ markdown: String) -> [Block] {
        parse(lines: markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline))
    }

    private static func parse(lines: [Substring]) -> [Block] {
        var blocks: [Block] = []
        var index = lines.startIndex

        while index < lines.endIndex {
            let line = String(lines[index])
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "<details>" {
                index = lines.index(after: index)
                var title = "Toggle"
                if index < lines.endIndex {
                    let summary = String(lines[index]).trimmingCharacters(in: .whitespaces)
                    if summary.hasPrefix("<summary>"), summary.hasSuffix("</summary>") {
                        title = String(summary.dropFirst("<summary>".count).dropLast("</summary>".count))
                        index = lines.index(after: index)
                    }
                }
                var childLines: [Substring] = []
                var depth = 1
                while index < lines.endIndex {
                    let candidate = String(lines[index]).trimmingCharacters(in: .whitespaces)
                    if candidate == "<details>" { depth += 1 }
                    if candidate == "</details>" {
                        depth -= 1
                        if depth == 0 {
                            index = lines.index(after: index)
                            break
                        }
                    }
                    childLines.append(lines[index])
                    index = lines.index(after: index)
                }
                let children = childLines.isEmpty ? [] : parse(lines: childLines)
                blocks.append(Block(kind: .toggle, text: title, children: children))
                continue
            }

            if trimmed.hasPrefix("```") {
                var body: [String] = []
                index = lines.index(after: index)
                while index < lines.endIndex {
                    let inner = String(lines[index])
                    if inner.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        index = lines.index(after: index)
                        break
                    }
                    body.append(inner)
                    index = lines.index(after: index)
                }
                blocks.append(Block(kind: .code, text: body.joined(separator: "\n")))
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(Block(kind: .divider))
                index = lines.index(after: index)
                continue
            }

            if trimmed.isEmpty {
                if blocks.last?.kind == .paragraph, blocks.last?.text.isEmpty == true {
                    index = lines.index(after: index)
                    continue
                }
                blocks.append(Block(kind: .paragraph, text: ""))
                index = lines.index(after: index)
                continue
            }

            if trimmed.hasPrefix("### ") {
                blocks.append(Block(kind: .heading3, text: String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("## ") {
                blocks.append(Block(kind: .heading2, text: String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("# ") {
                blocks.append(Block(kind: .heading1, text: String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("> ") {
                blocks.append(Block(kind: .quote, text: String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                blocks.append(Block(kind: .bullet, text: String(trimmed.dropFirst(2))))
            } else if let dot = trimmed.firstIndex(of: "."),
                      dot < trimmed.index(trimmed.startIndex, offsetBy: 4),
                      trimmed[..<dot].allSatisfy(\.isNumber),
                      trimmed.index(after: dot) < trimmed.endIndex,
                      trimmed[trimmed.index(after: dot)] == " "
            {
                let after = trimmed.index(trimmed.index(after: dot), offsetBy: 1, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
                blocks.append(Block(kind: .numbered, text: String(trimmed[after...])))
            } else {
                blocks.append(Block(kind: .paragraph, text: trimmed))
            }
            index = lines.index(after: index)
        }

        if blocks.isEmpty {
            blocks.append(Block())
        }
        return blocks
    }

    static func serialize(_ blocks: [Block]) -> String {
        var lines: [String] = []
        for block in blocks {
            switch block.kind {
            case .paragraph:
                lines.append(block.text)
            case .heading1:
                lines.append("# \(block.text)")
            case .heading2:
                lines.append("## \(block.text)")
            case .heading3:
                lines.append("### \(block.text)")
            case .bullet:
                lines.append("- \(block.text)")
            case .numbered:
                lines.append("1. \(block.text)")
            case .quote:
                lines.append("> \(block.text)")
            case .code:
                lines.append("```")
                if !block.text.isEmpty {
                    lines.append(block.text)
                }
                lines.append("```")
            case .divider:
                lines.append("---")
            case .toggle:
                lines.append("<details>")
                lines.append("<summary>\(block.text)</summary>")
                if !block.children.isEmpty {
                    lines.append(serialize(block.children))
                }
                lines.append("</details>")
            }
        }
        return lines.joined(separator: "\n")
    }
}
