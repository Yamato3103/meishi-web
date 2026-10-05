/**
 * SQLite ドライバの抽象(継ぎ目)。
 *
 * ブラウザは wa-sqlite + OPFS、テスト/Node は node:sqlite を実装として差し込む。
 * マイグレーションとリポジトリはこのインターフェイスだけに依存し、同じ SQL を
 * どちらの実装でも動かす(SQLite 方言は共通)。OPFS が非同期のため API は Promise ベース。
 */
export type SqlValue = string | number | null;
export type SqlParams = SqlValue[];
export type Row = Record<string, SqlValue>;

export interface SqlDriver {
  /** 複数文を含む SQL スクリプトを実行する(トリガ定義など)。 */
  exec(sql: string): Promise<void>;
  /** パラメータ付きで1文を実行する(戻り値なし)。 */
  run(sql: string, params?: SqlParams): Promise<void>;
  /** 複数行を取得する。 */
  all<T = Row>(sql: string, params?: SqlParams): Promise<T[]>;
  /** 先頭1行を取得する(無ければ undefined)。 */
  get<T = Row>(sql: string, params?: SqlParams): Promise<T | undefined>;
  /** トランザクション。fn が投げれば ROLLBACK する。 */
  transaction<T>(fn: () => Promise<T>): Promise<T>;
  close(): Promise<void>;
}
