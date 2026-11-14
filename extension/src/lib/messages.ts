/** Handled by the background script. */
export type BackgroundMessage =
  | { type: "translate"; text: string }
  | { type: "set-page"; tabId: number; active: boolean }
  | { type: "toggle-page"; tabId: number }
  | { type: "retranslate"; tabId: number }
  | { type: "page-state"; tabId: number }
  | { type: "translate-selection"; tabId: number; frameId?: number; text: string };

/** Handled by the content script. */
export type ContentMessage =
  | { type: "set-page"; active: boolean }
  | { type: "toggle-page" }
  | { type: "retranslate" }
  | { type: "page-state" }
  | { type: "show-selection"; text: string };

export type TranslateResult = { ok: true; text: string } | { ok: false; error: string };
export type PageState = { active: boolean; error?: string };
