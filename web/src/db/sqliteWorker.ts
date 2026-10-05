import sqlite3InitModule from '@sqlite.org/sqlite-wasm';

/**
 * SQLite を動かす Web Worker。
 *
 * Chromium は OPFS の `createSyncAccessHandle` を **Worker でのみ**公開するため、
 * 永続化(OPFS SAHPool VFS)はワーカ内で初期化する。SAHPool はハンドルを事前確保
 * するので SharedArrayBuffer / COOP・COEP を必要とせず、通常ホスティングで動く。
 *
 * メインスレッド(WasmSqliteDriver)とは postMessage で 1 リクエスト=1 レスポンスの
 * 素朴なプロトコルでやり取りする。DB は単一スレッドで、メッセージ順に処理される。
 */

interface Oo1Db {
  exec(opts: {
    sql: string;
    bind?: readonly (string | number | null)[];
    rowMode?: 'object' | 'array';
    returnValue?: 'resultRows' | 'this';
  }): unknown;
  exec(sql: string): unknown;
  close(): void;
}

type Req =
  | { id: number; op: 'open'; filename: string }
  | { id: number; op: 'exec'; sql: string }
  | { id: number; op: 'run'; sql: string; params: (string | number | null)[] }
  | { id: number; op: 'all'; sql: string; params: (string | number | null)[] }
  | { id: number; op: 'get'; sql: string; params: (string | number | null)[] }
  | { id: number; op: 'close' };

// DOM/WebWorker の lib 衝突を避けるため self を最小 shape で扱う。
const ctx = self as unknown as {
  postMessage(message: unknown): void;
  onmessage: ((e: MessageEvent<Req>) => void) | null;
};

let db: Oo1Db | null = null;
let persistent = false;
/** 単一書き込み者ロック(Web Locks)の解放関数。close 時に呼ぶ。 */
let releaseLock: (() => void) | null = null;

ctx.onmessage = async (e: MessageEvent<Req>) => {
  const msg = e.data;
  try {
    const result = await handle(msg);
    ctx.postMessage({ id: msg.id, ok: true, result, persistent });
  } catch (err) {
    ctx.postMessage({ id: msg.id, ok: false, error: err instanceof Error ? err.message : String(err) });
  }
};

function requireDb(): Oo1Db {
  if (!db) throw new Error('DB is not open');
  return db;
}

async function handle(msg: Req): Promise<unknown> {
  switch (msg.op) {
    case 'open':
      await open(msg.filename);
      return null;
    case 'exec':
      requireDb().exec(msg.sql);
      return null;
    case 'run':
      requireDb().exec({ sql: msg.sql, bind: msg.params });
      return null;
    case 'all':
      return requireDb().exec({ sql: msg.sql, bind: msg.params, rowMode: 'object', returnValue: 'resultRows' }) ?? [];
    case 'get': {
      const rows = (requireDb().exec({ sql: msg.sql, bind: msg.params, rowMode: 'object', returnValue: 'resultRows' }) ?? []) as unknown[];
      return rows[0];
    }
    case 'close':
      db?.close();
      db = null;
      releaseLock?.();
      releaseLock = null;
      return null;
  }
}

interface SahPool {
  OpfsSAHPoolDb: new (filename: string) => Oo1Db;
}
interface Sqlite3 {
  oo1: { DB: new (filename: string, flags?: string) => Oo1Db };
  installOpfsSAHPoolVfs?: (opts: {
    name?: string;
    directory?: string;
    clearOnInit?: boolean;
    initialCapacity?: number;
  }) => Promise<SahPool>;
}

const delay = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

const LOCK_NAME = 'meishivault-db';

async function open(filename: string): Promise<void> {
  const sqlite3 = (await sqlite3InitModule()) as unknown as Sqlite3;

  // OPFS SAHPool は全タブで単一書き込み者のみ許す。Web Locks で排他を取り、
  // 取れたタブだけ OPFS を使う。別タブが保持中なら(タイムアウト)OPFS を試みず
  // :memory: に落とす — 二重オープンのライブラリエラーを出さずに素直に降格する。
  const single = await acquireSingleWriterLock();
  if (single && sqlite3.installOpfsSAHPoolVfs) {
    const pool = await installPoolWithRetry(sqlite3);
    if (pool) {
      db = new pool.OpfsSAHPoolDb(filename);
      persistent = true;
      db.exec('PRAGMA foreign_keys = ON;');
      return;
    }
  }

  db = new sqlite3.oo1.DB(':memory:');
  persistent = false;
  db.exec('PRAGMA foreign_keys = ON;');
}

/**
 * 書き込み者ロックを取得する。取れたら true(close まで保持)、他タブが保持し続けて
 * いれば false。`ifAvailable` で「今すぐ取れるか」を繰り返し試す — 再読込直後は前タブの
 * ロックがまだ解放されていないことがあるので数回リトライ(単一タブの通常運用では取れる)。
 * signal 方式は一部エンジンでアボートが発火せず刺さるため、この即時ポーリング方式にする。
 */
async function acquireSingleWriterLock(): Promise<boolean> {
  const locks = (navigator as unknown as { locks?: LockManager }).locks;
  if (!locks) return true; // Web Locks 非対応環境は単一タブ前提で素通り
  const attempts = 12; // 約 1.8 秒(150ms × 12)
  for (let i = 0; i < attempts; i++) {
    if (await tryLockOnce(locks)) return true;
    await delay(150);
  }
  return false; // 別タブが保持中 → :memory: に降格
}

function tryLockOnce(locks: LockManager): Promise<boolean> {
  return new Promise<boolean>((resolve) => {
    locks
      .request(LOCK_NAME, { mode: 'exclusive', ifAvailable: true }, (lock) => {
        if (!lock) { resolve(false); return; } // 今は取れない
        resolve(true);
        // 解放関数が呼ばれるまで pending にしておくことでロックを保持し続ける。
        return new Promise<void>((rel) => { releaseLock = rel; });
      })
      .catch(() => resolve(false));
  });
}

/**
 * SAHPool VFS を導入する。ページ再読込直後は前ページのワーカがまだ OPFS の
 * sync access handle を保持していることがあり、取得が一時的に失敗する(回復可能)。
 * 数回リトライして確実に永続 VFS を掴む。全滅した場合だけ null(→:memory:)。
 */
async function installPoolWithRetry(sqlite3: Sqlite3): Promise<SahPool | null> {
  const install = sqlite3.installOpfsSAHPoolVfs!;
  const attempts = 4;
  for (let i = 0; i < attempts; i++) {
    try {
      // 導入時、ライブラリは「掴めなかったハンドル」を回復可能でも console.error に
      // 出す。再読込レースのノイズなので、この呼び出しの間だけ握り潰す(戻したら復元)。
      return await withSilencedErrors(() => install({ name: 'meishivault-pool', directory: '.meishivault' }));
    } catch (error) {
      if (i === attempts - 1) {
        console.warn('[sqliteWorker] OPFS SAHPool を確保できませんでした。:memory: にフォールバックします。', error);
        return null;
      }
      await delay(150);
    }
  }
  return null;
}

/** fn の実行中だけ console.error を握り潰す(SAHPool 導入の回復可能ログ抑制用)。 */
async function withSilencedErrors<T>(fn: () => Promise<T>): Promise<T> {
  const original = console.error;
  console.error = () => {};
  try {
    return await fn();
  } finally {
    console.error = original;
  }
}
