import { describe, expect, it } from "vitest";
import { looksJapanese, needsTranslation } from "../../src/lib/language";

describe("needsTranslation", () => {
  it("leaves Japanese prose alone when the target is Japanese", () => {
    expect(needsTranslation("会議は来週の月曜日に変更されました。", "ja")).toBe(false);
  });

  it("translates English prose into Japanese", () => {
    expect(needsTranslation("The meeting has been rescheduled to next Monday.", "ja")).toBe(true);
  });

  it("does not treat a kanji-only name as Japanese prose", () => {
    expect(looksJapanese("東京")).toBe(false);
    expect(needsTranslation("東京", "ja")).toBe(true);
  });

  it("translates into English only what is not already English", () => {
    expect(needsTranslation("会議は月曜日です。", "en")).toBe(true);
    expect(needsTranslation("The meeting is on Monday.", "en")).toBe(false);
  });

  it("sends every block when switching between Japanese and English", () => {
    expect(needsTranslation("The meeting is on Monday.", "auto")).toBe(true);
    expect(needsTranslation("会議は月曜日です。", "auto")).toBe(true);
  });

  it("sends every block for other targets", () => {
    expect(needsTranslation("会議は月曜日です。", "fr")).toBe(true);
  });
});
