[![CI](https://github.com/keewai704/plamo-app/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/keewai704/plamo-app/actions/workflows/ci.yml)

# Kotoba

自分のサーバーで動かす PLaMo 3 Translate 0.8B を使う翻訳クライアントです。

| ディレクトリ | 内容 |
|---|---|
| `server/` | llama-server と vLLM の起動スクリプト。モデルと依存のバージョンは `model.env`、`vllm/` で固定 |
| `ios/` | iPhone / iPad アプリ（SwiftUI、iOS 17 以降） |
| `extension/` | Chrome / Firefox 拡張（Manifest V3） |

クライアントはサーバーの OpenAI 互換 API（`/v1/chat/completions`）を直接呼びます。

## サーバー

サーバーだけを Nix でインストールできます。

```bash
nix profile install github:keewai704/plamo-app          # CPU（Linux）/ Metal（macOS）
nix profile install github:keewai704/plamo-app#vulkan   # Vulkan GPU
nix profile install github:keewai704/plamo-app#vllm     # NVIDIA Blackwell（x86_64 の NixOS）
plamo-server                                            # 初回はモデルを取得して sha256 を検証
```

`#vllm` は NVFP4 版の重みを vLLM で動かします。NVIDIA Blackwell 世代で最も高速ですが、起動から停止まで重みを GPU に保持します。
初回起動時に `uv.lock` で固定した依存を `PLAMO_MODEL_DIR` に取得します。

Nix を使わない場合は `llama-server` を PATH に入れるか（`brew install llama.cpp` など）、
`server/install-llama.sh`（Linux x64 / macOS arm64）で固定バージョンを導入して `server/serve.sh` を実行します。

設定は `~/.config/plamo-server/config.env` に書きます（`PLAMO_CONFIG` で変更可）。環境変数のほうが優先されます。
ひな形は [`server/config.example.env`](server/config.example.env) です。

| キー | 既定値 | 内容 |
|---|---|---|
| `PLAMO_IDLE_SECONDS` | `600` | アイドル時に重みをメモリに保持する秒数。`0` で無期限。解放後は次のリクエストで再読み込み（llama.cpp のみ） |
| `PLAMO_HOST` | `127.0.0.1` | 待ち受けアドレス |
| `PLAMO_PORT` | `8000` | ポート |
| `PLAMO_API_KEY` | なし | Bearer トークン。ループバック以外では必須。ファイルの権限は `600` に |
| `PLAMO_GPU_LAYERS` | llama.cpp が判断 | GPU に載せる層の数（llama.cpp のみ） |
| `PLAMO_GPU_MEMORY` | `0.25` | vLLM が確保する GPU メモリの割合（vLLM のみ） |
| `PLAMO_MODEL_DIR` | `~/.local/share/plamo-server/models` | モデルの保存先 |

llama-server と vLLM は TLS を提供しないので、LAN の外に出すときは
`tailscale serve 8000` やリバースプロキシで HTTPS にしてください。
iOS アプリが平文 HTTP で接続できるのはローカルネットワークだけです。

## サーバーの状態表示

どのクライアントも、言語の選択欄の隣に同じ意味の丸印を表示します。

| 表示 | 状態 |
|---|---|
| 塗りつぶし（緑） | モデル読み込み済み |
| 輪郭のみ | 重みを解放済み。次の翻訳で読み込み |
| 点滅（黄） | モデル読み込み中 |
| 塗りつぶし（赤） | 接続できない、または API キーの誤り |

vLLM は重みを読み込み終えてから待ち受けを始めるので、起動中は赤で表示されます。

## ブラウザ拡張

ツールバーのアイコン、ページの右クリック、`Alt+Shift+T` で、そのタブの本文をブロックごとに訳文へ置き換えます。
もう一度押すと原文に戻ります。ページを開いただけでは翻訳しません。

```bash
cd extension
npm ci
npm run build
```

- Chrome: `chrome://extensions` のデベロッパーモードで `dist/chrome` を読み込む
- Firefox: `about:debugging` で `dist/firefox/manifest.json` を一時的に読み込む

サーバーの URL と API キーは設定ページで指定します。ループバック以外のサーバーを保存するときに、そのサーバーへのアクセスを許可します。
ページを読むのは翻訳を頼まれたときだけなので、すべてのサイトへのアクセスは求めません。本文は翻訳するときにだけ、設定したサーバーへ送られます。

コード、`translate="no"` の要素、メニューやファイル名のようなリンクだけのブロックは翻訳しません。アイコンや画像はそのまま残します。
選択範囲は右クリックのメニューから翻訳できます。

## iOS / iPadOS アプリ

macOS と Xcode、[XcodeGen](https://github.com/yonaskolb/XcodeGen) が必要です。

```bash
cd ios
xcodegen generate
open Kotoba.xcodeproj
```

Signing & Capabilities で Team を選んで実行し、起動後の設定画面でサーバーの URL と API キーを入力します。

## テスト

E2E はモックを使わず、実モデルを動かした llama-server に対して実行します。
重みの解放と再読み込みも検証するため、`PLAMO_IDLE_SECONDS` を短くして起動します。

```bash
PLAMO_API_KEY=dev PLAMO_IDLE_SECONDS=3 server/serve.sh &
server/test-config.sh
PLAMO_API_KEY=dev server/test-idle.sh

cd extension
npm test
npm run build && npm run package
PLAMO_API_KEY=dev npm run test:e2e

cd ../ios
make test-core
make build-for-testing
PLAMO_URL=http://127.0.0.1:8000 PLAMO_API_KEY=dev make test-ui DEVICE=iPad
```

拡張の E2E には Chrome for Testing（製品版 Chrome は `--load-extension` を無視します）と Firefox が必要です。
`CHROME_BIN`、`CHROMEDRIVER`、`FIREFOX_BIN`、`GECKODRIVER` でパスを指定できます。

## CI/CD

`ci.yml` は push と pull request で動き、flake でビルドしたサーバーの検証と、拡張（Chrome / Firefox）・アプリ（iPhone / iPad シミュレータ）の E2E を実行します。

`v*` タグを push すると `release.yml` が CI の成功後にパッケージを作り、GitHub Release に添付します。
ストアへの提出は、Environment `release` に次の Secrets がある場合だけ実行します。

| 提出先 | Secrets |
|---|---|
| TestFlight | `ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_KEY_CONTENT_BASE64`、`APPLE_TEAM_ID` |
| Firefox（署名済み XPI を unlisted で発行） | `AMO_API_KEY`、`AMO_API_SECRET` |
| Chrome Web Store | `CWS_EXTENSION_ID`、`CWS_CLIENT_ID`、`CWS_CLIENT_SECRET`、`CWS_REFRESH_TOKEN` |

## ライセンス

モデルは同梱していません。利用条件は [NOTICE.md](NOTICE.md) を参照してください。
