<div align="center">

[🇨🇳 中文](README_zh.md) | [🇺🇸 English](README.md) | **🇯🇵 日本語**

# <img src="docs/images/crawfish.png" width="36" height="36" alt="Rockpile" style="vertical-align: middle;" /> Rockpile

**MacBook の Notch に住むピクセルコンパニオン — AI エージェントの動作状態をリアルタイム表示**

[![macOS 15+](https://img.shields.io/badge/macOS-15.0%2B-black?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-2.0.5-brightgreen)](https://github.com/ar-gen-tin/rockpile/releases)

[![GitHub Stars](https://img.shields.io/github/stars/ar-gen-tin/rockpile?style=flat-square&logo=github)](https://github.com/ar-gen-tin/rockpile/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/ar-gen-tin/rockpile?style=flat-square&logo=github)](https://github.com/ar-gen-tin/rockpile/network/members)
[![GitHub Issues](https://img.shields.io/github/issues/ar-gen-tin/rockpile?style=flat-square&logo=github)](https://github.com/ar-gen-tin/rockpile/issues)
[![GitHub Last Commit](https://img.shields.io/github/last-commit/ar-gen-tin/rockpile?style=flat-square&logo=github)](https://github.com/ar-gen-tin/rockpile/commits/main)

<br>

<!-- ![Rockpile Screenshot](docs/images/screenshot-hero.png) -->

</div>

---

## Rockpile とは？

Rockpile は MacBook の **Notch エリア** に住むピクセルアートのザリガニコンパニオンです。Socket 経由で AI エージェント（Claude Code など）と接続し、エージェントの思考・コーディング・待機・エラーなどの状態を、リアルタイムのスプライトアニメーション・感情・水中環境の変化にマッピングします。

- 🧠 **エージェント思考中** — ザリガニが考え込む
- 🔨 **ツール呼び出し中** — ザリガニが忙しく働く
- ⏳ **入力待ち** — ザリガニがキョロキョロ
- 💀 **トークン枯渇** — 水が濁り、ザリガニがひっくり返る…

> ノッチの中のエビ。

---

## 機能

### 🎮 デュアル生物システム

2匹のピクセル生物が同じ水槽で暮らし、それぞれ異なる AI データソースを追跡：

| 生物 | 役割 | データソース |
|------|------|------------|
| 🦀 **ヤドカリ** | ローカル AI | Unix Socket / ローカルファイル |
| 🦞 **ザリガニ** | リモート AI | TCP / Gateway WebSocket |

### 🌊 没入型水中シーン

- ピクセルアートの海底 — 砂地、揺れる海藻、浮かぶ気泡、光線
- O₂ 連動 — トークン消費が多いほど、水が濁り気泡が減少
- インタラクションパーティクル — 2匹がアイドル時に出会って遊び、星や水しぶきが弾ける

### 📊 O₂ タンク（トークン使用量メーター）

ストリートファイター風ピクセルヘルスバーで、トークン消費を直感的に表示：

| O₂ % | 色 | 水面効果 |
|-------|-----|---------|
| 100–60% | 🟢 緑 | 澄んだ水、通常の気泡 |
| 60–30% | 🟡 黄 | 暗めの水、気泡減少 |
| 30–10% | 🔴 赤点滅 | 濁った水、薄暗い光 |
| 0% | 💀 K.O. | ひっくり返り |

2つのモードに対応：
- **Claude クォータ** — `stats-cache.json` を読み取り、日次サブスクリプション枠を追跡
- **従量課金** — Anthropic / xAI / OpenAI API の実使用量クエリに対応

### 🔌 3つの動作モード

```
モードA：ローカル     モードB：リモート2台      モードC：サーバー
┌──────────┐     ┌──────────┐  ┌──────────┐    ┌──────────┐
│ Agent    │     │ Agent    │  │ Rockpile │    │ Agent    │
│ Rockpile │     │ Rockpile │  │ 🦞 Notch │    │ Rockpile │
│ 🦞 Notch │     │ (UIなし) │  │ (モニター)│    │ (UIなし) │
└──────────┘     └────┬─────┘  └────┬─────┘    └──────────┘
  Unix Socket         TCP:18790     │              Gateway
                      ────────────▶ │              WebSocket
```

| モード | 比喩 | ユースケース |
|--------|------|------------|
| **ローカル** | 養殖エビ 🏠 | エージェントとアプリが同じ Mac |
| **モニター** | 水槽 🐟 | MacBook がリモート Mac Mini のエージェント状態を表示 |
| **サーバー** | 野生エビ 🌊 | Mac Mini がエージェントを実行、モニターにイベント送信 |

### 🎭 7つの状態 × 4つの感情

| 状態 | トリガー | 感情バリエーション |
|------|---------|-----------------|
| 💤 アイドル | エージェントがタスク完了 | 😐 😊 😢 😠 |
| 🧠 思考中 | LLM 推論中 | 😐 😊 |
| 🔨 作業中 | ツール呼び出し / コード生成 | 😐 😊 😢 |
| ⏳ 待機中 | ユーザー入力待ち | 😐 😢 |
| ❌ エラー | ツール呼び出し失敗 | 😐 😢 |
| 🌀 圧縮中 | コンテキスト圧縮 | 😐 😊 |
| 😴 スリープ | 5分間非アクティブ | 😐 😊 |

感情は Claude Haiku がユーザーメッセージの感情をリアルタイム分析し、60秒で自然減衰。

### 🤝 インタラクションシステム

| 操作 | 効果 |
|------|------|
| クリック | 状態に応じた反応（ジャンプ+テキスト） |
| ダブルクリック | ハートパーティクル |
| 長押し | 情報カード |
| 右クリック | エサやり（+O₂） |

2匹の生物はアイドル時に自動でインタラクション — バンプ、追いかけっこ、ハサミグータッチ、横並びスウェイ。

### 📡 Gateway 双方向通信

- WebSocket でリモートエージェントに接続（`ws://<host>:18789`）
- リモートセッション、トークン詳細、ヘルス状態をリアルタイム取得
- **リバースコマンド** — Notch からリモートエージェントに直接メッセージ送信
- 自動再接続（指数バックオフ 1s → 30s）
- トークン認証（HMAC-SHA256）

### 🐾 セッションフットプリント

セッション完了後に自動保存、表示内容：
- タイムスタンプ（スマートフォーマット：今日 `14:32` / 昨日 `昨日 14:32` / `3/8 14:32`）
- トークン消費量（`1.2K` / `2.1M`）
- ツール呼び出しサマリー（`bash·edit·grep +2`）
- 展開可能なトークン内訳（入力 / 出力 / キャッシュ読取 / キャッシュ書込）

### 🌏 3言語対応

- 🇨🇳 中国語
- 🇺🇸 英語
- 🇯🇵 日本語

---

## 📈 プロジェクト統計

| 指標 | データ |
|------|--------|
| **言語** | Swift 6.0 (100%) |
| **ソースファイル** | 63 個の Swift ファイル |
| **コード行数** | ~12,600+ |
| **スプライト素材** | 34 セット（41 画像） |
| **モジュール** | Core (6) · Models (9) · Services (19) · Views (22) · Window (5) |
| **多言語** | 🇨🇳 中文 · 🇺🇸 English · 🇯🇵 日本語 |
| **最小バージョン** | macOS 15.0 Sequoia |

---

## 必要環境

| 項目 | 要件 |
|------|------|
| **OS** | macOS 15.0 (Sequoia) 以降 |
| **ハードウェア** | Notch 付き MacBook（2021年以降） |
| **Xcode** | 16.0+（ソースからビルド時） |
| **XcodeGen** | `brew install xcodegen` |

---

## インストール

### 方法 1：DMG インストーラー（推奨）

[Releases](https://github.com/ar-gen-tin/rockpile/releases) から最新の `.dmg` をダウンロードし、Applications にドラッグ。

> 署名済み + Apple 公証済み。ダブルクリックで開けます。

### 方法 2：ソースからビルド

```bash
# プロジェクトをクローン
git clone https://github.com/ar-gen-tin/rockpile.git
cd rockpile

# ビルドツールをインストール
brew install xcodegen

# Xcode プロジェクト生成 & ビルド
xcodegen generate
xcodebuild -project Rockpile.xcodeproj \
  -scheme Rockpile \
  -configuration Release \
  build

# または Xcode で直接開く
open Rockpile.xcodeproj   # Cmd+R で実行
```

---

## クイックスタート

### 1. 初回起動

Rockpile を開くと、セットアップウィザードが自動表示：

1. **言語選択** — 中国語 / English / 日本語
2. **モード選択** — ローカル / モニター / サーバー
3. **O₂ 設定** — AI プロバイダー、タンク容量、Admin Key（任意）
4. **プラグインインストール** — `~/.rockpile/plugins/rockpile/` に Hook プラグインを自動生成

### 2. 日常使用

- Notch の横にザリガニが出現 — エージェントの状態をリアルタイム反映
- **Notch をホバー / クリック** — パネル展開、アクティビティログ・O₂ 使用量・セッション履歴を表示
- **メニューバーアイコン** — ステータス、ペアリングコード、設定にクイックアクセス

### 3. リモートペアリング（2台モード）

```
MacBook（モニター）                    Mac Mini（サーバー）
1.「モニター」モードを選択              1.「サーバー」モードを選択
2. ペアリングコード表示: 1HG-E15W  →   2. ペアリングコードを入力
3. 🦞 リモートイベントに応答開始        3. プラグイン自動インストール
```

ペアリングコード = IP アドレスの Base-36 エンコード（例：`192.168.1.100` → `1HG-E15W`）

---

## アーキテクチャ

```
Claude Code Plugin (JS)
    ↓ Unix Socket / TCP:18790
SocketServer (BSD Socket, DispatchSource)
    ↓ HookEvent JSON
StateMachine (@MainActor, @Observable)
    ↓ 状態ルーティング
SessionStore → SessionData[] → ClawState / EmotionState / TokenTracker
    ↓ SwiftUI リアクティブ
NotchContentView → PondView (水中シーン) + ExpandedPanelView (情報パネル)

Gateway WebSocket (ws://<host>:18789)
    ↓ 双方向通信
GatewayClient → GatewayDashboard (health/status/sessions)
    ↓ リバースコマンド
CommandSender → chat.send → Remote Agent
```

### 技術スタック

| 項目 | 技術 |
|------|------|
| 言語 | Swift 6.0（strict concurrency） |
| UI | SwiftUI + AppKit |
| 状態管理 | @Observable + @MainActor |
| ネットワーク | BSD Socket + URLSession WebSocket |
| アニメーション | TimelineView + Canvas（Timer リークなし） |
| 永続化 | UserDefaults + Keychain + アトミックファイル書込 |
| ビルド | XcodeGen + xcodebuild |
| 署名 | Developer ID + Hardened Runtime + 公証 |

### プロジェクト構造

```
Rockpile/
├── Core/             # 設定、ローカライズ、デザインシステム、起動
├── Models/           # 状態enum、感情、セッションデータ、トークン追跡
├── Services/         # Socket サーバー、Gateway、感情分析、プラグイン管理
├── Views/            # 水中シーン、スプライトアニメ、パネル、オンボーディング
├── Window/           # Notch ウィンドウ、シェイプ、ヒットテスト
├── Assets.xcassets/  # 38 スプライトセット（7状態 × 2-3感情 × 2生物）
├── AppDelegate.swift # ライフサイクル & モードルーティング
└── RockpileApp.swift # @main エントリー
```

---

## ロードマップ

- [x] v0.1 — 基盤：3モード、7状態、O₂システム、セットアップウィザード
- [x] v1.0 — リブランド ClawEMO → Rockpile
- [x] v1.1 — セッション履歴（フットプリント）、バージョン更新フロー
- [x] v1.2 — フットプリントシステム、アトミック書込永続化
- [x] v1.3 — Gateway WebSocket、リバースコマンド、リモートアクティビティ追跡
- [x] v2.0 — デュアル生物システム、Token API モニタリング、3言語 i18n
- [ ] v2.5 — ドラッグ給餌、緊急停止、育成システム
- [ ] v3.0 — LAN 水槽訪問、チームランキング、共有水槽

---

## ドキュメント

| ドキュメント | 説明 |
|------------|------|
| [INSTALL.md](INSTALL.md) | インストールガイド（3モードの詳細手順） |
| [DEVLOG.md](DEVLOG.md) | 開発ログ（アーキテクチャ、バージョン履歴、技術詳細） |
| [ROADMAP.md](docs/ROADMAP.md) | プロダクトロードマップ |

---

## ライセンス

[MIT License](LICENSE) — 自由に使用・改変・配布可能。

スプライトアート素材は本プロジェクト専用であり、MIT ライセンスの対象外です。

---

<div align="center">

**🦞 ノッチの中のエビ。**

[ダウンロード](https://github.com/ar-gen-tin/rockpile/releases) · [インストールガイド](INSTALL.md) · [開発ログ](DEVLOG.md) · [ロードマップ](docs/ROADMAP.md)

</div>
