import { chunkText } from "./chunk";
import type { Settings } from "./settings";

const MAX_OUTPUT_TOKENS = 2048;

export type ServerStatus = "ready" | "sleeping" | "loading" | "unauthorized" | "unreachable";

export const STATUS_ERRORS: Partial<Record<ServerStatus, string>> = {
  unauthorized: "API キーが正しくありません",
  unreachable: "サーバーに接続できません",
};

export class TranslationError extends Error {}

export interface TranslateOptions {
  context?: string;
  signal?: AbortSignal;
  /** Called with the translation so far, after each chunk. */
  onProgress?: (translated: string) => void;
}

function endpoint(settings: Settings, path: string): string {
  return `${settings.serverUrl.replace(/\/+$/, "")}${path}`;
}

function headers(settings: Settings): Record<string, string> {
  return {
    "Content-Type": "application/json",
    ...(settings.apiKey ? { Authorization: `Bearer ${settings.apiKey}` } : {}),
  };
}

async function request(url: string, init: RequestInit): Promise<Response> {
  let response: Response;
  try {
    response = await fetch(url, init);
  } catch (error) {
    if (init.signal?.aborted) throw error;
    throw new TranslationError(STATUS_ERRORS.unreachable);
  }
  if (response.status === 401) throw new TranslationError(STATUS_ERRORS.unauthorized);
  if (!response.ok) {
    const body = await response.json().catch(() => undefined);
    throw new TranslationError(body?.error?.message ?? `サーバーエラー (${response.status})`);
  }
  return response;
}

function templateOptions(settings: Settings, context?: string): Record<string, string> {
  const options: Record<string, string> = {};
  if (settings.target !== "auto") options.target_lang = settings.target;
  if (settings.target === "ja" && settings.form) options.form = settings.form;
  if (context) options.context = context;
  return options;
}

async function translateChunk(settings: Settings, text: string, options: TranslateOptions): Promise<string> {
  const response = await request(endpoint(settings, "/v1/chat/completions"), {
    method: "POST",
    headers: headers(settings),
    signal: options.signal,
    body: JSON.stringify({
      model: "plamo-3-translate",
      messages: [{ role: "user", content: text }],
      chat_template_kwargs: templateOptions(settings, options.context),
      temperature: 0,
      max_tokens: MAX_OUTPUT_TOKENS,
      stop: ["<|plamo:tag|>", "<|plamo:bos|>"],
    }),
  });
  const choice = (await response.json()).choices[0];
  if (choice.finish_reason === "length") throw new TranslationError("訳文が長すぎて途中で打ち切られました");
  return choice.message.content;
}

export async function translate(settings: Settings, text: string, options: TranslateOptions = {}): Promise<string> {
  const translated: string[] = [];
  for (const chunk of chunkText(text)) {
    translated.push(await translateChunk(settings, chunk, options));
    options.onProgress?.(translated.join("\n"));
  }
  return translated.join("\n");
}

/** Reports whether the weights are loaded. Neither request wakes a sleeping server. */
export async function fetchStatus(settings: Settings): Promise<ServerStatus> {
  try {
    const health = await fetch(endpoint(settings, "/health"));
    if (health.status === 503) return "loading";
    if (!health.ok) return "unreachable";

    const props = await fetch(endpoint(settings, "/props"), { headers: headers(settings) });
    if (props.status === 401) return "unauthorized";
    if (!props.ok) return "unreachable";
    return (await props.json()).is_sleeping ? "sleeping" : "ready";
  } catch {
    return "unreachable";
  }
}
