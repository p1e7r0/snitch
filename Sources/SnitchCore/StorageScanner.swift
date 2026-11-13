import Foundation

struct StorageTag: Sendable {
    enum Kind: Sendable {
        case opening
        case closing
        case selfClosing
    }

    let name: String
    let kind: Kind
    let range: Range<Int>
}

struct StorageScanner: Sendable {
    let bytes: [UInt8]

    private static let lessThan = UInt8(ascii: "<")
    private static let greaterThan = UInt8(ascii: ">")
    private static let slash = UInt8(ascii: "/")
    private static let exclamationMark = UInt8(ascii: "!")
    private static let questionMark = UInt8(ascii: "?")
    private static let doubleQuote = UInt8(ascii: "\"")
    private static let singleQuote = UInt8(ascii: "'")
    private static let commentStart = Array("<!--".utf8)
    private static let commentEnd = Array("-->".utf8)
    private static let characterDataStart = Array("<![CDATA[".utf8)
    private static let characterDataEnd = Array("]]>".utf8)
    private static let blankTagNames: Set<String> = ["br", "p", "div", "span"]

    func tags(in range: Range<Int>) -> [StorageTag] {
        var tags: [StorageTag] = []
        let limit = range.upperBound
        var position = range.lowerBound
        while position < limit {
            guard bytes[position] == Self.lessThan else {
                position += 1
                continue
            }
            if hasSequence(Self.commentStart, at: position, limit: limit) {
                position = index(after: Self.commentEnd, from: position + Self.commentStart.count, limit: limit)
                continue
            }
            if hasSequence(Self.characterDataStart, at: position, limit: limit) {
                position = index(after: Self.characterDataEnd, from: position + Self.characterDataStart.count, limit: limit)
                continue
            }
            var cursor = position + 1
            guard cursor < limit else {
                break
            }
            if bytes[cursor] == Self.exclamationMark || bytes[cursor] == Self.questionMark {
                position = index(after: [Self.greaterThan], from: cursor, limit: limit)
                continue
            }
            let isClosing = bytes[cursor] == Self.slash
            if isClosing {
                cursor += 1
            }
            let nameStart = cursor
            while cursor < limit, Self.isNameByte(bytes[cursor]) {
                cursor += 1
            }
            guard cursor > nameStart else {
                position += 1
                continue
            }
            let name = String(decoding: bytes[nameStart..<cursor], as: UTF8.self).lowercased()
            var openQuote: UInt8?
            while cursor < limit {
                let byte = bytes[cursor]
                if let quote = openQuote {
                    if byte == quote {
                        openQuote = nil
                    }
                } else if byte == Self.doubleQuote || byte == Self.singleQuote {
                    openQuote = byte
                } else if byte == Self.greaterThan {
                    break
                }
                cursor += 1
            }
            guard cursor < limit else {
                break
            }
            let kind: StorageTag.Kind
            if isClosing {
                kind = .closing
            } else if bytes[cursor - 1] == Self.slash {
                kind = .selfClosing
            } else {
                kind = .opening
            }
            tags.append(StorageTag(name: name, kind: kind, range: position..<(cursor + 1)))
            position = cursor + 1
        }
        return tags
    }

    func source(in range: Range<Int>) -> String {
        String(decoding: bytes[range], as: UTF8.self)
    }

    func plainText(in range: Range<Int>) -> String {
        plainText(in: range, excluding: tags(in: range))
    }

    func isBlank(in range: Range<Int>) -> Bool {
        let tags = tags(in: range)
        guard tags.allSatisfy({ Self.blankTagNames.contains($0.name) }) else {
            return false
        }
        return plainText(in: range, excluding: tags).isEmpty
    }

    private func plainText(in range: Range<Int>, excluding tags: [StorageTag]) -> String {
        var text = ""
        var position = range.lowerBound
        for tag in tags {
            text += source(in: position..<tag.range.lowerBound)
            position = tag.range.upperBound
        }
        text += source(in: position..<range.upperBound)
        return StorageText.collapsingWhitespace(StorageText.decodingEntities(text))
    }

    func contains(_ sequence: [UInt8], in range: Range<Int>) -> Bool {
        guard !sequence.isEmpty else {
            return true
        }
        var position = range.lowerBound
        while position + sequence.count <= range.upperBound {
            if hasSequence(sequence, at: position, limit: range.upperBound) {
                return true
            }
            position += 1
        }
        return false
    }

    private func hasSequence(_ sequence: [UInt8], at position: Int, limit: Int) -> Bool {
        guard position + sequence.count <= limit else {
            return false
        }
        return bytes[position..<(position + sequence.count)].elementsEqual(sequence)
    }

    private func index(after terminator: [UInt8], from start: Int, limit: Int) -> Int {
        var position = start
        while position + terminator.count <= limit {
            if hasSequence(terminator, at: position, limit: limit) {
                return position + terminator.count
            }
            position += 1
        }
        return limit
    }

    private static func isNameByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            return true
        case UInt8(ascii: ":"), UInt8(ascii: "-"), UInt8(ascii: "_"), UInt8(ascii: "."):
            return true
        default:
            return false
        }
    }
}

enum StorageText {
    private static let namedEntities: [String: String] = [
        "amp": "&",
        "lt": "<",
        "gt": ">",
        "quot": "\"",
        "apos": "'",
        "nbsp": "\u{00A0}",
    ]

    static func escaped(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "&":
                result += "&amp;"
            case "<":
                result += "&lt;"
            case ">":
                result += "&gt;"
            case "\"":
                result += "&quot;"
            default:
                if character.isNewline || character == "\t" {
                    result += " "
                } else if character.unicodeScalars.allSatisfy({ $0.properties.generalCategory != .control }) {
                    result.append(character)
                }
            }
        }
        return result
    }

    static func decodingEntities(_ text: String) -> String {
        var result = ""
        var remainder = Substring(text)
        while let ampersand = remainder.firstIndex(of: "&") {
            result += remainder[..<ampersand]
            let afterAmpersand = remainder.index(after: ampersand)
            let candidate = remainder[afterAmpersand...].prefix(12)
            if let semicolon = candidate.firstIndex(of: ";"),
               let replacement = replacement(forEntityNamed: remainder[afterAmpersand..<semicolon]) {
                result += replacement
                remainder = remainder[remainder.index(after: semicolon)...]
            } else {
                result.append("&")
                remainder = remainder[afterAmpersand...]
            }
        }
        result += remainder
        return result
    }

    static func collapsingWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func replacement(forEntityNamed name: Substring) -> String? {
        if let named = namedEntities[String(name)] {
            return named
        }
        guard name.hasPrefix("#") else {
            return nil
        }
        let digits = name.dropFirst()
        let codePoint: UInt32?
        if digits.hasPrefix("x") || digits.hasPrefix("X") {
            codePoint = UInt32(digits.dropFirst(), radix: 16)
        } else {
            codePoint = UInt32(digits, radix: 10)
        }
        guard let codePoint, let scalar = Unicode.Scalar(codePoint) else {
            return nil
        }
        return String(Character(scalar))
    }
}
