import type { Card } from './card';
import { makeCard } from './card';
import type { ExtractionResult } from './ocr';

/** フルネームを空白で姓・名に分割(iOS Card.splitFullName と一致)。 */
export function splitFullName(full: string | null | undefined): { family: string | null; given: string | null } {
  if (!full || full.length === 0) return { family: null, given: null };
  const parts = full.split(/[ 　]+/).filter((p) => p.length > 0);
  if (parts.length === 0) return { family: null, given: null };
  if (parts.length === 1) return { family: parts[0], given: null };
  return { family: parts[0], given: parts.slice(1).join(' ') };
}

/** 抽出結果から確認画面の初期値となる Card ドラフトを作る(代表値を各1つ採用)。 */
export function draftFromExtraction(result: ExtractionResult, id: string = crypto.randomUUID()): Card {
  const { family, given } = splitFullName(result.personName?.full?.value);
  return makeCard({
    id,
    familyName: family,
    givenName: given,
    familyNameKana: result.personName?.familyKana?.value ?? null,
    givenNameKana: result.personName?.givenKana?.value ?? null,
    company: result.company?.value ?? null,
    department: result.department?.value ?? null,
    title: result.title?.value ?? null,
    email: result.email[0]?.value ?? null,
    phone: result.phone[0]?.value ?? null,
    mobile: result.mobile[0]?.value ?? null,
    fax: result.fax[0]?.value ?? null,
    postalCode: result.postalCode?.value ?? null,
    address: result.address?.value ?? null,
    url: result.url[0]?.value ?? null,
  });
}
