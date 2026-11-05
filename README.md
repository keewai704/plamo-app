[![CI](https://github.com/keewai704/plamo-app/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/keewai704/plamo-app/actions/workflows/ci.yml)

# Kotoba — オンデバイス翻訳（PLaMo 3 Translate 0.8B）

iOS 18.4 以降で **デフォルトの翻訳アプリ** として選べる、完全オンデバイスの翻訳アプリです。
PLaMo 3 Translate 0.8B の GGUF を llama.cpp（Metal）で動かし、Translation UI Provider
拡張を iOS の「翻訳」導線に差し込みます。

> このリポジトリは会話スレッド「iPhone で Plamo 3 Translate を動かす」の結論を実装したものです。
> アプリ名は PLaMo の公式アプリと誤認されないよう **Kotoba** にしています（モデル名は PLaMo のまま）。

## できること

- テキスト選択 →「翻訳」で、システムのシートに Kotoba の訳文を表示
- 「置き換え」で元のテキストを訳文に置換
- アプリ本体でも同じエンジンで翻訳（言語自動判定つき）
- GGUF のダウンロード（Q2_K / Q3_K_M / Q4_K_M）と Files からの読み込み
- モデルは App Group に置き、アプリと拡張の両プロセスが mmap で共有
- クラウド推論なし（初回のモデル取得を除く）

## 構成

```
Kotoba.app
├── Kotoba (SwiftUI)
│   ├── TranslationViewModel ── PLaMoKit（PFML3 プロンプト / 言語判定 / チャンク分割）
│   └── LlamaEngine ─────────── llama.xcframework (ios-arm64)
├── Extensions/
│   └── TranslationProvider.appex   ← ExtensionKit / com.apple.public.translation-ui-provider
└── Frameworks/
    └── llama.framework            ← make fetch-llama で取得（リポジトリには含めない）
```

- **アプリ**: `jp.keewai.kotoba`
- **拡張**: `jp.keewai.kotoba.TranslationProvider`
- **App Group**: `group.jp.keewai.kotoba`
- **Entitlement**: アプリ側に `com.apple.developer.translation-app`

## 必要環境

| 用途 | 必要なもの |
|---|---|
| ビルド | macOS 15+ / Xcode 26 / XcodeGen 2.46+ |
| 実行 | iPhone（arm64）/ iOS 18.4+ |
| モデル | 空き容量 500MB 以上（Q3_K_M は 486MB） |

このリポジトリは Linux ではビルドできません（Xcode が必要です）。

## セットアップ

```bash
brew install xcodegen
make bootstrap          # llama.cpp b12121 の xcframework を取得・検証
make generate           # Kotoba.xcodeproj を生成
open Kotoba.xcodeproj
```

Xcode で以下を設定してください。

1. 両ターゲットの Signing & Capabilities で Team を選択
2. Bundle Identifier を自分のものに変更する場合は、以下を揃えて変更
   - `project.yml` の `PRODUCT_BUNDLE_IDENTIFIER`
   - `PLaMoKit/Sources/PLaMoKit/AppGroup.swift` の `AppGroup.identifier`
   - 2 つの `.entitlements` の App Group
3. 実機で Run → アプリ内でモデルをダウンロード
4. 設定 → アプリ → 翻訳 → デフォルトの翻訳アプリ → **Kotoba**

App Group と Translation 拡張はプロビジョニングプロファイルに含まれる必要があります。
自動署名（Automatic）なら Xcode が App ID を作り直します。

## PFML3 プロンプト

GGUF 同梱の `chat_template.jinja` と同一の形式を `PLaMoKit` で生成します。

```
<|plamo:tag|>dataset<|plamo:msg|>translation
<|plamo:tag|>input<|plamo:msg|>会議は来週の月曜日に変更されました。
<|plamo:tag|>output<|plamo:key|>lang<|plamo:val|>en<|plamo:msg|>
```

- 先頭の `<bos>` は付けません（llama.cpp が `add_special=true` で付与します）
- `form` は `target_lang=ja` のときだけ付けます（テンプレートの制約）
- トークンは `<|plamo:...|>` です

## テスト

```bash
make test        # build-for-testing → unit → XCUITest
make test-unit   # ビルド済みなら再ビルドなしで unit のみ
make test-ui     # ビルド済みなら再ビルドなしで E2E のみ
```

- **Unit** (`Tests/KotobaTests`): PFML3 の完全一致、言語判定、チャンク分割、モデルカタログ、
  モデルストア、ViewModel の成功・失敗・分割
- **E2E** (`Tests/KotobaUITests`): アプリ起動 → 入力 → 翻訳 → 出力を XCUITest で検証。
  `-ui-testing` で決定的なモックエンジンに切り替えます。

### シミュレータではモックで動きます

上流の `llama-<tag>-xcframework.zip` には **ios-arm64（実機）と macOS のスライスしか入っていません**。
シミュレータ用スライスが無いため、シミュレータでは `#if canImport(llama)` が false になり
`MockTranslationEngine` を使います。実機ビルドでは `LLAMA_REQUIRED` を定義しているので、
llama.xcframework が無いままビルドすると **コンパイルエラー** になります（CI の担保）。

実機と同じモデルをシミュレータで試したい場合は、llama.cpp を
`-DCMAKE_OSX_SYSROOT=iphonesimulator` で自前ビルドして xcframework に追加してください。

## CI/CD（GitHub Actions）

### CI（`.github/workflows/ci.yml`）

| ジョブ | 内容 |
|---|---|
| Detect changes | ドキュメントだけの変更では重いジョブをスキップ |
| Build + unit + E2E | XcodeGen → ビルド → unit → XCUITest（シミュレータ） |
| Device build | llama.cpp をリンクした **署名なし実機ビルド** で Swift/C ブリッジを検証 |

### Release（`.github/workflows/release.yml`）

`v*` タグ（または手動実行で `upload` を選択）で TestFlight にアップロードします。

```bash
git tag v0.1.0
git push origin v0.1.0
```

必要な Secrets（Environment: `release`）:

| Secret | 内容 |
|---|---|
| `ASC_KEY_ID` | App Store Connect API Key ID |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_CONTENT_BASE64` | `.p8` を base64 にしたもの |
| `APPLE_TEAM_ID` | 10 桁の Team ID |

API キーのロールは **App Manager** 以上にしてください（プロビジョニングプロファイルの作成に必要）。

自動署名 + `-allowProvisioningUpdates` でプロファイルを作ります。Bundle ID・App Group・
Translation 拡張の capability は事前に App Store Connect 側で有効にしてください。

### キャッシュ戦略

| キャッシュ | key | 短縮されるもの |
|---|---|---|
| XcodeGen バイナリ | `xcodegen-<os>-2.46.0` | ダウンロード（毎回 ~20 秒） |
| DerivedData（テスト） | `dd-test-<os>-<sha>` + prefix | Swift の増分コンパイル |
| DerivedData（実機） | `dd-device-<os>-<sha>` + prefix | Release の増分コンパイル |
| DerivedData（リリース） | `dd-release-<os>-<sha>` + prefix | Archive の増分 |
| llama.cpp xcframework | `llama-xcframework-<tag>` | 76MB のダウンロード |
| Ruby gems | `ruby/setup-ruby` の `bundler-cache` | `bundle install` |

さらに CI では次を固定してビルドを軽くしています。

- `COMPILER_INDEX_STORE_ENABLE=NO`（インデックスを作らない）
- `build-for-testing` を 1 回だけ実行し、unit と E2E は `test-without-building` で再利用
- E2E はモデルをダウンロードしない（モックエンジン）
- `concurrency.cancel-in-progress` で古い実行を停止

## 既知の制限

- **拡張のメモリ上限**: 共有拡張と同程度（経験的に ~120MB）と見て、2k コンテキスト + q8 KV にしています。
  実機の Instruments / `os_proc_available_memory` で確認し、足りなければ Q2_K・1k コンテキストに落としてください。
- **ストリーミングなし**: 現状はチャンク単位で結果をまとめて表示します。
- **シミュレータはモック**: 上記のとおり上流 xcframework にシミュレータスライスがありません。
- **ページ全体翻訳・Live Translation は置き換え不可**: テキスト選択の翻訳導線のみです。
- **ライセンス**: モデルは同梱せず利用者が取得します。商用配布（App Store 含む）は
  PLaMo Community License の登録条件を確認してください。詳細は [NOTICE.md](NOTICE.md)。

## 開発メモ

- `make build-device` は署名なしで実機向けにビルドします（CI と同じ）。
- 実機向けビルドでは `vendor/llama/llama.xcframework/ios-arm64` を検索パスに追加し、
  `llama.framework` を `Frameworks/` に埋め込み・署名します（`project.yml` の postBuildScript）。
- ビルド設定は `project.yml` が唯一の正です。`Kotoba.xcodeproj` は生成物なのでコミットしません。
