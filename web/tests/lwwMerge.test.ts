import { describe, it, expect } from 'vitest';
import { CardFieldName } from '../src/core/card';
import type { CardDocument, CardField, ImageRef } from '../src/core/cardDocument';
import { mergeDocuments } from '../src/core/lwwMerger';

const base = Date.parse('2026-07-19T00:00:00Z');
const at = (offsetSec: number): string => new Date(base + offsetSec * 1000).toISOString();

function doc(opts: {
  id?: string; revision: number; device: string; updated: string; deleted?: string | null;
  fields: Record<string, [unknown, string]>; tags?: string[]; images?: ImageRef[];
}): CardDocument {
  const fields: Record<string, CardField> = {};
  for (const [k, [v, t]] of Object.entries(opts.fields)) {
    fields[k] = { v: v as CardField['v'], t };
  }
  return {
    schemaVersion: '1.0',
    id: opts.id ?? 'card-1',
    revision: opts.revision,
    deviceId: opts.device,
    fields,
    tags: opts.tags ?? [],
    ocrFulltext: null,
    images: opts.images ?? [],
    createdAt: at(0),
    updatedAt: opts.updated,
    deletedAt: opts.deleted ?? null,
    mergedInto: null,
    unknown: {},
  };
}

describe('LWW merge', () => {
  it('フィールドごとに新しい方を採用', () => {
    const a = doc({ revision: 2, device: 'A', updated: at(30), fields: {
      [CardFieldName.company]: ['新A社', at(30)],
      [CardFieldName.title]: ['旧A役職', at(5)],
    }});
    const b = doc({ revision: 2, device: 'B', updated: at(20), fields: {
      [CardFieldName.company]: ['旧B社', at(10)],
      [CardFieldName.title]: ['新B役職', at(25)],
    }});
    const result = mergeDocuments(a, b);
    expect(result.document.fields[CardFieldName.company].v).toBe('新A社');
    expect(result.document.fields[CardFieldName.title].v).toBe('新B役職');
    const fields = result.conflicts.map((c) => c.field).sort();
    expect(fields).toEqual([CardFieldName.company, CardFieldName.title].sort());
  });

  it('同時刻は revision で決着', () => {
    const a = doc({ revision: 5, device: 'A', updated: at(10), fields: { [CardFieldName.email]: ['a@x.com', at(10)] }});
    const b = doc({ revision: 9, device: 'B', updated: at(10), fields: { [CardFieldName.email]: ['b@x.com', at(10)] }});
    const result = mergeDocuments(a, b);
    expect(result.document.fields[CardFieldName.email].v).toBe('b@x.com');
    expect(result.document.revision).toBe(9);
  });

  it('マージは可換', () => {
    const a = doc({ revision: 3, device: 'A', updated: at(40), fields: {
      [CardFieldName.company]: ['A社', at(40)], [CardFieldName.phone]: ['03-1', at(5)],
    }});
    const b = doc({ revision: 4, device: 'B', updated: at(20), fields: {
      [CardFieldName.company]: ['B社', at(10)], [CardFieldName.phone]: ['03-2', at(30)],
    }});
    const ab = mergeDocuments(a, b).document;
    const ba = mergeDocuments(b, a).document;
    expect(ab.fields[CardFieldName.company].v).toBe(ba.fields[CardFieldName.company].v);
    expect(ab.fields[CardFieldName.phone].v).toBe(ba.fields[CardFieldName.phone].v);
    expect(ab.fields[CardFieldName.company].v).toBe('A社');
    expect(ab.fields[CardFieldName.phone].v).toBe('03-2');
  });

  it('負けた値が null なら履歴に残さない', () => {
    const a = doc({ revision: 1, device: 'A', updated: at(30), fields: { [CardFieldName.fax]: ['03-9', at(30)] }});
    const b = doc({ revision: 1, device: 'B', updated: at(10), fields: { [CardFieldName.fax]: [null, at(10)] }});
    const result = mergeDocuments(a, b);
    expect(result.document.fields[CardFieldName.fax].v).toBe('03-9');
    expect(result.conflicts).toHaveLength(0);
  });

  it('削除は新しい版に従う', () => {
    const a = doc({ revision: 1, device: 'A', updated: at(10), fields: { [CardFieldName.company]: ['生存', at(10)] }});
    const b = doc({ revision: 2, device: 'B', updated: at(50), deleted: at(50), fields: { [CardFieldName.company]: ['生存', at(10)] }});
    const result = mergeDocuments(a, b);
    expect(result.document.deletedAt).toBe(at(50));
  });

  it('画像は sha256 で和集合', () => {
    const a = doc({ revision: 1, device: 'A', updated: at(20), fields: {}, images: [{ side: 'front', file: 'a.jpg', sha256: 'sha-A' }] });
    const b = doc({ revision: 1, device: 'B', updated: at(10), fields: {}, images: [{ side: 'back', file: 'b.jpg', sha256: 'sha-B' }] });
    const shas = mergeDocuments(a, b).document.images.map((i) => i.sha256).sort();
    expect(shas).toEqual(['sha-A', 'sha-B']);
  });

  it('id 不一致は例外', () => {
    const a = doc({ id: 'x', revision: 1, device: 'A', updated: at(1), fields: {} });
    const b = doc({ id: 'y', revision: 1, device: 'B', updated: at(1), fields: {} });
    expect(() => mergeDocuments(a, b)).toThrow();
  });
});
