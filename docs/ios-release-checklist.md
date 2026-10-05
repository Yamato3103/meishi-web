# MeishiVault iOS — 保留分 & リリース前チェックリスト

Phase 1(単体 MVP)+ Phase 2(Google Drive 同期)まで**実装は完了**しており、`swift test`(累計 81 テスト)と Debug/Release 両ビルドは成功している。残っているのは **実機/Xcode/App Store Connect でしか進められない作業**が中心。ここではその保留分を洗い出す。

## 現状サマリ

| 項目 | 値 |
|---|---|
| Bundle ID | `com.meishivault.app` |
| バージョン / ビルド | `1.0` / `1` |
| 対象 | iPhone 専用・縦固定・最小 iOS 17 |
| 課金 | **本体無料 + 寄付(Tip Jar = 消費型 IAP で開発を応援)**。将来一部機能の有料化は別途検討。Web 版は無償公開方針(設計書 §20) |
| 署名 | `CODE_SIGN_STYLE = Automatic`・**`DEVELOPMENT_TEAM` 未設定** |
| 権限(Info.plist) | カメラ / 連絡先の用途文言あり・`UIFileSharingEnabled` 有効 |
| アイコン | `AppIcon-1024.png` の単一サイズ(Xcode single-size) |
| Google OAuth | コードは実装済みだが **Info.plist の設定は未投入** |
| entitlements | **ファイル無し**(iCloud Drive 等の capability 未付与) |

> ⚠️ **検証の限界**: この Mac は `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` が未実行のため、iOS Simulator MCP と実タップ自動化が使えない。これまで UI は `xcrun simctl` の表示確認と `#if DEBUG` の `--demo-*` 起動引数で代替してきた。**下記 A/B/C の多くは実機 + Xcode の手動作業が前提**。

## 課金方針(2026-08-16 変更)

**本体無料 + 寄付(応援)**。将来的に一部機能の有料化を検討。

App Store 準拠のための注意:

- **「寄付(donation)」を IAP で集められるのは認定 NPO 等のみ**。個人/営利の開発者は不可。
- 代わりに **Tip Jar(開発者を応援)= 消費型 IAP(機能を一切解放しない)** で実装するのが標準・準拠ルート(例: ¥120 / ¥370 / ¥730 の複数額)。文言は「寄付」より「**開発を応援 / チップ**」が安全。
- **アプリ外の寄付リンク**(Buy Me a Coffee 等)へアプリ内から誘導するのは 3.1.1 で却下リスク。アプリ内 Tip Jar に寄せる。
- IAP を載せる以上、**有料アプリ契約(Paid Applications Agreement)は必須**(無料本体でも)。
- 将来の「一部機能を有料」= 非消費型 IAP(機能アンロック)または有料メジャーバージョンで対応(サブスクは要件どおり不採用)。

---

## A. 実機でしか確認できない機能検証(コードは実装済み)

- [ ] カメラ撮影 → 端検出 → 透視補正 → 画像保存(実機カメラ)
- [ ] 写真ライブラリ(PHPicker)からの取り込み
- [ ] 実写真の名刺で OCR → 抽出 → 確認画面プリフィルの精度(日本語氏名の姓名分割は崩れやすい)
- [ ] App Lock(Face ID / Touch ID)の解除・復帰時ロック
- [ ] vCard 共有(ShareLink)/ Apple 連絡先へ登録(実機の連絡先)
- [ ] 重複検知 → 統合 / 別人として登録の実操作
- [ ] 最近削除(30日)→ 復元 / 完全削除
- [ ] バックアップの書き出し / 復元(Files 経由)
- [ ] 同期フォルダが Files アプリに見える(`UIFileSharingEnabled`) ← **2026-08-20 バグ修正**: `INFOPLIST_KEY_UIFileSharingEnabled` は Xcode 26 の生成plistで**無視されており、これまでビルドに入っていなかった**(実測)。`ios/MeishiVault/Info.plist` に直接 `UIFileSharingEnabled=true` を置いて修正済み(ビルド後plistで `true` を確認)。実機で Files 可視化を要確認

## B. 署名・配布設定(Xcode / Apple Developer)

- [ ] Apple Developer Program 登録(有料)
- [ ] **有料アプリ契約(Paid Applications Agreement)を締結・発効** — 本体無料でも **Tip Jar(IAP)を載せるなら必須**。**姉妹アプリ「オニリマ」で実際に審査 2.1(b) 却下の原因になった最重要ブロッカー**
- [ ] Xcode の署名に開発チーム(`DEVELOPMENT_TEAM`)を設定(現状 pbxproj 未設定)
- [ ] 実機で Debug 実行(プロビジョニングの確認)
- [ ] Release アーカイブ → App Store Connect へアップロード
- [ ] TestFlight で実機動作確認(任意だが推奨)

## C. Google Drive 連携(任意機能・使う場合のみ)

未設定でもアプリは完全に動く。使う場合のみ以下(手順: [google-drive-setup.md](google-drive-setup.md))。

- [ ] Google Cloud で **iOS 用 OAuth クライアント**を作成
- [~] Info.plist の枠は配線済み → `ios/MeishiVault/Info.plist`(`INFOPLIST_FILE` で接続・生成キーとマージ・ビルド確認済み)。**残りは実 ClientID/RedirectScheme を埋めるだけ**(空なら Drive 非表示・フォルダ同期は動く)
- [~] `CFBundleURLTypes` の枠も同ファイルに用意済み → プレースホルダ `com.googleusercontent.apps.YOUR-CLIENT-ID` を実IDへ置換するだけ
- [ ] OAuth 同意画面の「テストユーザー」に自分を追加
- [ ] 実機で実 OAuth 疎通(サインイン → 接続 → 今すぐ同期 → Drive の `MeishiVault/` に card.json + 画像)
- [ ] (任意)同期フォルダを iCloud Drive に置くなら **iCloud entitlement を追加**(現状 entitlements ファイル無し)

## D. App Store Connect 提出物

- [ ] アプリ新規登録(Bundle ID / 名前 / SKU / 主要言語 = 日本語)
- [ ] **価格 = 無料(¥0)**
- [ ] **Tip Jar 用の消費型 IAP を登録**(複数額。例: `com.meishivault.app.tip.small/medium/large`)+ 各ローカライズ表示名・審査用スクショ
- [ ] スクリーンショット(必須サイズ: 6.7" 等。iPhone 専用) ← 実機/シミュレータのスクショが要る
- [~] アプリ説明・キーワード: 作成済み([docs/appstore-metadata.md](appstore-metadata.md)・JP/EN・アプリ名/サブタイトル/キーワード欄/説明/プロモ文)。`aso.py audit --offline` で NG 無しを確認(名前21/30・サブ24/30・キーワード97/100)。**サポート URL は要ホスティング**
- [~] **プライバシーポリシー**: 本文は作成済み([docs/privacy-policy.html](privacy-policy.html)・JP/EN・データ非収集)。**残りはホスティングして URL を ASC に入力**(GitHub Pages 等、または任意のサーバ)
- [ ] App Privacy 申告 — 端末内完結なので「**Data Not Collected**」を宣言できる(本アプリの売り)
- [ ] 年齢レーティング(アンケート)
- [ ] カテゴリ(例: 仕事効率化 / ビジネス)
- [x] 審査メモ(端末内完結・カメラ/連絡先の用途・Google Drive は任意機能・**Tip Jar への2タップ手順**を明記) → [docs/app-review-notes.md](app-review-notes.md) にコピペ用の英語メモ
- [x] 輸出コンプライアンス(暗号は標準のみ / 該当なし) → `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` を pbxproj の Debug/Release 両方に設定済み(ビルド後の Info.plist に `false` が入るのを確認)。アップロード時の輸出コンプライアンス確認は出なくなる

## E. Tip Jar(寄付/応援)の実装 — **コード実装済み(2026-08-20)**

実装済み(Xcode ビルド/実購入の検証だけが残る):

- [x] StoreKit 2 で消費型 IAP を実装(商品ロード → 購入 → `Transaction.finish`。機能解放はしない) → `App/TipJarController.swift`(`@MainActor @Observable`、`Transaction.updates` 監視、価格昇順ソート)
- [x] 設定に「開発を応援」導線(額を複数表示、購入後にお礼表示) → `Views/TipJarView.swift` + `SettingsView` に NavigationLink、`MeishiVaultApp` で `.environment(tips)` 注入
- [x] ローカルテスト用の StoreKit Configuration file → `ios/MeishiVault/MeishiVault.storekit`(消費型3種 `tip.small/medium/large`、¥120/¥370/¥730、ja/en ローカライズ)
- [x] 文言は「開発を応援 / チップ」(「寄付」表現は避ける)

検証済み(2026-08-20、`xcodebuild` を `/private/tmp` から絶対パスで実行):

- [x] **Debug / Release 両ビルド成功**(iPhone 17 シミュレータ・警告0)。Swift 6 の `@MainActor` `deinit` から `updatesTask` に触れられない件を修正済み(アプリ生存期間の `@State` なので明示 cancel 不要)
- [x] **スキームに `.storekit` を紐付け済み**(`MeishiVault.xcscheme` の LaunchAction に `StoreKitConfigurationFileReference identifier="../MeishiVault.storekit"`)。→ Xcode で Run すればローカル購入テストがそのまま有効
- [x] **実機シミュレータで起動・画面描画を確認**(`--demo-tipjar` 起動引数で Tip Jar を直接提示しスクショ。タイトル「開発を応援」・説明文・お礼文言が正しく描画、クラッシュ無し。`simctl launch` はスキームの StoreKit 設定を適用しないため商品は空=「応援メニューを取得できませんでした」の**ハンドリング済み空状態**を確認)

残り(**Xcode/Sandbox が前提。ユーザー作業**):

- [ ] **Xcode で Run** → StoreKit Configuration が効き、¥120/¥370/¥730 の3行が出る → タップ購入 → お礼表示・`Transaction.finish` を確認(スキーム紐付け済みなので追加設定不要)
- [ ] Sandbox アカウントで実機購入(実 App Store 経路)
- [ ] (配信時)ASC で消費型 IAP 3種を登録 + Paid Applications Agreement 締結

## F. アセット・ビルド最終確認

- [ ] AppIcon が全用途で正しく出る(現状 1024 単一。Xcode single-size 前提の確認)
- [ ] `#if DEBUG` の `--demo-*` 起動引数が Release から除外されている(実装済み・要再確認)
- [ ] Debug / Release 両ビルド成功(最終ビルドで再確認)
- [ ] `cd ios/MeishiKit && swift test` 通過(ロジック層の回帰)

---

## この Mac 側の前提(作業を始める前に)

- [ ] `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` を実行(パスワードが要るためユーザー作業)。これで Simulator MCP / 実機ビルド系が使えるようになる。

## 参考

- [google-drive-setup.md](google-drive-setup.md) — iOS 版 OAuth の設定手順
- リポジトリ直下 `README.md`「現状(Phase 1 / Phase 2)」
- `設計書.md` §20(買い切り/Web 無償の位置づけ・価格帯)
