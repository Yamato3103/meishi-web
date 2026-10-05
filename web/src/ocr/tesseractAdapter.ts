import type { OcrDocument } from '../core/ocr';

/** Tesseract.js の行(bbox はピクセル座標・左上原点 x0,y0,x1,y1)。 */
export interface TesseractLine {
  text: string;
  confidence?: number;
  bbox: { x0: number; y0: number; x1: number; y1: number };
}

export interface TesseractRecognition {
  lines: TesseractLine[];
}

/**
 * Tesseract.js の認識結果を共通入力 OcrDocument へ整形する。
 * ピクセル bbox を画像サイズで割って 0..1 正規化(左上原点)し、信頼度は 0..1 に丸める。
 * この変換を純関数にすることで、ブラウザ無しでも座標整形を単体テストできる。
 */
export function documentFromTesseract(
  data: TesseractRecognition,
  imageWidth: number,
  imageHeight: number,
  source = 'tesseract',
): OcrDocument {
  const lines = data.lines
    .map((l) => ({ ...l, text: l.text.replace(/\s+$/g, '') }))
    .filter((l) => l.text.trim().length > 0)
    .map((l) => ({
      text: l.text,
      confidence: l.confidence != null ? l.confidence / 100 : undefined,
      bbox: {
        x: l.bbox.x0 / imageWidth,
        y: l.bbox.y0 / imageHeight,
        w: (l.bbox.x1 - l.bbox.x0) / imageWidth,
        h: (l.bbox.y1 - l.bbox.y0) / imageHeight,
      },
    }));

  return { imageSize: { width: imageWidth, height: imageHeight }, source, lines };
}
