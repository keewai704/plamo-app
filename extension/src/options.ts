import { STATUS_ERRORS } from "./lib/client";
import { loadSettings, saveSettings, type Form, type Settings } from "./lib/settings";
import { StatusView } from "./lib/status-view";

const form = document.querySelector<HTMLFormElement>("#form")!;
const serverUrl = document.querySelector<HTMLInputElement>("#server-url")!;
const apiKey = document.querySelector<HTMLInputElement>("#api-key")!;
const error = document.querySelector<HTMLOutputElement>("#error")!;
const status = new StatusView(document.querySelector<HTMLElement>("#server-status")!);

// Firefox only promises the WebExtension namespace versions of these calls.
const permissions = (
  globalThis as {
    browser?: { permissions: { request: (requested: chrome.permissions.Permissions) => Promise<boolean> } };
  }
).browser?.permissions;

function requestOrigin(origin: string): Promise<boolean> {
  const requested = { origins: [origin] };
  return permissions ? permissions.request(requested) : chrome.permissions.request(requested);
}

function originPattern(url: string): string | undefined {
  try {
    const { protocol, hostname } = new URL(url);
    return protocol === "http:" || protocol === "https:" ? `${protocol}//${hostname}/*` : undefined;
  } catch {
    return undefined;
  }
}

async function finishSave(values: Pick<Settings, "serverUrl" | "apiKey" | "form">, granted: Promise<boolean>): Promise<void> {
  if (!(await granted.catch(() => false))) {
    error.textContent = "サーバーへのアクセスが許可されていません";
    return;
  }
  await saveSettings(values);
  error.textContent = STATUS_ERRORS[await status.refresh()] ?? "";
}

form.addEventListener("submit", (event) => {
  event.preventDefault();
  const url = serverUrl.value.trim();
  const origin = originPattern(url);
  if (!origin) {
    error.textContent = "URL が正しくありません";
    return;
  }
  const style = form.querySelector<HTMLInputElement>('input[name="style"]:checked')!;
  // permissions.request must run synchronously inside the user gesture.
  const granted = requestOrigin(origin);
  void finishSave({ serverUrl: url, apiKey: apiKey.value.trim(), form: style.value as Form }, granted);
});

void loadSettings().then((settings) => {
  serverUrl.value = settings.serverUrl;
  apiKey.value = settings.apiKey;
  form.querySelector<HTMLInputElement>(`input[name="style"][value="${settings.form}"]`)!.checked = true;
});
