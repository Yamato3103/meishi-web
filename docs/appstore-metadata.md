# MeishiVault App Store 掲載メタデータ（コピペ用）

App Store Connect にそのまま貼れる形。**索引ルール**（アプリ名＋サブタイトル＋キーワード欄は
**合算**索引・同じ語を2箇所に書くと文字数の無駄・キーワード欄は半角カンマのみで区切る）に沿う。
字数上限: アプリ名30／サブタイトル30／キーワード欄100。検査は `python3 aso.py audit --offline`。

> ⚠️ アプリ名は暫定（MeishiVault 仮称）。確定名に変える場合は下記とスキーム/バンドル表示名も合わせる。
> サブタイトルとキーワード欄は公開APIから取れない → 変更したら手で `aso.json` も直す。

---

## 日本語（主要言語）

**アプリ名（30以内）**
```
MeishiVault 名刺スキャナ・管理
```
→ 索引: 名刺 / スキャナ / 名刺スキャナ / 管理 / 名刺管理

**サブタイトル（30以内）**
```
オフラインOCR・連絡先へ登録・広告も追跡もなし
```
→ 索引で足す語: オフライン / OCR / 連絡先 / 登録 / 広告 / 追跡

**キーワード欄（100以内・半角カンマのみ・上の2つと重複しない原子語）**
```
読み取り,人脈,顧客,営業,データ化,vCard,バックアップ,プライバシー,整理,撮影,交換,名刺入れ,名刺帳,デジタル名刺,保存,取り込み,ビジネスカード,電子名刺,スキャン,電話帳,住所録
```
→ Apple が「名刺＋読み取り＝名刺読み取り」等に自動で組み合わせるので、`名刺◯◯` はできるだけ入れない。
「ビジネスカード」はカテゴリ語「ビジネス」を含むため audit が WARN を出すが、実検索語なので残す判断。
「アプリ」は競合過多で効きにくい（audit 指摘）ため外し、より意図の強い「電話帳／住所録」に差し替えた。

**プロモーションテキスト（170以内・審査なしで随時更新可・索引されない）**
```
端末内で完結する名刺管理。撮影→OCR→保存まで全部オフライン。人脈情報をサーバに預けず、広告も追跡もなし。連絡先への書き出し・タグ・全文検索・重複マージに対応。無料＋任意のチップ。
```

**説明（Description）**
```
名刺を、あなたの端末の中だけで。

MeishiVault は「データを預けない」名刺管理アプリです。撮影・文字認識(OCR)・保存・検索まで、すべて端末内で完結。サーバに送らないので、あなたの人脈情報が外に出ることはありません。広告も、行動追跡も、アカウント登録もありません。

■ こんな人に
・名刺を写真フォルダに溜めて放置しがち
・人脈情報をクラウドに預けたくない
・シンプルで速い名刺管理がほしい

■ 主な機能
・カメラ / 写真から取り込み → 端末内OCRで氏名・会社・連絡先を自動抽出
・電話 / メール / URL はワンタップで発信・作成
・タグ・お気に入り・全文検索ですぐ再会
・重複を自動検知してマージ
・Apple 連絡先へ書き出し(vCard)
・「最近削除」で30日間は復元可能
・ローカルバックアップの書き出し / 復元
・(任意) あなた自身の Google Drive にだけ同期(drive.file スコープ・開発者のサーバは通りません)

■ プライバシー
本アプリはデータを収集しません(App Privacy: Data Not Collected)。名刺情報は端末内にのみ保存されます。

無料でお使いいただけます。気に入ったら「開発を応援」(任意のチップ)で応援いただけると励みになります。チップで機能が変わることはありません(純粋な応援です)。
```

---

## English

**App Name (≤30)**
```
MeishiVault - Card Scanner
```

**Subtitle (≤30)**
```
On-device OCR, no tracking
```

**Keyword field (≤100, commas only, atomic, no overlap with name/subtitle)**
```
contacts,vcard,networking,CRM,digital,privacy,rolodex,namecard,save,backup,meishi,export,camera,scan,business
```

**Promotional text (≤170)**
```
A business card manager that stays entirely on your device. Capture → OCR → save, all offline. Your network never touches a server. No ads, no tracking. Free, with an optional tip.
```

**Description**
```
Your business cards, kept entirely on your device.

MeishiVault is a privacy-first business card manager. Capture, on-device OCR, storage, and search all happen locally — nothing is sent to a server, so your network never leaves your phone. No ads, no tracking, no account.

WHO IT'S FOR
- You pile up card photos and never sort them
- You don't want your contacts living in someone's cloud
- You want a fast, simple card manager

FEATURES
- Import from camera or photos → on-device OCR auto-extracts name, company, contact info
- One tap to call, email, or open a URL
- Tags, favorites, and full-text search to find people fast
- Automatic duplicate detection and merge
- Export to Apple Contacts (vCard)
- "Recently Deleted" keeps items restorable for 30 days
- Local backup export / restore
- Optional sync to YOUR OWN Google Drive (drive.file scope — never through our servers)

PRIVACY
The app collects no data (App Privacy: Data Not Collected). Card data is stored only on your device.

Free to use. If you like it, an optional tip ("Support the developer") is appreciated. Tipping changes no features.
```

---

## 補足

- **サポート URL / マーケティング URL**: 必須（サポート URL）。[docs/privacy-policy.html](privacy-policy.html)
  は末尾に「お問い合わせ」節(`mailto:` 付き)を既に持つので、**新規ページを作らずこの1枚をサポート URL
  にも流用できる**（GitHub Pages 公開後は `<公開URL>/privacy-policy.html` を両方の欄に入力すればよい）。
- **カテゴリ**: 仕事効率化（Productivity）を主、ビジネスを副、あたりが素直。
- **順位追跡**: `aso.json` に MeishiVault を追加済み（`trackId` は配信後に埋める）。配信後 `aso.py snapshot` で蓄積開始。
