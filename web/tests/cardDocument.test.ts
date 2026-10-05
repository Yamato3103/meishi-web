import { describe, it, expect } from 'vitest';
import { makeCard, CardFieldName } from '../src/core/card';
import {
  documentFromCard, cardFromDocument, encodeDocument, decodeDocument, isDeleted,
} from '../src/core/cardDocument';

const t0 = '2026-07-19T03:12:00Z';

function sampleCard() {
  return makeCard({
    id: '3f2a-uuid',
    familyName: '山田', givenName: '太郎',
    familyNameKana: 'やまだ', givenNameKana: 'たろう',
    company: 'ABC株式会社', department: '営業部', title: '部長',
    email: 'yamada@abc.co.jp',
    phone: '03-1234-5678', mobile: '090-1234-5678', fax: null,
    postalCode: '100-0001', address: '東京都千代田区…', url: 'https://abc.co.jp',
    memo: '展示会で名刺交換', isFavorite: true, exchangedAt: null,
    createdAt: t0, updatedAt: t0,
    revision: 12, deviceId: 'iphone-abc123', dirty: false,
  });
}

describe('CardDocument', () => {
  it('Card ⇄ document ラウンドトリップ', () => {
    const doc = documentFromCard(sampleCard(), { tags: ['展示会', '重要'] });
    const back = cardFromDocument(doc);
    expect(back.familyName).toBe('山田');
    expect(back.company).toBe('ABC株式会社');
    expect(back.email).toBe('yamada@abc.co.jp');
    expect(back.mobile).toBe('090-1234-5678');
    expect(back.fax).toBeNull();
    expect(back.url).toBe('https://abc.co.jp');
    expect(back.isFavorite).toBe(true);
    expect(back.revision).toBe(12);
    // 正規化キーは同期しない。
    expect(back.companyNormalized).toBeNull();
    expect(back.emailNormalized).toBeNull();
  });

  it('encode/decode は安定・忠実', () => {
    const doc = documentFromCard(sampleCard(), { tags: ['展示会'] });
    const text = encodeDocument(doc);
    const decoded = decodeDocument(text);
    expect(decoded.id).toBe('3f2a-uuid');
    expect(decoded.revision).toBe(12);
    expect(decoded.deviceId).toBe('iphone-abc123');
    expect(decoded.tags).toEqual(['展示会']);
    expect(decoded.fields[CardFieldName.company].v).toBe('ABC株式会社');
    expect(decoded.fields[CardFieldName.isFavorite].v).toBe(true);
    expect(decoded.fields[CardFieldName.fax].v).toBeNull();
    expect(decoded.fields[CardFieldName.company].t).toBe(t0);
    // 再符号化してバイト一致(安定)。
    expect(encodeDocument(decoded)).toBe(text);
  });

  it('JSON 形状が §10.1 の契約に一致', () => {
    const obj = JSON.parse(encodeDocument(documentFromCard(sampleCard(), { tags: ['展示会'] })));
    expect(obj.schema_version).toBe('1.0');
    expect(obj.device_id).toBe('iphone-abc123');
    expect(obj.fields.email.v).toBe('yamada@abc.co.jp');
    expect(typeof obj.fields.email.t).toBe('string');
    expect(obj.deleted_at).toBeNull();
  });

  it('未知トップレベルキーをラウンドトリップ保持', () => {
    const text = JSON.stringify({
      schema_version: '1.0', id: 'x-1', revision: 3, device_id: 'dev-x',
      fields: { company: { v: '未来社', t: t0 } },
      tags: [], ocr_fulltext: null, images: [],
      created_at: '2026-07-18T10:00:00Z', updated_at: t0, deleted_at: null, merged_into: null,
      future_field: { nested: [1, true, 'x'] }, priority: 5,
    });
    const doc = decodeDocument(text);
    expect(doc.unknown.priority).toBe(5);
    expect(doc.unknown.future_field).toEqual({ nested: [1, true, 'x'] });
    const reobj = JSON.parse(encodeDocument(doc));
    expect(reobj.priority).toBe(5);
    expect(reobj.future_field).toEqual({ nested: [1, true, 'x'] });
  });

  it('tombstone のラウンドトリップ', () => {
    const card = sampleCard();
    card.deletedAt = t0;
    const decoded = decodeDocument(encodeDocument(documentFromCard(card)));
    expect(isDeleted(decoded)).toBe(true);
    expect(decoded.deletedAt).toBe(t0);
    expect(cardFromDocument(decoded).deletedAt).toBe(t0);
  });
});
