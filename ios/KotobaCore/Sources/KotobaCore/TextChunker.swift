import Foundation

/// Splits text at paragraph and sentence boundaries so that each piece fits one server slot.
public enum TextChunker {
    public static let defaultMaxCharacters = 1200

    private static let sentenceEnds: Set<Character> = ["。", "！", "？", "!", "?", ".", ";", "、", ","]

    public static func chunks(in text: String, maxCharacters: Int = defaultMaxCharacters) -> [String] {
        var chunks: [String] = []
        var buffer = ""

        for line in text.split(whereSeparator: \.isNewline) {
            let paragraph = line.trimmingCharacters(in: .whitespaces)
            guard !paragraph.isEmpty else { continue }

            for piece in split(paragraph, maxCharacters: maxCharacters) {
                if !buffer.isEmpty, buffer.count + 1 + piece.count > maxCharacters {
                    chunks.append(buffer)
                    buffer = ""
                }
                buffer = buffer.isEmpty ? piece : buffer + "\n" + piece
            }
        }
        if !buffer.isEmpty { chunks.append(buffer) }
        return chunks
    }

    private static func split(_ paragraph: String, maxCharacters: Int) -> [String] {
        var pieces: [String] = []
        var rest = Substring(paragraph)

        while rest.count > maxCharacters {
            let window = rest.prefix(maxCharacters)
            let end = window.lastIndex(where: sentenceEnds.contains).map(rest.index(after:)) ?? window.endIndex
            pieces.append(rest[..<end].trimmingCharacters(in: .whitespaces))
            rest = rest[end...].drop(while: \.isWhitespace)
        }
        if !rest.isEmpty { pieces.append(String(rest)) }
        return pieces
    }
}
