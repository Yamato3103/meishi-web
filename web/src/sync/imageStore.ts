/**
 * 画像バイナリの保存先(iOS の MeishiKit.ImageStore に対応する最小契約)。
 *
 * card.json は sha256 参照だけを持ち、実体はこのストアが内容アドレス(相対パス)で保持する。
 * ブラウザ実装(OPFS/IndexedDB)はアプリ結線時に差し込む。テストや同期ロジック検証は
 * `MemoryImageStore` を使う。OPFS が非同期のため API は Promise ベース。
 */
export interface ImageStore {
  /** 相対パスの画像が存在するか。 */
  exists(relativePath: string): Promise<boolean>;
  /** 画像バイナリを取得する(存在しなければ例外)。 */
  read(relativePath: string): Promise<Uint8Array>;
  /** 画像バイナリを保存する(内容アドレスで不変=同名なら同一内容)。 */
  saveRaw(data: Uint8Array, relativePath: string): Promise<void>;
}

/** インメモリ実装(テスト・簡易利用向け)。 */
export class MemoryImageStore implements ImageStore {
  private files = new Map<string, Uint8Array>();

  async exists(relativePath: string): Promise<boolean> {
    return this.files.has(relativePath);
  }

  async read(relativePath: string): Promise<Uint8Array> {
    const data = this.files.get(relativePath);
    if (!data) throw new Error(`image not found: ${relativePath}`);
    return data;
  }

  async saveRaw(data: Uint8Array, relativePath: string): Promise<void> {
    this.files.set(relativePath, data);
  }
}
