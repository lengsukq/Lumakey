import Foundation

public struct QueryNeedle: Sendable {
    public let rawLowercased: String
    public let utf8Bytes: [UInt8]
    public let isPureASCII: Bool

    public init(_ lowercased: String) {
        self.rawLowercased = lowercased
        let bytes = Array(lowercased.utf8)
        self.utf8Bytes = bytes
        self.isPureASCII = bytes.allSatisfy { $0 < 0x80 }
    }

    public func matches(in haystack: String) -> Bool {
        let m = utf8Bytes.count
        guard m > 0 else { return true }
        let fastHit: Bool? = haystack.utf8.withContiguousStorageIfAvailable { buf in
            Self.containsASCIICaseInsensitive(buf, needle: utf8Bytes)
        }
        if let fastHit {
            if fastHit { return true }
        } else {
            let hayBytes = Array(haystack.utf8)
            let fallbackHit = hayBytes.withUnsafeBufferPointer { Self.containsASCIICaseInsensitive($0, needle: utf8Bytes) }
            if fallbackHit { return true }
        }
        if !isPureASCII && Self.mayContainNonASCIICasedLetters(haystack.utf8) {
            return haystack.lowercased().contains(rawLowercased)
        }
        return false
    }

    private static func containsASCIICaseInsensitive(
        _ hay: UnsafeBufferPointer<UInt8>,
        needle: [UInt8]
    ) -> Bool {
        let n = hay.count
        let m = needle.count
        guard n >= m else { return false }
        let first = needle[0]
        let limit = n - m
        var i = 0
        while i <= limit {
            let b = hay[i]
            let folded = (b >= 0x41 && b <= 0x5A) ? (b &+ 32) : b
            if folded == first {
                var matched = true
                var j = 1
                while j < m {
                    let hb = hay[i &+ j]
                    let hf = (hb >= 0x41 && hb <= 0x5A) ? (hb &+ 32) : hb
                    if hf != needle[j] {
                        matched = false
                        break
                    }
                    j &+= 1
                }
                if matched { return true }
            }
            i &+= 1
        }
        return false
    }

    private static func mayContainNonASCIICasedLetters(_ utf8: String.UTF8View) -> Bool {
        for b in utf8 {
            if (b >= 0xC2 && b <= 0xDF) || (b >= 0xE1 && b <= 0xE3) {
                return true
            }
        }
        return false
    }
}

public struct EverythingQuery: Sendable {
    public enum Predicate: Sendable {
        case text(QueryNeedle)
        case extensions(Set<String>)
        case foldersOnly
        case filesOnly
        case videosOnly
        case imagesOnly
        case pathContains(String)
    }

    public struct Term: Sendable {
        public let negated: Bool
        public let predicate: Predicate
    }

    public struct Clause: Sendable {
        public let terms: [Term]
    }

    public let clauses: [Clause]
    public var isEmpty: Bool { clauses.isEmpty }

    public static func parse(_ raw: String) -> EverythingQuery {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return EverythingQuery(clauses: []) }

        let rawClauses = trimmed.components(separatedBy: "|")
        let clauses: [Clause] = rawClauses.compactMap { part in
            let tokens = tokenize(part)
            let terms = tokens.compactMap(parseToken)
            return terms.isEmpty ? nil : Clause(terms: terms)
        }
        return EverythingQuery(clauses: clauses)
    }

    public func matches(name: String, isDirectory: Bool, parentPathProvider: () -> String) -> Bool {
        if clauses.isEmpty { return true }
        var cachedExtLower: String?
        for clause in clauses {
            if matchesClause(
                clause,
                name: name,
                cachedExtLower: &cachedExtLower,
                isDirectory: isDirectory,
                parentPathProvider: parentPathProvider
            ) {
                return true
            }
        }
        return false
    }

    private func matchesClause(
        _ clause: Clause,
        name: String,
        cachedExtLower: inout String?,
        isDirectory: Bool,
        parentPathProvider: () -> String
    ) -> Bool {
        var cachedParentPath: String?
        func extLower() -> String {
            if let cachedExtLower { return cachedExtLower }
            let computed = EverythingIndex.extractExtensionLower(fromName: name)
            cachedExtLower = computed
            return computed
        }

        for term in clause.terms {
            let hit: Bool
            switch term.predicate {
            case .text(let needle):
                hit = needle.matches(in: name)
            case .extensions(let exts):
                hit = !isDirectory && exts.contains(extLower())
            case .foldersOnly:
                hit = isDirectory
            case .filesOnly:
                hit = !isDirectory
            case .videosOnly:
                hit = !isDirectory && MediaClassifier.videoExtensions.contains(extLower())
            case .imagesOnly:
                hit = !isDirectory && MediaClassifier.imageExtensions.contains(extLower())
            case .pathContains(let substr):
                let parent = cachedParentPath ?? {
                    let resolved = parentPathProvider().lowercased()
                    cachedParentPath = resolved
                    return resolved
                }()
                hit = parent.contains(substr)
            }
            if term.negated ? hit : !hit {
                return false
            }
        }
        return true
    }

    private static func tokenize(_ input: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for ch in input {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch.isWhitespace && !inQuotes {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func parseToken(_ token: String) -> Term? {
        var raw = token
        var negated = false
        if raw.hasPrefix("!") && raw.count > 1 {
            negated = true
            raw.removeFirst()
        }
        let lower = raw.lowercased()
        if lower == "folder:" { return Term(negated: negated, predicate: .foldersOnly) }
        if lower == "file:" { return Term(negated: negated, predicate: .filesOnly) }
        if lower == "video:" { return Term(negated: negated, predicate: .videosOnly) }
        if lower == "pic:" { return Term(negated: negated, predicate: .imagesOnly) }
        if lower.hasPrefix("ext:") {
            let list = String(lower.dropFirst(4))
                .split(whereSeparator: { $0 == ";" || $0 == "," })
                .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
                .filter { !$0.isEmpty }
            if list.isEmpty { return nil }
            return Term(negated: negated, predicate: .extensions(Set(list)))
        }
        if lower.hasPrefix("path:") {
            let sub = String(lower.dropFirst(5))
            if sub.isEmpty { return nil }
            return Term(negated: negated, predicate: .pathContains(sub))
        }
        return Term(negated: negated, predicate: .text(QueryNeedle(lower)))
    }
}
