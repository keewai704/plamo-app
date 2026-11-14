import { translate } from "./lib/client";
import type { BackgroundMessage, ContentMessage, PageState, TranslateResult } from "./lib/messages";
import { loadSettings } from "./lib/settings";

const MENU_SELECTION = "translate-selection";
const MENU_PAGE = "toggle-page";
const COMMAND_PAGE = "toggle-page";

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

chrome.commands.onCommand.addListener((command) => {
  if (command !== COMMAND_PAGE) return;
  void activeTabId().then((tabId) => (tabId === undefined ? undefined : togglePage(tabId)));
});

async function activeTabId(): Promise<number | undefined> {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  return tab?.id;
}

/** Sends a command to a frame, injecting the content script into pages opened before the install. */
async function sendToFrame<T>(tabId: number, message: ContentMessage, frameId = 0): Promise<T> {
  const options: chrome.tabs.MessageSendOptions = { frameId };
  try {
    return await chrome.tabs.sendMessage(tabId, message, options);
  } catch {
    const target: chrome.scripting.InjectionTarget = frameId === 0 ? { tabId } : { tabId, frameIds: [frameId] };
    await chrome.scripting.executeScript({ target, files: ["content.js"] });
    return chrome.tabs.sendMessage(tabId, message, options);
  }
}

async function pageCommand(tabId: number, message: ContentMessage): Promise<PageState> {
  try {
    return await sendToFrame<PageState>(tabId, message);
  } catch (error) {
    return { active: false, error: error instanceof Error ? error.message : String(error) };
  }
}

function togglePage(tabId: number): Promise<PageState> {
  return pageCommand(tabId, { type: "toggle-page" });
}

async function showSelection(tabId: number, frameId: number | undefined, text: string): Promise<void> {
  const message: ContentMessage = { type: "show-selection", text };
  await sendToFrame(tabId, message, frameId ?? 0);
}

async function translateMessage(text: string): Promise<TranslateResult> {
  try {
    return { ok: true, text: await translate(await loadSettings(), text) };
  } catch (error) {
    return { ok: false, error: error instanceof Error ? error.message : String(error) };
  }
}

function handle(message: BackgroundMessage): Promise<unknown> {
  switch (message.type) {
    case "translate":
      return translateMessage(message.text);
    case "set-page":
      return pageCommand(message.tabId, { type: "set-page", active: message.active });
    case "toggle-page":
      return togglePage(message.tabId);
    case "retranslate":
      return pageCommand(message.tabId, { type: "retranslate" });
    case "page-state":
      return pageCommand(message.tabId, { type: "page-state" });
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
