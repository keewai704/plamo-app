/** Handled by the background script. */
export type BackgroundMessage =
  | { type: "translate"; text: string; context?: string }
  | { type: "toggle-page"; tabId: number }
  | { type: "translate-selection"; tabId: number; frameId?: number; text: string };

/** Handled by the content script. */
export type ContentMessage = { type: "toggle-page" } | { type: "page-state" } | { type: "show-selection"; text: string };

export type TranslateResult = { ok: true; text: string } | { ok: false; error: string };
export type PageState = { active: boolean };
