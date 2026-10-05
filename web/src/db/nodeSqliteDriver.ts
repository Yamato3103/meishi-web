import { createRequire } from 'node:module';
import type { DatabaseSync as DatabaseSyncType } from 'node:sqlite';
import type { SqlDriver, SqlParams, Row } from './driver';

// Vite/Rollup は新しい組み込み 'node:sqlite' を静的解決できず失敗する。
// 実行時 require(型は type-only import で取得)で読み込み、静的解決を回避する。
const nodeRequire = createRequire(import.meta.url);
const { DatabaseSync } = nodeRequire('node:sqlite') as { DatabaseSync: typeof DatabaseSyncType };

/**
 * node:sqlite 実装(Node 22+ 同梱の SQLite。FTS5 trigram 対応)。
 *
 * 主にテスト/CI と Node CLI 用。ブラウザは wa-sqlite + OPFS の実装を使う。
 * SQLite 方言は共通なので、ここで検証した SQL はブラウザでも同じ挙動になる。
 * ※ node:sqlite に依存するため、ブラウザ向けバンドル(App)からは import しないこと
 *   (db/index.ts はこのファイルを再輸出しない)。
 */
export class NodeSqliteDriver implements SqlDriver {
  private constructor(private readonly db: DatabaseSyncType) {}

  static open(path = ':memory:'): NodeSqliteDriver {
    const db = new DatabaseSync(path);
    db.exec('PRAGMA foreign_keys = ON;');
    return new NodeSqliteDriver(db);
  }

  async exec(sql: string): Promise<void> {
    this.db.exec(sql);
  }

  async run(sql: string, params: SqlParams = []): Promise<void> {
    this.db.prepare(sql).run(...params);
  }

  async all<T = Row>(sql: string, params: SqlParams = []): Promise<T[]> {
    return this.db.prepare(sql).all(...params) as T[];
  }

  async get<T = Row>(sql: string, params: SqlParams = []): Promise<T | undefined> {
    return this.db.prepare(sql).get(...params) as T | undefined;
  }

  async transaction<T>(fn: () => Promise<T>): Promise<T> {
    this.db.exec('BEGIN');
    try {
      const result = await fn();
      this.db.exec('COMMIT');
      return result;
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
  }

  async close(): Promise<void> {
    this.db.close();
  }
}
