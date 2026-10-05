import { useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import type { OpenedDatabase } from './database';
import { deviceId } from './database';
import { SyncController, getSyncController, useSyncState } from './syncController';
import { s } from './ui';

/** 設定: ストレージ状態・端末ID・件数・最近削除への導線。 */
export function SettingsScreen({
  db, onBack, onOpenDeleted,
}: {
  db: OpenedDatabase;
  onBack: () => void;
  onOpenDeleted: () => void;
}) {
  const [total, setTotal] = useState<number | null>(null);
  const [deleted, setDeleted] = useState<number | null>(null);

  useEffect(() => {
    let alive = true;
    Promise.all([db.repo.fetchAll(), db.repo.fetchDeleted()]).then(([all, del]) => {
      if (!alive) return;
      setTotal(all.length);
      setDeleted(del.length);
    });
    return () => { alive = false; };
  }, [db]);

  return (
    <div>
      <div style={s.topbar}>
        <button style={s.iconButton} onClick={onBack}>← 戻る</button>
        <h1 style={s.title}>設定</h1>
      </div>

      <div style={s.card}>
        <Row label="ストレージ">
          <span style={{ ...s.badge, ...(db.persistent ? s.badgeOk : s.badgeWarn) }}>
            {db.persistent ? 'OPFS 永続化' : 'メモリのみ(非永続)'}
          </span>
        </Row>
        <Row label="端末 ID"><code style={{ fontSize: '0.8rem' }}>{deviceId()}</code></Row>
        <Row label="名刺(有効)">{total ?? '—'} 件</Row>
        <Row label="最近削除">
          <button style={s.ghost} onClick={onOpenDeleted}>{deleted ?? 0} 件を表示</button>
        </Row>
      </div>

      <SyncSection db={db} />

      <p style={{ ...s.meta, marginTop: '1rem' }}>
        データはこの端末内(ブラウザの OPFS)にのみ保存されます。サーバには送信しません。
        Google Drive を接続したときだけ、あなたの Drive の `MeishiVault` フォルダに card.json と画像を同期します。
      </p>
    </div>
  );
}

/** 同期(Google Drive)。クライアント ID 未設定なら接続導線は出さず案内のみ。 */
function SyncSection({ db }: { db: OpenedDatabase }) {
  const controller = getSyncController(db);
  const sync = useSyncState(controller);
  const configured = SyncController.isDriveConfigured();

  return (
    <div style={{ ...s.card, marginTop: '1rem' }}>
      <div style={{ ...s.label, marginBottom: '0.5rem' }}>同期(Google Drive)</div>

      {!configured && (
        <p style={{ ...s.meta, margin: 0 }}>
          未設定です。<code>VITE_GOOGLE_CLIENT_ID</code> を設定すると Google Drive 同期を有効にできます
          (docs/web-google-drive-setup.md)。
        </p>
      )}

      {configured && (
        <>
          <Row label="接続">
            <span style={{ ...s.badge, ...(sync.status === 'connected' ? s.badgeOk : s.badgeWarn) }}>
              {sync.status === 'connected' ? `接続済み（${sync.remoteName}）` : sync.status === 'connecting' ? '接続中…' : '未接続'}
            </span>
          </Row>

          {sync.status !== 'connected' ? (
            <button
              style={{ ...s.primaryWide, marginTop: '0.5rem', ...(sync.status === 'connecting' ? s.disabled : {}) }}
              disabled={sync.status === 'connecting'}
              onClick={() => void controller.connectGoogleDrive()}
            >
              Google Drive に接続
            </button>
          ) : (
            <>
              <button
                style={{ ...s.primaryWide, marginTop: '0.5rem', ...(sync.isSyncing ? s.disabled : {}) }}
                disabled={sync.isSyncing}
                onClick={() => void controller.syncNow()}
              >
                {sync.isSyncing ? '同期中…' : '今すぐ同期'}
              </button>
              {sync.lastSyncedAt && (
                <p style={{ ...s.meta, marginBottom: 0 }}>
                  最終同期: {new Date(sync.lastSyncedAt).toLocaleString()}
                  {sync.lastSummary && `（送信 ${sync.lastSummary.pushed} / 受信 ${sync.lastSummary.pulled} / 削除 ${sync.lastSummary.deletionsPulled}）`}
                </p>
              )}
            </>
          )}
        </>
      )}

      {sync.error && <p style={{ color: '#c0392b', ...s.meta, marginBottom: 0 }}>エラー: {sync.error}</p>}
    </div>
  );
}

function Row({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div style={{ ...s.fieldRow, display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
      <div style={{ ...s.label, margin: 0, flex: 1 }}>{label}</div>
      <div>{children}</div>
    </div>
  );
}
