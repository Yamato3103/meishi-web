/**
 * リモート同期バックエンドの抽象(iOS の MeishiKit.RemoteStore と同一契約・§10.3)。
 *
 * 同期エンジン(`SyncEngine`)はこのインターフェイスだけに依存し、Drive API を
 * 直接は呼ばない(将来 iCloud/Dropbox/WebDAV に差し替え可能。§5.4/§20)。
 * データ本文は Uint8Array(card.json はテキストを UTF-8 で、画像はバイナリを載せる)。
 */

/** リモート上のファイル1件のメタ情報(files.list 相当)。 */
export interface RemoteFileMeta {
  /** リモートのファイル識別子(Drive の fileId 相当)。 */
  id: string;
  /** ファイル名(例: `<uuid>.json`、`<uuid>_front.jpg`)。 */
  name: string;
  /** リモートの版識別子(etag / Drive の version 相当)。楽観ロックに使う。 */
  revision: string;
  /** 最終更新時刻(判明する場合、ISO8601)。 */
  updatedAt: string | null;
  /** tombstone(changes 上で削除として現れたか)。 */
  deleted: boolean;
}

/** `changes.list` 相当の差分取得結果。 */
export interface RemoteChanges {
  files: RemoteFileMeta[];
  /** 次回の差分取得に渡すトークン(永続化する)。 */
  nextToken: string;
}

/** 楽観ロック失敗(If-Match 相当。リモート側が想定 revision と違う)。 */
export class RemoteConflictError extends Error {
  constructor(
    public readonly fileName: string,
    public readonly expected: string | null,
    public readonly actual: string,
  ) {
    super(`remote conflict on ${fileName}: expected ${expected ?? '<nil>'}, actual ${actual}`);
    this.name = 'RemoteConflictError';
  }
}

/** リモートに対象ファイルが無い。 */
export class RemoteNotFoundError extends Error {
  constructor(public readonly id: string) {
    super(`remote file not found: ${id}`);
    this.name = 'RemoteNotFoundError';
  }
}

export interface RemoteStore {
  /** 設定画面や診断に使う人間可読な名称(例: "Google Drive")。 */
  readonly displayName: string;

  /** 同期フォルダ内の全ファイルを列挙する(初回ブートストラップ用)。 */
  list(): Promise<RemoteFileMeta[]>;

  /** ファイル本文を取得する。 */
  read(id: string): Promise<Uint8Array>;

  /**
   * ファイルを作成/更新する。
   * @param ifMatch 期待するリモート revision。既存版と食い違えば `RemoteConflictError`。
   *   null なら無条件上書き(新規作成 or 強制)。
   */
  write(name: string, data: Uint8Array, ifMatch: string | null): Promise<RemoteFileMeta>;

  /** ファイルを削除する。 */
  delete(id: string): Promise<void>;

  /** 前回トークン以降の差分を取得する。token が null なら現時点のトークンを確立して差分は空。 */
  changes(token: string | null): Promise<RemoteChanges>;
}
