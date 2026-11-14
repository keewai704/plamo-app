import { needsTranslation } from "./lib/language";
import type { BackgroundMessage, ContentMessage, PageState, TranslateResult } from "./lib/messages";
import { loadSettings, type Settings } from "./lib/settings";

declare global {
  // The script is injected on every command; only the first injection may register listeners.
  var __kotobaLoaded: boolean | undefined;
}

const CONCURRENCY = 4;
const RESCAN_DELAY_MS = 600;
const OVERLAY_ID = "kotoba-overlay";
const EXCLUDED =
  "script,style,noscript,textarea,input,select,option,code,pre,kbd,samp,var,svg,math,canvas,template," +
  `[translate="no"],.notranslate,[contenteditable=""],[contenteditable="true"],#${OVERLAY_ID}`;
/** Blocks of prose. The text of each leaf block is replaced with its translation. */
const UNIT_SELECTOR =
  "p,li,td,th,dt,dd,h1,h2,h3,h4,h5,h6,blockquote,figcaption,summary,caption,legend,label," +
  "div,section,article,main,header,footer,aside,nav,form,fieldset";
/** Chrome shared by every page: menus and the footer. */
const SKIPPED = "nav,footer,[role='navigation'],[role='contentinfo']";

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

/** A block that is only a link is a file name or a menu item, not prose. */
function isLinkOnly(element: HTMLElement, text: string): boolean {
  for (const link of element.querySelectorAll("a, button, summary")) {
    if (unitText(link) === text) return true;
  }
  return false;
}

/** File names and identifiers, which read worse translated. */
function looksLikeCode(text: string): boolean {
  return !/\s/.test(text) && /[._/\\]/.test(text) && /\p{L}/u.test(text);
}

/** Leaf blocks of prose: blocks that have no smaller block of their own inside them. */
function collectUnits(): HTMLElement[] {
  const body = document.body;
  if (!body) return [];
  const candidates = new Set<HTMLElement>();
  for (const element of body.querySelectorAll<HTMLElement>(UNIT_SELECTOR)) {
    if (element.closest(EXCLUDED) || element.closest(SKIPPED) || element.isContentEditable) continue;
    const text = unitText(element);
    if (!/\p{L}/u.test(text) || isLinkOnly(element, text) || looksLikeCode(text)) continue;
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

interface Unit {
  element: HTMLElement;
  text: string;
}

/**
 * Replaces the text of each block with its translation and keeps the original nodes,
 * so that the page can be put back as it was. Only what the reader is about to see
 * is sent to the server.
 */
class PageSession {
  private readonly settings: Settings;
  private readonly queue: Unit[] = [];
  private readonly scheduled = new WeakSet<HTMLElement>();
  /** The children each translated block had before its text was replaced. */
  private readonly originals = new Map<HTMLElement, Node[]>();
  /** Blocks this session rewrote, whose mutations are its own doing. */
  private readonly replaced = new WeakSet<Element>();
  private readonly observer: IntersectionObserver;
  private readonly mutations: MutationObserver;
  private running = 0;
  private stopped = false;
  private scanTimer: number | undefined;

  constructor(settings: Settings) {
    this.settings = settings;
    this.observer = new IntersectionObserver((entries) => this.onIntersect(entries), { rootMargin: "400px" });
    // Infinite feeds and other pages built by scripts keep adding prose.
    this.mutations = new MutationObserver((records) => {
      if (records.every((record) => this.replaced.has(record.target as Element))) return;
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
    for (const [element, nodes] of this.originals) element.replaceChildren(...nodes);
    this.originals.clear();
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
    this.originals.set(unit.element, [...unit.element.childNodes]);
    this.replaced.add(unit.element);
    unit.element.replaceChildren(translated);
  }
}

// --- Page commands ---------------------------------------------------------

let session: PageSession | undefined;

function failure(error: unknown): PageState {
  return { active: false, error: messageOf(error) };
}

async function setPage(active: boolean): Promise<PageState> {
  if (active && !session?.active) {
    session = new PageSession(await loadSettings());
  } else if (!active && session) {
    const current = session;
    session = undefined;
    current.restore();
  }
  return { active: session?.active ?? false };
}

async function togglePage(): Promise<PageState> {
  return setPage(!(session?.active ?? false));
}

/** Starts over with the current settings, so that a new target language is used. */
async function retranslate(): Promise<PageState> {
  const settings = await loadSettings();
  session?.restore();
  session = new PageSession(settings);
  return { active: session.active };
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
}
