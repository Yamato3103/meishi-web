# MeishiVault（名刺管理）

共通ルールは上位 `../CLAUDE.md`（または AGENTS.md）。ここはこのアプリ固有の入口だけ。

- monorepo: `ios/MeishiKit`（ロジック層・SwiftPM・GRDB）/ `ios/MeishiVault`（SwiftUI シェル）/ `web/`（Vite + React + TS）/ `spec/`（抽出ルール。iOS と Web で共有）/ `docs/`
- ロジックのテスト（高速）: `cd ios/MeishiKit && swift test`
- アプリのビルド: `cd ios/MeishiVault && xcodebuild build -scheme MeishiVault -destination 'platform=iOS Simulator,name=iPhone 17'`
- 環境: Xcode 26 / Swift 6 系、最小 iOS 17、iPhone 専用（縦固定）、開発リージョン=日本語
- 検索のとき `ios/MeishiKit/.build`（数千ファイル）は無視する
- 設計は `設計書.md`（20章）と `Phase1タスク分解.md`。必要な章だけ読む
- リポジトリ: Yamato3103/meishi-web（公開）
