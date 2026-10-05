import { WasmSqliteDriver } from '../db/wasmSqliteDriver';
import { runMigrations, CardRepository } from '../db';
import type { ImageStore } from '../sync/imageStore';
import { openImageStore } from './opfsImageStore';

const DEVICE_ID_KEY = 'meishivault.deviceId';

/** この端末の device_id(LWW のタイブレーク用)。初回に生成して localStorage に保存する。 */
export function deviceId(): string {
  let id = localStorage.getItem(DEVICE_ID_KEY);
  if (!id) {
    id = 'web-' + crypto.randomUUID();
    localStorage.setItem(DEVICE_ID_KEY, id);
  }
  return id;
}

export interface OpenedDatabase {
  repo: CardRepository;
  driver: WasmSqliteDriver;
  /** 名刺画像のバイナリ保存先(OPFS、非対応環境ではメモリ)。 */
  imageStore: ImageStore;
  /** OPFS で永続化されているか(false = メモリのみ)。 */
  persistent: boolean;
}

let opening: Promise<OpenedDatabase> | null = null;

/** DB を開いてマイグレーションを適用し、リポジトリを返す(プロセス内で1回だけ実行)。 */
export function openDatabase(): Promise<OpenedDatabase> {
  if (!opening) {
    opening = (async () => {
      const driver = await WasmSqliteDriver.open();
      await runMigrations(driver);
      const repo = new CardRepository(driver, deviceId());
      const { store: imageStore } = openImageStore();
      return { repo, driver, imageStore, persistent: driver.persistent };
    })();
  }
  return opening;
}
