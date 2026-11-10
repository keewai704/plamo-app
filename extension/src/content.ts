import type { BackgroundMessage, ContentMessage, PageState, TranslateResult } from "./lib/messages";

declare global {
  // The script is injected on every command; only the first injection may register listeners.
  var __kotobaLoaded: boolean | undefined;
}

const CONCURRENCY = 4;
const MAX_CONTEXT_CHARS = 600;
const OVERLAY_ID = "kotoba-overlay";
const EXCLUDED =
  "script,style,noscript,textarea,input,select,option,code,pre,kbd,samp,var,svg,math,canvas,template," +
  `[translate="no"],.notranslate,[contenteditable=""],[contenteditable="true"],#${OVERLAY_ID}`;
const BLOCK = "p,li,td,th,h1,h2,h3,h4,h5,h6,blockquote,figcaption,dd,dt,div,section,article";

function requestTranslation(text: string, context?: string): Promise<TranslateResult> {
  const message: BackgroundMessage = { type: "translate", text, context };
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

async function showSelection(text: string): Promise<void> {
  const selection = window.getSelection();
  const anchor = selection?.rangeCount ? selection.getRangeAt(0).getBoundingClientRect() : undefined;
  const card = openOverlay(anchor);
  setOverlay(card, "loading", "");
  const result = await requestTranslation(selection?.toString() || text);
  if (result.ok) setOverlay(card, "done", result.text);
  else setOverlay(card, "error", result.error);
}

// --- Page translation ------------------------------------------------------

class PageSession {
  private readonly originals = new Map<Text, string>();
  private readonly nodesByParent = new Map<Element, Text[]>();
  private readonly queue: Text[] = [];
  private readonly observer: IntersectionObserver;
  private running = 0;
  private stopped = false;

  constructor() {
    // Only what the reader is about to see is sent to the server.
    this.observer = new IntersectionObserver((entries) => this.onIntersect(entries), { rootMargin: "400px" });
    for (const node of collectTextNodes()) {
      const parent = node.parentElement!;
      const nodes = this.nodesByParent.get(parent);
      if (nodes) {
        nodes.push(node);
      } else {
        this.nodesByParent.set(parent, [node]);
        this.observer.observe(parent);
      }
    }
  }

  restore(): void {
    this.stopped = true;
    this.observer.disconnect();
    for (const [node, original] of this.originals) node.data = original;
  }

  private onIntersect(entries: IntersectionObserverEntry[]): void {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      this.observer.unobserve(entry.target);
      this.queue.push(...(this.nodesByParent.get(entry.target) ?? []));
    }
    this.pump();
  }

  private pump(): void {
    while (!this.stopped && this.running < CONCURRENCY && this.queue.length > 0) {
      this.running++;
      void this.translateNode(this.queue.shift()!).finally(() => {
        this.running--;
        this.pump();
      });
    }
  }

  private async translateNode(node: Text): Promise<void> {
    const original = node.data;
    const result = await requestTranslation(original, blockContext(node));
    if (this.stopped) return;
    if (!result.ok) {
      this.stopped = true;
      this.observer.disconnect();
      setOverlay(openOverlay(undefined), "error", result.error);
      return;
    }
    const [leading] = original.match(/^\s*/)!;
    const [trailing] = original.match(/\s*$/)!;
    this.originals.set(node, original);
    node.data = `${leading}${result.text}${trailing}`;
  }
}

function collectTextNodes(): Text[] {
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
    acceptNode(node) {
      if (!/\p{L}/u.test(node.nodeValue ?? "")) return NodeFilter.FILTER_REJECT;
      return node.parentElement?.closest(EXCLUDED) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT;
    },
  });
  const nodes: Text[] = [];
  while (walker.nextNode()) nodes.push(walker.currentNode as Text);
  return nodes;
}

/** Surrounding text for a node that is only a fragment of its paragraph, such as a link. */
function blockContext(node: Text): string | undefined {
  const block = node.parentElement?.closest(BLOCK)?.textContent?.replace(/\s+/g, " ").trim();
  if (!block || block.length > MAX_CONTEXT_CHARS || block === node.data.trim()) return undefined;
  return block;
}

let session: PageSession | undefined;

function togglePage(): PageState {
  if (session) {
    session.restore();
    session = undefined;
  } else {
    session = new PageSession();
  }
  return { active: session !== undefined };
}

// ---------------------------------------------------------------------------

if (!globalThis.__kotobaLoaded) {
  globalThis.__kotobaLoaded = true;
  chrome.runtime.onMessage.addListener((message: ContentMessage, _sender, sendResponse) => {
    switch (message.type) {
      case "toggle-page":
        sendResponse(togglePage());
        break;
      case "page-state":
        sendResponse({ active: session !== undefined } satisfies PageState);
        break;
      case "show-selection":
        void showSelection(message.text);
        sendResponse();
        break;
    }
  });
}
