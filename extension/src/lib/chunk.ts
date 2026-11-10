const MAX_CHARS = 1200;
const SENTENCE_END = /[。！？!?.;、,]/u;

/** Splits text at paragraph and sentence boundaries so that each piece fits one server slot. */
export function chunkText(text: string, maxChars = MAX_CHARS): string[] {
  const chunks: string[] = [];
  let buffer = "";

  const flush = () => {
    if (buffer) chunks.push(buffer);
    buffer = "";
  };

  for (const line of text.replace(/\r\n?/g, "\n").split("\n")) {
    const paragraph = line.trim();
    if (!paragraph) continue;
    for (const piece of splitParagraph(paragraph, maxChars)) {
      if (buffer && buffer.length + 1 + piece.length > maxChars) flush();
      buffer = buffer ? `${buffer}\n${piece}` : piece;
    }
  }
  flush();
  return chunks;
}

function splitParagraph(paragraph: string, maxChars: number): string[] {
  const pieces: string[] = [];
  let rest = paragraph;
  while (rest.length > maxChars) {
    let end = maxChars;
    for (let i = maxChars - 1; i > 0; i--) {
      if (SENTENCE_END.test(rest[i]!)) {
        end = i + 1;
        break;
      }
    }
    pieces.push(rest.slice(0, end).trim());
    rest = rest.slice(end).trimStart();
  }
  if (rest) pieces.push(rest);
  return pieces;
}
