import type { JSONValue } from './json';
import { stableStringify } from './json';
import type { Card } from './card';
import { CardFieldName, KNOWN_FIELDS, makeCard } from './card';

/** フィールド1つ分。値 v と更新時刻 t(ISO8601)。フィールド単位 LWW の単位(§5.3)。 */
export interface CardField {
  v: JSONValue;
  t: string;
}

/** card.json に埋め込む画像参照(§10.1 images[])。 */
export interface ImageRef {
  side: string;
  file: string;
  sha256: string;
}

/** 端末間の同期単位「1名刺 = 1 JSONファイル」(§10.1)。 */
export interface CardDocument {
  schemaVersion: string;
  id: string;
  revision: number;
  deviceId: string;
  fields: Record<string, CardField>;
  tags: string[];
  ocrFulltext: string | null;
  images: ImageRef[];
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
  mergedInto: string | null;
  /** 未知トップレベルキー(前方互換のため素通しで保持)。 */
  unknown: Record<string, JSONValue>;
}

export const CURRENT_SCHEMA_VERSION = '1.0';

const KNOWN_TOP_LEVEL = new Set([
  'schema_version', 'id', 'revision', 'device_id', 'fields', 'tags',
  'ocr_fulltext', 'images', 'created_at', 'updated_at', 'deleted_at', 'merged_into',
]);

export function isDeleted(doc: CardDocument): boolean {
  return doc.deletedAt !== null;
}

/** 安定(キーソート・人間可読)な card.json 文字列に符号化する。 */
export function encodeDocument(doc: CardDocument): string {
  const obj: Record<string, JSONValue> = { ...doc.unknown };
  obj['schema_version'] = doc.schemaVersion;
  obj['id'] = doc.id;
  obj['revision'] = doc.revision;
  obj['device_id'] = doc.deviceId;

  const fields: Record<string, JSONValue> = {};
  for (const [name, field] of Object.entries(doc.fields)) {
    fields[name] = { v: field.v, t: field.t };
  }
  obj['fields'] = fields;

  obj['tags'] = doc.tags;
  obj['ocr_fulltext'] = doc.ocrFulltext;
  obj['images'] = doc.images.map((i) => ({ side: i.side, file: i.file, sha256: i.sha256 }));
  obj['created_at'] = doc.createdAt;
  obj['updated_at'] = doc.updatedAt;
  obj['deleted_at'] = doc.deletedAt;
  obj['merged_into'] = doc.mergedInto;

  return stableStringify(obj);
}

/** card.json 文字列から復元する(未知トップレベルキーは unknown に退避)。 */
export function decodeDocument(text: string): CardDocument {
  const obj = JSON.parse(text) as Record<string, unknown>;
  if (obj === null || typeof obj !== 'object') {
    throw new Error('card.json: not an object');
  }

  const fields: Record<string, CardField> = {};
  const rawFields = (obj['fields'] ?? {}) as Record<string, { v?: JSONValue; t?: string }>;
  for (const [name, entry] of Object.entries(rawFields)) {
    fields[name] = { v: (entry?.v ?? null) as JSONValue, t: entry?.t ?? '1970-01-01T00:00:00Z' };
  }

  const images: ImageRef[] = Array.isArray(obj['images'])
    ? (obj['images'] as Array<Record<string, unknown>>)
        .filter((i) => typeof i.side === 'string' && typeof i.file === 'string' && typeof i.sha256 === 'string')
        .map((i) => ({ side: i.side as string, file: i.file as string, sha256: i.sha256 as string }))
    : [];

  const unknown: Record<string, JSONValue> = {};
  for (const [key, value] of Object.entries(obj)) {
    if (!KNOWN_TOP_LEVEL.has(key)) unknown[key] = value as JSONValue;
  }

  return {
    schemaVersion: (obj['schema_version'] as string) ?? CURRENT_SCHEMA_VERSION,
    id: obj['id'] as string,
    revision: typeof obj['revision'] === 'number' ? (obj['revision'] as number) : 0,
    deviceId: (obj['device_id'] as string) ?? '',
    fields,
    tags: Array.isArray(obj['tags']) ? (obj['tags'] as string[]) : [],
    ocrFulltext: typeof obj['ocr_fulltext'] === 'string' ? (obj['ocr_fulltext'] as string) : null,
    images,
    createdAt: obj['created_at'] as string,
    updatedAt: obj['updated_at'] as string,
    deletedAt: typeof obj['deleted_at'] === 'string' ? (obj['deleted_at'] as string) : null,
    mergedInto: typeof obj['merged_into'] === 'string' ? (obj['merged_into'] as string) : null,
    unknown,
  };
}

/** Card から card.json を組み立てる(正規化キーは同期しない)。 */
export function documentFromCard(
  card: Card,
  options: { tags?: string[]; images?: ImageRef[]; ocrFulltext?: string | null; fieldTimestamps?: Record<string, string> } = {},
): CardDocument {
  const { tags = [], images = [], ocrFulltext = null, fieldTimestamps = {} } = options;
  const ts = (name: string): string => fieldTimestamps[name] ?? card.updatedAt;
  const str = (name: string, value: string | null): CardField => ({ v: value ?? null, t: ts(name) });

  const fields: Record<string, CardField> = {
    [CardFieldName.familyName]: str(CardFieldName.familyName, card.familyName),
    [CardFieldName.givenName]: str(CardFieldName.givenName, card.givenName),
    [CardFieldName.familyNameKana]: str(CardFieldName.familyNameKana, card.familyNameKana),
    [CardFieldName.givenNameKana]: str(CardFieldName.givenNameKana, card.givenNameKana),
    [CardFieldName.company]: str(CardFieldName.company, card.company),
    [CardFieldName.department]: str(CardFieldName.department, card.department),
    [CardFieldName.title]: str(CardFieldName.title, card.title),
    [CardFieldName.phone]: str(CardFieldName.phone, card.phone),
    [CardFieldName.mobile]: str(CardFieldName.mobile, card.mobile),
    [CardFieldName.fax]: str(CardFieldName.fax, card.fax),
    [CardFieldName.email]: str(CardFieldName.email, card.email),
    [CardFieldName.postalCode]: str(CardFieldName.postalCode, card.postalCode),
    [CardFieldName.address]: str(CardFieldName.address, card.address),
    [CardFieldName.website]: str(CardFieldName.website, card.url),
    [CardFieldName.memo]: str(CardFieldName.memo, card.memo),
    [CardFieldName.isFavorite]: { v: card.isFavorite, t: ts(CardFieldName.isFavorite) },
    [CardFieldName.exchangedAt]: { v: card.exchangedAt ?? null, t: ts(CardFieldName.exchangedAt) },
  };

  return {
    schemaVersion: CURRENT_SCHEMA_VERSION,
    id: card.id,
    revision: card.revision,
    deviceId: card.deviceId,
    fields,
    tags,
    ocrFulltext,
    images,
    createdAt: card.createdAt,
    updatedAt: card.updatedAt,
    deletedAt: card.deletedAt,
    mergedInto: null,
    unknown: {},
  };
}

/** card.json から Card を復元する(正規化キーは各端末で再計算=ここでは null)。 */
export function cardFromDocument(doc: CardDocument, dirty = false): Card {
  const str = (name: string): string | null => {
    const v = doc.fields[name]?.v;
    return typeof v === 'string' ? v : null;
  };
  const favoriteValue = doc.fields[CardFieldName.isFavorite]?.v;

  return makeCard({
    id: doc.id,
    familyName: str(CardFieldName.familyName),
    givenName: str(CardFieldName.givenName),
    familyNameKana: str(CardFieldName.familyNameKana),
    givenNameKana: str(CardFieldName.givenNameKana),
    company: str(CardFieldName.company),
    companyNormalized: null,
    department: str(CardFieldName.department),
    title: str(CardFieldName.title),
    email: str(CardFieldName.email),
    emailNormalized: null,
    phone: str(CardFieldName.phone),
    mobile: str(CardFieldName.mobile),
    fax: str(CardFieldName.fax),
    postalCode: str(CardFieldName.postalCode),
    address: str(CardFieldName.address),
    url: str(CardFieldName.website),
    memo: str(CardFieldName.memo),
    isFavorite: favoriteValue === true,
    exchangedAt: str(CardFieldName.exchangedAt),
    createdAt: doc.createdAt,
    updatedAt: doc.updatedAt,
    revision: doc.revision,
    deviceId: doc.deviceId,
    dirty,
    deletedAt: doc.deletedAt,
  });
}

/** 既知フィールドの一覧を返す(参照の便宜)。 */
export function knownFields(): string[] {
  return KNOWN_FIELDS;
}
