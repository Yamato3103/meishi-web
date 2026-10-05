# spec/ — 名刺フィールド抽出ルール(iOS/Web共有資産)

このディレクトリは **決定論的フィールド抽出エンジン**の仕様。クラウドAIを使わず、正規表現 + ラベル + 辞書 + レイアウト(座標)ヒューリスティックだけで、OCR結果から名刺の各フィールドを推定する。

- **iOS(Vision)** と **Web(Tesseract.js)** は、OCR結果を共通の入力形式(`OcrDocument`)に整形してから、この `rules/extraction-rules.json` を読んで**同一ロジック**で抽出する。
- ルールを1か所(`spec/`)に置くことで、Phase 3のWeb版で抽出ルールを作り直さずに再利用する(設計書 確定#6)。
- CIは `test-vectors/` の「OCR入力 → 期待フィールド」対を回帰テストにかける。

## データフロー

```
[iOS] Vision (VNRecognizeTextRequest)  ┐
                                        ├─→ OcrDocument(共通入力) ─→ 抽出エンジン(rules適用) ─→ ExtractionResult ─→ 確認・修正UI ─→ 保存
[Web] Tesseract.js                      ┘
```

エンジン本体(Swift / TypeScript)は各プラットフォームで実装するが、**振る舞いは本specとtest-vectorsで固定**する。同じ入力に同じ出力を返すことをCIで担保する(実装差異=バグ)。

## ファイル

| パス | 役割 |
|------|------|
| `rules/extraction-rules.json` | 抽出ルール本体(detector順・辞書・正規化設定) |
| `schema/ocr-document.schema.json` | エンジン**入力**の形(OCR行 + 座標 + 信頼度) |
| `schema/extraction-result.schema.json` | エンジン**出力**の形(フィールド + 信頼度 + 由来行) |
| `schema/extraction-rules.schema.json` | ルールファイル自体の妥当性検証スキーマ |
| `test-vectors/*.json` | `{input: OcrDocument, expected: ExtractionResult(部分)}` の回帰ケース |

## 座標系の約束
- `bbox` は画像左上原点、**0.0〜1.0 に正規化**(`x,y,w,h`)。iOSのVisionは左下原点なので、共通入力へ整形する時点で**上下反転して合わせる**。
- フォントサイズの代理値は `bbox.h`(行の高さ)。氏名/会社の推定に使う。

## detector種別(エンジンが実装する抽出手段)

| kind | 説明 | 主な対象 |
|------|------|---------|
| `regex` | 正規表現マッチ。Swift(NSRegularExpression)/JS(RegExp)双方で動く記法に限定(**後読み・名前付きグループ不使用**) | email, url, 郵便番号, 電話, FAX, 携帯 |
| `labeledValue` | 同一行/近接行のラベル語(TEL, FAX, 〒 等)に続く値を採用。ラベルで種別を確定。**1行に番号が複数あるときは番号ごとに「直前のラベル → 直後のラベル → 行全体」の順で判定**(`TEL … / FAX …` を両方FAXにしない。test-vectors 003/004) | 電話 vs FAX vs 携帯 の判別 |
| `dictionaryContains` | 辞書語を含む行を候補化。**部署と役職が1行に並ぶ行は、役職語より前に部署語があるときだけ分割**(「営業部 課長」→部署+課長。「営業部長」は分けない)。役職だけの行は部署にしない | 役職, 部署, 会社(法人格) |
| `prefectureLine` | 都道府県辞書 or 直前の〒に続く行を住所とみなし、複数行連結 | 住所 |
| `layoutLargestText` | `bbox.h` が最大級の行(会社を除く)を氏名候補に | 氏名 |
| `layoutTopCompany` | 上部かつ法人格を含む/大きい行を会社候補に | 会社名 |
| `furiganaLine` | 氏名候補の直上/直下にある「ひらがな/カタカナのみ・小さい」行をふりがなに | 氏名かな |

各 detector は候補に `confidence`(0〜1)を付ける。同一フィールドに複数候補が出たら**信頼度降順**で保持し、確認UIで採用/修正できるようにする(確定#2: 氏名かなは空でも保存可・後補完可)。

## 正規化(抽出前後の共通処理)
- 入力テキストは **NFKC** 正規化(全角英数・記号を半角へ)。
- email は小文字化。
- 電話/FAX/携帯は**表示は原文維持**、突合キー用に数字のみ版も保持(重複検知E6で使用)。
- 会社の突合キーは法人格サフィックス除去 + NFKC(重複検知で使用。抽出結果自体は原文を保持)。

## バージョニング
- `rules/extraction-rules.json` の `version` は semver。ルール変更でtest-vectorsの期待値が動く場合は同PRで更新する。
- 破壊的変更(フィールドkey改名・detector種別削除)は minor 以上を上げ、設計書の変更履歴にも記録。
