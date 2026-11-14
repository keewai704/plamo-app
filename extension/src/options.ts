import { STATUS_ERRORS } from "./lib/client";
import { loadSettings, saveSettings, type Form, type Settings } from "./lib/settings";
import { StatusView } from "./lib/status-view";

const form = document.querySelector<HTMLFormElement>("#form")!;
const serverUrl = document.querySelector<HTMLInputElement>("#server-url")!;
const apiKey = document.querySelector<HTMLInputElement>("#api-key")!;
const auto = document.querySelector<HTMLInputElement>("#auto")!;
const error = document.querySelector<HTMLOutputElement>("#error")!;
const status = new StatusView(document.querySelector<HTMLElement>("#server-status")!);

const ALL_SITES: chrome.permissions.Permissions = {
  origins: ["http://*/*", "https://*/*"],
};

const permissions = (
  globalThis as {
    browser?: { permissions: { request: (requested: chrome.permissions.Permissions) => Promise<boolean> } };
  }
).browser?.permissions;

function requestAllSites(): Promise<boolean> {
  return permissions ? permissions.request(ALL_SITES) : chrome.permissions.request(ALL_SITES);
}

function validServerUrl(value: string): boolean {
  try {
    const { protocol } = new URL(value);
    return protocol === "http:" || protocol === "https:";
  } catch {
    return false;
  }
}

async function finishSave(
  values: Pick<Settings, "serverUrl" | "apiKey" | "form" | "autoTranslate">,
  granted: Promise<boolean>,
): Promise<void> {
  if (!(await granted)) {
    error.textContent = "すべてのサイトへのアクセスが許可されていません。もう一度保存してください";
    return;
  }
  await saveSettings({ ...values, configured: true });
  error.textContent = STATUS_ERRORS[await status.refresh()] ?? "";
}

form.addEventListener("submit", (event) => {
  event.preventDefault();
  const url = serverUrl.value.trim();
  if (!validServerUrl(url)) {
    error.textContent = "URL が正しくありません";
    return;
  }
  const style = form.querySelector<HTMLInputElement>('input[name="style"]:checked')!;
  const granted = requestAllSites().catch(() => false);
  void finishSave(
    {
      serverUrl: url,
      apiKey: apiKey.value.trim(),
      form: style.value as Form,
      autoTranslate: auto.checked,
    },
    granted,
  );
});

void loadSettings().then((settings) => {
  serverUrl.value = settings.serverUrl;
  apiKey.value = settings.apiKey;
  auto.checked = settings.autoTranslate;
  form.querySelector<HTMLInputElement>(`input[name="style"][value="${settings.form}"]`)!.checked = true;
});
