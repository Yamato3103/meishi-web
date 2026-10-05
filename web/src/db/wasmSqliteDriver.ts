import type { SqlDriver, SqlParams, Row } from './driver';

/**
 * ブラウザ用の SQLite ドライバ(公式 @sqlite.org/sqlite-wasm)。
 *
 * 実体は Web Worker(`sqliteWorker.ts`)で動く。Chromium は OPFS の
 * `createSyncAccessHandle` を Worker でのみ公開するため、永続化(OPFS SAHPool)は
 * ワーカ側で初期化する。SAHPool は COOP/COEP 不要なので通常ホスティングで動く。
 * ここではメインスレッド側として、postMessage の 1 リクエスト=1 レスポンスを
 * SqlDriver 契約(Promise ベース)に橋渡しする。
 *
 * SQLite 方言は node:sqlite と共通なので、テストで検証した SQL がそのまま動く。
 */

interface WorkerResponse {
  id: number;
  ok: boolean;
  result?: unknown;
  error?: string;
  persistent?: boolean;
}

export class WasmSqliteDriver implements SqlDriver {
  private seq = 0;
  private readonly pending = new Map<number, { resolve: (v: unknown) => void; reject: (e: Error) => void }>();
  private persistentFlag = false;

  private constructor(private readonly worker: Worker) {
    this.worker.onmessage = (e: MessageEvent<WorkerResponse>) => this.onMessage(e.data);
    this.worker.onerror = (e: ErrorEvent) => this.failAll(new Error(e.message || 'sqlite worker error'));
  }

  /** OPFS で永続化されているか(false = :memory: フォールバック)。 */
  get persistent(): boolean {
    return this.persistentFlag;
  }

  static async open(filename = '/meishivault.sqlite'): Promise<WasmSqliteDriver> {
    const worker = new Worker(new URL('./sqliteWorker.ts', import.meta.url), { type: 'module' });
    const driver = new WasmSqliteDriver(worker);
    const res = await driver.request({ op: 'open', filename });
    driver.persistentFlag = res.persistent === true;
    return driver;
  }

  async exec(sql: string): Promise<void> {
    await this.request({ op: 'exec', sql });
  }

  async run(sql: string, params: SqlParams = []): Promise<void> {
    await this.request({ op: 'run', sql, params });
  }

  async all<T = Row>(sql: string, params: SqlParams = []): Promise<T[]> {
    const res = await this.request({ op: 'all', sql, params });
    return (res.result ?? []) as T[];
  }

  async get<T = Row>(sql: string, params: SqlParams = []): Promise<T | undefined> {
    const res = await this.request({ op: 'get', sql, params });
    return res.result as T | undefined;
  }

  async transaction<T>(fn: () => Promise<T>): Promise<T> {
    await this.exec('BEGIN');
    try {
      const result = await fn();
      await this.exec('COMMIT');
      return result;
    } catch (error) {
      await this.exec('ROLLBACK');
      throw error;
    }
  }

  async close(): Promise<void> {
    try {
      await this.request({ op: 'close' });
    } finally {
      this.worker.terminate();
      this.failAll(new Error('DB closed'));
    }
  }

  // MARK: - 内部(メッセージング)

  private request(payload: Record<string, unknown>): Promise<WorkerResponse> {
    const id = ++this.seq;
    return new Promise<WorkerResponse>((resolve, reject) => {
      this.pending.set(id, { resolve: resolve as (v: unknown) => void, reject });
      this.worker.postMessage({ id, ...payload });
    });
  }

  private onMessage(res: WorkerResponse): void {
    const entry = this.pending.get(res.id);
    if (!entry) return;
    this.pending.delete(res.id);
    if (res.ok) entry.resolve(res);
    else entry.reject(new Error(res.error ?? 'sqlite worker error'));
  }

  private failAll(error: Error): void {
    for (const { reject } of this.pending.values()) reject(error);
    this.pending.clear();
  }
}
