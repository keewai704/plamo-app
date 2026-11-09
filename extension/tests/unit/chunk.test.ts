import { describe, expect, it } from "vitest";
import { chunkText } from "../../src/lib/chunk";

describe("chunkText", () => {
  it("returns nothing for blank input", () => {
    expect(chunkText(" \n\r\n ")).toEqual([]);
  });

  it("keeps short paragraphs together and normalizes newlines", () => {
    expect(chunkText("  一行目\r\n\r\n二行目  ")).toEqual(["一行目\n二行目"]);
  });

  it("starts a new chunk when the next paragraph would overflow", () => {
    expect(chunkText("aaaa\nbbbb\ncc", 9)).toEqual(["aaaa\nbbbb", "cc"]);
  });

  it("splits long paragraphs at the last sentence boundary", () => {
    expect(chunkText("あいう。えおか。きくけこ", 9)).toEqual(["あいう。えおか。", "きくけこ"]);
  });

  it("cuts text without boundaries at the limit", () => {
    const chunks = chunkText("x".repeat(25), 10);
    expect(chunks.map((chunk) => chunk.length)).toEqual([10, 10, 5]);
  });

  it("never exceeds the limit", () => {
    const text = Array.from({ length: 200 }, (_, i) => `Sentence number ${i}.`).join(" ");
    for (const chunk of chunkText(text, 100)) expect(chunk.length).toBeLessThanOrEqual(100);
  });
});
