import codes from "../../../ios/KotobaCore/Sources/KotobaCore/Resources/languages.json";

/** Fills a <select> with the target languages, named in the browser's language. */
export function populateTargets(select: HTMLSelectElement): void {
  const names = new Intl.DisplayNames([navigator.language], { type: "language", fallback: "code" });
  select.add(new Option("日本語 ⇄ 英語", "auto"));
  for (const code of codes) {
    select.add(new Option(names.of(code) ?? code, code));
  }
}
