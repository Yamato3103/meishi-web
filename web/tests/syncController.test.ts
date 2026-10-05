import { describe, it, expect } from 'vitest';
import { NodeSqliteDriver } from '../src/db/nodeSqliteDriver';
import { runMigrations } from '../src/db/migrations';
import { CardRepository } from '../src/db/cardRepository';
import { makeCard } from '../src/core/card';
import { InMemoryRemoteStore } from '../src/sync/inMemoryRemoteStore';
import { MemoryImageStore } from '../src/sync/imageStore';
import { SyncController } from '../src/app/syncController';

async function makeController(deviceId: string) {
  const driver = NodeSqliteDriver.open();
  await runMigrations(driver);
  const repo = new CardRepository(driver, deviceId);
  return { repo, controller: new SyncController(repo, new MemoryImageStore()) };
}

describe('SyncController(RemoteStore を差し込んで push/pull を駆動)', () => {
  it('attachRemote → syncNow で状態が更新される', async () => {
    const remote = new InMemoryRemoteStore();
    const { repo, controller } = await makeController('A');
    await repo.create(makeCard({ id: 'c1', familyName: '山田' }));

    controller.attachRemote(remote);
    expect(controller.getSnapshot().status).toBe('connected');

    await controller.syncNow();
    const snap = controller.getSnapshot();
    expect(snap.isSyncing).toBe(false);
    expect(snap.lastSyncedAt).not.toBeNull();
    expect(snap.lastSummary?.pushed).toBe(1);
  });

  it('2台の Controller が同じストア越しに収束する', async () => {
    const remote = new InMemoryRemoteStore();
    const a = await makeController('A');
    const b = await makeController('B');
    a.controller.attachRemote(remote);
    b.controller.attachRemote(remote);

    await a.repo.create(makeCard({ id: 'c1', familyName: '山田', email: 'y@x.jp' }));
    await a.controller.syncNow();
    await b.controller.syncNow();

    expect((await b.repo.fetchOne('c1'))?.familyName).toBe('山田');
    expect(b.controller.getSnapshot().lastSummary?.pulled).toBe(1);
  });

  it('購読者に状態変化が通知される', async () => {
    const { controller } = await makeController('A');
    let hits = 0;
    const unsub = controller.subscribe(() => { hits += 1; });
    controller.attachRemote(new InMemoryRemoteStore());
    expect(hits).toBeGreaterThan(0);
    unsub();
  });

  it('Drive 未設定では isDriveConfigured が false', () => {
    expect(SyncController.isDriveConfigured()).toBe(false);
  });
});
