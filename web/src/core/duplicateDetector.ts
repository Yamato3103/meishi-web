/**
 * 重複検知(iOS の MeishiKit.DuplicateDetector と完全一致させる)。
 *
 * 純ロジック(I/O なし)。スコアリング・しきい値・マージ規則を iOS と同一にし、
 * どちらの端末で登録しても同じ人物を同じように束ねられるようにする(§10「1データフォーマット原則」)。
 */

import type { Card } from './card';
import { nfkc, normalizeEmail, companyKey } from './normalizer';

/** 重複候補1件。score は下記 score() の合計、isStrong は強一致(自動マージ推奨)。 */
export interface DuplicateMatch {
  card: Card;
  score: number;
  isStrong: boolean;
}

/** 候補として提示する下限。これ未満は無視。 */
export const CANDIDATE_THRESHOLD = 40;
/** 強一致(同一人物とほぼ断定)の下限。 */
export const STRONG_THRESHOLD = 60;

/**
 * 2件の一致スコア。iOS と同じ配点:
 * - メール一致 … +60
 * - 電話番号(7桁以上の数字列)の共有 … +40
 * - 氏名(姓+名)キー一致 … +30
 * - 会社名キー + 姓キー の一致 … +20
 */
export function score(a: Card, b: Card): number {
  let total = 0;

  const emailA = normalizeEmail(a.email);
  const emailB = normalizeEmail(b.email);
  if (emailA != null && emailB != null && emailA === emailB) total += 60;

  const phonesA = phoneDigits(a);
  const phonesB = phoneDigits(b);
  if (intersects(phonesA, phonesB)) total += 40;

  const nameA = fullNameKey(a);
  const nameB = fullNameKey(b);
  if (nameA != null && nameB != null && nameA === nameB) total += 30;

  const companyA = companyKey(a.company);
  const companyB = companyKey(b.company);
  const famA = nameKey(a.familyName);
  const famB = nameKey(b.familyName);
  if (companyA != null && companyB != null && companyA === companyB
      && famA != null && famB != null && famA === famB) {
    total += 20;
  }

  return total;
}

/**
 * primary を主として secondary を統合した Card を返す。
 * - 空(null/空文字)のテキスト項目は secondary の値で埋める。
 * - メモは両方あれば改行で連結。
 * - お気に入りは論理和。
 * - 交換日は primary が無ければ secondary。
 * id・作成日時・revision 等は primary を維持する(呼び出し側で更新)。
 */
export function merged(primary: Card, secondary: Card): Card {
  const out: Card = { ...primary };

  for (const key of MERGE_TEXT_FIELDS) {
    if (isBlank(out[key]) && !isBlank(secondary[key])) {
      out[key] = secondary[key];
    }
  }

  // メモは両方あれば連結(iOS と同じく空文字判定・トリムしない)。
  const sMemo = secondary.memo;
  if (sMemo != null && sMemo.length > 0) {
    const pMemo = out.memo;
    out.memo = pMemo != null && pMemo.length > 0 ? `${pMemo}\n${sMemo}` : sMemo;
  }

  out.isFavorite = primary.isFavorite || secondary.isFavorite;

  if (out.exchangedAt == null) out.exchangedAt = secondary.exchangedAt;

  return out;
}

// MARK: - 突合キー(iOS と同一)

/** phone/mobile/fax から数字だけを取り出し、7桁以上のものの集合。 */
export function phoneDigits(card: Card): Set<string> {
  const set = new Set<string>();
  for (const raw of [card.phone, card.mobile, card.fax]) {
    if (raw == null) continue;
    const digits = nfkc(raw).replace(/\D/g, '');
    if (digits.length >= 7) set.add(digits);
  }
  return set;
}

/** 姓+名を連結した氏名キー。空なら null。 */
export function fullNameKey(card: Card): string | null {
  return nameKey((card.familyName ?? '') + (card.givenName ?? ''));
}

/** 氏名系キー生成。NFKC + 空白(半角/全角)除去。空は null。 */
export function nameKey(raw: string | null | undefined): string | null {
  if (raw == null) return null;
  const key = nfkc(raw).replace(/[ 　]/g, '');
  return key.length === 0 ? null : key;
}

// MARK: - 内部

/** merged で空なら secondary から埋めるテキスト項目(iOS と同一)。値型は string | null。 */
type TextField =
  | 'familyName' | 'givenName' | 'familyNameKana' | 'givenNameKana'
  | 'company' | 'department' | 'title'
  | 'email' | 'phone' | 'mobile' | 'fax' | 'postalCode' | 'address' | 'url';

const MERGE_TEXT_FIELDS: TextField[] = [
  'familyName', 'givenName', 'familyNameKana', 'givenNameKana',
  'company', 'department', 'title',
  'email', 'phone', 'mobile', 'fax', 'postalCode', 'address', 'url',
];

function isBlank(v: string | null): boolean {
  return v == null || v === '';
}

function intersects(a: Set<string>, b: Set<string>): boolean {
  for (const x of a) if (b.has(x)) return true;
  return false;
}
