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
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var index = 0
        var counter = 0

        func nextID(_ prefix: String) -> String {
            counter += 1
            return "\(prefix)-\(counter)"
        }

        if let (pairs, nextIdx) = parseFrontmatter(lines: lines) {
            blocks.append(.frontmatter(id: nextID("fm"), pairs: pairs))
            index = nextIdx
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fence = trimmed.hasPrefix("```") ? "```" : "~~~"
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                index += 1
                var codeLines: [String] = []
                while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
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

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let qTrim = lines[index].trimmingCharacters(in: .whitespaces)
                    guard qTrim.hasPrefix(">") else { break }
                    let stripped = String(qTrim.dropFirst()).trimmingCharacters(in: .whitespaces)
                    quoteLines.append(stripped)
                    index += 1
                }
                if let alert = parseAlert(lines: quoteLines) {
                    blocks.append(.alert(id: nextID("alert"), kind: alert.kind, lines: alert.lines))
                } else {
                    blocks.append(.quote(id: nextID("q"), lines: quoteLines))
                }
                continue
            }

            if index + 1 < lines.count && trimmed.contains("|") && isTableSeparator(lines[index + 1]) {
                let headers = splitTableRow(trimmed)
                index += 2
                var rows: [[String]] = []
                while index < lines.count {
                    let rowTrim = lines[index].trimmingCharacters(in: .whitespaces)
                    if rowTrim.isEmpty || !rowTrim.contains("|") { break }
                    rows.append(splitTableRow(rowTrim))
                    index += 1
                }
                blocks.append(.table(id: nextID("tbl"), headers: headers, rows: rows))
                continue
            }

            if parseTaskLine(trimmed) != nil {
                var tasks: [MarkdownTaskItem] = []
                while index < lines.count, let task = parseTaskLine(lines[index].trimmingCharacters(in: .whitespaces)) {
                    tasks.append(task)
                    index += 1
                }
                blocks.append(.taskList(id: nextID("task"), items: tasks))
                continue
            }

            if parseBulletLine(trimmed) != nil {
                var items: [String] = []
                while index < lines.count, let item = parseBulletLine(lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(item)
                    index += 1
                }
                blocks.append(.bulletList(id: nextID("ul"), items: items))
                continue
            }

            if let firstOrd = parseOrderedLine(trimmed) {
                var items: [String] = [firstOrd.text]
                index += 1
                while index < lines.count, let nextOrd = parseOrderedLine(lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(nextOrd.text)
                    index += 1
                }
                blocks.append(.orderedList(id: nextID("ol"), start: firstOrd.num, items: items))
                continue
            }

            var paraLines: [String] = [trimmed]
            index += 1
            while index < lines.count {
                let nextTrim = lines[index].trimmingCharacters(in: .whitespaces)
                if nextTrim.isEmpty || startsSpecialBlock(nextTrim, nextLine: index + 1 < lines.count ? lines[index + 1] : nil) {
                    break
                }
                paraLines.append(nextTrim)
                index += 1
            }
            blocks.append(.paragraph(id: nextID("p"), text: paraLines.joined(separator: " ")))
        }

        return blocks
    }

    private static func parseFrontmatter(lines: [String]) -> ([MarkdownMetaPair], Int)? {
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        var pairs: [MarkdownMetaPair] = []
        for idx in 1..<lines.count {
            let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "..." { return pairs.isEmpty ? nil : (pairs, idx + 1) }
            if let colon = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                let val = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty { pairs.append(MarkdownMetaPair(key: key, value: val)) }
            }
        }
        return nil
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), line.count > hashes else { return nil }
        let after = line.dropFirst(hashes)
        guard after.first == " " || after.first == "\t" else { return nil }
        let text = String(after).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (hashes, text)
    }

    private static func isDivider(_ line: String) -> Bool {
        let s = line.replacingOccurrences(of: " ", with: "")
        return s.count >= 3 && (s.allSatisfy { $0 == "-" } || s.allSatisfy { $0 == "*" } || s.allSatisfy { $0 == "_" })
    }

    private static func parseAlert(lines: [String]) -> (kind: MarkdownAlertKind, lines: [String])? {
        guard let first = lines.first?.trimmingCharacters(in: .whitespaces),
              first.hasPrefix("[!") && first.hasSuffix("]"),
              let kind = MarkdownAlertKind(rawValue: String(first.dropFirst(2).dropLast()).uppercased())
        else { return nil }
        return (kind, Array(lines.dropFirst()))
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.contains("|") && t.contains("-") && t.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "|-: \t").contains($0) }
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var w = line.trimmingCharacters(in: .whitespaces)
        if w.hasPrefix("|") { w.removeFirst() }
        if w.hasSuffix("|") { w.removeLast() }
        return w.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func parseTaskLine(_ line: String) -> MarkdownTaskItem? {
        for p in ["- [ ] ", "* [ ] ", "- [x] ", "- [X] ", "* [x] ", "* [X] "] where line.hasPrefix(p) {
            return MarkdownTaskItem(checked: p.contains("x") || p.contains("X"), text: String(line.dropFirst(p.count)).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    private static func parseBulletLine(_ line: String) -> String? {
        for p in ["- ", "* ", "+ "] where line.hasPrefix(p) {
            return String(line.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func parseOrderedLine(_ line: String) -> (num: Int, text: String)? {
        guard let dot = line.firstIndex(of: "."), let num = Int(line[..<dot]) else { return nil }
        let after = line[line.index(after: dot)...]
        guard after.first == " " || after.first == "\t" else { return nil }
        return (num, String(after).trimmingCharacters(in: .whitespaces))
    }

    private static func startsSpecialBlock(_ line: String, nextLine: String?) -> Bool {
        line.hasPrefix("```") || line.hasPrefix("~~~") || line.hasPrefix(">")
            || parseHeading(line) != nil || isDivider(line)
            || parseTaskLine(line) != nil || parseBulletLine(line) != nil || parseOrderedLine(line) != nil
            || (nextLine.map { line.contains("|") && isTableSeparator($0) } ?? false)
    }
}
