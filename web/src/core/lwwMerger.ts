import type { JSONValue } from './json';
import { jsonEqual } from './json';
import type { CardDocument, CardField, ImageRef } from './cardDocument';

/** マージで「負けた」フィールド値(サイレントロス防止・§5.3)。 */
export interface FieldConflict {
  field: string;
  losingValue: JSONValue;
  losingTimestamp: string;
  winningValue: JSONValue;
  winningTimestamp: string;
}

export interface MergeResult {
  document: CardDocument;
  conflicts: FieldConflict[];
}

interface Rank {
  time: number;
  revision: number;
  deviceId: string;
}

function rankLess(l: Rank, r: Rank): boolean {
  if (l.time !== r.time) return l.time < r.time;
  if (l.revision !== r.revision) return l.revision < r.revision;
  return l.deviceId < r.deviceId;
}

function docRank(d: CardDocument): Rank {
  return { time: Date.parse(d.updatedAt), revision: d.revision, deviceId: d.deviceId };
}

function fieldRank(f: CardField, doc: CardDocument): Rank {
  return { time: Date.parse(f.t), revision: doc.revision, deviceId: doc.deviceId };
}

/**
 * フィールド単位 Last-Write-Wins マージ(§5.3)。
 * 同じ id の2版を、フィールドごとに新しい t を採用して統合する。
 * t が同時刻なら revision、それも同じなら device_id 辞書順で決定論的に決める。
 */
export function mergeDocuments(a: CardDocument, b: CardDocument): MergeResult {
  if (a.id !== b.id) {
    throw new Error(`LWW merge: id mismatch (${a.id} vs ${b.id})`);
  }

  const aWins = !rankLess(docRank(a), docRank(b)); // a >= b
  const newer = aWins ? a : b;
  const older = aWins ? b : a;

  const earliestCreated = Math.min(Date.parse(a.createdAt), Date.parse(b.createdAt));

  const mergedFields: Record<string, CardField> = {};
  const conflicts: FieldConflict[] = [];
  const names = new Set<string>([...Object.keys(a.fields), ...Object.keys(b.fields)]);

  for (const name of names) {
    const fa = a.fields[name];
    const fb = b.fields[name];
    if (fa && fb) {
      const aFieldWins = !rankLess(fieldRank(fa, a), fieldRank(fb, b));
      const pick = aFieldWins ? fa : fb;
      const lose = aFieldWins ? fb : fa;
      mergedFields[name] = pick;
      // 値が食い違い・負けた側が非null・作成後に編集されたものだけ履歴に残す。
      if (!jsonEqual(pick.v, lose.v) && lose.v !== null && Date.parse(lose.t) > earliestCreated) {
        conflicts.push({
          field: name,
          losingValue: lose.v,
          losingTimestamp: lose.t,
          winningValue: pick.v,
          winningTimestamp: pick.t,
        });
      }
    } else if (fa) {
      mergedFields[name] = fa;
    } else if (fb) {
      mergedFields[name] = fb;
    }
  }

  // 画像は内容アドレス(sha256)で和集合。新しい版の並び順を優先。
  const mergedImages: ImageRef[] = [...newer.images];
  const known = new Set(mergedImages.map((i) => i.sha256));
  for (const img of older.images) {
    if (!known.has(img.sha256)) mergedImages.push(img);
  }

  // 未知トップレベルキーはキー単位で統合し、衝突は新しい版を採用。
  const mergedUnknown: Record<string, JSONValue> = { ...older.unknown, ...newer.unknown };

  const document: CardDocument = {
    schemaVersion: newer.schemaVersion,
    id: a.id,
    revision: Math.max(a.revision, b.revision),
    deviceId: newer.deviceId,
    fields: mergedFields,
    tags: newer.tags, // タグ配列はレコード単位 LWW(per-tag 時刻を持たない設計)
    ocrFulltext: newer.ocrFulltext ?? older.ocrFulltext,
    images: mergedImages,
    createdAt: Date.parse(a.createdAt) <= Date.parse(b.createdAt) ? a.createdAt : b.createdAt,
    updatedAt: Date.parse(a.updatedAt) >= Date.parse(b.updatedAt) ? a.updatedAt : b.updatedAt,
    deletedAt: newer.deletedAt, // 削除/復元は updated_at の新しい版に従う
    mergedInto: newer.mergedInto ?? older.mergedInto,
    unknown: mergedUnknown,
  };

  conflicts.sort((x, y) => (x.field < y.field ? -1 : x.field > y.field ? 1 : 0));
  return { document, conflicts };
}
