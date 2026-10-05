/**
 * フィールド抽出エンジンの共通入出力型(iOS の OcrDocument / ExtractionResult と一致)。
 * 詳細は spec/schema/*.json。
 */

/** 画像左上原点・0..1 正規化のバウンディングボックス。 */
export interface BBox {
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface OcrLine {
  text: string;
  confidence?: number;
  bbox: BBox;
}

export interface ImageSize {
  width: number;
  height: number;
}

/** エンジン入力。iOS(Vision)/ Web(Tesseract.js)はこの形へ整形してから渡す。 */
export interface OcrDocument {
  imageSize: ImageSize;
  source?: string;
  lines: OcrLine[];
}

/** 抽出された1フィールドの候補。信頼度降順で保持する。 */
export interface Candidate {
  value: string;
  confidence: number;
  /** 由来した OcrDocument.lines の index。 */
  sourceLineIndices?: number[];
  /** 突合キー(電話の数字のみ版・会社の法人格除去版など)。 */
  normalizedKey?: string | null;
}

export interface PersonName {
  full?: Candidate;
  familyKana?: Candidate;
  givenKana?: Candidate;
}

/** 抽出エンジンの出力。 */
export interface ExtractionResult {
  email: Candidate[];
  url: Candidate[];
  phone: Candidate[];
  fax: Candidate[];
  mobile: Candidate[];
  sns: Candidate[];
  postalCode?: Candidate;
  company?: Candidate;
  department?: Candidate;
  title?: Candidate;
  address?: Candidate;
  personName?: PersonName;
}

export function emptyResult(): ExtractionResult {
  return { email: [], url: [], phone: [], fax: [], mobile: [], sns: [] };
}
