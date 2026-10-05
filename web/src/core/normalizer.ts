/**
 * 突合キー生成の正規化(iOS の MeishiKit.Normalizer と完全一致させる)。
 *
 * 表示値は原文を維持し、ここで作る値は検索・重複検知の突合キーに使う。
 */

/** NFKC 正規化(全角英数・記号を半角へ、互換文字を統一)。iOS の precomposedStringWithCompatibilityMapping と等価。 */
export function nfkc(s: string): string {
  return s.normalize('NFKC');
}

/** メールの突合キー。NFKC + 前後空白除去 + 小文字化。空は null。 */
export function normalizeEmail(raw: string | null | undefined): string | null {
  if (raw == null) return null;
  const normalized = nfkc(raw).trim().toLowerCase();
  return normalized.length === 0 ? null : normalized;
}

/**
 * 除去対象の法人格表記(前後どちらでも除去)。
 * iOS Normalizer.corporateAffixes と同一・同順(順序依存: "Ltd." を "Ltd" より先に)。
 */
export const CORPORATE_AFFIXES: string[] = [
  '株式会社', '有限会社', '合同会社', '合資会社', '合名会社',
  '(株)', '(有)', '（株）', '（有）',
  'Co., Ltd.', 'Co.,Ltd.', 'Corporation', 'Corp.',
  'Inc.', 'K.K.', 'LLC', 'Ltd.', 'Ltd',
];

/**
 * 会社名の突合キー。NFKC + 法人格除去 + 空白畳み。
 * 例: "株式会社サンプル商事" → "サンプル商事"、"Sample Co., Ltd." → "Sample"。
 * (email と違い小文字化はしない。)
 */
export function companyKey(raw: string | null | undefined): string | null {
  if (raw == null) return null;
  let value = nfkc(raw).trim();
  for (const affix of CORPORATE_AFFIXES) {
    value = value.split(affix).join(' ');
  }
  // 半角/全角スペースで分割し、空要素を除いて1スペースで連結。
  const collapsed = value.split(/[ 　]+/).filter((p) => p.length > 0).join(' ');
  return collapsed.length === 0 ? null : collapsed;
}
