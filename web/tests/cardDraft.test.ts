import { describe, it, expect } from 'vitest';
import { splitFullName, draftFromExtraction } from '../src/core/cardDraft';
import { emptyResult } from '../src/core/ocr';

describe('cardDraft', () => {
  it('splitFullName は空白で姓・名に分割(iOS と一致)', () => {
    expect(splitFullName('山田 太郎')).toEqual({ family: '山田', given: '太郎' });
    expect(splitFullName('山田太郎')).toEqual({ family: '山田太郎', given: null });
    expect(splitFullName(null)).toEqual({ family: null, given: null });
    expect(splitFullName('Taro Van Der Berg')).toEqual({ family: 'Taro', given: 'Van Der Berg' });
  });

  it('draftFromExtraction が代表値を採用', () => {
    const r = emptyResult();
    r.email.push({ value: 'a@x.com', confidence: 0.9 });
    r.company = { value: '株式会社X', confidence: 0.9 };
    r.personName = { full: { value: '山田 太郎', confidence: 0.6 } };

    const card = draftFromExtraction(r, 'fixed-id');
    expect(card.id).toBe('fixed-id');
    expect(card.familyName).toBe('山田');
    expect(card.givenName).toBe('太郎');
    expect(card.company).toBe('株式会社X');
    expect(card.email).toBe('a@x.com');
    expect(card.phone).toBeNull();
  });
});
