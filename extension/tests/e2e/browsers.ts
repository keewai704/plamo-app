import { resolve } from "node:path";
import { Builder, type WebDriver } from "selenium-webdriver";
import chrome from "selenium-webdriver/chrome.js";
import firefox from "selenium-webdriver/firefox.js";

export interface ExtensionSession {
  driver: WebDriver;
  /** Base URL of the extension's own pages, without a trailing slash. */
  baseUrl: string;
}

const FIREFOX_UUID = "6f1e0a3c-3f4b-4a55-9a11-2f6f3c1d7e10";

export async function startChrome(): Promise<ExtensionSession> {
  const options = new chrome.Options();
  options.addArguments(`--load-extension=${resolve("dist/chrome")}`, "--headless=new", "--no-sandbox", "--disable-dev-shm-usage");
  if (process.env.CHROME_BIN) options.setChromeBinaryPath(process.env.CHROME_BIN);

  const service = new chrome.ServiceBuilder(process.env.CHROMEDRIVER);
  const driver = await new Builder().forBrowser("chrome").setChromeOptions(options).setChromeService(service).build();

  const extensionId = await findChromeExtensionId(driver);
  return { driver, baseUrl: `chrome-extension://${extensionId}` };
}

async function findChromeExtensionId(driver: WebDriver): Promise<string> {
  const chromeDriver = driver as chrome.Driver;
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    const { targetInfos } = (await chromeDriver.sendAndGetDevToolsCommand("Target.getTargets", {})) as unknown as {
      targetInfos: { url: string }[];
    };
    const worker = targetInfos.find((target) => /^chrome-extension:\/\/[a-p]{32}\/background\.js$/.test(target.url));
    if (worker) return new URL(worker.url).host;
    await driver.sleep(250);
  }
  throw new Error("the extension's service worker did not start");
}

export async function startFirefox(): Promise<ExtensionSession> {
  const options = new firefox.Options()
    .addArguments("-headless")
    .setPreference("extensions.webextensions.uuids", JSON.stringify({ "kotoba@keewai.jp": FIREFOX_UUID }));
  if (process.env.FIREFOX_BIN) options.setBinary(process.env.FIREFOX_BIN);

  // Without system access, Marionette refuses to navigate to moz-extension pages.
  const service = new firefox.ServiceBuilder(process.env.GECKODRIVER).addArguments("--allow-system-access");
  const driver = (await new Builder()
    .forBrowser("firefox")
    .setFirefoxOptions(options)
    .setFirefoxService(service)
    .build()) as firefox.Driver;

  await driver.installAddon(resolve("artifacts/kotoba-firefox.zip"), true);
  return { driver, baseUrl: `moz-extension://${FIREFOX_UUID}` };
}
