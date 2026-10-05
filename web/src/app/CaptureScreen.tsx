import { useEffect, useRef, useState } from 'react';
import type { ChangeEvent, CSSProperties } from 'react';
import type { Card } from '../core';
import { extract, draftFromExtraction } from '../core';
import { recognize } from '../ocr/recognize';
import type { OpenedDatabase } from './database';
import { sha256hex } from './opfsImageStore';
import { EditScreen } from './EditScreen';
import { s } from './ui';

type Phase =
  | { name: 'pick' }
  | { name: 'working'; progress: number }
  | { name: 'confirm'; draft: Card; previewUrl: string; file: File; width: number; height: number }
  | { name: 'error'; message: string };

/** 画像の自然寸法とプレビュー URL を得る。 */
function loadImage(file: File): Promise<{ width: number; height: number; url: string }> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => resolve({ width: img.naturalWidth, height: img.naturalHeight, url });
    img.onerror = () => { URL.revokeObjectURL(url); reject(new Error('画像を読み込めませんでした')); };
    img.src = url;
  });
}

/**
 * 取り込み: 画像を選ぶ → 端末内 OCR(Tesseract.js)→ 決定論抽出 → 確認画面(EditScreen)。
 * 画像はアップロードされず、認識も抽出もすべて端末内で行う。
 */
export function CaptureScreen({
  db, onSaved, onCancel,
}: {
  db: OpenedDatabase;
  onSaved: (id: string) => void;
  onCancel: () => void;
}) {
  const [phase, setPhase] = useState<Phase>({ name: 'pick' });
  const inputRef = useRef<HTMLInputElement>(null);
  const previewRef = useRef<string | null>(null);

  // プレビュー URL は使い終わったら解放する。
  useEffect(() => {
    return () => { if (previewRef.current) URL.revokeObjectURL(previewRef.current); };
  }, []);

  const onFile = async (e: ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setPhase({ name: 'working', progress: 0 });
    try {
      const { width, height, url } = await loadImage(file);
      previewRef.current = url;
      const document = await recognize(file, { width, height }, {
        onProgress: (r) => setPhase({ name: 'working', progress: r }),
      });
      const draft = draftFromExtraction(extract(document));
      setPhase({ name: 'confirm', draft, previewUrl: url, file, width, height });
    } catch (err) {
      setPhase({ name: 'error', message: err instanceof Error ? err.message : String(err) });
    }
  };

  if (phase.name === 'confirm') {
    const { file, width, height } = phase;
    // 保存されたカード(統合先/新規いずれの id でも)に取り込んだ画像を紐づける。
    const saveWithImage = async (id: string) => {
      try {
        const bytes = new Uint8Array(await file.arrayBuffer());
        const sha = await sha256hex(bytes);
        const ext = file.type === 'image/png' ? 'png' : 'jpg';
        const path = `${id}_front.${ext}`;
        await db.imageStore.saveRaw(bytes, path);
        await db.repo.addImage({
          id: crypto.randomUUID(), cardId: id, side: 'front',
          relativePath: path, sha256: sha, width, height, createdAt: new Date().toISOString(),
        });
      } catch (err) {
        console.error('画像の保存に失敗しました', err);
      }
      onSaved(id);
    };
    return (
      <div>
        <img src={phase.previewUrl} alt="取り込んだ名刺" style={styles.preview} />
        <EditScreen
          db={db}
          initial={phase.draft}
          title="取り込み内容を確認"
          onSaved={saveWithImage}
          onCancel={onCancel}
        />
      </div>
    );
  }

  return (
    <div>
      <div style={s.topbar}>
        <button style={s.iconButton} onClick={onCancel}>← 戻る</button>
        <h1 style={s.title}>名刺を取り込む</h1>
      </div>

      {phase.name === 'pick' && (
        <div style={styles.pickCard}>
          <p style={{ ...s.meta, marginTop: 0 }}>
            名刺の写真を選ぶと、端末内で文字を読み取り(OCR)、各項目を自動で埋めます。
            画像や文字はサーバに送信されません。
          </p>
          <button style={s.primaryWide} onClick={() => inputRef.current?.click()}>写真を選ぶ / 撮影</button>
          <input
            ref={inputRef}
            type="file"
            accept="image/*"
            capture="environment"
            style={{ display: 'none' }}
            onChange={onFile}
          />
        </div>
      )}

      {phase.name === 'working' && (
        <div style={styles.pickCard}>
          <p style={{ margin: 0, fontWeight: 600 }}>読み取り中… {Math.round(phase.progress * 100)}%</p>
          <div style={styles.barTrack}><div style={{ ...styles.barFill, width: `${Math.round(phase.progress * 100)}%` }} /></div>
          <p style={s.meta}>初回は言語データの読み込みに少し時間がかかります。</p>
        </div>
      )}

      {phase.name === 'error' && (
        <div style={styles.pickCard}>
          <p style={{ color: '#c0392b', marginTop: 0 }}>読み取りに失敗しました: {phase.message}</p>
          <button style={s.ghost} onClick={() => setPhase({ name: 'pick' })}>もう一度</button>
        </div>
      )}
    </div>
  );
}

const styles: Record<string, CSSProperties> = {
  pickCard: { border: '1px solid #e5e5ea', borderRadius: 12, background: '#fafafa', padding: '1.25rem', marginTop: '1rem', display: 'flex', flexDirection: 'column', gap: '0.75rem' },
  preview: { display: 'block', maxWidth: '100%', maxHeight: 220, objectFit: 'contain', borderRadius: 10, border: '1px solid #e5e5ea', margin: '0.5rem auto 0' },
  barTrack: { height: 8, background: '#e5e5ea', borderRadius: 999, overflow: 'hidden' },
  barFill: { height: '100%', background: '#1e66f5', transition: 'width 0.2s' },
};
