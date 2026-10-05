#!/usr/bin/env bash
# 端末内 OCR(Tesseract.js)の資産を public/ に配置する。
#   - worker / core: node_modules からコピー(オフライン & CDN 非依存)
#   - traineddata:  tessdata_fast(jpn/eng)をダウンロード
# 資産は容量が大きいので repo には commit しない(.gitignore 済)。開発/デプロイ時に一度実行する。
#
# 使い方: cd web && npm install && npm run setup:ocr
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"   # web/
pub="$here/public"
core="$here/node_modules/tesseract.js-core"
worker="$here/node_modules/tesseract.js/dist/worker.min.js"

mkdir -p "$pub/tesseract" "$pub/tessdata"

echo "▶ worker / core をコピー…"
cp "$worker" "$pub/tesseract/"
# SIMD + LSTM のみ(Chromium/Safari は wasm SIMD 対応)。glue(.wasm.js)と実体(.wasm)を対で置く。
cp "$core/tesseract-core-simd-lstm.wasm.js" "$pub/tesseract/"
cp "$core/tesseract-core-simd-lstm.wasm"    "$pub/tesseract/"

echo "▶ traineddata(tessdata_fast: jpn, eng)をダウンロード…"
base="https://tessdata.projectnaptha.com/4.0.0_fast"
for lang in jpn eng; do
  out="$pub/tessdata/$lang.traineddata.gz"
  if [ -f "$out" ]; then
    echo "  - $lang: 既にあり(スキップ)"
  else
    echo "  - $lang: 取得中…"
    curl -fsSL "$base/$lang.traineddata.gz" -o "$out"
  fi
done

echo "✔ 完了: $pub/tesseract, $pub/tessdata"
