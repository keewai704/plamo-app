import { fetchStatus, type ServerStatus } from "./client";
import { loadSettings } from "./settings";

const POLL_INTERVAL_MS = 2000;

const NAMES: Record<ServerStatus, string> = {
  ready: "モデル読み込み済み",
  sleeping: "モデル未読み込み",
  loading: "モデル読み込み中",
  unauthorized: "API キーが正しくありません",
  unreachable: "サーバーに接続できません",
};

/** Keeps a status dot in step with the server for as long as the page is open. */
export class StatusView {
  private status: ServerStatus = "unreachable";

  constructor(private readonly element: HTMLElement) {
    void this.refresh();
    setInterval(() => void this.refresh(), POLL_INTERVAL_MS);
  }

  async refresh(): Promise<ServerStatus> {
    this.status = await fetchStatus(await loadSettings());
    this.element.dataset.state = this.status;
    this.element.title = NAMES[this.status];
    this.element.setAttribute("aria-label", NAMES[this.status]);
    return this.status;
  }
}
