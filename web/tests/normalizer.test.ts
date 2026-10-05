import { describe, it, expect } from 'vitest';
import { nfkc, normalizeEmail, companyKey } from '../src/core/normalizer';

describe('normalizer', () => {
  it('NFKC で全角英数を半角化する', () => {
    expect(nfkc('ＡＢＣ１２３')).toBe('ABC123');
  });

  it('email は NFKC + trim + 小文字化', () => {
    expect(normalizeEmail('  Yamada@Sample.co.jp ')).toBe('yamada@sample.co.jp');
    expect(normalizeEmail(null)).toBeNull();
    expect(normalizeEmail('   ')).toBeNull();
  });

  it('companyKey は法人格を除去する(iOS と一致)', () => {
    expect(companyKey('株式会社サンプル商事')).toBe('サンプル商事');
    expect(companyKey('サンプル商事株式会社')).toBe('サンプル商事');
    expect(companyKey('Sample Co., Ltd.')).toBe('Sample');
    expect(companyKey('有限会社テスト')).toBe('テスト');
  });

  it('companyKey は空白を畳み、空は null', () => {
    expect(companyKey('  ＡＢＣ　商店  ')).toBe('ABC 商店');
    expect(companyKey('株式会社')).toBeNull();
    expect(companyKey(null)).toBeNull();
  });
});
