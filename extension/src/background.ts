import { translate } from "./lib/client";
import type { BackgroundMessage, ContentMessage, PageState, TranslateResult } from "./lib/messages";
import { loadSettings } from "./lib/settings";

const MENU_SELECTION = "translate-selection";
const MENU_PAGE = "toggle-page";

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({ id: MENU_SELECTION, title: "選択範囲を翻訳", contexts: ["selection"] });
  chrome.contextMenus.create({ id: MENU_PAGE, title: "ページを翻訳 / 原文に戻す", contexts: ["page"] });
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (tab?.id === undefined) return;
  if (info.menuItemId === MENU_SELECTION) {
    void showSelection(tab.id, info.frameId, info.selectionText ?? "");
  } else if (info.menuItemId === MENU_PAGE) {
    void togglePage(tab.id);
  }
});

async function showSelection(tabId: number, frameId: number | undefined, text: string): Promise<void> {
  const frameIds = frameId === undefined ? undefined : [frameId];
  await chrome.scripting.executeScript({ target: { tabId, frameIds }, files: ["content.js"] });
  const message: ContentMessage = { type: "show-selection", text };
  await chrome.tabs.sendMessage(tabId, message, frameId === undefined ? {} : { frameId });
}

async function togglePage(tabId: number): Promise<PageState> {
  await chrome.scripting.executeScript({ target: { tabId }, files: ["content.js"] });
  const message: ContentMessage = { type: "toggle-page" };
  return chrome.tabs.sendMessage(tabId, message, { frameId: 0 });
}

async function translateMessage(text: string, context?: string): Promise<TranslateResult> {
  try {
    return { ok: true, text: await translate(await loadSettings(), text, { context }) };
  } catch (error) {
    return { ok: false, error: error instanceof Error ? error.message : String(error) };
  }
}

function handle(message: BackgroundMessage): Promise<unknown> {
  switch (message.type) {
    case "translate":
      return translateMessage(message.text, message.context);
    case "toggle-page":
      return togglePage(message.tabId);
    case "translate-selection":
      return showSelection(message.tabId, message.frameId, message.text);
  }
}

chrome.runtime.onMessage.addListener((message: BackgroundMessage, _sender, sendResponse) => {
  handle(message).then(sendResponse, (error: unknown) =>
    sendResponse({ error: error instanceof Error ? error.message : String(error) }),
  );
  return true;
});
