export type Form = "" | "polite" | "plain";

export interface Settings {
  serverUrl: string;
  apiKey: string;
  /** A language code, or "auto" to switch between Japanese and English. */
  target: string;
  form: Form;
  /** Translate pages as they open, unless the site is excluded. */
  autoTranslate: boolean;
  /** Set once a server has been saved; automatic translation waits for it. */
  configured: boolean;
  /** Origins to leave alone when a page opens. */
  excludedOrigins: string[];
}

export const DEFAULT_SETTINGS: Settings = {
  serverUrl: "http://127.0.0.1:8000",
  apiKey: "",
  target: "ja",
  form: "",
  autoTranslate: true,
  configured: false,
  excludedOrigins: [],
};

export async function loadSettings(): Promise<Settings> {
  const stored = await chrome.storage.local.get(Object.keys(DEFAULT_SETTINGS));
  return { ...DEFAULT_SETTINGS, ...stored };
}

export async function saveSettings(settings: Partial<Settings>): Promise<void> {
  await chrome.storage.local.set(settings);
}

/** Remembers whether pages on this origin should open translated. */
export async function setOriginAuto(origin: string, auto: boolean): Promise<void> {
  const { excludedOrigins } = await loadSettings();
  const next = new Set(excludedOrigins);
  if (auto) next.delete(origin);
  else next.add(origin);
  await saveSettings({ excludedOrigins: [...next] });
}
