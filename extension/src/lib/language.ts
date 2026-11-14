const KANA = /[\u3040-\u30ff]/gu;
const CJK = /[\u3040-\u30ff\u3400-\u9fff\uf900-\ufaff]/u;
const LETTER = /\p{L}/gu;

/** True when the text already reads as Japanese: enough kana for the letters it has. */
export function looksJapanese(text: string): boolean {
  const letters = text.match(LETTER)?.length ?? 0;
  if (letters === 0) return false;
  return (text.match(KANA)?.length ?? 0) / letters >= 0.2;
}

/**
 * Whether the server can change this text. Saves the requests that would only send a
 * page back as it is when the reader already reads its language.
 */
export function needsTranslation(text: string, target: string): boolean {
  if (target === "ja") return !looksJapanese(text);
  if (target === "en") return CJK.test(text);
  return true;
}
