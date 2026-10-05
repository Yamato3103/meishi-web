import { useEffect, useState } from 'react';
import { useDatabase } from './app/useDatabase';
import { ListScreen } from './app/ListScreen';
import { DetailScreen } from './app/DetailScreen';
import { EditScreen } from './app/EditScreen';
import { SettingsScreen } from './app/SettingsScreen';
import { DeletedScreen } from './app/DeletedScreen';
import { CaptureScreen } from './app/CaptureScreen';
import { s } from './app/ui';

/**
 * 画面遷移(軽量ルータ)。ルータ用ライブラリは持たず useState で切り替える。
 * list ⇄ new/detail、detail → edit、list → settings → deleted。
 */
type Screen =
  | { name: 'list' }
  | { name: 'new' }
  | { name: 'capture' }
  | { name: 'detail'; id: string }
  | { name: 'edit'; id: string }
  | { name: 'settings' }
  | { name: 'deleted' };

export function App() {
  const { db, error } = useDatabase();
  const [screen, setScreen] = useState<Screen>({ name: 'list' });

  // 開発時のみ、デバッグ/検証用に db をグローバル公開する。
  useEffect(() => {
    if (db && import.meta.env.DEV) (globalThis as { __db?: unknown }).__db = db;
  }, [db]);

  if (error) {
    return (
      <main style={s.app}>
        <div style={s.topbar}><h1 style={s.title}>MeishiVault</h1></div>
        <p style={{ color: '#c0392b' }}>DB の初期化に失敗しました: {error}</p>
      </main>
    );
  }

  if (!db) {
    return (
      <main style={s.app}>
        <div style={s.topbar}><h1 style={s.title}>MeishiVault</h1><span style={s.badge}>読み込み中…</span></div>
      </main>
    );
  }

  return (
    <main style={s.app}>
      {screen.name === 'list' && (
        <ListScreen
          db={db}
          onOpen={(id) => setScreen({ name: 'detail', id })}
          onNew={() => setScreen({ name: 'new' })}
          onCapture={() => setScreen({ name: 'capture' })}
          onSettings={() => setScreen({ name: 'settings' })}
        />
      )}

      {screen.name === 'capture' && (
        <CaptureScreen
          db={db}
          onSaved={(id) => setScreen({ name: 'detail', id })}
          onCancel={() => setScreen({ name: 'list' })}
        />
      )}

      {screen.name === 'new' && (
        <EditScreen
          db={db}
          onSaved={(id) => setScreen({ name: 'detail', id })}
          onCancel={() => setScreen({ name: 'list' })}
        />
      )}

      {screen.name === 'detail' && (
        <DetailScreen
          db={db}
          cardId={screen.id}
          onEdit={(id) => setScreen({ name: 'edit', id })}
          onBack={() => setScreen({ name: 'list' })}
          onDeleted={() => setScreen({ name: 'list' })}
        />
      )}

      {screen.name === 'edit' && (
        <EditScreen
          db={db}
          cardId={screen.id}
          onSaved={(id) => setScreen({ name: 'detail', id })}
          onCancel={() => setScreen({ name: 'detail', id: screen.id })}
        />
      )}

      {screen.name === 'settings' && (
        <SettingsScreen
          db={db}
          onBack={() => setScreen({ name: 'list' })}
          onOpenDeleted={() => setScreen({ name: 'deleted' })}
        />
      )}

      {screen.name === 'deleted' && (
        <DeletedScreen db={db} onBack={() => setScreen({ name: 'settings' })} />
      )}
    </main>
  );
}
