import { translate } from "./lib/client";
import { populateTargets } from "./lib/languages";
import type { BackgroundMessage, ContentMessage, PageState } from "./lib/messages";
import { loadSettings, saveSettings } from "./lib/settings";
import { StatusView } from "./lib/status-view";

const source = document.querySelector<HTMLTextAreaElement>("#source")!;
const target = document.querySelector<HTMLSelectElement>("#target")!;
const translateButton = document.querySelector<HTMLButtonElement>("#translate")!;
const stopButton = document.querySelector<HTMLButtonElement>("#stop")!;
const output = document.querySelector<HTMLOutputElement>("#output")!;
const copyButton = document.querySelector<HTMLButtonElement>("#copy")!;
const pageButton = document.querySelector<HTMLButtonElement>("#page")!;
const settingsButton = document.querySelector<HTMLButtonElement>("#settings")!;
const status = new StatusView(document.querySelector<HTMLElement>("#server-status")!);

let running: AbortController | undefined;

async function activeTabId(): Promise<number | undefined> {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  return tab?.id;
}

function showPageState(active: boolean): void {
  pageButton.setAttribute("aria-pressed", String(active));
}

async function refreshPageState(): Promise<void> {
  const tabId = await activeTabId();
  if (tabId === undefined) return;
  const message: ContentMessage = { type: "page-state" };
  // Rejects when the content script has not been injected yet.
  const state: PageState | undefined = await chrome.tabs.sendMessage(tabId, message, { frameId: 0 }).catch(() => undefined);
  showPageState(state?.active ?? false);
}

function showOutput(state: "idle" | "loading" | "done" | "error", text: string): void {
  output.dataset.state = state;
  output.textContent = text;
  copyButton.hidden = state !== "done";
}

function setRunning(controller: AbortController | undefined): void {
  running = controller;
  translateButton.hidden = controller !== undefined;
  stopButton.hidden = controller === undefined;
  status.setTranslating(controller !== undefined);
}

async function translateSource(): Promise<void> {
  const text = source.value.trim();
  if (!text || running) return;

  const controller = new AbortController();
  setRunning(controller);
  showOutput("loading", "");
  try {
    const translated = await translate(await loadSettings(), text, {
      signal: controller.signal,
      onProgress: (partial) => {
        output.textContent = partial;
      },
    });
    showOutput("done", translated);
  } catch (error) {
    if (controller.signal.aborted) showOutput("idle", "");
    else showOutput("error", error instanceof Error ? error.message : String(error));
  } finally {
    setRunning(undefined);
    void status.refresh();
  }
}

async function togglePage(): Promise<void> {
  const tabId = await activeTabId();
  if (tabId === undefined) return;
  const message: BackgroundMessage = { type: "toggle-page", tabId };
  const state: PageState & { error?: string } = await chrome.runtime.sendMessage(message);
  if (state.error) {
    showOutput("error", "このページは翻訳できません");
    return;
  }
  showPageState(state.active);
}

translateButton.addEventListener("click", () => void translateSource());
stopButton.addEventListener("click", () => running?.abort());
source.addEventListener("keydown", (event) => {
  if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) void translateSource();
});
copyButton.addEventListener("click", () => void navigator.clipboard.writeText(output.textContent ?? ""));
target.addEventListener("change", () => void saveSettings({ target: target.value }));
pageButton.addEventListener("click", () => void togglePage());
settingsButton.addEventListener("click", () => void chrome.runtime.openOptionsPage());

populateTargets(target);
void loadSettings().then((settings) => {
  target.value = settings.target;
});
void refreshPageState();
source.focus();
