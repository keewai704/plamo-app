import { afterEach, describe, expect, it, vi } from "vitest";
import { fetchStatus, translate } from "../../src/lib/client";
import { DEFAULT_SETTINGS, type Settings } from "../../src/lib/settings";

const settings: Settings = { ...DEFAULT_SETTINGS, serverUrl: "http://server:8000/", apiKey: "secret" };

function completion(content: string, finishReason = "stop"): Response {
  return Response.json({ choices: [{ message: { content }, finish_reason: finishReason }] });
}

function stubFetch(...responses: Response[]) {
  const mock = vi.fn<typeof fetch>();
  for (const response of responses) mock.mockResolvedValueOnce(response);
  vi.stubGlobal("fetch", mock);
  return mock;
}

function sentBody(mock: ReturnType<typeof stubFetch>, call = 0) {
  return JSON.parse(mock.mock.calls[call]![1]!.body as string);
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("translate", () => {
  it("posts the chat completion request the model expects", async () => {
    const mock = stubFetch(completion("Hello"));

    await expect(translate(settings, "こんにちは")).resolves.toBe("Hello");

    const [url, init] = mock.mock.calls[0]!;
    expect(url).toBe("http://server:8000/v1/chat/completions");
    expect(init!.headers).toMatchObject({ Authorization: "Bearer secret" });
    expect(sentBody(mock)).toMatchObject({
      messages: [{ role: "user", content: "こんにちは" }],
      chat_template_kwargs: { target_lang: "ja" },
      temperature: 0,
      stop: ["<|plamo:tag|>", "<|plamo:bos|>"],
    });
  });

  it("omits target_lang in auto mode", async () => {
    const mock = stubFetch(completion("x"));
    await translate({ ...settings, target: "auto", form: "polite" }, "text");
    expect(sentBody(mock).chat_template_kwargs).toEqual({});
  });

  it("sends form only for Japanese output", async () => {
    const mock = stubFetch(completion("x"), completion("y"));
    await translate({ ...settings, target: "ja", form: "polite" }, "text");
    await translate({ ...settings, target: "en", form: "polite" }, "text");
    expect(sentBody(mock, 0).chat_template_kwargs).toEqual({ target_lang: "ja", form: "polite" });
    expect(sentBody(mock, 1).chat_template_kwargs).toEqual({ target_lang: "en" });
  });

  it("passes surrounding context", async () => {
    const mock = stubFetch(completion("x"));
    await translate(settings, "bank", { context: "beside the river bank" });
    expect(sentBody(mock).chat_template_kwargs.context).toBe("beside the river bank");
  });

  it("omits the Authorization header without a key", async () => {
    const mock = stubFetch(completion("x"));
    await translate({ ...settings, apiKey: "" }, "text");
    expect(mock.mock.calls[0]![1]!.headers).not.toHaveProperty("Authorization");
  });

  it("translates long text chunk by chunk, in order", async () => {
    const mock = stubFetch(completion("one"), completion("two"));
    const text = `${"a".repeat(1000)}\n${"b".repeat(1000)}`;
    await expect(translate(settings, text)).resolves.toBe("one\ntwo");
    expect(mock).toHaveBeenCalledTimes(2);
  });

  it("rejects truncated output instead of returning part of a translation", async () => {
    stubFetch(completion("partial", "length"));
    await expect(translate(settings, "text")).rejects.toThrow("打ち切られました");
  });

  it("reports an unreachable server", async () => {
    vi.stubGlobal("fetch", vi.fn<typeof fetch>().mockRejectedValue(new TypeError("failed")));
    await expect(translate(settings, "text")).rejects.toThrow("接続できません");
  });

  it("reports a rejected API key", async () => {
    stubFetch(new Response("{}", { status: 401 }));
    await expect(translate(settings, "text")).rejects.toThrow("API キー");
  });

  it("surfaces the server's error message", async () => {
    stubFetch(Response.json({ error: { message: "bad input" } }, { status: 400 }));
    await expect(translate(settings, "text")).rejects.toThrow("bad input");
  });
});

describe("translate progress and cancellation", () => {
  it("reports the translation after each chunk", async () => {
    stubFetch(completion("one"), completion("two"));
    const seen: string[] = [];
    await translate(settings, `${"a".repeat(1000)}\n${"b".repeat(1000)}`, { onProgress: (text) => seen.push(text) });
    expect(seen).toEqual(["one", "one\ntwo"]);
  });

  it("lets an abort through instead of reporting a connection error", async () => {
    const controller = new AbortController();
    controller.abort();
    const aborted = new DOMException("aborted", "AbortError");
    vi.stubGlobal("fetch", vi.fn<typeof fetch>().mockRejectedValue(aborted));
    await expect(translate(settings, "text", { signal: controller.signal })).rejects.toBe(aborted);
  });
});

describe("fetchStatus", () => {
  const healthy = () => Response.json({ status: "ok" });

  it("is ready when the weights are loaded", async () => {
    const mock = stubFetch(healthy(), Response.json({ is_sleeping: false }));
    await expect(fetchStatus(settings)).resolves.toBe("ready");
    expect(mock.mock.calls[0]![0]).toBe("http://server:8000/health");
    expect(mock.mock.calls[1]![0]).toBe("http://server:8000/props");
    expect(mock.mock.calls[1]![1]!.headers).toMatchObject({ Authorization: "Bearer secret" });
  });

  it("is sleeping when the weights were released", async () => {
    stubFetch(healthy(), Response.json({ is_sleeping: true }));
    await expect(fetchStatus(settings)).resolves.toBe("sleeping");
  });

  it("is ready on a vLLM server, which has no /props", async () => {
    const mock = stubFetch(healthy(), new Response("{}", { status: 404 }), Response.json({ data: [] }));
    await expect(fetchStatus(settings)).resolves.toBe("ready");
    expect(mock.mock.calls[2]![0]).toBe("http://server:8000/v1/models");
    expect(mock.mock.calls[2]![1]!.headers).toMatchObject({ Authorization: "Bearer secret" });
  });

  it("reports a key rejected by a vLLM server", async () => {
    stubFetch(healthy(), new Response("{}", { status: 404 }), new Response("{}", { status: 401 }));
    await expect(fetchStatus(settings)).resolves.toBe("unauthorized");
  });

  it("is loading while /health answers 503", async () => {
    const mock = stubFetch(Response.json({ error: { message: "Loading model" } }, { status: 503 }));
    await expect(fetchStatus(settings)).resolves.toBe("loading");
    expect(mock).toHaveBeenCalledTimes(1);
  });

  it("reports a rejected API key", async () => {
    stubFetch(healthy(), new Response("{}", { status: 401 }));
    await expect(fetchStatus(settings)).resolves.toBe("unauthorized");
  });

  it("reports an unreachable server", async () => {
    vi.stubGlobal("fetch", vi.fn<typeof fetch>().mockRejectedValue(new TypeError("failed")));
    await expect(fetchStatus(settings)).resolves.toBe("unreachable");
  });
});
