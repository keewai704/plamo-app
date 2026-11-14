import { populateTargets } from "./lib/languages";
import type { BackgroundMessage, PageState } from "./lib/messages";
import { loadSettings, saveSettings } from "./lib/settings";
import { StatusView } from "./lib/status-view";

const target = document.querySelector<HTMLSelectElement>("#target")!;
const pageButton = document.querySelector<HTMLButtonElement>("#page")!;
const pageLabel = document.querySelector<HTMLElement>("#page-label")!;
const note = document.querySelector<HTMLParagraphElement>("#note")!;
const settingsButton = document.querySelector<HTMLButtonElement>("#settings")!;
new StatusView(document.querySelector<HTMLElement>("#server-status")!);

async function activeTab(): Promise<chrome.tabs.Tab | undefined> {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  return tab;
}

function originOf(url: string | undefined): string | undefined {
  try {
    return url ? new URL(url).origin : undefined;
  } catch {
    return undefined;
  }
}

function showNote(text: string): void {
  note.textContent = text;
  note.hidden = !text;
}

function renderPage(active: boolean): void {
  pageButton.setAttribute("aria-pressed", String(active));
  pageLabel.textContent = active ? "原文に戻す" : "このページを翻訳";
}

async function pageState(tabId: number): Promise<boolean> {
  const state: { active?: boolean } | undefined = await chrome.tabs
    .sendMessage(tabId, { type: "page-state" }, { frameId: 0 })
    .catch(() => undefined);
  return state?.active ?? false;
}

async function refresh(): Promise<void> {
  const settings = await loadSettings();
  target.value = settings.target;

  const tab = await activeTab();
  const origin = originOf(tab?.url);
  if (tab?.id === undefined || origin === undefined) {
    pageButton.disabled = true;
    renderPage(false);
    showNote("このページは翻訳できません");
    return;
  }

  renderPage(await pageState(tab.id));
  showNote("");
}

async function togglePage(): Promise<void> {
  const tab = await activeTab();
  if (tab?.id === undefined) return;
  const active = pageButton.getAttribute("aria-pressed") === "true";
  const message: BackgroundMessage = { type: "set-page", tabId: tab.id, active: !active };
  const state: PageState = await chrome.runtime.sendMessage(message);
  if (state.error) {
    pageButton.disabled = true;
    showNote("このページは翻訳できません");
    return;
  }
  renderPage(state.active);
  showNote("");
}

async function changeTarget(): Promise<void> {
  await saveSettings({ target: target.value });
  if (pageButton.getAttribute("aria-pressed") !== "true") return;
  const tab = await activeTab();
  if (tab?.id === undefined) return;
  const message: BackgroundMessage = { type: "retranslate", tabId: tab.id };
  const state: PageState = await chrome.runtime.sendMessage(message);
  if (state.error) showNote(state.error);
  else renderPage(state.active);
}

target.addEventListener("change", () => void changeTarget());
pageButton.addEventListener("click", () => void togglePage());
settingsButton.addEventListener("click", () => void chrome.runtime.openOptionsPage());

populateTargets(target);
void refresh();
