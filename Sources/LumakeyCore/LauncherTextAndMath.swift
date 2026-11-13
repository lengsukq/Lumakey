import Foundation

public enum PinyinHelper {
    public static func convert(_ text: String) -> (full: String, initials: String) {
        let stripped = text
            .applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false)?
            .lowercased() ?? text.lowercased()
        let tokens = stripped
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return (tokens.joined(), String(tokens.compactMap(\.first)))
    }
}

public enum SafeMathEvaluator {
    public static func evaluate(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }
        let hasOpOrHex = trimmed.contains(where: { "+-*/%^()".contains($0) })
            || trimmed.lowercased().hasPrefix("0x")
        guard hasOpOrHex else { return nil }
        var parser = Parser(chars: Array(trimmed))
        guard let value = parser.parseExpression(), parser.isAtEnd, value.isFinite else { return nil }
        if value.rounded() == value && abs(value) <= Double(Int64.max / 2) {
            return String(Int64(value))
        }
        return String(format: "%.6g", value)
    }

    private struct Parser {
        let chars: [Character]
        var index: Int = 0
        var isAtEnd: Bool { mutating get { skipSpaces(); return index >= chars.count } }

        mutating func parseExpression() -> Double? {
            guard var lhs = parseTerm() else { return nil }
            while true {
                skipSpaces()
                guard index < chars.count, chars[index] == "+" || chars[index] == "-" else { break }
                let op = chars[index]; index += 1
                guard let rhs = parseTerm() else { return nil }
                lhs = (op == "+") ? (lhs + rhs) : (lhs - rhs)
            }
            return lhs
        }

        mutating func parseTerm() -> Double? {
            guard var lhs = parsePower() else { return nil }
            while true {
                skipSpaces()
                guard index < chars.count, "*/%".contains(chars[index]) else { break }
                let op = chars[index]; index += 1
                guard let rhs = parsePower() else { return nil }
                if (op == "/" || op == "%") && rhs == 0 { return nil }
                lhs = op == "*" ? lhs * rhs : (op == "/" ? lhs / rhs : lhs.truncatingRemainder(dividingBy: rhs))
            }
            return lhs
        }

        mutating func parsePower() -> Double? {
            guard let base = parseFactor() else { return nil }
            skipSpaces()
            if index < chars.count && chars[index] == "^" {
                index += 1
                guard let exp = parsePower() else { return nil }
                return pow(base, exp)
            }
            return base
        }

        mutating func parseFactor() -> Double? {
            skipSpaces()
            guard index < chars.count else { return nil }
            if chars[index] == "+" { index += 1; return parseFactor() }
            if chars[index] == "-" { index += 1; return parseFactor().map { -$0 } }
            if chars[index] == "(" {
                index += 1
                guard let inner = parseExpression() else { return nil }
                skipSpaces()
                guard index < chars.count && chars[index] == ")" else { return nil }
                index += 1
                return inner
            }
            return parseNumber()
        }

        mutating func parseNumber() -> Double? {
            skipSpaces()
            let start = index
            if index + 1 < chars.count && chars[index] == "0" && (chars[index + 1] == "x" || chars[index + 1] == "X") {
                index += 2
                let hexStart = index
                while index < chars.count && chars[index].isHexDigit { index += 1 }
                guard index > hexStart, let hexVal = UInt64(String(chars[hexStart..<index]), radix: 16) else { return nil }
                return Double(hexVal)
            }
            var seenDot = false
            while index < chars.count {
                let c = chars[index]
                if c.isNumber { index += 1 }
                else if c == "." && !seenDot { seenDot = true; index += 1 }
                else { break }
            }
            guard index > start else { return nil }
            return Double(String(chars[start..<index]))
        }

        mutating func skipSpaces() {
            while index < chars.count && chars[index].isWhitespace { index += 1 }
        }
    }
}
