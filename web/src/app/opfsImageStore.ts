import type { ImageStore } from '../sync/imageStore';
import { MemoryImageStore } from '../sync/imageStore';

/**
 * OPFS(Origin Private File System)に画像バイナリを保存する `ImageStore`。
 *
 * SQLite 本体と違い画像は独立ファイルなので、メインスレッドの非同期 API
 * (`createWritable` / `getFile`)で読み書きできる(Worker/SAHPool は不要)。
 * 名刺画像は `images/` ディレクトリ配下に相対パス名で置く(内容アドレス=不変)。
 */
export class OpfsImageStore implements ImageStore {
  private static readonly DIR = 'images';

  private async dir(): Promise<FileSystemDirectoryHandle> {
    const root = await navigator.storage.getDirectory();
    return root.getDirectoryHandle(OpfsImageStore.DIR, { create: true });
  }

  async exists(relativePath: string): Promise<boolean> {
    try {
      const dir = await this.dir();
      await dir.getFileHandle(relativePath);
      return true;
    } catch {
      return false;
    }
  }

  async read(relativePath: string): Promise<Uint8Array> {
    const dir = await this.dir();
    const handle = await dir.getFileHandle(relativePath);
    const file = await handle.getFile();
    return new Uint8Array(await file.arrayBuffer());
  }

  async saveRaw(data: Uint8Array, relativePath: string): Promise<void> {
    const dir = await this.dir();
    const handle = await dir.getFileHandle(relativePath, { create: true });
    const writable = await handle.createWritable();
    // BlobPart として書き込むため、確実に ArrayBuffer 実体を渡す。
    await writable.write(data.slice());
    await writable.close();
  }
}

/**
 * この環境に合った `ImageStore` を返す。OPFS の書き込み API が使えれば永続化、
 * 使えなければメモリ(非永続)にフォールバックする。
 */
export function openImageStore(): { store: ImageStore; persistent: boolean } {
  const hasOpfs = typeof navigator !== 'undefined'
    && !!navigator.storage?.getDirectory
    && typeof FileSystemFileHandle !== 'undefined'
    && 'createWritable' in FileSystemFileHandle.prototype;
  return hasOpfs
    ? { store: new OpfsImageStore(), persistent: true }
    : { store: new MemoryImageStore(), persistent: false };
}

/** バイナリの SHA-256 を16進文字列で返す(card.json の画像参照キー)。 */
export async function sha256hex(data: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', data.slice());
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}
