import type { OcrDocument, ExtractionResult, BBox } from './ocr';
import { emptyResult } from './ocr';
import { nfkc, normalizeEmail, companyKey } from './normalizer';

/**
 * 決定論的フィールド抽出エンジン(iOS MeishiKit.FieldExtractor と同一挙動)。
 * 正規表現 + ラベル + 辞書 + レイアウト(座標)で OcrDocument から各フィールドを推定する。
 * 振る舞いは spec/rules と spec/test-vectors で固定(回帰テストで担保)。
 *
 * 注: spec の単一文字ラベル("T"/"F"/"M")は誤検出が大きいため不採用(iOS と同じ意図的逸脱)。
 */
export function extract(document: OcrDocument): ExtractionResult {
  const result = emptyResult();

  const lines = document.lines.map((l) => nfkc(l.text));
  const bboxes = document.lines.map((l) => l.bbox);
  const claimed = new Set<number>();

  // メール
  lines.forEach((line, i) => {
    for (const m of regexMatches(P.email, line)) {
      const value = m.toLowerCase();
      result.email.push({ value, confidence: 0.96, sourceLineIndices: [i], normalizedKey: normalizeEmail(value) });
      claimed.add(i);
    }
  });

  // URL / SNS
  lines.forEach((line, i) => {
    for (const m of regexMatches(P.sns, line)) {
      result.sns.push({ value: m, confidence: 0.8, sourceLineIndices: [i] });
      claimed.add(i);
    }
    for (const m of regexMatches(P.urlHttp, line)) {
      result.url.push({ value: m, confidence: 0.95, sourceLineIndices: [i] });
      claimed.add(i);
    }
    for (const m of regexMatches(P.urlWww, line)) {
      if (!isPartOfEmail(m, line)) {
        result.url.push({ value: m, confidence: 0.8, sourceLineIndices: [i] });
        claimed.add(i);
      }
    }
  });

  // 郵便番号(〒を含む行を優先)
  const postal = firstMatch(P.postal, lines, '〒');
  if (postal) {
    result.postalCode = { value: postal.value, confidence: 0.9, sourceLineIndices: [postal.index] };
  }

  // 電話 / FAX / 携帯
  const claimedNumbers = new Set<string>();

  // 携帯
  lines.forEach((line, i) => {
    const hasLabel = containsAny(line, D.mobileLabels);
    for (const n of regexMatches(P.mobileNumber, line)) {
      result.mobile.push({ value: n, confidence: hasLabel ? 0.9 : 0.75, sourceLineIndices: [i], normalizedKey: digitsOnly(n) });
      claimedNumbers.add(digitsOnly(n));
      claimed.add(i);
    }
  });
  // FAX(ラベル必須。1行に TEL と FAX が並ぶ名刺があるので、番号ごとにラベルで判定する)
  lines.forEach((line, i) => {
    for (const { value: n, isFax } of classifyNumbers(line)) {
      if (!isFax || claimedNumbers.has(digitsOnly(n))) continue;
      result.fax.push({ value: n, confidence: 0.9, sourceLineIndices: [i], normalizedKey: digitsOnly(n) });
      claimedNumbers.add(digitsOnly(n));
      claimed.add(i);
    }
  });
  // 固定電話
  lines.forEach((line, i) => {
    const hasLabel = containsAny(line, D.phoneLabels);
    for (const n of regexMatches(P.phoneNumber, line)) {
      if (claimedNumbers.has(digitsOnly(n))) continue;
      result.phone.push({ value: n, confidence: hasLabel ? 0.9 : 0.6, sourceLineIndices: [i], normalizedKey: digitsOnly(n) });
      claimedNumbers.add(digitsOnly(n));
      if (hasLabel) claimed.add(i);
    }
  });

  // 会社(法人格を含む行)
  const companyIdx = lines.findIndex((l) => containsAny(l, D.corporateSuffixes));
  if (companyIdx >= 0) {
    result.company = { value: lines[companyIdx], confidence: 0.9, sourceLineIndices: [companyIdx], normalizedKey: companyKey(lines[companyIdx]) };
    claimed.add(companyIdx);
  }

  // 役職(「営業部 課長」のように部署と同じ行なら分け合う)
  const titleIdx = lines.findIndex((l) => containsAny(l, D.titles));
  const titleSplit = titleIdx >= 0 ? splitDepartmentAndTitle(lines[titleIdx]) : undefined;
  if (titleIdx >= 0) {
    result.title = { value: titleSplit?.title ?? lines[titleIdx], confidence: 0.8, sourceLineIndices: [titleIdx] };
    claimed.add(titleIdx);
  }

  // 部署(会社の行は除外。役職だけの行は部署にしない)
  for (let i = 0; i < lines.length; i++) {
    if (i === companyIdx) continue;
    if (i === titleIdx) {
      if (!titleSplit) continue;
      result.department = { value: titleSplit.department, confidence: 0.7, sourceLineIndices: [i] };
      break;
    }
    if (containsAny(lines[i], D.departmentTokens)) {
      result.department = { value: lines[i], confidence: 0.7, sourceLineIndices: [i] };
      claimed.add(i);
      break;
    }
  }

  // 住所(都道府県を含む行)
  const addrIdx = lines.findIndex((l) => containsAny(l, D.prefectures));
  if (addrIdx >= 0) {
    result.address = { value: lines[addrIdx], confidence: 0.75, sourceLineIndices: [addrIdx] };
    claimed.add(addrIdx);
  }

  // 氏名(会社/部署/役職/連絡先でない行のうち bbox.h 最大)
  const nameCandidates = lines
    .map((_, i) => i)
    .filter((i) => !claimed.has(i) && !lines[i].includes('@') && !containsDigit(lines[i]) && lines[i].trim().length > 0);
  const nameIdx = maxBy(nameCandidates, (i) => bboxes[i].h);
  if (nameIdx !== undefined) {
    result.personName = { full: { value: lines[nameIdx], confidence: 0.6, sourceLineIndices: [nameIdx] } };
    const kanaIdx = furiganaIndex(nameIdx, lines, bboxes);
    if (kanaIdx !== undefined) {
      const parts = lines[kanaIdx].split(/[ 　]+/).filter((p) => p.length > 0);
      if (parts.length >= 1) {
        result.personName.familyKana = { value: parts[0], confidence: 0.55, sourceLineIndices: [kanaIdx] };
      }
      if (parts.length > 1) {
        result.personName.givenKana = { value: parts[1], confidence: 0.55, sourceLineIndices: [kanaIdx] };
      }
    }
  }

  return result;
}

// MARK: - ヘルパー

function furiganaIndex(nameIdx: number, lines: string[], bboxes: BBox[]): number | undefined {
  const nameY = bboxes[nameIdx].y;
  const candidates = lines
    .map((_, i) => i)
    .filter((i) => i !== nameIdx && isKanaOnly(lines[i]) && bboxes[i].h <= bboxes[nameIdx].h && Math.abs(bboxes[i].y - nameY) < 0.12);
  return minBy(candidates, (i) => Math.abs(bboxes[i].y - nameY));
}

function isKanaOnly(text: string): boolean {
  const trimmed = text.replace(/[ 　]/g, '');
  if (trimmed.length === 0) return false;
  for (const ch of trimmed) {
    const v = ch.codePointAt(0)!;
    const isHiragana = v >= 0x3041 && v <= 0x309f;
    const isKatakana = v >= 0x30a0 && v <= 0x30ff;
    if (!(isHiragana || isKatakana)) return false;
  }
  return true;
}

/**
 * 1行の電話番号を、直前のラベル(無ければ直後のラベル、それも無ければ行全体)で TEL / FAX に分ける。
 * "TEL 03-1234-5678 / FAX 03-1234-5679" のような並びで、両方を FAX にしないため。
 */
function classifyNumbers(line: string): { value: string; isFax: boolean }[] {
  const found = [...line.matchAll(new RegExp(P.phoneNumber, 'g'))];
  const lineHasFax = containsAny(line, D.faxLabels);
  const lineHasPhone = containsAny(line, D.phoneLabels);
  let prevEnd = 0;
  return found.map((m, k) => {
    const start = m.index ?? 0;
    const end = start + m[0].length;
    const before = line.slice(prevEnd, start);
    const after = line.slice(end, found[k + 1]?.index ?? line.length);
    prevEnd = end;
    const beforeFax = lastLabelEnd(before, D.faxLabels);
    const beforePhone = lastLabelEnd(before, D.phoneLabels);
    if (beforeFax !== beforePhone) return { value: m[0], isFax: beforeFax > beforePhone };
    const afterFax = firstLabelStart(after, D.faxLabels);
    const afterPhone = firstLabelStart(after, D.phoneLabels);
    if (afterFax !== afterPhone) return { value: m[0], isFax: afterFax < afterPhone };
    return { value: m[0], isFax: lineHasFax && !lineHasPhone };
  });
}

/** text 内で最後に現れるラベルの終端位置(無ければ -1)。 */
function lastLabelEnd(text: string, labels: readonly string[]): number {
  return Math.max(-1, ...labels.map((l) => (text.lastIndexOf(l) >= 0 ? text.lastIndexOf(l) + l.length : -1)));
}

/** text 内で最初に現れるラベルの開始位置(無ければ Infinity)。 */
function firstLabelStart(text: string, labels: readonly string[]): number {
  return Math.min(Infinity, ...labels.map((l) => (text.indexOf(l) >= 0 ? text.indexOf(l) : Infinity)));
}

/**
 * 「営業本部 第一営業部  課長」のように部署と役職が1行に並ぶとき、役職語の手前を部署、
 * そこから後ろを役職に分ける。手前に部署語が無ければ(「営業部長」など)分けない。
 */
function splitDepartmentAndTitle(line: string): { department: string; title: string } | undefined {
  let start = -1;
  for (const t of D.titles) {
    const at = line.indexOf(t);
    if (at < 0) continue;
    if (start < 0 || at < start) start = at;
  }
  if (start <= 0) return undefined;
  const department = line.slice(0, start).trim();
  const title = line.slice(start).trim();
  if (department.length === 0 || !containsAny(department, D.departmentTokens)) return undefined;
  return { department, title };
}

function containsAny(text: string, needles: readonly string[]): boolean {
  return needles.some((n) => text.includes(n));
}

function containsDigit(text: string): boolean {
  return /[0-9]/.test(text);
}

function digitsOnly(text: string): string {
  return text.replace(/[^0-9]/g, '');
}

function isPartOfEmail(substring: string, line: string): boolean {
  return regexMatches(P.email, line).some((e) => e.includes(substring));
}

function regexMatches(pattern: string, text: string): string[] {
  const re = new RegExp(pattern, 'g');
  const out: string[] = [];
  for (const m of text.matchAll(re)) out.push(m[0]);
  return out;
}

/** marker を含む行を優先して最初にマッチした値を返す(安定=元の並びを保つ)。 */
function firstMatch(pattern: string, lines: string[], marker: string): { index: number; value: string } | undefined {
  const ordered = lines
    .map((_, i) => i)
    .sort((a, b) => (lines[a].includes(marker) ? 0 : 1) - (lines[b].includes(marker) ? 0 : 1));
  for (const i of ordered) {
    const m = regexMatches(pattern, lines[i])[0];
    if (m !== undefined) return { index: i, value: m };
  }
  return undefined;
}

function maxBy(indices: number[], key: (i: number) => number): number | undefined {
  let best: number | undefined;
  let bestKey = -Infinity;
  for (const i of indices) {
    const k = key(i);
    if (k > bestKey) { bestKey = k; best = i; }
  }
  return best;
}

function minBy(indices: number[], key: (i: number) => number): number | undefined {
  let best: number | undefined;
  let bestKey = Infinity;
  for (const i of indices) {
    const k = key(i);
    if (k < bestKey) { bestKey = k; best = i; }
  }
  return best;
}

// MARK: - パターン / 辞書(iOS FieldExtractor と同一)

const P = {
  email: '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}',
  urlHttp: 'https?://[A-Za-z0-9./?#@%&=_~+-]+',
  urlWww: 'www\\.[A-Za-z0-9.-]+\\.[A-Za-z]{2,}',
  sns: '(https?://)?(www\\.)?(twitter|facebook|instagram|linkedin)\\.com/[A-Za-z0-9._/-]+',
  postal: '[0-9]{3}-[0-9]{4}',
  mobileNumber: '0[789]0-?[0-9]{4}-?[0-9]{4}',
  phoneNumber: '0[0-9]{1,3}-[0-9]{1,4}-[0-9]{3,4}',
} as const;

const D = {
  mobileLabels: ['携帯', 'Mobile', 'Cell', 'モバイル'],
  faxLabels: ['FAX', 'Fax', 'fax', 'ファックス', 'ファクス'],
  phoneLabels: ['TEL', 'Tel', 'tel', '電話', '℡', '代表', 'Phone'],
  corporateSuffixes: [
    '株式会社', '有限会社', '合同会社', '合資会社', '合名会社',
    '一般社団法人', '公益社団法人', '一般財団法人', '公益財団法人',
    '(株)', '(有)', '（株）', '（有）',
    'Co., Ltd.', 'Co.,Ltd.', 'Corporation', 'Corp.', 'Inc.', 'Inc',
    'K.K.', 'LLC', 'Ltd.', 'Ltd', 'Company',
  ],
  titles: [
    '代表取締役社長', '代表取締役', '取締役会長', '取締役', '執行役員',
    '会長', '社長', '副社長', '専務', '常務', '監査役',
    '本部長', '部長', '次長', '課長', '係長', '主任', '主査',
    'マネージャー', 'ディレクター', 'プロデューサー', 'エンジニア', 'デザイナー',
    '代表', 'CEO', 'COO', 'CTO', 'CFO', 'President', 'Director', 'Manager', 'Engineer',
  ],
  departmentTokens: [
    '事業部', '本部', '統括部', '部', '課', '室', 'グループ', 'チーム',
    '支店', '営業所', '支社', 'センター', '研究所', 'Division', 'Department', 'Group', 'Team',
  ],
  prefectures: [
    '北海道', '青森県', '岩手県', '宮城県', '秋田県', '山形県', '福島県',
    '茨城県', '栃木県', '群馬県', '埼玉県', '千葉県', '東京都', '神奈川県',
    '新潟県', '富山県', '石川県', '福井県', '山梨県', '長野県', '岐阜県',
    '静岡県', '愛知県', '三重県', '滋賀県', '京都府', '大阪府', '兵庫県',
    '奈良県', '和歌山県', '鳥取県', '島根県', '岡山県', '広島県', '山口県',
    '徳島県', '香川県', '愛媛県', '高知県', '福岡県', '佐賀県', '長崎県',
    '熊本県', '大分県', '宮崎県', '鹿児島県', '沖縄県',
  ],
} as const;
