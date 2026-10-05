import type { SqlDriver } from './driver';
import type { Card } from '../core/card';
import { KNOWN_FIELDS } from '../core/card';
import { normalizeEmail, companyKey, nfkc } from '../core/normalizer';
import type { CardDocument, ImageRef } from '../core/cardDocument';
import { documentFromCard, cardFromDocument } from '../core/cardDocument';
import { jsonEqual, displayText } from '../core/json';
import type { DuplicateMatch } from '../core/duplicateDetector';
import { score as duplicateScore, merged as mergedCard, CANDIDATE_THRESHOLD, STRONG_THRESHOLD } from '../core/duplicateDetector';
import type { FieldConflict } from '../core/lwwMerger';

export interface CardImage {
  id: string;
  cardId: string;
  side: string;
  relativePath: string;
  sha256: string;
  width: number | null;
  height: number | null;
  createdAt: string;
}

export interface Tag {
  id: string;
  name: string;
  createdAt: string;
}

/** card ↔ リモートファイルの版参照(楽観ロック用)。 */
export interface RemoteRef {
  remoteId: string | null;
  remoteRevision: string | null;
}

/** マージで負けた値の履歴レコード(名刺詳細の「編集履歴」表示用)。 */
export interface FieldConflictRecord {
  id: string;
  cardId: string;
  field: string;
  losingValue: string | null;
  winningValue: string | null;
  losingAt: string;
  winningAt: string;
  createdAt: string;
}

/** cards テーブルの列(insert/update のパラメータ順)。 */
const CARD_COLUMNS = [
  'id', 'family_name', 'given_name', 'family_name_kana', 'given_name_kana',
  'company', 'company_normalized', 'department', 'title',
  'email', 'email_normalized', 'phone', 'mobile', 'fax',
  'postal_code', 'address', 'url',
  'memo', 'is_favorite', 'exchanged_at',
  'created_at', 'updated_at', 'revision', 'device_id', 'dirty', 'deleted_at', 'field_updated_at',
] as const;

/** sync_kv に保存する差分カーソルのキー(iOS の changes_token と同一)。 */
const TOKEN_KEY = 'changes_token';

const INSERT_SQL = `INSERT INTO cards (${CARD_COLUMNS.join(', ')}) VALUES (${CARD_COLUMNS.map(() => '?').join(', ')})`;
const UPDATE_SQL = `UPDATE cards SET ${CARD_COLUMNS.filter((c) => c !== 'id').map((c) => `${c} = ?`).join(', ')} WHERE id = ?`;

interface RawCardRow {
  id: string;
  family_name: string | null; given_name: string | null; family_name_kana: string | null; given_name_kana: string | null;
  company: string | null; company_normalized: string | null; department: string | null; title: string | null;
  email: string | null; email_normalized: string | null; phone: string | null; mobile: string | null; fax: string | null;
  postal_code: string | null; address: string | null; url: string | null;
  memo: string | null; is_favorite: number; exchanged_at: string | null;
  created_at: string; updated_at: string; revision: number; device_id: string; dirty: number; deleted_at: string | null;
  field_updated_at: string | null;
}

/**
 * 名刺の永続化ユースケース(iOS の MeishiKit.CardRepository と対応)。
 * 書き込み時に revision++/dirty/updated_at/正規化/device_id/フィールド別時刻を一括で通す。
 */
export class CardRepository {
  constructor(
    private readonly driver: SqlDriver,
    private readonly deviceId: string,
    private readonly now: () => string = () => new Date().toISOString(),
  ) {}

  // MARK: - 書き込み

  async create(card: Card): Promise<Card> {
    const t = this.now();
    const c: Card = { ...card, createdAt: t, updatedAt: t, revision: 1, dirty: true, deviceId: this.deviceId, deletedAt: null };
    this.applyNormalization(c);
    const fua = computeFieldTimestamps(c, null, {}, t);
    await this.driver.run(INSERT_SQL, cardParams(c, JSON.stringify(sortObject(fua))));
    return c;
  }

  async update(card: Card): Promise<Card> {
    const t = this.now();
    const row = await this.driver.get<RawCardRow>('SELECT * FROM cards WHERE id = ?', [card.id]);
    const old = row ? rowToCard(row) : null;
    const existingFua = row?.field_updated_at ? (JSON.parse(row.field_updated_at) as Record<string, string>) : {};
    const c: Card = { ...card, updatedAt: t, revision: card.revision + 1, dirty: true, deviceId: this.deviceId };
    this.applyNormalization(c);
    const fua = computeFieldTimestamps(c, old, existingFua, t);
    await this.driver.run(UPDATE_SQL, updateParams(c, JSON.stringify(sortObject(fua))));
    return c;
  }

  async softDelete(id: string): Promise<void> {
    await this.mutate(id, (c, t) => { c.deletedAt = t; });
  }

  async restore(id: string): Promise<void> {
    await this.mutate(id, (c) => { c.deletedAt = null; });
  }

  /** 完全削除(復元不可)。card_images/card_tags は FK カスケードで消える。 */
  async permanentlyDelete(id: string): Promise<void> {
    await this.driver.run('DELETE FROM cards WHERE id = ?', [id]);
  }

  // MARK: - 重複検知

  /**
   * ドラフト(新規/編集中カード)に対する重複候補を、スコア降順で返す。
   * ブロッキング: email_normalized / company_normalized / 電話文字列で候補を絞り、
   * not_duplicate で「別人」確定済みのペアは除外する(iOS と同一)。
   */
  async findDuplicates(draft: Card): Promise<DuplicateMatch[]> {
    const emailKey = normalizeEmail(draft.email);
    const compKey = companyKey(draft.company);
    const phones = [draft.phone, draft.mobile, draft.fax].filter((p): p is string => p != null && p.length > 0);

    const clauses: string[] = [];
    const args: (string | null)[] = [];
    if (emailKey != null) { clauses.push('email_normalized = ?'); args.push(emailKey); }
    if (compKey != null) { clauses.push('company_normalized = ?'); args.push(compKey); }
    for (const phone of phones) {
      clauses.push('phone = ?'); args.push(phone);
      clauses.push('mobile = ?'); args.push(phone);
      clauses.push('fax = ?'); args.push(phone);
    }
    if (clauses.length === 0) return [];

    const sql = `SELECT * FROM cards WHERE deleted_at IS NULL AND id <> ? AND (${clauses.join(' OR ')})`;
    const rows = await this.driver.all<RawCardRow>(sql, [draft.id, ...args]);

    const matches: DuplicateMatch[] = [];
    for (const row of rows) {
      const candidate = rowToCard(row);
      if (await this.isNotDuplicate(draft.id, candidate.id)) continue;
      const s = duplicateScore(draft, candidate);
      if (s >= CANDIDATE_THRESHOLD) {
        matches.push({ card: candidate, score: s, isStrong: s >= STRONG_THRESHOLD });
      }
    }
    return matches.sort((a, b) => b.score - a.score);
  }

  /**
   * 2枚を1枚に統合する。primary を残し空欄を secondary で補完、
   * secondary の画像を primary に付け替え、secondary は tombstone にする。
   */
  async merge(primaryId: string, secondaryId: string): Promise<Card> {
    const primaryRow = await this.driver.get<RawCardRow>('SELECT * FROM cards WHERE id = ?', [primaryId]);
    const secondaryRow = await this.driver.get<RawCardRow>('SELECT * FROM cards WHERE id = ?', [secondaryId]);
    if (!primaryRow || !secondaryRow) throw new Error('merge: カードが見つかりません');
    const primaryOriginal = rowToCard(primaryRow);
    const secondary = rowToCard(secondaryRow);

    const t = this.now();
    const primary = mergedCard(primaryOriginal, secondary);
    primary.updatedAt = t; primary.revision += 1; primary.dirty = true; primary.deviceId = this.deviceId;
    this.applyNormalization(primary);

    const existingFua = primaryRow.field_updated_at ? (JSON.parse(primaryRow.field_updated_at) as Record<string, string>) : {};
    const fua = computeFieldTimestamps(primary, primaryOriginal, existingFua, t);

    await this.driver.transaction(async () => {
      await this.driver.run(UPDATE_SQL, updateParams(primary, JSON.stringify(sortObject(fua))));
      // 画像を primary へ付け替え(ファイルはそのまま、card_id のみ更新)。
      await this.driver.run('UPDATE card_images SET card_id = ? WHERE card_id = ?', [primaryId, secondaryId]);
      // secondary を tombstone。
      await this.driver.run(UPDATE_SQL, updateParams(
        { ...secondary, deletedAt: t, updatedAt: t, revision: secondary.revision + 1, dirty: true, deviceId: this.deviceId },
        secondaryRow.field_updated_at ?? JSON.stringify({}),
      ));
    });
    return primary;
  }

  /** 「別人」確定を記録する(正準順で保存)。 */
  async markNotDuplicate(idA: string, idB: string): Promise<void> {
    const [a, b] = canonicalPair(idA, idB);
    await this.driver.run(
      'INSERT OR IGNORE INTO not_duplicate_pairs (card_id_a, card_id_b, created_at) VALUES (?, ?, ?)',
      [a, b, this.now()],
    );
  }

  private async isNotDuplicate(idA: string, idB: string): Promise<boolean> {
    const [a, b] = canonicalPair(idA, idB);
    const row = await this.driver.get<{ hit: number }>(
      'SELECT EXISTS(SELECT 1 FROM not_duplicate_pairs WHERE card_id_a = ? AND card_id_b = ?) AS hit',
      [a, b]);
    return (row?.hit ?? 0) === 1;
  }

  private async mutate(id: string, change: (c: Card, t: string) => void): Promise<void> {
    const row = await this.driver.get<RawCardRow>('SELECT * FROM cards WHERE id = ?', [id]);
    if (!row) return;
    const c = rowToCard(row);
    const old = rowToCard(row);
    const existingFua = row.field_updated_at ? (JSON.parse(row.field_updated_at) as Record<string, string>) : {};
    const t = this.now();
    change(c, t);
    c.updatedAt = t; c.revision += 1; c.dirty = true; c.deviceId = this.deviceId;
    this.applyNormalization(c);
    const fua = computeFieldTimestamps(c, old, existingFua, t);
    await this.driver.run(UPDATE_SQL, updateParams(c, JSON.stringify(sortObject(fua))));
  }

  // MARK: - 読み取り

  async fetchAll(includeDeleted = false): Promise<Card[]> {
    const where = includeDeleted ? '' : 'WHERE deleted_at IS NULL';
    const rows = await this.driver.all<RawCardRow>(`SELECT * FROM cards ${where} ORDER BY updated_at DESC`);
    return rows.map(rowToCard);
  }

  async fetchOne(id: string): Promise<Card | undefined> {
    const row = await this.driver.get<RawCardRow>('SELECT * FROM cards WHERE id = ?', [id]);
    return row ? rowToCard(row) : undefined;
  }

  async fetchDeleted(): Promise<Card[]> {
    const rows = await this.driver.all<RawCardRow>('SELECT * FROM cards WHERE deleted_at IS NOT NULL ORDER BY deleted_at DESC');
    return rows.map(rowToCard);
  }

  /**
   * 全文検索。3文字以上は FTS5(trigram)、それ未満は trigram が索引を作れないため LIKE で代替。
   * 削除済みは除外し、更新日時の降順で返す(iOS と同一挙動)。
   */
  async search(query: string): Promise<Card[]> {
    const q = query.trim();
    if (q.length === 0) return this.fetchAll();

    if ([...q].length < 3) {
      const like = `%${escapeLike(q)}%`;
      const sql = `
        SELECT cards.* FROM cards
        WHERE cards.deleted_at IS NULL AND (
          family_name LIKE ? ESCAPE '\\' OR given_name LIKE ? ESCAPE '\\'
          OR family_name_kana LIKE ? ESCAPE '\\' OR given_name_kana LIKE ? ESCAPE '\\'
          OR company LIKE ? ESCAPE '\\' OR email LIKE ? ESCAPE '\\'
        )
        ORDER BY cards.updated_at DESC`;
      const rows = await this.driver.all<RawCardRow>(sql, Array(6).fill(like) as string[]);
      return rows.map(rowToCard);
    }

    const phrase = '"' + q.replace(/"/g, '""') + '"';
    const sql = `
      SELECT cards.* FROM cards
      JOIN cards_fts ON cards_fts.rowid = cards.rowid
      WHERE cards_fts MATCH ? AND cards.deleted_at IS NULL
      ORDER BY cards.updated_at DESC`;
    const rows = await this.driver.all<RawCardRow>(sql, [phrase]);
    return rows.map(rowToCard);
  }

  // MARK: - 画像

  async addImage(image: CardImage): Promise<CardImage> {
    await this.driver.run(
      `INSERT INTO card_images (id, card_id, side, relative_path, sha256, width, height, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      [image.id, image.cardId, image.side, image.relativePath, image.sha256, image.width, image.height, image.createdAt],
    );
    return image;
  }

  async fetchImages(cardId: string): Promise<CardImage[]> {
    const rows = await this.driver.all<{
      id: string; card_id: string; side: string; relative_path: string; sha256: string;
      width: number | null; height: number | null; created_at: string;
    }>('SELECT * FROM card_images WHERE card_id = ? ORDER BY created_at', [cardId]);
    return rows.map((r) => ({
      id: r.id, cardId: r.card_id, side: r.side, relativePath: r.relative_path,
      sha256: r.sha256, width: r.width, height: r.height, createdAt: r.created_at,
    }));
  }

  // MARK: - タグ

  async allTags(): Promise<Tag[]> {
    const rows = await this.driver.all<{ id: string; name: string; created_at: string }>('SELECT id, name, created_at FROM tags ORDER BY name');
    return rows.map((r) => ({ id: r.id, name: r.name, createdAt: r.created_at }));
  }

  async tags(forCardId: string): Promise<Tag[]> {
    const rows = await this.driver.all<{ id: string; name: string; created_at: string }>(
      `SELECT tags.id, tags.name, tags.created_at FROM tags
       JOIN card_tags ON card_tags.tag_id = tags.id
       WHERE card_tags.card_id = ? ORDER BY tags.name`, [forCardId]);
    return rows.map((r) => ({ id: r.id, name: r.name, createdAt: r.created_at }));
  }

  async createOrGetTag(name: string): Promise<Tag> {
    const trimmed = name.trim();
    const normalized = nfkc(trimmed).toLowerCase();
    const existing = await this.driver.get<{ id: string; name: string; created_at: string }>(
      'SELECT id, name, created_at FROM tags WHERE name_normalized = ?', [normalized]);
    if (existing) return { id: existing.id, name: existing.name, createdAt: existing.created_at };
    const tag: Tag = { id: crypto.randomUUID(), name: trimmed, createdAt: this.now() };
    await this.driver.run('INSERT INTO tags (id, name, name_normalized, created_at) VALUES (?, ?, ?, ?)',
      [tag.id, tag.name, normalized, tag.createdAt]);
    return tag;
  }

  async addTag(tagId: string, toCardId: string): Promise<void> {
    await this.driver.run('INSERT OR IGNORE INTO card_tags (card_id, tag_id) VALUES (?, ?)', [toCardId, tagId]);
    await this.touchCard(toCardId);
  }

  async removeTag(tagId: string, fromCardId: string): Promise<void> {
    await this.driver.run('DELETE FROM card_tags WHERE card_id = ? AND tag_id = ?', [fromCardId, tagId]);
    await this.touchCard(fromCardId);
  }

  async cardIds(withTagId: string): Promise<Set<string>> {
    const rows = await this.driver.all<{ card_id: string }>('SELECT card_id FROM card_tags WHERE tag_id = ?', [withTagId]);
    return new Set(rows.map((r) => r.card_id));
  }

  async deleteTag(id: string): Promise<void> {
    const affected = await this.driver.all<{ card_id: string }>('SELECT card_id FROM card_tags WHERE tag_id = ?', [id]);
    await this.driver.run('DELETE FROM tags WHERE id = ?', [id]);
    for (const row of affected) await this.touchCard(row.card_id);
  }

  // MARK: - フィールド別更新時刻

  async fieldTimestamps(forCardId: string): Promise<Record<string, string>> {
    const row = await this.driver.get<{ field_updated_at: string | null }>('SELECT field_updated_at FROM cards WHERE id = ?', [forCardId]);
    if (!row?.field_updated_at) return {};
    return JSON.parse(row.field_updated_at) as Record<string, string>;
  }

  // MARK: - 同期(SyncEngine 用)

  /** 未同期(dirty)のカードを更新日時の昇順で返す(tombstone 含む)。 */
  async dirtyCards(): Promise<Card[]> {
    const rows = await this.driver.all<RawCardRow>('SELECT * FROM cards WHERE dirty = 1 ORDER BY updated_at');
    return rows.map(rowToCard);
  }

  /** カード1件を card.json(CardDocument)に組み立てる(tombstone も対象)。 */
  async buildDocument(cardId: string): Promise<CardDocument | null> {
    const row = await this.driver.get<RawCardRow>('SELECT * FROM cards WHERE id = ?', [cardId]);
    if (!row) return null;
    const card = rowToCard(row);
    const fieldTimestamps = row.field_updated_at ? (JSON.parse(row.field_updated_at) as Record<string, string>) : {};
    const tagRows = await this.driver.all<{ name: string }>(
      `SELECT tags.name FROM tags JOIN card_tags ON card_tags.tag_id = tags.id
       WHERE card_tags.card_id = ? ORDER BY tags.name`, [cardId]);
    const imgs = await this.fetchImages(cardId);
    const images: ImageRef[] = imgs.map((i) => ({ side: i.side, file: i.relativePath, sha256: i.sha256 }));
    return documentFromCard(card, { tags: tagRows.map((t) => t.name), images, fieldTimestamps });
  }

  /** card ↔ リモートの版参照。 */
  async remoteRef(cardId: string): Promise<RemoteRef> {
    const row = await this.driver.get<{ remote_id: string | null; remote_revision: string | null }>(
      'SELECT remote_id, remote_revision FROM card_remote WHERE card_id = ?', [cardId]);
    return { remoteId: row?.remote_id ?? null, remoteRevision: row?.remote_revision ?? null };
  }

  /** push 成功を記録する(リモート版を保存し dirty を落とす)。 */
  async markSynced(cardId: string, remoteId: string | null, remoteRevision: string, at: string): Promise<void> {
    await this.driver.transaction(async () => {
      await this.upsertRemote(cardId, remoteId, remoteRevision, at);
      await this.driver.run('UPDATE cards SET dirty = 0 WHERE id = ?', [cardId]);
    });
  }

  /**
   * リモート由来の card.json をローカルへ適用する(挿入/更新)。revision は doc の値をそのまま採用し、
   * 通常の書き込み経路(revision++/正規化以外)を通さない=マージ結果を忠実に格納する。
   * @param dirty ローカルに未 push の内容が残るなら true。
   */
  async applyRemoteDocument(doc: CardDocument, remoteId: string | null, remoteRevision: string | null, dirty: boolean): Promise<void> {
    const card = cardFromDocument(doc, dirty);
    // 正規化キーは同期しないため各端末で再計算する。
    card.emailNormalized = normalizeEmail(card.email);
    card.companyNormalized = companyKey(card.company);

    // フィールド別時刻を doc の t から反映。
    const fua: Record<string, string> = {};
    for (const name of KNOWN_FIELDS) {
      const t = doc.fields[name]?.t;
      if (t) fua[name] = t;
    }
    const fuaJson = JSON.stringify(sortObject(fua));

    await this.driver.transaction(async () => {
      const exists = await this.driver.get<{ x: number }>('SELECT 1 AS x FROM cards WHERE id = ?', [card.id]);
      if (exists) await this.driver.run(UPDATE_SQL, updateParams(card, fuaJson));
      else await this.driver.run(INSERT_SQL, cardParams(card, fuaJson));
      // タグ・画像行を doc に合わせる(画像バイナリ本体は SyncEngine が別途転送)。
      await this.replaceTags(card.id, doc.tags);
      await this.replaceImages(card.id, doc.images);
      if (remoteRevision != null) await this.upsertRemote(card.id, remoteId, remoteRevision, this.now());
    });
  }

  // MARK: - 競合履歴(field_conflicts)

  /** マージで負けた値を履歴として記録する。 */
  async recordConflicts(cardId: string, conflicts: FieldConflict[]): Promise<void> {
    if (conflicts.length === 0) return;
    const t = this.now();
    await this.driver.transaction(async () => {
      for (const c of conflicts) {
        await this.driver.run(
          `INSERT INTO field_conflicts (id, card_id, field, losing_value, winning_value, losing_at, winning_at, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
          [crypto.randomUUID(), cardId, c.field, displayText(c.losingValue), displayText(c.winningValue), c.losingTimestamp, c.winningTimestamp, t]);
      }
    });
  }

  /** カードの競合履歴(新しい順)。 */
  async conflicts(forCardId: string): Promise<FieldConflictRecord[]> {
    const rows = await this.driver.all<{
      id: string; card_id: string; field: string; losing_value: string | null; winning_value: string | null;
      losing_at: string; winning_at: string; created_at: string;
    }>('SELECT * FROM field_conflicts WHERE card_id = ? ORDER BY created_at DESC', [forCardId]);
    return rows.map((r) => ({
      id: r.id, cardId: r.card_id, field: r.field, losingValue: r.losing_value, winningValue: r.winning_value,
      losingAt: r.losing_at, winningAt: r.winning_at, createdAt: r.created_at,
    }));
  }

  /** 競合履歴を1件破棄する。 */
  async dismissConflict(id: string): Promise<void> {
    await this.driver.run('DELETE FROM field_conflicts WHERE id = ?', [id]);
  }

  /** カードの競合履歴をすべて破棄する。 */
  async dismissConflicts(forCardId: string): Promise<void> {
    await this.driver.run('DELETE FROM field_conflicts WHERE card_id = ?', [forCardId]);
  }

  // MARK: - 同期カーソル(sync_kv)

  async syncToken(): Promise<string | null> {
    const row = await this.driver.get<{ value: string }>('SELECT value FROM sync_kv WHERE key = ?', [TOKEN_KEY]);
    return row?.value ?? null;
  }

  async setSyncToken(token: string): Promise<void> {
    await this.driver.run(
      'INSERT INTO sync_kv (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [TOKEN_KEY, token]);
  }

  // MARK: - 内部

  private async upsertRemote(cardId: string, remoteId: string | null, remoteRevision: string, at: string): Promise<void> {
    await this.driver.run(
      `INSERT INTO card_remote (card_id, remote_id, remote_revision, synced_at) VALUES (?, ?, ?, ?)
       ON CONFLICT(card_id) DO UPDATE SET
         remote_id = excluded.remote_id, remote_revision = excluded.remote_revision, synced_at = excluded.synced_at`,
      [cardId, remoteId, remoteRevision, at]);
  }

  /** card_tags を names 集合に一致させる(名前で既存タグ解決、無ければ作成)。 */
  private async replaceTags(cardId: string, names: string[]): Promise<void> {
    await this.driver.run('DELETE FROM card_tags WHERE card_id = ?', [cardId]);
    for (const name of names) {
      const trimmed = name.trim();
      if (trimmed.length === 0) continue;
      const normalized = nfkc(trimmed).toLowerCase();
      const existing = await this.driver.get<{ id: string }>('SELECT id FROM tags WHERE name_normalized = ?', [normalized]);
      let tagId: string;
      if (existing) {
        tagId = existing.id;
      } else {
        tagId = crypto.randomUUID();
        await this.driver.run('INSERT INTO tags (id, name, name_normalized, created_at) VALUES (?, ?, ?, ?)',
          [tagId, trimmed, normalized, this.now()]);
      }
      await this.driver.run('INSERT OR IGNORE INTO card_tags (card_id, tag_id) VALUES (?, ?)', [cardId, tagId]);
    }
  }

  /** card_images を doc の参照集合に一致させる(relative_path をキーに差分適用)。 */
  private async replaceImages(cardId: string, refs: ImageRef[]): Promise<void> {
    const existing = await this.fetchImages(cardId);
    const wanted = new Set(refs.map((r) => r.file));
    for (const row of existing) {
      if (!wanted.has(row.relativePath)) await this.driver.run('DELETE FROM card_images WHERE id = ?', [row.id]);
    }
    const existingPaths = new Set(existing.map((e) => e.relativePath));
    for (const ref of refs) {
      if (existingPaths.has(ref.file)) continue;
      await this.driver.run(
        `INSERT INTO card_images (id, card_id, side, relative_path, sha256, width, height, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        [crypto.randomUUID(), cardId, ref.side, ref.file, ref.sha256, null, null, this.now()]);
    }
  }

  private async touchCard(id: string): Promise<void> {
    await this.driver.run('UPDATE cards SET dirty = 1, revision = revision + 1, updated_at = ?, device_id = ? WHERE id = ?',
      [this.now(), this.deviceId, id]);
  }

  private applyNormalization(c: Card): void {
    c.emailNormalized = normalizeEmail(c.email);
    c.companyNormalized = companyKey(c.company);
  }
}

// MARK: - マッピング / ヘルパー

function rowToCard(r: RawCardRow): Card {
  return {
    id: r.id,
    familyName: r.family_name, givenName: r.given_name, familyNameKana: r.family_name_kana, givenNameKana: r.given_name_kana,
    company: r.company, companyNormalized: r.company_normalized, department: r.department, title: r.title,
    email: r.email, emailNormalized: r.email_normalized, phone: r.phone, mobile: r.mobile, fax: r.fax,
    postalCode: r.postal_code, address: r.address, url: r.url,
    memo: r.memo, isFavorite: r.is_favorite === 1, exchangedAt: r.exchanged_at,
    createdAt: r.created_at, updatedAt: r.updated_at,
    revision: r.revision, deviceId: r.device_id, dirty: r.dirty === 1, deletedAt: r.deleted_at,
  };
}

function cardParams(c: Card, fieldUpdatedAtJson: string): (string | number | null)[] {
  return [
    c.id, c.familyName, c.givenName, c.familyNameKana, c.givenNameKana,
    c.company, c.companyNormalized, c.department, c.title,
    c.email, c.emailNormalized, c.phone, c.mobile, c.fax,
    c.postalCode, c.address, c.url,
    c.memo, c.isFavorite ? 1 : 0, c.exchangedAt,
    c.createdAt, c.updatedAt, c.revision, c.deviceId, c.dirty ? 1 : 0, c.deletedAt, fieldUpdatedAtJson,
  ];
}

function updateParams(c: Card, fieldUpdatedAtJson: string): (string | number | null)[] {
  const params = cardParams(c, fieldUpdatedAtJson);
  return [...params.slice(1), params[0]]; // id 以外 → 末尾に id(WHERE)
}

function computeFieldTimestamps(
  newCard: Card, oldCard: Card | null, existing: Record<string, string>, t: string,
): Record<string, string> {
  const nf = documentFromCard(newCard).fields;
  const of = oldCard ? documentFromCard(oldCard).fields : null;
  const result: Record<string, string> = { ...existing };
  for (const name of KNOWN_FIELDS) {
    const nv = nf[name]?.v ?? null;
    if (of) {
      const ov = of[name]?.v ?? null;
      if (!jsonEqual(ov, nv)) result[name] = t;
      else if (result[name] == null) result[name] = t;
    } else {
      result[name] = t;
    }
  }
  return result;
}

function sortObject(obj: Record<string, string>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const key of Object.keys(obj).sort()) out[key] = obj[key];
  return out;
}

function escapeLike(s: string): string {
  return s.replace(/\\/g, '\\\\').replace(/%/g, '\\%').replace(/_/g, '\\_');
}

/** 「別人」ペアの正準順(小さい id が先)。iOS の canonicalPair と同一。 */
function canonicalPair(idA: string, idB: string): [string, string] {
  return idA < idB ? [idA, idB] : [idB, idA];
}
