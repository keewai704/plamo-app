export type Form = "" | "polite" | "plain";

export interface Settings {
  serverUrl: string;
  apiKey: string;
  /** A language code, or "auto" to switch between Japanese and English. */
  target: string;
  form: Form;
}

export const DEFAULT_SETTINGS: Settings = {
  serverUrl: "http://127.0.0.1:8000",
  apiKey: "",
  target: "ja",
  form: "",
};

export async function loadSettings(): Promise<Settings> {
  const stored = await chrome.storage.local.get(Object.keys(DEFAULT_SETTINGS));
  return { ...DEFAULT_SETTINGS, ...stored };
}

export async function saveSettings(settings: Partial<Settings>): Promise<void> {
  await chrome.storage.local.set(settings);
}
