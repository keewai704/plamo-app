import { needsTranslation } from "./lib/language";
import type { BackgroundMessage, ContentMessage, PageState, TranslateResult } from "./lib/messages";
import { loadSettings, setOriginAuto, type Settings } from "./lib/settings";

declare global {
  // The script is injected on every command; only the first injection may register listeners.
  var __kotobaLoaded: boolean | undefined;
}

const CONCURRENCY = 4;
const RESCAN_DELAY_MS = 600;
const OVERLAY_ID = "kotoba-overlay";
const STYLE_ID = "kotoba-style";
const TRANSLATION_CLASS = "kotoba-tr";
const TRANSLATION_SELECTOR = `.${TRANSLATION_CLASS}`;
const EXCLUDED =
  "script,style,noscript,textarea,input,select,option,code,pre,kbd,samp,var,svg,math,canvas,template," +
  `[translate="no"],.notranslate,[contenteditable=""],[contenteditable="true"],${TRANSLATION_SELECTOR},#${OVERLAY_ID}`;
/** Blocks of prose. The translation of each leaf block is added below it. */
const UNIT_SELECTOR =
  "p,li,td,th,dt,dd,h1,h2,h3,h4,h5,h6,blockquote,figcaption,summary,caption,legend,label," +
  "div,section,article,main,header,footer,aside,nav,form,fieldset";

const PAGE_STYLE = `
  .${TRANSLATION_CLASS} {
    display: block;
    margin-top: 0.3em;
    opacity: 0.78;
    text-decoration: none;
  }
`;

function requestTranslation(text: string): Promise<TranslateResult> {
  const message: BackgroundMessage = { type: "translate", text };
  return chrome.runtime.sendMessage(message);
}

// --- Overlay ---------------------------------------------------------------

const OVERLAY_STYLE = `
  :host { all: initial; position: fixed; z-index: 2147483647; }
  .card {
    box-sizing: border-box; width: min(420px, calc(100vw - 16px)); max-height: 50vh; overflow: auto;
    padding: 12px 14px; border-radius: 10px; font: 14px/1.6 system-ui, sans-serif;
    color: #1c2321; background: #fff; box-shadow: 0 6px 24px rgb(0 0 0 / 28%); white-space: pre-wrap;
  }
  .card[data-state="loading"]::before {
    content: ""; display: block; width: 18px; height: 18px; border-radius: 50%;
    border: 2px solid #6b7572; border-top-color: transparent; animation: spin .8s linear infinite;
  }
  @keyframes spin { to { transform: rotate(360deg); } }
  .card[data-state="error"] { color: #b3261e; }
  @media (prefers-color-scheme: dark) {
    .card { color: #e7ecea; background: #1f2624; }
    .card[data-state="error"] { color: #f2b8b5; }
  }
`;

function closeOverlay(): void {
  document.getElementById(OVERLAY_ID)?.remove();
  document.removeEventListener("pointerdown", onOutsidePointer, true);
  document.removeEventListener("keydown", onEscape, true);
}

function onOutsidePointer(event: Event): void {
  if ((event.target as Element | null)?.id !== OVERLAY_ID) closeOverlay();
}

function onEscape(event: KeyboardEvent): void {
  if (event.key === "Escape") closeOverlay();
}

function openOverlay(anchor: DOMRect | undefined): HTMLElement {
  closeOverlay();
  const host = document.createElement("div");
  host.id = OVERLAY_ID;
  host.style.left = `${Math.max(8, Math.min(anchor?.left ?? 8, window.innerWidth - 428))}px`;
  if (anchor && anchor.bottom < window.innerHeight * 0.6) {
    host.style.top = `${anchor.bottom + 8}px`;
  } else {
    host.style.bottom = "8px";
  }
  const shadow = host.attachShadow({ mode: "open" });
  const style = document.createElement("style");
  style.textContent = OVERLAY_STYLE;
  const card = document.createElement("div");
  card.className = "card";
  card.setAttribute("role", "status");
  shadow.append(style, card);
  document.documentElement.append(host);
  document.addEventListener("pointerdown", onOutsidePointer, true);
  document.addEventListener("keydown", onEscape, true);
  return card;
}

function setOverlay(card: HTMLElement, state: "loading" | "done" | "error", text: string): void {
  card.dataset.state = state;
  card.textContent = text;
  card.setAttribute("aria-busy", String(state === "loading"));
}

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

async function showSelection(text: string): Promise<void> {
  const selection = window.getSelection();
  const anchor = selection?.rangeCount ? selection.getRangeAt(0).getBoundingClientRect() : undefined;
  const card = openOverlay(anchor);
  setOverlay(card, "loading", "");
  try {
    const result = await requestTranslation(selection?.toString() || text);
    if (result.ok) setOverlay(card, "done", result.text);
    else setOverlay(card, "error", result.error);
  } catch (error) {
    setOverlay(card, "error", messageOf(error));
  }
}

function showError(message: string): void {
  setOverlay(openOverlay(undefined), "error", message);
}

// --- Page text -------------------------------------------------------------

function installStyle(): void {
  if (document.getElementById(STYLE_ID)) return;
  const style = document.createElement("style");
  style.id = STYLE_ID;
  style.textContent = PAGE_STYLE;
  document.documentElement.append(style);
}

/** The text of an element without the parts the page reads as code or leaves untranslated. */
function inlineText(element: Element): string {
  let text = "";
  for (const node of element.childNodes) {
    if (node.nodeType === Node.TEXT_NODE) {
      text += node.nodeValue ?? "";
    } else if (node.nodeType === Node.ELEMENT_NODE) {
      const child = node as Element;
      if (child.tagName === "BR") text += " ";
      else if (!child.matches(EXCLUDED)) text += inlineText(child);
    }
  }
  return text;
}

function unitText(element: Element): string {
  return inlineText(element).replace(/\s+/g, " ").trim();
}

/** Leaf blocks of prose: blocks that have no smaller block of their own inside them. */
function collectUnits(): HTMLElement[] {
  const body = document.body;
  if (!body) return [];
  const candidates = new Set<HTMLElement>();
  for (const element of body.querySelectorAll<HTMLElement>(UNIT_SELECTOR)) {
    if (element.closest(EXCLUDED) || element.isContentEditable) continue;
    if (!/\p{L}/u.test(unitText(element))) continue;
    candidates.add(element);
  }
  const nested = new Set<HTMLElement>();
  for (const element of candidates) {
    for (let parent = element.parentElement; parent; parent = parent.parentElement) {
      if (candidates.has(parent)) nested.add(parent);
    }
  }
  return [...candidates].filter((element) => !nested.has(element));
}

function isOwnInsertion(record: MutationRecord): boolean {
  const nodes = [...record.addedNodes, ...record.removedNodes];
  return nodes.length > 0 && nodes.every((node) => node instanceof Element && node.classList.contains(TRANSLATION_CLASS));
}

interface Unit {
  element: HTMLElement;
  text: string;
}

/**
 * Adds the translation of each block below it, leaving the original in place.
 * Only what the reader is about to see is sent to the server.
 */
class PageSession {
  private readonly settings: Settings;
  private readonly queue: Unit[] = [];
  private readonly scheduled = new WeakSet<HTMLElement>();
  private readonly observer: IntersectionObserver;
  private readonly mutations: MutationObserver;
  private running = 0;
  private stopped = false;
  private scanTimer: number | undefined;

  constructor(settings: Settings) {
    this.settings = settings;
    installStyle();
    this.observer = new IntersectionObserver((entries) => this.onIntersect(entries), { rootMargin: "400px" });
    // Infinite feeds and other pages built by scripts keep adding prose.
    this.mutations = new MutationObserver((records) => {
      if (records.every((record) => isOwnInsertion(record))) return;
      this.scheduleScan();
    });
    if (document.body) this.mutations.observe(document.body, { childList: true, subtree: true });
    this.scan();
  }

  get active(): boolean {
    return !this.stopped;
  }

  restore(): void {
    this.halt();
    for (const span of document.querySelectorAll(TRANSLATION_SELECTOR)) span.remove();
  }

  private halt(): void {
    this.stopped = true;
    this.observer.disconnect();
    this.mutations.disconnect();
    if (this.scanTimer !== undefined) clearTimeout(this.scanTimer);
    this.scanTimer = undefined;
    this.queue.length = 0;
  }

  private scheduleScan(): void {
    if (this.stopped || this.scanTimer !== undefined) return;
    this.scanTimer = window.setTimeout(() => {
      this.scanTimer = undefined;
      this.scan();
    }, RESCAN_DELAY_MS);
  }

  private scan(): void {
    if (this.stopped) return;
    for (const element of collectUnits()) {
      if (this.scheduled.has(element)) continue;
      this.scheduled.add(element);
      this.observer.observe(element);
    }
  }

  private onIntersect(entries: IntersectionObserverEntry[]): void {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      this.observer.unobserve(entry.target);
      const element = entry.target as HTMLElement;
      const text = unitText(element);
      if (text && needsTranslation(text, this.settings.target)) this.queue.push({ element, text });
    }
    this.pump();
  }

  private pump(): void {
    while (!this.stopped && this.running < CONCURRENCY && this.queue.length > 0) {
      const unit = this.queue.shift()!;
      this.running++;
      void this.translateUnit(unit).finally(() => {
        this.running--;
        this.pump();
      });
    }
  }

  private async translateUnit(unit: Unit): Promise<void> {
    let result: TranslateResult;
    try {
      result = await requestTranslation(unit.text);
    } catch (error) {
      // The extension was reloaded or removed while this page stayed open.
      if (this.stopped) return;
      this.halt();
      showError(messageOf(error));
      return;
    }
    if (this.stopped) return;
    if (!result.ok) {
      this.halt();
      showError(result.error);
      return;
    }
    const translated = result.text.trim();
    if (!translated || translated === unit.text) return;
    const span = document.createElement("span");
    span.className = TRANSLATION_CLASS;
    if (this.settings.target !== "auto") span.lang = this.settings.target;
    span.textContent = translated;
    unit.element.append(span);
  }
}

// --- Page commands ---------------------------------------------------------

let session: PageSession | undefined;
/** Set by any command from the reader, so that a late automatic start stays out of the way. */
let manual = false;

function failure(error: unknown): PageState {
  return { active: false, error: messageOf(error) };
}

async function setPage(active: boolean): Promise<PageState> {
  manual = true;
  if (active && !session?.active) {
    session = new PageSession(await loadSettings());
    await setOriginAuto(location.origin, true);
  } else if (!active && session) {
    const current = session;
    session = undefined;
    current.restore();
    await setOriginAuto(location.origin, false);
  }
  return { active: session?.active ?? false };
}

async function togglePage(): Promise<PageState> {
  return setPage(!(session?.active ?? false));
}

/** Starts over with the current settings, so that a new target language is used. */
async function retranslate(): Promise<PageState> {
  manual = true;
  const settings = await loadSettings();
  session?.restore();
  session = new PageSession(settings);
  return { active: session.active };
}

async function autoStart(): Promise<void> {
  if (window !== window.top) return;
  const settings = await loadSettings();
  if (manual || session || !settings.configured || !settings.autoTranslate) return;
  if (settings.excludedOrigins.includes(location.origin)) return;
  if (!document.body) return;
  session = new PageSession(settings);
}

if (!globalThis.__kotobaLoaded) {
  globalThis.__kotobaLoaded = true;
  chrome.runtime.onMessage.addListener((message: ContentMessage, _sender, sendResponse) => {
    switch (message.type) {
      case "set-page":
        void setPage(message.active).then(sendResponse, (error: unknown) => sendResponse(failure(error)));
        return true;
      case "toggle-page":
        void togglePage().then(sendResponse, (error: unknown) => sendResponse(failure(error)));
        return true;
      case "retranslate":
        void retranslate().then(sendResponse, (error: unknown) => sendResponse(failure(error)));
        return true;
      case "page-state":
        sendResponse({ active: session?.active ?? false } satisfies PageState);
        break;
      case "show-selection":
        void showSelection(message.text);
        sendResponse();
        break;
    }
  });
  void autoStart();
}
