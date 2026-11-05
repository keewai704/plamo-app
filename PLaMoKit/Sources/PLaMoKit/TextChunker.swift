import Foundation

/// Splits long input into chunks that fit comfortably in the small context
/// window used on iPhone (2k tokens by default).
public enum TextChunker {
    public static let defaultMaxCharacters = 1_200

    public static func chunks(in text: String, maxCharacters: Int = defaultMaxCharacters) -> [String] {
        precondition(maxCharacters > 0, "maxCharacters must be positive")

        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        var result: [String] = []
        var buffer = ""

        func flush() {
            let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { result.append(trimmed) }
            buffer = ""
        }

        for rawParagraph in normalized.components(separatedBy: "\n") {
            let paragraph = rawParagraph.trimmingCharacters(in: .whitespaces)
            guard !paragraph.isEmpty else { continue }

            for piece in splitParagraph(paragraph, maxCharacters: maxCharacters) {
                if buffer.isEmpty {
                    buffer = piece
                } else if buffer.count + 1 + piece.count <= maxCharacters {
                    buffer += "\n" + piece
                } else {
                    flush()
                    buffer = piece
                }
            }
        }

        flush()
        return result
    }

    private static func splitParagraph(_ text: String, maxCharacters: Int) -> [String] {
        guard text.count > maxCharacters else { return [text] }

        let separators: Set<Character> = ["。", "！", "？", "!", "?", ".", ";", "、", ","]
        var pieces: [String] = []
        var remainder = Substring(text)

        while remainder.count > maxCharacters {
            let window = remainder.prefix(maxCharacters)
            let breakPoint = window.lastIndex(where: { separators.contains($0) })
            let end = breakPoint.map { remainder.index(after: $0) } ?? window.endIndex
            let piece = String(remainder[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { pieces.append(piece) }
            remainder = remainder[end...].drop(while: { $0.isWhitespace })
        }

        let tail = String(remainder).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { pieces.append(tail) }
        return pieces
    }
}
