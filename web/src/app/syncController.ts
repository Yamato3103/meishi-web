import { useSyncExternalStore } from 'react';
import type { CardRepository } from '../db';
import type { ImageStore, RemoteStore, SyncSummary } from '../sync';
import { SyncEngine, GoogleDriveRemoteStore } from '../sync';
import type { OpenedDatabase } from './database';
import { googleDriveTokens } from './googleAuth';

export type SyncStatus = 'disconnected' | 'connecting' | 'connected';

/** UI が購読する同期状態のスナップショット。 */
export interface SyncState {
  status: SyncStatus;
  isSyncing: boolean;
  lastSyncedAt: string | null;
  lastSummary: SyncSummary | null;
  error: string | null;
  remoteName: string | null;
}

/**
 * 同期の状態機械(iOS の SyncController に対応)。
 *
 * `RemoteStore` を差し込むと `SyncEngine`(画像転送つき)を組み立て、`syncNow()` で push→pull する。
 * Google Drive 接続は GIS トークン→`GoogleDriveRemoteStore`。テストは `attachRemote` に
 * `InMemoryRemoteStore` を差し込んで駆動できる。
 */
export class SyncController {
  private engine: SyncEngine | null = null;
  private listeners = new Set<() => void>();
  private snap: SyncState = {
    status: 'disconnected', isSyncing: false, lastSyncedAt: null,
    lastSummary: null, error: null, remoteName: null,
  };

  constructor(private readonly repo: CardRepository, private readonly imageStore: ImageStore) {}

  /** Google Drive のクライアント ID が設定されているか。 */
  static isDriveConfigured(): boolean {
    return !!driveClientId();
  }

  subscribe = (fn: () => void): (() => void) => {
    this.listeners.add(fn);
    return () => { this.listeners.delete(fn); };
  };

  getSnapshot = (): SyncState => this.snap;

  private update(patch: Partial<SyncState>): void {
    this.snap = { ...this.snap, ...patch };
    for (const l of this.listeners) l();
  }

  /** 任意の RemoteStore を差し込んで同期エンジンを組み立てる(テスト・非 Drive 用)。 */
  attachRemote(remote: RemoteStore): void {
    this.engine = new SyncEngine(this.repo, remote, () => new Date().toISOString(), this.imageStore);
    this.update({ status: 'connected', remoteName: remote.displayName, error: null });
  }

  /** Google Drive に接続する(GIS トークン取得 → RemoteStore 構築)。 */
  async connectGoogleDrive(): Promise<void> {
    const clientId = driveClientId();
    if (!clientId) { this.update({ error: 'VITE_GOOGLE_CLIENT_ID が未設定です' }); return; }
    this.update({ status: 'connecting', error: null });
    try {
      const tokens = await googleDriveTokens(clientId);
      this.attachRemote(new GoogleDriveRemoteStore({ tokens }));
    } catch (e) {
      this.update({ status: 'disconnected', error: errorMessage(e) });
    }
  }

  disconnect(): void {
    this.engine = null;
    this.update({ status: 'disconnected', remoteName: null });
  }

  /** push→pull を実行し、結果を状態に反映する。 */
  async syncNow(): Promise<void> {
    if (!this.engine || this.snap.isSyncing) return;
    this.update({ isSyncing: true, error: null });
    try {
      const summary = await this.engine.sync();
      this.update({ isSyncing: false, lastSummary: summary, lastSyncedAt: new Date().toISOString() });
    } catch (e) {
      this.update({ isSyncing: false, error: errorMessage(e) });
    }
  }
}

function driveClientId(): string | undefined {
  const env = import.meta.env as Record<string, string | undefined>;
  return env.VITE_GOOGLE_CLIENT_ID;
}

function errorMessage(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

// MARK: - アプリ結線(シングルトン + React フック)

let instance: SyncController | null = null;

/** この端末の SyncController(プロセス内で1つ。接続状態を画面遷移で保持する)。 */
export function getSyncController(db: OpenedDatabase): SyncController {
  if (!instance) instance = new SyncController(db.repo, db.imageStore);
  return instance;
}

/** SyncController の状態を購読する。 */
export function useSyncState(controller: SyncController): SyncState {
  return useSyncExternalStore(controller.subscribe, controller.getSnapshot);
}
