import type { SqlDriver } from './driver';

/**
 * スキーマ定義(追記のみ)。iOS の MeishiKit AppDatabase.migrator と同一構成。
 * SQLite のためブール値は INTEGER(0/1)、日時は ISO8601 の TEXT で保持する
 * (ローカル DB の格納形式は各プラットフォーム独自。共有するのは card.json のみ)。
 */
export interface Migration {
  name: string;
  sql: string;
}

export const MIGRATIONS: Migration[] = [
  {
    name: 'v1_create_cards_and_images',
    sql: `
      CREATE TABLE cards (
        id TEXT PRIMARY KEY,
        family_name TEXT, given_name TEXT, family_name_kana TEXT, given_name_kana TEXT,
        company TEXT, company_normalized TEXT, department TEXT, title TEXT,
        email TEXT, email_normalized TEXT, phone TEXT, mobile TEXT, fax TEXT,
        postal_code TEXT, address TEXT, url TEXT,
        memo TEXT, is_favorite INTEGER NOT NULL DEFAULT 0, exchanged_at TEXT,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 0, device_id TEXT NOT NULL DEFAULT '',
        dirty INTEGER NOT NULL DEFAULT 1, deleted_at TEXT
      );
      CREATE INDEX idx_cards_updated_at ON cards(updated_at);
      CREATE INDEX idx_cards_deleted_at ON cards(deleted_at);
      CREATE INDEX idx_cards_email_normalized ON cards(email_normalized);
      CREATE INDEX idx_cards_company_normalized ON cards(company_normalized);

      CREATE TABLE card_images (
        id TEXT PRIMARY KEY,
        card_id TEXT NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
        side TEXT NOT NULL, relative_path TEXT NOT NULL, sha256 TEXT NOT NULL,
        width INTEGER, height INTEGER, created_at TEXT NOT NULL
      );
      CREATE INDEX idx_card_images_card_id ON card_images(card_id);
      CREATE INDEX idx_card_images_sha256 ON card_images(sha256);
    `,
  },
  {
    name: 'v2_cards_fts5',
    sql: `
      CREATE VIRTUAL TABLE cards_fts USING fts5(
        family_name, given_name, family_name_kana, given_name_kana,
        company, department, title, email, address, memo,
        content='cards', content_rowid='rowid', tokenize='trigram'
      );

      INSERT INTO cards_fts(
        rowid, family_name, given_name, family_name_kana, given_name_kana,
        company, department, title, email, address, memo)
      SELECT rowid, family_name, given_name, family_name_kana, given_name_kana,
        company, department, title, email, address, memo
      FROM cards;

      CREATE TRIGGER cards_fts_ai AFTER INSERT ON cards BEGIN
        INSERT INTO cards_fts(
          rowid, family_name, given_name, family_name_kana, given_name_kana,
          company, department, title, email, address, memo)
        VALUES (new.rowid, new.family_name, new.given_name, new.family_name_kana, new.given_name_kana,
          new.company, new.department, new.title, new.email, new.address, new.memo);
      END;

      CREATE TRIGGER cards_fts_ad AFTER DELETE ON cards BEGIN
        INSERT INTO cards_fts(
          cards_fts, rowid, family_name, given_name, family_name_kana, given_name_kana,
          company, department, title, email, address, memo)
        VALUES ('delete', old.rowid, old.family_name, old.given_name, old.family_name_kana, old.given_name_kana,
          old.company, old.department, old.title, old.email, old.address, old.memo);
      END;

      CREATE TRIGGER cards_fts_au AFTER UPDATE ON cards BEGIN
        INSERT INTO cards_fts(
          cards_fts, rowid, family_name, given_name, family_name_kana, given_name_kana,
          company, department, title, email, address, memo)
        VALUES ('delete', old.rowid, old.family_name, old.given_name, old.family_name_kana, old.given_name_kana,
          old.company, old.department, old.title, old.email, old.address, old.memo);
        INSERT INTO cards_fts(
          rowid, family_name, given_name, family_name_kana, given_name_kana,
          company, department, title, email, address, memo)
        VALUES (new.rowid, new.family_name, new.given_name, new.family_name_kana, new.given_name_kana,
          new.company, new.department, new.title, new.email, new.address, new.memo);
      END;
    `,
  },
  {
    name: 'v3_not_duplicate_pairs',
    sql: `
      CREATE TABLE not_duplicate_pairs (
        card_id_a TEXT NOT NULL,
        card_id_b TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (card_id_a, card_id_b)
      );
    `,
  },
  {
    name: 'v4_tags',
    sql: `
      CREATE TABLE tags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        name_normalized TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE (name_normalized)
      );
      CREATE TABLE card_tags (
        card_id TEXT NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
        tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
        PRIMARY KEY (card_id, tag_id)
      );
      CREATE INDEX idx_card_tags_tag_id ON card_tags(tag_id);
    `,
  },
  {
    name: 'v5_sync_field_timestamps',
    sql: `
      ALTER TABLE cards ADD COLUMN field_updated_at TEXT;

      CREATE TABLE sync_kv (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );

      CREATE TABLE card_remote (
        card_id TEXT PRIMARY KEY REFERENCES cards(id) ON DELETE CASCADE,
        remote_id TEXT,
        remote_revision TEXT,
        synced_at TEXT
      );
    `,
  },
  {
    name: 'v6_field_conflicts',
    sql: `
      CREATE TABLE field_conflicts (
        id TEXT PRIMARY KEY,
        card_id TEXT NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
        field TEXT NOT NULL,
        losing_value TEXT,
        winning_value TEXT,
        losing_at TEXT NOT NULL,
        winning_at TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
      CREATE INDEX idx_field_conflicts_card_id ON field_conflicts(card_id);
    `,
  },
];

/** 未適用のマイグレーションを順に適用する(冪等)。 */
export async function runMigrations(driver: SqlDriver): Promise<void> {
  await driver.exec(`CREATE TABLE IF NOT EXISTS _migrations (name TEXT PRIMARY KEY, applied_at TEXT NOT NULL);`);
  const rows = await driver.all<{ name: string }>(`SELECT name FROM _migrations`);
  const applied = new Set(rows.map((r) => r.name));
  for (const migration of MIGRATIONS) {
    if (applied.has(migration.name)) continue;
    await driver.transaction(async () => {
      await driver.exec(migration.sql);
      await driver.run(`INSERT INTO _migrations (name, applied_at) VALUES (?, ?)`, [migration.name, new Date().toISOString()]);
    });
  }
}
