# MeishiVault Web(Phase 3)

Vite + React + TypeScript の **PWA**(オフライン対応・ホーム追加可)。iOS 版(`../ios`)と **同じ `spec/` 抽出ルール・card.json フォーマット・正規化・フィールド単位 LWW** を共有し、同じ Google Drive フォルダに相互アクセスする(設計書 §10「1データフォーマット原則」)。

## セットアップ(要 Node.js 20+)

```bash
cd web
npm install
npm run setup:ocr  # OCR 資産を public/ に配置(worker/core コピー + jpn/eng traineddata 取得)
npm run build:icons # PWA アイコンを生成(public/icons/、依存ゼロの純 Node PNG ライター)
npm test           # vitest(共有コアの単体テスト)
npm run dev        # Vite 開発サーバ
npm run build      # 型チェック + 本番ビルド
```

> `setup:ocr` は取り込み(OCR)機能の資産(`public/tesseract/`・`public/tessdata/`)を用意する。
> CDN に依存せず端末内・オフラインで OCR するため。資産は容量が大きいので repo には含めない(gitignore)。

> 検証済み: `tsc --noEmit`(型エラー0)/ `vitest run`(16/16 pass)/ `vite build`(本番ビルド成功)。
> 併せて実 iOS の card.json との形一致・normalizer・LWW を Python でも相互検証済み。

## 構成(現状 = P3-A〜F 完了: 共有コア + 抽出 + OPFS DB/画像 + 画面 + 取り込み OCR + 重複検知 + 同期(エンジン/Drive/画像/設定導線/競合履歴)+ PWA)

```
web/
├─ src/
│  ├─ core/                … iOS MeishiKit と対応する純ロジック(I/O なし)
│  │  ├─ json.ts           … JSONValue / 安定 stringify / 等価判定 / 表示テキスト
│  │  ├─ card.ts           … Card 型・CardFieldName(snake_case 契約)
│  │  ├─ normalizer.ts     … NFKC / email / companyKey(法人格除去、iOS と同一リスト)
│  │  ├─ cardDocument.ts   … card.json コーデック(§10.1)+ Card 相互変換・未知キー保持
│  │  ├─ lwwMerger.ts      … フィールド単位 LWW・競合(負けた値)抽出
│  │  ├─ ocr.ts            … OcrDocument / ExtractionResult 型(iOS と一致)
│  │  ├─ fieldExtractor.ts … 決定論的フィールド抽出(iOS FieldExtractor と同一挙動)
│  │  ├─ cardDraft.ts      … 抽出結果 → Card ドラフト(姓名分割)
│  │  ├─ duplicateDetector.ts … 重複スコアリング + マージ規則(iOS DuplicateDetector と同一)
│  │  └─ index.ts
│  ├─ ocr/
│  │  ├─ tesseractAdapter.ts … Tesseract 結果 → OcrDocument(ピクセル→0..1 正規化。純関数・テスト有)
│  │  └─ recognize.ts        … Tesseract.js による端末内 OCR(worker/core/lang は public/ から。ブラウザ実行)
│  ├─ db/                  … SQLite 層(iOS と同一スキーマ)
│  │  ├─ driver.ts         … SqlDriver 抽象(async)。ブラウザ=sqlite-wasm/OPFS、テスト=node:sqlite
│  │  ├─ migrations.ts     … v1〜v6(cards/FTS5 trigram/tags/同期メタ…iOS と同一)
│  │  ├─ cardRepository.ts … CRUD・FTS/LIKE 検索・タグ・画像・フィールド別時刻・重複検知・同期(dirtyCards/buildDocument/applyRemoteDocument/競合履歴/カーソル)
│  │  ├─ nodeSqliteDriver.ts … node:sqlite 実装(テスト/CI 専用。App からは import しない)
│  │  ├─ sqliteWorker.ts   … Web Worker。@sqlite.org/sqlite-wasm + OPFS SAHPool で永続化 + Web Locks 単一書込
│  │  ├─ wasmSqliteDriver.ts … ブラウザ用 SqlDriver(ワーカを postMessage で駆動)
│  │  └─ index.ts          … ブラウザ安全な再輸出(node ドライバは含めない)
│  ├─ sync/                … 同期(iOS と同じ card.json/LWW/RemoteStore 契約)
│  │  ├─ remoteStore.ts    … RemoteStore 抽象 + RemoteFileMeta/RemoteChanges/RemoteConflictError
│  │  ├─ inMemoryRemoteStore.ts … テスト用の偽ストア(競合シナリオ検証の継ぎ目)
│  │  ├─ syncEngine.ts     … push(楽観ロック/衝突時 LWW 再送)+ pull(初回ブートストラップ+差分)+ 画像バイナリ転送
│  │  ├─ imageStore.ts     … ImageStore 抽象(exists/read/saveRaw)+ MemoryImageStore(テスト用)
│  │  ├─ driveHttp.ts      … DriveHttp(fetch 抽象)+ DriveTokenProvider(Static/Callback)+ DriveError
│  │  ├─ googleDriveRemoteStore.ts … Google Drive REST v3(drive.file)実装の RemoteStore
│  │  └─ index.ts
│  ├─ app/                 … 画面と DB 接続(React)
│  │  ├─ database.ts       … DB を開き migration 適用 → CardRepository / ImageStore を返す(device_id 管理)
│  │  ├─ opfsImageStore.ts … OPFS 実体の ImageStore(images/ 配下)+ フォールバック + sha256hex
│  │  ├─ syncController.ts  … 同期の状態機械(RemoteStore+SyncEngine 保持・購読)+ getSyncController/useSyncState
│  │  ├─ googleAuth.ts      … Google Identity Services トークン取得 → CallbackTokenProvider
│  │  ├─ useDatabase.ts    … DB を一度だけ開く薄いフック
│  │  ├─ ui.ts            … 共有スタイル・氏名/URL ヘルパ
│  │  ├─ ListScreen.tsx    … 一覧(検索・タグ絞り込み)
│  │  ├─ DetailScreen.tsx  … 詳細(名刺画像表示・連絡先アクション・タグ編集・お気に入り・削除・編集履歴=競合の表示/破棄)
│  │  ├─ EditScreen.tsx    … 新規/編集/確認フォーム(全項目・initial でプリフィル可・新規保存時に重複候補提示→統合/別人登録)
│  │  ├─ CaptureScreen.tsx … 取り込み: 画像選択→OCR→抽出→確認(EditScreen)→保存時に画像を OPFS 永続化
│  │  ├─ SettingsScreen.tsx … ストレージ状態・端末ID・件数・最近削除への導線・同期(Google Drive)節
│  │  └─ DeletedScreen.tsx … 最近削除(復元/完全削除)
│  ├─ App.tsx / main.tsx   … 画面遷移(軽量ルータ)
├─ public/
│  ├─ manifest.webmanifest … PWA マニフェスト(standalone・テーマ色・icons)
│  ├─ sw.js               … Service Worker(ナビ=network-first / 資産=SWR、外部は不介入)
│  └─ icons/              … PWA アイコン(192/512/maskable、build:icons で生成)
├─ tools/setup-ocr-assets.sh … OCR 資産を public/ に配置(npm run setup:ocr)
├─ tools/make-icons.mjs   … PWA アイコン生成(依存ゼロの純 Node PNG ライター、npm run build:icons)
└─ tests/                  … vitest(57 tests: normalizer / cardDocument / lwwMerge / extraction / cardDraft / tesseractAdapter / database / duplicate / sync / googleDrive / syncController)
```

## ロードマップ(Phase 3)

- **P3-A(済)**: 足場 + 共有コア(card.json / 正規化 / LWW)+ テスト。
- **P3-B(済)**: フィールド抽出エンジン(`spec/test-vectors` で **iOS と同一回帰**)+ Tesseract.js OCR 入力。
- **P3-C(済)**: SQLite 層(`SqlDriver` 抽象 + iOS と同一スキーマ/FTS5 + リポジトリ)。`node:sqlite` で headless 検証(FTS5 trigram も実動)。
- **P3-D part1(済)**: ブラウザ DB ドライバ。公式 `@sqlite.org/sqlite-wasm` を **Web Worker** で動かし **OPFS SAHPool VFS** で永続化(Chromium は `createSyncAccessHandle` を Worker のみ公開/SAHPool は COOP・COEP 不要)。実ブラウザで作成/検索/削除/リロード後残存を検証。
- **P3-D part2(済)**: 画面の骨組み。一覧(検索・タグ絞り込み)→ 詳細(連絡先アクション・タグ・お気に入り)→ 編集/新規、設定、最近削除(復元/完全削除)。**多タブ排他を Web Locks で実装**(単一書き込み者、別タブは `:memory:` に静かに降格)。実ブラウザで全導線を検証。
- **P3-D part3(済)**: 取り込み(OCR)。画像選択→端末内 Tesseract.js OCR→`spec/` 決定論抽出→確認画面(プリフィル)→保存。worker/core/traineddata は `public/` から配信(CDN 非依存・オフライン)。**下記 `npm run setup:ocr` が必要**。実ブラウザで合成名刺の OCR→プリフィル→保存→残存まで検証。
- **P3-D part4(済)**: 重複検知(iOS `DuplicateDetector` の TS 移植)。配点(メール+60/電話+40/氏名+30/会社+姓+20)・閾値(候補40・強一致60)・マージ規則を iOS と一致。リポジトリに `findDuplicates`(email_normalized/company_normalized/電話でブロッキング→別人確定ペア除外→スコア降順)・`merge`(空欄補完+画像付替え+secondary tombstone)・`markNotDuplicate` を追加。新規保存時に候補提示→「この人に統合」/「別人として登録」を UI に組み込み、実ブラウザで統合(全1件)・別人登録(全2件)・リロード残存を検証。
- **P3-E part1(済)**: Drive 同期の土台。`src/sync/`=`RemoteStore`(抽象)・`InMemoryRemoteStore`(テスト用偽ストア)・`SyncEngine`(push=楽観ロック付きアップロード/衝突時 LWW マージ再送、pull=初回ブートストラップ+差分、tombstone 伝播)。リポジトリに同期用メソッド(dirtyCards/buildDocument/remoteRef/markSynced/applyRemoteDocument/recordConflicts/syncToken)を追加。2端末 + 共有偽ストアで収束・同一フィールド競合の履歴記録・削除/タグ伝播・冪等を検証(`vitest` 43/43)。
- **P3-E part2(済)**: **Google Drive** 実装。`src/sync/googleDriveRemoteStore.ts`(Drive REST v3・`drive.file`・フォルダ自動作成・multipart 作成/media 更新・version 楽観ロック・changes)+ `src/sync/driveHttp.ts`(`DriveHttp` = fetch 抽象、`DriveTokenProvider`/`StaticTokenProvider`/`CallbackTokenProvider`、`DriveError`)。REST は HTTP モックで 8 テスト。認可はブラウザ GIS トークンモデルを `CallbackTokenProvider` に結線(→ [../docs/web-google-drive-setup.md](../docs/web-google-drive-setup.md))。iOS と同じ `MeishiVault/` フォルダ・`card.json` を共有。
- **P3-E part3(済)**: 画像バイナリ転送。`src/sync/imageStore.ts`(`ImageStore` 抽象=exists/read/saveRaw + `MemoryImageStore`)。`SyncEngine` に `imageStore` を渡すと push で card.json より先に未アップロード画像を write、pull で参照画像を `list()` カタログから read→save(内容アドレスで不変)。2端末 + 共有偽ストア + インメモリ画像ストアで伝播を検証。
- **P3-E part4(済)**: ブラウザ用 OPFS `ImageStore` 実体 + 取り込み画像の永続化・詳細表示。`src/app/opfsImageStore.ts`(`OpfsImageStore`=OPFS の `images/` に読み書き、非対応なら `MemoryImageStore` フォールバック、`openImageStore()`/`sha256hex()`)。取り込み保存時に画像を OPFS へ保存し `card_images` 行を追加、詳細画面に画像表示。実ブラウザで OCR→保存→詳細表示→リロード後も残存を検証。
- **P3-E part5(済)**: アプリ結線の仕上げ。`src/app/syncController.ts`(`SyncController`=RemoteStore+SyncEngine を保持し状態を購読可能に、`getSyncController`/`useSyncState`)+ `src/app/googleAuth.ts`(GIS→`CallbackTokenProvider`)。設定に「同期」節、名刺詳細に「編集履歴(自動解決)」節(表示・破棄)。SyncController を偽ストアで駆動する 4 テスト、実ブラウザで競合履歴の表示/破棄・同期節の未設定案内を検証。実 Drive 同期はユーザーの Google Cloud 設定後(`VITE_GOOGLE_CLIENT_ID`)。
- **P3-F(済)**: PWA 化。`public/manifest.webmanifest`(standalone・テーマ色・192/512/maskable アイコン)+ `public/sw.js`(ナビ=network-first→オフラインでキャッシュ / 資産=stale-while-revalidate、外部オリジン不介入)+ `tools/make-icons.mjs`(依存ゼロの純 Node PNG ライター)。実ブラウザで manifest 解析・SW が active でページ制御・`meishivault-v1` キャッシュに wasm/worker/icons 蓄積を検証。残り(ユーザー作業): 実 Google OAuth 疎通・公開ホスティング(HTTPS)。
