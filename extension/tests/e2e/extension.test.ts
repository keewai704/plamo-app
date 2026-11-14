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

const FIXTURE = `<!doctype html><html lang="en"><body>
  <p id="plain">The meeting has been rescheduled to next Monday.</p>
  <p id="mixed">Please read <a id="link" href="#">the manual</a> before you start.</p>
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
  await driver.wait(async () => pattern.test(await textOf(driver, id)), 120_000, `#${id} never matched ${pattern}`);
  return textOf(driver, id);
}

/** The translation added below the block, or null when there is none. */
function translationOf(driver: WebDriver, selector: string): Promise<string | null> {
  return driver.executeScript<string | null>(
    `return document.querySelector(${JSON.stringify(`${selector} .kotoba-tr`)})?.textContent ?? null;`,
  );
}

async function waitForTranslation(driver: WebDriver, selector: string, pattern: RegExp): Promise<string> {
  let seen: string | null = null;
  await driver.wait(
    async () => {
      seen = await translationOf(driver, selector);
      return seen !== null && pattern.test(seen);
    },
    120_000,
    `${selector} was never translated`,
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

  it("translates a page as it opens, below the original", async () => {
    const { extensionHandle, pageHandle } = await openFixture(session);
    await driver.switchTo().window(pageHandle);

    await expect(waitForTranslation(driver, "#plain", JAPANESE)).resolves.toMatch(/月曜/);
    await waitForTranslation(driver, "#mixed", JAPANESE);
    // Prose the page adds later is translated too.
    await waitForTranslation(driver, "#late-text", JAPANESE);

    // The original stays where it was, and links keep their own text.
    expect(await driver.executeScript<string>("return document.querySelector('#plain').firstChild.textContent")).toContain(
      "The meeting has been rescheduled",
    );
    expect(await driver.executeScript<string>("return document.querySelector('#link').textContent")).toBe("the manual");
    // Code and opted-out blocks are left alone.
    expect(await translationOf(driver, "#pre")).toBeNull();
    expect(await translationOf(driver, "#opt-out")).toBeNull();

    await driver.close();
    await driver.switchTo().window(extensionHandle);
  });

  it("re-translates the page when the target language changes", async () => {
    const { extensionHandle, pageHandle, tabId } = await openFixture(session);
    await driver.switchTo().window(pageHandle);
    const japanese = await waitForTranslation(driver, "#plain", JAPANESE);

    await driver.switchTo().window(extensionHandle);
    await driver.executeScript("return chrome.storage.local.set({ target: 'fr' })");
    await expect(sendToBackground(driver, { type: "retranslate", tabId })).resolves.toEqual({ active: true });

    await driver.switchTo().window(pageHandle);
    await driver.wait(
      async () => {
        const translation = await translationOf(driver, "#plain");
        return translation !== null && translation !== japanese;
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

  it("restores the original and leaves the site untranslated next time", async () => {
    const { extensionHandle, pageHandle, tabId } = await openFixture(session);
    await driver.switchTo().window(pageHandle);
    await waitForTranslation(driver, "#plain", /月曜/);
    await driver.switchTo().window(extensionHandle);

    await expect(sendToBackground(driver, { type: "set-page", tabId, active: false })).resolves.toEqual({ active: false });

    await driver.switchTo().window(pageHandle);
    expect(await driver.executeScript("return document.querySelectorAll('.kotoba-tr').length")).toBe(0);
    expect(await textOf(driver, "plain")).toBe("The meeting has been rescheduled to next Monday.");

    // Turning it off is remembered for the site.
    await driver.navigate().refresh();
    await driver.sleep(5000);
    expect(await driver.executeScript("return document.querySelectorAll('.kotoba-tr').length")).toBe(0);

    await driver.switchTo().window(extensionHandle);
    const excluded = (await driver.executeAsyncScript(
      "const done = arguments[0]; chrome.storage.local.get('excludedOrigins').then(({ excludedOrigins = [] }) => done(excludedOrigins));",
    )) as string[];
    expect(excluded).toEqual([new URL(fixtureUrl).origin]);

    // Turning it back on forgets the exception.
    await expect(sendToBackground(driver, { type: "set-page", tabId, active: true })).resolves.toEqual({ active: true });

    await driver.switchTo().window(pageHandle);
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
