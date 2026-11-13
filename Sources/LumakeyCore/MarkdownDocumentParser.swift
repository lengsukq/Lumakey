import Foundation

public struct MarkdownMetaPair: Sendable, Hashable {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public enum MarkdownAlertKind: String, Sendable, Hashable {
    case note = "NOTE"
    case tip = "TIP"
    case important = "IMPORTANT"
    case warning = "WARNING"
    case caution = "CAUTION"

    public var title: String {
        switch self {
        case .note: return "Note"
        case .tip: return "Tip"
        case .important: return "Important"
        case .warning: return "Warning"
        case .caution: return "Caution"
        }
    }
}

public struct MarkdownHeadingItem: Identifiable, Sendable, Hashable {
    public let id: String
    public let level: Int
    public let text: String

    public init(id: String, level: Int, text: String) {
        self.id = id
        self.level = level
        self.text = text
    }
}

public enum MarkdownBlock: Identifiable, Sendable, Hashable {
    case frontmatter(id: String, pairs: [MarkdownMetaPair])
    case heading(id: String, level: Int, text: String)
    case paragraph(id: String, text: String)
    case codeBlock(id: String, language: String, code: String)
    case quote(id: String, lines: [String])
    case alert(id: String, kind: MarkdownAlertKind, lines: [String])
    case bulletList(id: String, items: [String])
    case orderedList(id: String, start: Int, items: [String])
    case taskList(id: String, items: [MarkdownTaskItem])
    case table(id: String, headers: [String], rows: [[String]])
    case divider(id: String)

    public var id: String {
        switch self {
        case .frontmatter(let id, _),
             .heading(let id, _, _),
             .paragraph(let id, _),
             .codeBlock(let id, _, _),
             .quote(let id, _),
             .alert(let id, _, _),
             .bulletList(let id, _),
             .orderedList(let id, _, _),
             .taskList(let id, _),
             .table(let id, _, _),
             .divider(let id):
            return id
        }
    }
}

public struct MarkdownTaskItem: Sendable, Hashable {
    public let checked: Bool
    public let text: String

    public init(checked: Bool, text: String) {
        self.checked = checked
        self.text = text
    }
}

public enum MarkdownDocumentParser {
    public static func headings(in blocks: [MarkdownBlock]) -> [MarkdownHeadingItem] {
        blocks.compactMap { block in
            guard case .heading(let id, let level, let text) = block else { return nil }
            return MarkdownHeadingItem(id: id, level: level, text: text)
        }
    }

    public static func parse(_ source: String) -> [MarkdownBlock] {
        guard !source.isEmpty else { return [] }
        let rawLines = splitLinesPreservingEmpty(source)
        let trimmedLines = rawLines.map(trimHorizontalWhitespace)
        var blocks: [MarkdownBlock] = []
        blocks.reserveCapacity(min(rawLines.count / 2 + 1, 256))
        var index = 0
        var counter = 0

        func nextID(_ prefix: String) -> String {
            counter += 1
            return "\(prefix)-\(counter)"
        }

        if let (pairs, nextIdx) = parseFrontmatter(trimmedLines: trimmedLines) {
            blocks.append(.frontmatter(id: nextID("fm"), pairs: pairs))
            index = nextIdx
        }

        while index < rawLines.count {
            let trimmed = trimmedLines[index]
            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fence: Substring = trimmed.hasPrefix("```") ? "```" : "~~~"
                let lang = String(trimHorizontalWhitespace(trimmed.dropFirst(3)))
                index += 1
                var codeLines: [Substring] = []
                while index < rawLines.count && !trimmedLines[index].hasPrefix(fence) {
                    codeLines.append(rawLines[index])
                    index += 1
                }
                if index < rawLines.count { index += 1 }
                blocks.append(.codeBlock(id: nextID("code"), language: lang, code: codeLines.joined(separator: "\n")))
                continue
            }

            if let heading = parseHeading(trimmed) {
                blocks.append(.heading(id: nextID("h"), level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if isDivider(trimmed) {
                blocks.append(.divider(id: nextID("hr")))
                index += 1
                continue
            }

            if trimmed.first == ">" {
                let (block, nextIdx) = consumeQuoteOrAlert(trimmedLines: trimmedLines, from: index, nextID: nextID)
                blocks.append(block)
                index = nextIdx
                continue
            }

            if index + 1 < rawLines.count && trimmed.contains("|") && isTableSeparator(trimmedLines[index + 1]) {
                let (tableBlock, nextIdx) = consumeTable(trimmedLines: trimmedLines, from: index, id: nextID("tbl"))
                blocks.append(tableBlock)
                index = nextIdx
                continue
            }

            if let (listBlock, nextIdx) = consumeListBlock(trimmedLines: trimmedLines, from: index, nextID: nextID) {
                blocks.append(listBlock)
                index = nextIdx
                continue
            }

            var paraLines: [Substring] = [trimmed]
            index += 1
            while index < rawLines.count {
                let nextTrim = trimmedLines[index]
                let following = index + 1 < rawLines.count ? trimmedLines[index + 1] : nil
                if nextTrim.isEmpty || startsSpecialBlock(nextTrim, nextTrimmedLine: following) {
                    break
                }
                paraLines.append(nextTrim)
                index += 1
            }
            blocks.append(.paragraph(id: nextID("p"), text: paraLines.joined(separator: " ")))
        }

        return blocks
    }
}
