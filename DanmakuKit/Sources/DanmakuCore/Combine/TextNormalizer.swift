import Foundation

/// Text normalisation applied before similarity checks (pakku semantics).
public struct TextNormalizer: Sendable {
    public var trimEnding: Bool
    public var trimSpace: Bool
    public var trimWidth: Bool

    public init(trimEnding: Bool = true, trimSpace: Bool = true, trimWidth: Bool = true) {
        self.trimEnding = trimEnding
        self.trimSpace = trimSpace
        self.trimWidth = trimWidth
    }

    static let endingCharacters: Set<Character> = Set(".。,，/?？!！…~～@^、+=-_♂♀ ")

    public func normalize(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimEnding {
            var end = text.endIndex
            while end > text.startIndex {
                let prev = text.index(before: end)
                guard Self.endingCharacters.contains(text[prev]) else { break }
                end = prev
            }
            // A text made only of ending characters is kept as is.
            if end > text.startIndex { text = String(text[..<end]) }
        }

        if trimWidth {
            var scalars = String.UnicodeScalarView()
            for s in text.unicodeScalars {
                scalars.append(Self.halfWidth(s))
            }
            text = String(scalars)
        }

        if trimSpace {
            var scalars = String.UnicodeScalarView()
            var previousWasSpace = false
            for s in text.unicodeScalars {
                let isSpace = s == " " || s == "\u{3000}"
                if isSpace {
                    if !previousWasSpace { scalars.append(" ") }
                } else {
                    scalars.append(s)
                }
                previousWasSpace = isSpace
            }
            // Drop a single space between two CJK characters.
            var out = String.UnicodeScalarView()
            let arr = Array(scalars)
            for (i, s) in arr.enumerated() {
                if s == " ", i > 0, i + 1 < arr.count, Self.isCJK(arr[i - 1]), Self.isCJK(arr[i + 1]) { continue }
                out.append(s)
            }
            text = String(out)
        }
        return text
    }

    static func halfWidth(_ s: Unicode.Scalar) -> Unicode.Scalar {
        switch s.value {
        case 0x3000: return " "
        case 0xFF01...0xFF5E: return Unicode.Scalar(s.value - 0xFEE0)!
        default: return s
        }
    }

    static func isCJK(_ s: Unicode.Scalar) -> Bool {
        (0x3000...0x9FFF).contains(s.value) || (0xFF00...0xFFEF).contains(s.value)
    }
}
