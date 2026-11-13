import Foundation

extension MarkdownDocumentParser {
    static func splitLinesPreservingEmpty(_ source: String) -> [Substring] {
        var lines: [Substring] = []
        lines.reserveCapacity(max(8, source.utf8.count / 48))
        var lineStart = source.startIndex
        var idx = source.startIndex
        while idx < source.endIndex {
            let ch = source[idx]
            if ch == "\n" || ch == "\r\n" {
                var slice = source[lineStart..<idx]
                if slice.last == "\r" { slice = slice.dropLast() }
                lines.append(slice)
                idx = source.index(after: idx)
                lineStart = idx
            } else {
                idx = source.index(after: idx)
            }
        }
        var tail = source[lineStart..<source.endIndex]
        if tail.last == "\r" { tail = tail.dropLast() }
        lines.append(tail)
        return lines
    }

    @inline(__always)
    static func isHorizontalSpace(_ ch: Character) -> Bool {
        ch == " " || ch == "\t" || ch.unicodeScalars.allSatisfy { $0.properties.isWhitespace }
    }

    static func trimHorizontalWhitespace(_ slice: Substring) -> Substring {
        var s = slice
        while let first = s.first, isHorizontalSpace(first) {
            s = s.dropFirst()
        }
        while let last = s.last, isHorizontalSpace(last) {
            s = s.dropLast()
        }
        return s
    }

    static func parseFrontmatter(trimmedLines: [Substring]) -> ([MarkdownMetaPair], Int)? {
        guard trimmedLines.first == "---" else { return nil }
        var pairs: [MarkdownMetaPair] = []
        for idx in 1..<trimmedLines.count {
            let trimmed = trimmedLines[idx]
            if trimmed == "---" || trimmed == "..." {
                return pairs.isEmpty ? nil : (pairs, idx + 1)
            }
            if let colon = trimmed.firstIndex(of: ":") {
                let key = String(trimHorizontalWhitespace(trimmed[..<colon]))
                let val = String(trimHorizontalWhitespace(trimmed[trimmed.index(after: colon)...]))
                if !key.isEmpty {
                    pairs.append(MarkdownMetaPair(key: key, value: val))
                }
            }
        }
        return nil
    }

    static func parseHeading(_ trimmed: Substring) -> (level: Int, text: String)? {
        let hashes = trimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), trimmed.count > hashes else { return nil }
        let after = trimmed.dropFirst(hashes)
        guard after.first == " " || after.first == "\t" else { return nil }
        let text = String(trimHorizontalWhitespace(after))
        return text.isEmpty ? nil : (hashes, text)
    }

    static func isDivider(_ trimmed: Substring) -> Bool {
        guard let marker = trimmed.first, marker == "-" || marker == "*" || marker == "_" else { return false }
        var count = 0
        for ch in trimmed {
            if ch == marker {
                count += 1
            } else if ch != " " && ch != "\t" {
                return false
            }
        }
        return count >= 3
    }

    static func consumeQuoteOrAlert(
        trimmedLines: [Substring],
        from startIndex: Int,
        nextID: (String) -> String
    ) -> (MarkdownBlock, Int) {
        var index = startIndex
        var quoteLines: [String] = []
        while index < trimmedLines.count {
            let qTrim = trimmedLines[index]
            guard qTrim.first == ">" else { break }
            quoteLines.append(String(trimHorizontalWhitespace(qTrim.dropFirst())))
            index += 1
        }
        if let alert = parseAlert(lines: quoteLines) {
            return (.alert(id: nextID("alert"), kind: alert.kind, lines: alert.lines), index)
        }
        return (.quote(id: nextID("q"), lines: quoteLines), index)
    }

    static func parseAlert(lines: [String]) -> (kind: MarkdownAlertKind, lines: [String])? {
        guard let firstRaw = lines.first else { return nil }
        let first = trimHorizontalWhitespace(Substring(firstRaw))
        guard first.hasPrefix("[!") && first.hasSuffix("]"),
              let kind = MarkdownAlertKind(rawValue: String(first.dropFirst(2).dropLast()).uppercased())
        else { return nil }
        return (kind, Array(lines.dropFirst()))
    }

    static func consumeTable(trimmedLines: [Substring], from startIndex: Int, id: String) -> (MarkdownBlock, Int) {
        let headers = splitTableRow(trimmedLines[startIndex])
        var index = startIndex + 2
        var rows: [[String]] = []
        while index < trimmedLines.count {
            let rowTrim = trimmedLines[index]
            if rowTrim.isEmpty || !rowTrim.contains("|") { break }
            rows.append(splitTableRow(rowTrim))
            index += 1
        }
        return (.table(id: id, headers: headers, rows: rows), index)
    }

    static func isTableSeparator(_ trimmed: Substring) -> Bool {
        var hasPipe = false
        var hasDash = false
        for b in trimmed.utf8 {
            switch b {
            case 0x7C: hasPipe = true
            case 0x2D: hasDash = true
            case 0x3A, 0x20, 0x09: break
            default: return false
            }
        }
        return hasPipe && hasDash
    }

    static func splitTableRow(_ trimmed: Substring) -> [String] {
        var w = trimmed
        if w.first == "|" { w = w.dropFirst() }
        if w.last == "|" { w = w.dropLast() }
        return w.split(separator: "|", omittingEmptySubsequences: false).map { String(trimHorizontalWhitespace($0)) }
    }

    static func consumeListBlock(
        trimmedLines: [Substring],
        from startIndex: Int,
        nextID: (String) -> String
    ) -> (MarkdownBlock, Int)? {
        var index = startIndex
        let first = trimmedLines[index]

        if parseTaskLine(first) != nil {
            var tasks: [MarkdownTaskItem] = []
            while index < trimmedLines.count, let task = parseTaskLine(trimmedLines[index]) {
                tasks.append(task)
                index += 1
            }
            return (.taskList(id: nextID("task"), items: tasks), index)
        }

        if parseBulletLine(first) != nil {
            var items: [String] = []
            while index < trimmedLines.count, let item = parseBulletLine(trimmedLines[index]) {
                items.append(item)
                index += 1
            }
            return (.bulletList(id: nextID("ul"), items: items), index)
        }

        if let firstOrd = parseOrderedLine(first) {
            var items: [String] = [firstOrd.text]
            index += 1
            while index < trimmedLines.count, let nextOrd = parseOrderedLine(trimmedLines[index]) {
                items.append(nextOrd.text)
                index += 1
            }
            return (.orderedList(id: nextID("ol"), start: firstOrd.num, items: items), index)
        }

        return nil
    }

    static func parseTaskLine(_ trimmed: Substring) -> MarkdownTaskItem? {
        for p: StaticString in ["- [ ] ", "* [ ] ", "- [x] ", "- [X] ", "* [x] ", "* [X] "] {
            let prefixStr = p.description
            if trimmed.hasPrefix(prefixStr) {
                let checked = prefixStr.contains("x") || prefixStr.contains("X")
                let text = String(trimHorizontalWhitespace(trimmed.dropFirst(prefixStr.count)))
                return MarkdownTaskItem(checked: checked, text: text)
            }
        }
        return nil
    }

    static func parseBulletLine(_ trimmed: Substring) -> String? {
        for p in ["- ", "* ", "+ "] where trimmed.hasPrefix(p) {
            return String(trimHorizontalWhitespace(trimmed.dropFirst(2)))
        }
        return nil
    }

    static func parseOrderedLine(_ trimmed: Substring) -> (num: Int, text: String)? {
        guard let dot = trimmed.firstIndex(of: "."), let num = Int(trimmed[..<dot]) else { return nil }
        let after = trimmed[trimmed.index(after: dot)...]
        guard after.first == " " || after.first == "\t" else { return nil }
        return (num, String(trimHorizontalWhitespace(after)))
    }

    static func startsSpecialBlock(_ trimmed: Substring, nextTrimmedLine: Substring?) -> Bool {
        trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") || trimmed.first == ">"
            || parseHeading(trimmed) != nil || isDivider(trimmed)
            || parseTaskLine(trimmed) != nil || parseBulletLine(trimmed) != nil || parseOrderedLine(trimmed) != nil
            || (nextTrimmedLine.map { trimmed.contains("|") && isTableSeparator($0) } ?? false)
    }
}
