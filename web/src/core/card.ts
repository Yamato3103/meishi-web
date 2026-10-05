/**
 * 名刺1件(ローカルモデル)。iOS の MeishiKit.Card と同じフィールド構成。
 * 日時・日付は ISO 文字列で保持する(createdAt/updatedAt/deletedAt は datetime、
 * exchangedAt は date-only "yyyy-MM-dd")。
 */
export interface Card {
  id: string;

  familyName: string | null;
  givenName: string | null;
  familyNameKana: string | null;
  givenNameKana: string | null;

  company: string | null;
  companyNormalized: string | null;
  department: string | null;
  title: string | null;

  email: string | null;
  emailNormalized: string | null;
  phone: string | null;
  mobile: string | null;
  fax: string | null;
  postalCode: string | null;
  address: string | null;
  url: string | null;

  memo: string | null;
  isFavorite: boolean;
  exchangedAt: string | null;

  createdAt: string;
  updatedAt: string;

  revision: number;
  deviceId: string;
  dirty: boolean;
  deletedAt: string | null;
}

/** card.json のフィールド名(端末間の契約。snake_case・§10.1)。iOS の CardFieldName と一致。 */
export const CardFieldName = {
  familyName: 'family_name',
  givenName: 'given_name',
  familyNameKana: 'family_name_kana',
  givenNameKana: 'given_name_kana',
  company: 'company',
  department: 'department',
  title: 'title',
  phone: 'phone',
  mobile: 'mobile',
  fax: 'fax',
  email: 'email',
  postalCode: 'postal_code',
  address: 'address',
  website: 'website',
  memo: 'memo',
  isFavorite: 'is_favorite',
  exchangedAt: 'exchanged_at',
} as const;

/** Card にマッピングされる既知フィールド(card.json 見た目の順序)。 */
export const KNOWN_FIELDS: string[] = [
  CardFieldName.familyName,
  CardFieldName.givenName,
  CardFieldName.familyNameKana,
  CardFieldName.givenNameKana,
  CardFieldName.company,
  CardFieldName.department,
  CardFieldName.title,
  CardFieldName.phone,
  CardFieldName.mobile,
  CardFieldName.fax,
  CardFieldName.email,
  CardFieldName.postalCode,
  CardFieldName.address,
  CardFieldName.website,
  CardFieldName.memo,
  CardFieldName.isFavorite,
  CardFieldName.exchangedAt,
];

/** 空フィールドを埋めた Card を作る(テスト・生成用の簡易ファクトリ)。 */
export function makeCard(partial: Partial<Card> & { id: string }): Card {
  const now = new Date().toISOString();
  return {
    familyName: null, givenName: null, familyNameKana: null, givenNameKana: null,
    company: null, companyNormalized: null, department: null, title: null,
    email: null, emailNormalized: null, phone: null, mobile: null, fax: null,
    postalCode: null, address: null, url: null,
    memo: null, isFavorite: false, exchangedAt: null,
    createdAt: now, updatedAt: now,
    revision: 0, deviceId: '', dirty: true, deletedAt: null,
    ...partial,
  };
}
