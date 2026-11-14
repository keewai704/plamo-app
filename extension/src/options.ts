import { STATUS_ERRORS } from "./lib/client";
import { loadSettings, saveSettings, type Form, type Settings } from "./lib/settings";
import { StatusView } from "./lib/status-view";

const form = document.querySelector<HTMLFormElement>("#form")!;
const serverUrl = document.querySelector<HTMLInputElement>("#server-url")!;
const apiKey = document.querySelector<HTMLInputElement>("#api-key")!;
const auto = document.querySelector<HTMLInputElement>("#auto")!;
const error = document.querySelector<HTMLOutputElement>("#error")!;
const status = new StatusView(document.querySelector<HTMLElement>("#server-status")!);

function validServerUrl(value: string): boolean {
  try {
    const { protocol } = new URL(value);
    return protocol === "http:" || protocol === "https:";
  } catch {
    return false;
  }
}

async function finishSave(values: Pick<Settings, "serverUrl" | "apiKey" | "form" | "autoTranslate">): Promise<void> {
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
  void finishSave({
    serverUrl: url,
    apiKey: apiKey.value.trim(),
    form: style.value as Form,
    autoTranslate: auto.checked,
  });
});

void loadSettings().then((settings) => {
  serverUrl.value = settings.serverUrl;
  apiKey.value = settings.apiKey;
  auto.checked = settings.autoTranslate;
  form.querySelector<HTMLInputElement>(`input[name="style"][value="${settings.form}"]`)!.checked = true;
});
