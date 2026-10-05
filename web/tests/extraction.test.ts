import { describe, it, expect } from 'vitest';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { extract } from '../src/core/fieldExtractor';
import type { ExtractionResult, Candidate } from '../src/core/ocr';

// spec/ は monorepo ルート直下。canonical(web/tests → 名刺管理/spec)と
// temp 実行(web-run/tests → web-run/spec)の両レイアウトに対応する。
const here = dirname(fileURLToPath(import.meta.url));
function specVectorsDir(): string {
  for (const c of [join(here, '../../spec/test-vectors'), join(here, '../spec/test-vectors')]) {
    if (existsSync(c)) return c;
  }
  throw new Error('spec/test-vectors が見つかりません');
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function loadVector(name: string): any {
  return JSON.parse(readFileSync(join(specVectorsDir(), `${name}.json`), 'utf8'));
}

function listCandidates(field: string, r: ExtractionResult): Candidate[] {
  switch (field) {
    case 'email': return r.email;
    case 'url': return r.url;
    case 'phone': return r.phone;
    case 'fax': return r.fax;
    case 'mobile': return r.mobile;
    case 'sns': return r.sns;
    default: return [];
  }
}

function single(field: string, r: ExtractionResult): Candidate | undefined {
  switch (field) {
    case 'postalCode': return r.postalCode;
    case 'company': return r.company;
    case 'department': return r.department;
    case 'title': return r.title;
    case 'address': return r.address;
    default: return undefined;
  }
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function assertCandidate(c: Candidate | undefined, exp: any, label: string): void {
  const value = exp.value as string;
  const minConf = (exp.minConfidence ?? 0) as number;
  expect(c, `${label} 抽出されなかった (期待: ${value})`).toBeDefined();
  expect(c!.value, `${label} value`).toBe(value);
  expect(c!.confidence, `${label} confidence`).toBeGreaterThanOrEqual(minConf);
}

function runVector(name: string): void {
  const root = loadVector(name);
  const result = extract(root.input);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const expected = root.expected as Record<string, any>;

  for (const [field, exp] of Object.entries(expected)) {
    if (field === 'personName') {
      if (exp.full) assertCandidate(result.personName?.full, exp.full, `${name}.personName.full`);
      if (exp.familyKana) assertCandidate(result.personName?.familyKana, exp.familyKana, `${name}.personName.familyKana`);
      if (exp.givenKana) assertCandidate(result.personName?.givenKana, exp.givenKana, `${name}.personName.givenKana`);
      continue;
    }
    if (Array.isArray(exp)) {
      const cands = listCandidates(field, result);
      for (const e of exp) {
        const match = cands.find((c) => c.value === e.value);
        expect(match, `[${name}] ${field}: 期待値 '${e.value}' が無い。実際: ${cands.map((c) => c.value).join(', ')}`).toBeDefined();
        expect(match!.confidence, `[${name}] ${field} '${e.value}' confidence`).toBeGreaterThanOrEqual(e.minConfidence ?? 0);
      }
      continue;
    }
    assertCandidate(single(field, result), exp, `${name}.${field}`);
  }
}

describe('extraction (spec/test-vectors 回帰・iOS FieldExtractor と同一挙動)', () => {
  it('001-standard-jp', () => runVector('001-standard-jp'));
  it('002-english-labels', () => runVector('002-english-labels'));
  it('003-tel-fax-same-line', () => runVector('003-tel-fax-same-line'));
  it('004-label-variants', () => runVector('004-label-variants'));
});
