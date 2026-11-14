// Drives the built extension in real browsers against a real llama-server.
//   PLAMO_URL, PLAMO_API_KEY: the running server, started with a short PLAMO_IDLE_SECONDS
//   CHROME_BIN, CHROMEDRIVER, FIREFOX_BIN, GECKODRIVER: browser binaries
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { By, until, type WebDriver } from "selenium-webdriver";
import { startChrome, startFirefox, type ExtensionSession } from "./browsers";

const serverUrl = process.env.PLAMO_URL ?? "http://127.0.0.1:8000";
const apiKey = process.env.PLAMO_API_KEY ?? "";
const JAPANESE = /[ぁ-んァ-ヶ一-龠]/;
const PLAIN = "The meeting has been rescheduled to next Monday.";

const FIXTURE = `<!doctype html><html lang="en"><body>
  <p id="plain">${PLAIN}</p>
  <p id="mixed">Please read <a id="link" href="#">the manual</a> before you start.</p>
  <p id="with-icon">Please read the <img id="icon" alt="manual icon" src="data:image/gif;base64,R0lGODlhAQABAAAAACw="> manual before you start.</p>
  <div id="labels"><a id="label-a" href="#one">Detect changes</a> <a id="label-b" href="#two">Show more</a></div>
  <p id="file-name"><a id="file-link" href="#three">assets</a></p>
  <pre id="pre">const untouched = "code stays";</pre>
  <p id="opt-out" translate="no">Brand name stays</p>
  <div id="late"></div>
  <script>
    setTimeout(() => {
      document.querySelector("#late").innerHTML = '<p id="late-text">This paragraph appeared later.</p>';
    }, 500);
  </script>
</body></html>`;

let fixtureServer: Server;
let fixtureUrl: string;

beforeAll(async () => {
  fixtureServer = createServer((_request, response) => {
    response.setHeader("Content-Type", "text/html; charset=utf-8");
    response.end(FIXTURE);
  });
  await new Promise<void>((done) => fixtureServer.listen(0, "127.0.0.1", done));
  fixtureUrl = `http://127.0.0.1:${(fixtureServer.address() as AddressInfo).port}/`;
});

afterAll(() => {
  fixtureServer.close();
});

async function textOf(driver: WebDriver, id: string): Promise<string> {
  return (await driver.findElement(By.id(id)).getAttribute("textContent")) ?? "";
}

async function waitForText(driver: WebDriver, id: string, pattern: RegExp): Promise<string> {
  let seen: string | null = null;
  await driver.wait(
    async () => {
      seen = await driver.executeScript<string | null>(`return document.getElementById(${JSON.stringify(id)})?.textContent ?? null;`);
      return seen !== null && pattern.test(seen);
    },
    120_000,
    `#${id} never matched ${pattern}`,
  );
  return seen!;
}

async function saveOptions(session: ExtensionSession, url: string, key: string): Promise<void> {
  const { driver, baseUrl } = session;
  await driver.get(`${baseUrl}/options.html`);
  const urlField = await driver.wait(until.elementLocated(By.id("server-url")), 10_000);
  await driver.wait(async () => (await urlField.getAttribute("value")) !== "", 10_000);
  await urlField.clear();
  await urlField.sendKeys(url);
  const keyField = await driver.findElement(By.id("api-key"));
  await keyField.clear();
  if (key) await keyField.sendKeys(key);
  await driver.executeScript("document.querySelector('#error').textContent = ''");
  await driver.findElement(By.id("save")).click();
}

async function waitForStatus(driver: WebDriver, state: string): Promise<void> {
  const status = await driver.wait(until.elementLocated(By.id("server-status")), 10_000);
  await driver.wait(async () => (await status.getAttribute("data-state")) === state, 60_000, `status never became ${state}`);
}

/** Sends a command to the background script from an extension page, returning its response. */
function sendToBackground(driver: WebDriver, message: object): Promise<unknown> {
  return driver.executeAsyncScript(
    "const [message, done] = arguments; chrome.runtime.sendMessage(message).then(done, (e) => done({ error: String(e) }));",
    message,
  );
}

/** Opens the fixture next to the current extension page; returns both window handles and the tab id. */
async function openFixture(session: ExtensionSession) {
  const { driver, baseUrl } = session;
  await driver.get(`${baseUrl}/popup.html`);
  const extensionHandle = await driver.getWindowHandle();
  await driver.switchTo().newWindow("tab");
  const pageHandle = await driver.getWindowHandle();
  await driver.get(fixtureUrl);
  await driver.switchTo().window(extensionHandle);
  const tabId = (await driver.executeAsyncScript(
    "const [url, done] = arguments; chrome.tabs.query({}).then((tabs) => done(tabs.find((tab) => tab.url === url).id));",
    fixtureUrl,
  )) as number;
  return { extensionHandle, pageHandle, tabId };
}

describe.each([
  ["chrome", startChrome],
  ["firefox", startFirefox],
] as const)("%s", (_browser, start) => {
  let session: ExtensionSession;
  let driver: WebDriver;

  beforeAll(async () => {
    session = await start();
    driver = session.driver;
    await driver.manage().setTimeouts({ script: 170_000 });
  });

  afterAll(async () => {
    await driver?.quit();
    await session?.cleanup?.();
  });

  it("rejects a wrong API key", async () => {
    if (!apiKey) return;
    await saveOptions(session, serverUrl, "wrong-key");
    await expect(waitForText(driver, "error", /API キー/)).resolves.toMatch(/API キー/);
    await waitForStatus(driver, "unauthorized");
  });

  it("reports an unreachable server", async () => {
    await saveOptions(session, "http://127.0.0.1:1", apiKey);
    await expect(waitForText(driver, "error", /接続できません/)).resolves.toMatch(/接続できません/);
    await waitForStatus(driver, "unreachable");
  });

  it("connects with the right settings", async () => {
    await saveOptions(session, serverUrl, apiKey);
    await driver.wait(async () => (await textOf(driver, "error")) === "", 10_000);
    await waitForStatus(driver, "sleeping");
  });

  it("translates the page when asked, replacing the original text", async () => {
    const { extensionHandle, pageHandle, tabId } = await openFixture(session);
    await expect(sendToBackground(driver, { type: "set-page", tabId, active: true })).resolves.toEqual({ active: true });

    await driver.switchTo().window(pageHandle);
    const translated = await waitForText(driver, "plain", JAPANESE);
    expect(translated).toMatch(/月曜/);
    expect(translated).not.toContain("The meeting");
    await waitForText(driver, "mixed", JAPANESE);
    // Prose the page adds later is translated too.
    await waitForText(driver, "late-text", JAPANESE);

    // Code and opted-out blocks keep their text.
    expect(await textOf(driver, "pre")).toBe('const untouched = "code stays";');
    expect(await textOf(driver, "opt-out")).toBe("Brand name stays");

    // Icons keep their alt text and stay in the page.
    expect(await driver.executeScript("return document.querySelector('#icon')?.getAttribute('alt') ?? null")).toBe(
      "manual icon",
    );
    expect(await textOf(driver, "with-icon")).not.toContain("manual icon");

    // Labels are translated in place, each keeping its link.
    expect(await textOf(driver, "label-a")).toMatch(JAPANESE);
    expect(await textOf(driver, "label-b")).toMatch(JAPANESE);
    expect(await driver.executeScript("return document.querySelector('#label-a')?.getAttribute('href')")).toBe("#one");
    // A file name in a link is left alone.
    expect(await textOf(driver, "file-link")).toBe("assets");
    expect(await driver.executeScript("return document.querySelector('#file-link')?.getAttribute('href')")).toBe("#three");

    await driver.close();
    await driver.switchTo().window(extensionHandle);
  });

  it("re-translates the page when the target language changes", async () => {
    const { extensionHandle, pageHandle, tabId } = await openFixture(session);
    await expect(sendToBackground(driver, { type: "set-page", tabId, active: true })).resolves.toEqual({ active: true });

    await driver.switchTo().window(pageHandle);
    const japanese = await waitForText(driver, "plain", JAPANESE);

    await driver.switchTo().window(extensionHandle);
    await driver.executeScript("return chrome.storage.local.set({ target: 'fr' })");
    await expect(sendToBackground(driver, { type: "retranslate", tabId })).resolves.toEqual({ active: true });

    await driver.switchTo().window(pageHandle);
    await driver.wait(
      async () => {
        const text = await textOf(driver, "plain");
        return text !== japanese && text !== PLAIN;
      },
      120_000,
      "the page kept the old translation",
    );

    await driver.switchTo().window(extensionHandle);
    await driver.executeScript("return chrome.storage.local.set({ target: 'ja' })");

    await driver.switchTo().window(pageHandle);
    await driver.close();
    await driver.switchTo().window(extensionHandle);
  });

  it("shows the translation of a selection in an overlay", async () => {
    const { extensionHandle, pageHandle, tabId } = await openFixture(session);

    await sendToBackground(driver, { type: "translate-selection", tabId, text: "The meeting has been rescheduled to next Monday." });

    await driver.switchTo().window(pageHandle);
    const translation = await driver.wait(async () => {
      const text = (await driver.executeScript(
        "const card = document.querySelector('#kotoba-overlay')?.shadowRoot.querySelector('.card');" +
          "return card?.dataset.state === 'done' ? card.textContent : null;",
      )) as string | null;
      return text;
    }, 120_000);
    expect(translation).toMatch(/月曜/);

    await driver.close();
    await driver.switchTo().window(extensionHandle);
  });

  it("restores the original text", async () => {
    const { extensionHandle, pageHandle, tabId } = await openFixture(session);
    await expect(sendToBackground(driver, { type: "set-page", tabId, active: true })).resolves.toEqual({ active: true });

    await driver.switchTo().window(pageHandle);
    await waitForText(driver, "plain", /月曜/);
    await driver.switchTo().window(extensionHandle);

    await expect(sendToBackground(driver, { type: "set-page", tabId, active: false })).resolves.toEqual({ active: false });

    await driver.switchTo().window(pageHandle);
    expect(await textOf(driver, "plain")).toBe(PLAIN);
    expect(await textOf(driver, "mixed")).toBe("Please read the manual before you start.");
    expect(await textOf(driver, "label-a")).toBe("Detect changes");
    expect(await driver.executeScript("return document.querySelector('#link')?.textContent ?? null")).toBe("the manual");

    // Reloading the page does not translate it by itself.
    await driver.navigate().refresh();
    await driver.sleep(3000);
    expect(await textOf(driver, "plain")).toBe(PLAIN);

    await driver.close();
    await driver.switchTo().window(extensionHandle);
  });

  it("remembers the chosen target language", async () => {
    await driver.get(`${session.baseUrl}/popup.html`);
    const target = await driver.wait(until.elementLocated(By.id("target")), 10_000);
    await driver.wait(async () => (await target.getAttribute("value")) === "ja", 10_000);

    await target.findElement(By.css('option[value="en"]')).click();
    await driver.navigate().refresh();

    const reloaded = await driver.wait(until.elementLocated(By.id("target")), 10_000);
    await driver.wait(async () => (await reloaded.getAttribute("value")) === "en", 10_000);
    await reloaded.findElement(By.css('option[value="ja"]')).click();
  });
});
