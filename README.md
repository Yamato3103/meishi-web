# MeishiVault(仮)— データを預からない名刺管理

サーバレス・ローカルファーストの名刺管理プラットフォーム。iOS(SwiftUI)+ Web、本体無料・サブスクなし(開発を応援する任意の Tip Jar のみ)。詳細は [設計書.md](設計書.md) と [Phase1タスク分解.md](Phase1タスク分解.md)。

## リポジトリ構成(monorepo)

```
名刺管理/
├─ ios/
│  ├─ MeishiKit/        … ロジック層(Core/Data/Domain)のSwiftPMパッケージ。GRDB依存。`swift test` 可
│  └─ MeishiVault/      … SwiftUIアプリシェル(Feature層)。MeishiKitをローカル依存
├─ web/                 … Web版(Vite + React + TS)。iOSと同じ spec/・card.json・正規化・LWW を共有(Phase 3)
├─ spec/                … フィールド抽出ルール(iOS/Web共有)。JSONルール+スキーマ+テストベクタ
├─ docs/                … 補助ドキュメント(設計書は当面リポジトリ直下に配置)
├─ .github/workflows/   … CI(spec JSON検証 / MeishiKitテスト / アプリのシミュレータビルド)
├─ 設計書.md            … 20章の設計書 v1.1
└─ Phase1タスク分解.md   … Phase 1(iOS単体MVP)のチケットとM1手順
```

## 開発の始め方

ロジック層のテスト(シミュレータ不要・高速):

```bash
cd ios/MeishiKit && swift test
```

アプリをシミュレータでビルド:

```bash
cd ios/MeishiVault && xcodebuild build -scheme MeishiVault -destination 'platform=iOS Simulator,name=iPhone 17'
```

## 環境
- Xcode 26 / Swift 6 系、最小iOS 17、iPhone専用(縦固定)、開発リージョン=日本語
- 依存: GRDB.swift(SwiftPM)

## 現状(Phase 1 完了 → Phase 2 着手)
実装・検証済み(累計81テスト、Debug/Release ともビルド成功):
- **取り込み**: カメラ/写真ライブラリ → 端検出・透視補正 → 画像保存(sha256)
- **OCR**: Vision + `spec/` の決定論ルールで各フィールド自動抽出 → 確認画面にプリフィル
- **管理**: 一覧・全文検索(FTS5 trigram)・詳細(電話/メール/住所/URLアクション)・編集
- **重複検知**: 登録時に候補提示 → マージ / 別人として登録
- **タグ**: 作成・付与・一覧の絞り込み(お気に入り・メモも)
- **書き出し**: vCard 共有 / Apple 連絡先へ登録
- **安心**: App Lock(Face ID)・最近削除(30日)・ローカルバックアップ(書き出し/復元)
- **提出準備**: オンボーディング・アプリアイコン・アクセシビリティラベル。検証用 `--demo-*` 引数は `#if DEBUG` で Release から除外済み
- **応援(Tip Jar)**: StoreKit 2 の消費型 IAP で「開発を応援」(`App/TipJarController.swift` + `Views/TipJarView.swift`、設定から導線)。機能解放はしない純粋なチップ(¥120/¥370/¥730、商品ID `com.meishivault.app.tip.small/medium/large`)。ローカル検証用に `MeishiVault.storekit` 同梱。**Xcode ビルド/シミュレータ・Sandbox 実購入の検証はユーザー作業**(この Mac は `xcode-select` 未設定でビルド不可)。方針・残作業は [docs/ios-release-checklist.md](docs/ios-release-checklist.md) §E

### Phase 2(Drive 同期)
- **P2-A 完了**: `card.json` 契約(§10.1)+ フィールド単位 LWW + `RemoteStore` 抽象を純ロジックで実装(`ios/MeishiKit/Sources/MeishiKit/Sync/`)。未知フィールドのラウンドトリップ保持で前方互換。競合は「負けた値」を履歴に残しサイレントロスを防止。インメモリ偽ストアで検証。
- **P2-B 完了**: `SyncEngine`(push=楽観ロック付きアップロード/衝突時マージ再送、pull=初回ブートストラップ+差分、tombstone 伝播)+ DB のフィールド別更新時刻(`field_updated_at`)。2端末 + 共有偽ストアで**収束・同フィールド競合の履歴記録・削除/タグ伝播**を検証。
- **P2-C part1 完了**: 画像バイナリ転送 + **アプリの同期導線**。`FolderRemoteStore`(ユーザー所有フォルダ=端末内/将来 iCloud Drive に card.json + 画像を保存、`.sync-index.json` で版・差分管理)。設定に「同期」節(フォルダ同期トグル/今すぐ同期/最終同期・件数)。シミュレータで実際に `Documents/MeishiVaultSync/` へ card.json(可読)+画像が書き出されることを確認。
- **P2-C part2 完了**: **Google Drive** 実装(`GoogleDriveRemoteStore` = Drive REST v3・`drive.file`)+ **OAuth**(PKCE + `ASWebAuthenticationSession`、リフレッシュトークンは Keychain)+ 設定での Drive/フォルダ切替。REST ロジックは HTTP をモックした 7 テストで検証。実 Google 認証は各自の設定が必要 → [docs/google-drive-setup.md](docs/google-drive-setup.md)。
- **Phase 2 仕上げ 完了**: 競合の**編集履歴**を永続化し、名刺詳細に「編集履歴(自動解決)」として表示(負けた値を破棄可能)。**起動・復帰時の自動同期**。同期フォルダを **Files アプリに可視化**(`UIFileSharingEnabled`)。
- Phase 2 残り(実機/ユーザー作業): iCloud Drive フォルダ実配置(entitlements)、実機での実 OAuth 疎通、`manifest.json` 最適化。

### Phase 3(Web版)— 着手
- **P3-A 完了**: `web/`(Vite + React + TS)足場 + **共有コア**(`src/core/`: card.json コーデック・正規化・フィールド単位 LWW)。iOS と同一の契約。
  - 検証済み: `tsc --noEmit` 型エラー0 / `vitest run` 16/16 pass / `vite build` 成功。加えて実 iOS の card.json との形一致・normalizer・LWW を Python でも相互検証(26 チェック all pass)。
- **P3-B 完了**: フィールド抽出エンジン(`src/core/fieldExtractor.ts`)を iOS `FieldExtractor` から移植。`spec/test-vectors/{001,002}` で **iOS とまったく同じ回帰**が通る(`vitest` 21/21・`tsc` 型エラー0・`vite build` 成功)。Tesseract.js の OCR 入力(`src/ocr/`:座標正規化アダプタはテスト有、`recognize` はブラウザ実行)。
- **P3-C 完了**: SQLite 層(`src/db/`)。`SqlDriver` 抽象 + iOS と同一スキーマ(v1〜v6・FTS5 trigram)+ リポジトリ(CRUD・全文検索・タグ・画像・フィールド別時刻)。`node:sqlite` で headless 検証(**FTS5 trigram も実動**)。`vitest` 28/28・`tsc` 0・`vite build` 成功。
- **P3-D part1 完了**: ブラウザ DB ドライバ + 最小画面。**公式 `@sqlite.org/sqlite-wasm` を Web Worker で動かし OPFS SAHPool VFS で永続化**(Chromium は `createSyncAccessHandle` を Worker のみ公開/SAHPool は COOP・COEP 不要)。`WasmSqliteDriver` は postMessage 越しに同じ `SqlDriver` を実装し、OPFS 不可なら `:memory:` に自動フォールバック。**Browser ペインで実検証**(作成/検索(FTS5 trigram)/削除/**リロード後も残存**=永続化、コンソールエラー0)。
- **P3-D part2 完了**: 「使えるアプリ」の骨組み。画面遷移(軽量ルータ)で **一覧 → 詳細 → 編集/新規 + タグ + 設定 + 最近削除**。詳細は連絡先アクション(`tel:`/`mailto:`/`https:`)・お気に入り・タグ付与/絞り込み。**多タブ排他を Web Locks で実装**(単一書き込み者。別タブは OPFS を掴まず `:memory:` に静かに降格=ライブラリのエラー出力なし・ハングなし)。**Browser ペインで実検証**: 新規登録→詳細の全項目・リンク、タグ作成/付与/一覧絞り込み、お気に入り★のリロード後保持、削除→最近削除→復元、設定のストレージ「OPFS 永続化」/端末ID/件数、2 タブ目が「メモリのみ」でクリーン降格。`tsc` 0・`vitest` 28/28・`vite build` 成功。
- **P3-D part3 完了**: 取り込み(OCR)。「📷 取り込み」→画像選択→**端末内 Tesseract.js OCR**→`spec/` の決定論抽出→確認画面(プリフィル・編集可)→保存。worker/core/traineddata は CDN でなく **同一オリジンの `public/` から配信**(オフライン & プライバシー。`npm run setup:ocr` で node_modules からコピー+`tessdata_fast` jpn/eng を取得、資産は gitignore)。画像・文字はサーバに送信しない。**Browser ペインで実検証**: 合成名刺(会社/役職/メール/電話/携帯/URL)を実 OCR→確認画面に各項目が自動プリフィル(郵便の誤検出1件は確認画面で除去)→保存→詳細→**リロード後も残存**、コンソールエラー0。`tsc` 0・`vitest` 28/28・`vite build` 成功。
- **P3-D part4 完了**: 重複検知。iOS `DuplicateDetector` を TS 移植(`src/core/duplicateDetector.ts`:配点=メール+60/電話+40/氏名+30/会社+姓+20、候補閾値40・強一致60、マージは空欄補完+メモ連結+お気に入り論理和)。リポジトリに `findDuplicates`(email_normalized/company_normalized/電話でブロッキング→別人確定ペア除外→スコア降順)・`merge`(空欄補完+画像付替え+secondary を tombstone)・`markNotDuplicate` を追加。**新規保存時に候補提示→「この人に統合」/「別人として登録」**を UI に組み込み。**Browser ペインで実検証**: 同一メールの2枚目登録で「重複の確認(一致度 高)」→統合で電話が補完され secondary は消えて全1件→もう1枚を別人登録で全2件→リロード後も残存、コンソールエラー0。`tsc` 0・`vitest` 38/38・`vite build` 成功。
- **P3-E part1 完了**: Drive 同期の土台。iOS の `RemoteStore` 抽象・`SyncEngine`・`InMemoryRemoteStore` と `CardRepository+Sync` を TS 移植(`src/sync/`)。push=dirty を card.json 化して楽観ロック(If-Match)アップロード、衝突時はリモート取得→フィールド単位 LWW マージ→再送。pull=差分(初回は list=manifest 相当)を取得しローカルとマージ適用。tombstone は削除ファイルでなく `deleted_at` 付き card.json で伝播。リポジトリに `dirtyCards/buildDocument/remoteRef/markSynced/applyRemoteDocument/recordConflicts/conflicts/syncToken/setSyncToken` を追加。**2端末 + 共有偽ストア(node:sqlite=ブラウザと同一 SQL 方言)で検証**: 新規伝播・同一フィールド競合の LWW 収束と負けた値の両端末履歴記録・論理削除伝播・タグ伝播・冪等性。`tsc` 0・`vitest` 43/43・`vite build` 成功。
- **P3-E part2 完了**: **Google Drive** 実装(`GoogleDriveRemoteStore` = Drive REST v3・`drive.file`)+ HTTP/認可の抽象(`DriveHttp`/`DriveTokenProvider`)。iOS の `GoogleDriveRemoteStore.swift`/`DriveHTTP.swift` を `fetch`・`Uint8Array` に置き換えて移植(フォルダ自動作成・multipart 作成/media 更新・version 楽観ロック・changes 開始トークン→差分・tombstone)。認可はブラウザの Google Identity Services(GIS)トークンモデルを `CallbackTokenProvider` にラップ。REST ロジックは HTTP をモックした **8 テスト**で検証(list/作成/更新/version 衝突/changes/削除 tombstone/read/エラー表面化)。実 Google 認証は各自の設定が必要 → [docs/web-google-drive-setup.md](docs/web-google-drive-setup.md)。`tsc` 0・`vitest` 51/51・`vite build` 成功。
- **P3-E part3 完了**: 画像バイナリ転送。`ImageStore` 抽象(`exists`/`read`/`saveRaw`、テスト用 `MemoryImageStore`)を追加し、`SyncEngine` に `imageStore` を渡したときだけ画像本体を転送(push=card.json より先に未アップロード画像を write、pull=doc 参照でローカル未所持のものを `list()` カタログから read→save、内容アドレスで不変)。card.json は sha256 参照のみで実体はストアが保持。**2端末 + 共有偽ストア + インメモリ画像ストアで検証**: 画像バイナリが A→B に伝播し DB 行も再現/`imageStore` 無しならメタのみ同期。`tsc` 0・`vitest` 53/53・`vite build` 成功。
- **P3-E part4 完了**: ブラウザ用 OPFS `ImageStore` 実体 + 取り込み画像の永続化・詳細表示。`OpfsImageStore`(`images/` にメインスレッドの `createWritable`/`getFile` で読み書き、非対応環境は `MemoryImageStore` へフォールバック)+ `sha256hex`。取り込み保存時に画像バイナリを OPFS へ保存し `sha256` で `card_images` 行を追加(統合先/新規どちらの id にも紐づく)。名刺詳細に画像を表示(OPFS から読み Blob URL 化)。**Browser ペインで実検証**: 合成名刺を実 OCR→確認→保存→詳細に**名刺画像が表示**→**フルリロード後も表示**(OPFS の `images/<id>_front.jpg` に 21089B 実在を確認)、コンソールエラー0。`tsc` 0・`vitest` 53/53・`vite build` 成功。
- **P3-E part5 完了**: アプリ結線の仕上げ。`SyncController`(RemoteStore+`SyncEngine`(画像転送つき)を保持し `status/isSyncing/lastSyncedAt/lastSummary/error` を購読可能に。`attachRemote` で任意ストア、`connectGoogleDrive` で GIS トークン→`GoogleDriveRemoteStore`)+ `googleAuth`(GIS スクリプト読込→`CallbackTokenProvider`)。設定に「同期」節(Google Drive 接続/今すぐ同期/最終同期・送受信件数。`VITE_GOOGLE_CLIENT_ID` 未設定なら案内のみ)。名刺詳細に「編集履歴(自動解決)」節(`field_conflicts` を表示・**破棄**)。**検証**: `SyncController` を偽ストアで駆動する 4 テスト(attach→syncNow で状態更新/2台が同ストア越しに収束/購読通知/未設定判定)。**Browser ペインで実操作**: 競合を実 API で記録→詳細に「編集履歴 会社: 旧商事→新商事」表示→リロード後も残存→破棄で消える、設定の「同期」節が未設定案内を表示、コンソールエラー0。`tsc` 0・`vitest` 57/57・`vite build` 成功。実 Google サインインと Drive 実同期はユーザーの Google Cloud 設定後([docs/web-google-drive-setup.md](docs/web-google-drive-setup.md))。
- **P3-F 完了(PWA 化)**: `manifest.webmanifest`(standalone・テーマ色・192/512/maskable アイコン)+ `sw.js`(Service Worker: ナビゲーション=network-first→オフライン時キャッシュ、資産=stale-while-revalidate、外部オリジンは不介入)+ アイコン生成(依存ゼロの純 Node PNG ライター `tools/make-icons.mjs` = `npm run build:icons`)。`index.html`/`main.tsx` に manifest リンクと SW 登録を追加。**Browser ペインで実検証**: manifest 解析(standalone・アイコン any/maskable)、Service Worker が **active かつページを制御**、`meishivault-v1` キャッシュに sqlite wasm/worker/アイコン等が実際に蓄積(オフライン shell)、コンソールエラー0。`tsc` 0・`vitest` 57/57・`vite build`(dist に manifest/sw/icons を同梱)成功。
  - **Phase 3(Web MVP)一区切り**。残り(ユーザー作業): 実 Google OAuth 疎通、公開ホスティング(HTTPS・同一オリジン配信)。

残り(Phase 1 の外形): 提出メタデータ(スクショ・審査メモ・価格 = App Store Connect のユーザー作業)。
