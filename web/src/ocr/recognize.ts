import { createWorker, OEM, type ImageLike } from 'tesseract.js';
import type { OcrDocument } from '../core/ocr';
import { documentFromTesseract, type TesseractLine } from './tesseractAdapter';

/**
 * 端末内 OCR(Tesseract.js, WASM)。画像を認識し、共通入力 OcrDocument を返す。
 * 画像は端末外に出ない(プライバシーファースト)。ブラウザ実行前提のため単体テスト対象外
 * (座標整形は tesseractAdapter 側で純関数として検証する)。
 *
 * worker / core / traineddata は CDN ではなく **同一オリジンの public/ から** 読む
 * (オフライン動作とプライバシーのため)。資産は `tools/setup-ocr-assets.sh` で配置する。
 */

/** worker / core は node_modules から public/tesseract/ にコピーして配信する(base path 配下)。 */
const WORKER_PATH = `${import.meta.env.BASE_URL}tesseract/worker.min.js`;
const CORE_PATH = `${import.meta.env.BASE_URL}tesseract/tesseract-core-simd-lstm.wasm.js`;
/** traineddata(.gz)は public/tessdata/ に配置する。 */
const LANG_PATH = `${import.meta.env.BASE_URL}tessdata`;

export interface RecognizeOptions {
  /** 使用言語(既定: 日本語 + 英語)。 */
  langs?: string;
  /** 認識進捗(0..1)。UI のプログレス表示用。 */
  onProgress?: (ratio: number) => void;
}

export async function recognize(
  image: ImageLike,
  imageSize: { width: number; height: number },
  opts: RecognizeOptions = {},
): Promise<OcrDocument> {
  const { langs = 'jpn+eng', onProgress } = opts;
  const worker = await createWorker(langs, OEM.LSTM_ONLY, {
    workerPath: WORKER_PATH,
    corePath: CORE_PATH,
    langPath: LANG_PATH,
    workerBlobURL: false,
    logger: onProgress
      ? (m: { status?: string; progress?: number }) => {
          if (m.status === 'recognizing text' && typeof m.progress === 'number') onProgress(m.progress);
        }
      : undefined,
  });
  try {
    const { data } = await worker.recognize(image);
    // tesseract.js の型では data.lines を持つ(型定義が緩いため最小構造にキャスト)。
    const lines = ((data as unknown as { lines?: TesseractLine[] }).lines) ?? [];
    return documentFromTesseract({ lines }, imageSize.width, imageSize.height);
  } finally {
    await worker.terminate();
  }
}
