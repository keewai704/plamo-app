import { cp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { build } from "esbuild";

const pkg = JSON.parse(await readFile("package.json", "utf8"));
const version = process.env.KOTOBA_VERSION ?? pkg.version;

const manifest = {
  manifest_version: 3,
  name: "Kotoba",
  version,
  description: "自分のサーバーで動かす PLaMo 3 Translate でウェブページを翻訳します。Built with PLaMo.",
  icons: { 16: "icons/icon-16.png", 32: "icons/icon-32.png", 48: "icons/icon-48.png", 128: "icons/icon-128.png" },
  action: { default_popup: "popup.html", default_icon: { 16: "icons/icon-16.png", 32: "icons/icon-32.png" } },
  options_ui: { page: "options.html", open_in_tab: false },
  permissions: ["storage", "contextMenus", "scripting"],
  // Pages are translated where they open, so the extension reads them on every site.
  host_permissions: ["http://*/*", "https://*/*"],
  content_scripts: [
    {
      matches: ["http://*/*", "https://*/*"],
      js: ["content.js"],
      run_at: "document_idle",
    },
  ],
  commands: {
    "toggle-page": {
      suggested_key: { default: "Alt+Shift+T" },
      description: "ページを翻訳 / 原文に戻す",
    },
  },
};

const targets = {
  chrome: { ...manifest, background: { service_worker: "background.js" }, minimum_chrome_version: "121" },
  firefox: {
    ...manifest,
    background: { scripts: ["background.js"] },
    browser_specific_settings: {
      gecko: {
        id: "kotoba@keewai.jp",
        strict_min_version: "142.0",
        data_collection_permissions: { required: ["websiteContent"] },
      },
    },
  },
};

for (const [browser, browserManifest] of Object.entries(targets)) {
  const outdir = `dist/${browser}`;
  await rm(outdir, { recursive: true, force: true });
  await mkdir(outdir, { recursive: true });
  await cp("public", outdir, { recursive: true });
  await writeFile(`${outdir}/manifest.json`, `${JSON.stringify(browserManifest, null, 2)}\n`);
  await build({
    entryPoints: ["src/background.ts", "src/content.ts", "src/popup.ts", "src/options.ts"],
    bundle: true,
    format: "iife",
    target: browser === "chrome" ? "chrome121" : "firefox142",
    outdir,
    logLevel: "warning",
  });
}
