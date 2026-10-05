# App Store Connect 審査メモ / Review Notes（コピペ用）

App Store Connect の「App Review Information → Notes」に貼る英語メモ。
**過去にオニリマ/冷蔵庫で「購入画面が見つからない」= 2.1(b) 却下が繰り返された**ため、
Tip Jar（消費型 IAP）に到達する正確なタップ手順を必ず明記する。

---

## Notes（英語・貼り付け用）

```
Thank you for reviewing MeishiVault.

OVERVIEW
MeishiVault is a privacy-first business card manager. All data stays on the
device. There is NO account and NO login required — every feature is usable
immediately from a fresh install. The developer operates no server and collects
no data (App Privacy: Data Not Collected).

PERMISSIONS
- Camera: used only to photograph a business card for on-device OCR (Apple Vision).
- Contacts: requested ONLY if the user taps "Add to Apple Contacts" on a card,
  to write that single card into Contacts. The app never reads contacts.

OPTIONAL GOOGLE DRIVE SYNC
Sync to the user's OWN Google Drive is optional and OFF by default. It uses the
drive.file scope (access limited to files the app itself creates). No data passes
through any developer server. You do NOT need to test sync to review the app.

IN-APP PURCHASE — TIP JAR ("Support the developer")
The app is FREE. It offers consumable IAPs that are a pure "tip" to support
development. They unlock NOTHING — no features change after purchase.

HOW TO REACH THE PURCHASE SCREEN (2 taps from launch):
  1. On the main card list, tap the gear icon (Settings) at the TOP-LEFT.
  2. In Settings, tap "開発を応援" (Support the developer).
     -> The Tip Jar screen shows three tip amounts (approx. ¥120 / ¥370 / ¥730).
     Tapping an amount starts a standard StoreKit purchase; a thank-you message
     is shown afterward. No content is unlocked.

Product IDs (consumable):
  com.meishivault.app.tip.small
  com.meishivault.app.tip.medium
  com.meishivault.app.tip.large

CONTACT
kou.ohori@gmail.com
```

---

## 補足（日本語・ASC 入力のメモ）

- **Primary language**: 日本語。上記メモは英語（審査担当者向け）。
- **App Privacy**: すべて「Data Not Collected」を宣言できる（サーバなし・端末内完結）。
- **輸出コンプライアンス**: 標準暗号（HTTPS）のみ → 「非該当」。
  `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` を設定済みなので、
  アップロード時に毎回聞かれる輸出コンプライアンスの確認は出ない。
- **IAP 提出物**: 消費型3種（small/medium/large）に各ローカライズ表示名 + 審査用スクショが必要。
  価格帯は `.storekit` の ¥120/¥370/¥730 に対応（ASC 側は Tier で選ぶ）。
- **プライバシーポリシー URL**: `docs/privacy-policy.html` をホスティングした URL を入力
  （データ非収集でも URL 必須）。**`web/public/privacy-policy.html` にも同じ内容を配置済み**なので、
  Web版を GitHub Pages 等に公開すれば `<公開URL>/privacy-policy.html` がそのままこの欄に使える
  （二重管理注意: 内容を変えたら両方に反映する）。
