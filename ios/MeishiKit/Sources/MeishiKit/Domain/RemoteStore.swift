import Foundation

/// リモート上のファイル1件のメタ情報(§10.2 の files.list 相当)。
public struct RemoteFileMeta: Equatable, Sendable {
    /// リモートのファイル識別子(Drive の fileId 相当)。
    public var id: String
    /// ファイル名(例: `<uuid>.json`、`<uuid>_front.jpg`)。
    public var name: String
    /// リモートの版識別子(etag / Drive の version 相当)。楽観ロックに使う。
    public var revision: String
    /// 最終更新時刻(判明する場合)。
    public var updatedAt: Date?
    /// tombstone(changes 上で削除として現れたか)。
    public var deleted: Bool

    public init(id: String, name: String, revision: String, updatedAt: Date? = nil, deleted: Bool = false) {
        self.id = id
        self.name = name
        self.revision = revision
        self.updatedAt = updatedAt
        self.deleted = deleted
    }
}

/// `changes.list` 相当の差分取得結果。
public struct RemoteChanges: Sendable {
    public var files: [RemoteFileMeta]
    /// 次回の差分取得に渡すトークン(永続化する)。
    public var nextToken: String

    public init(files: [RemoteFileMeta], nextToken: String) {
        self.files = files
        self.nextToken = nextToken
    }
}

/// 楽観ロック失敗(If-Match 相当。リモート側が想定revisionと違う)。
public struct RemoteConflictError: Error, Equatable, Sendable {
    public var name: String
    public var expected: String?
    public var actual: String
    public init(name: String, expected: String?, actual: String) {
        self.name = name
        self.expected = expected
        self.actual = actual
    }
}

/// リモート同期バックエンドの抽象化(§10.3 の Sync 継ぎ目)。
///
/// Phase 2 で Google Drive を実装し、将来 iCloud / Dropbox / WebDAV を差し替え
/// 可能にする。同期エンジン(`SyncEngine`)はこのプロトコルだけに依存し、
/// Drive API を直接は呼ばない(Google 審査リスクへの保険。§5.4 / §20)。
public protocol RemoteStore: Sendable {

    /// 設定画面や診断表示に使う人間可読な名称(例: "Google Drive")。
    var displayName: String { get }

    /// 同期フォルダ内の全ファイルを列挙する(初回ブートストラップ用)。
    func list() async throws -> [RemoteFileMeta]

    /// ファイル本文を取得する。
    func read(id: String) async throws -> Data

    /// ファイルを作成/更新する。
    /// - Parameter ifMatch: 期待するリモート revision。既存版と食い違えば `RemoteConflictError`。
    ///   nil の場合は無条件上書き(新規作成 or 強制)。
    @discardableResult
    func write(name: String, data: Data, ifMatch: String?) async throws -> RemoteFileMeta

    /// ファイルを削除する。
    func delete(id: String) async throws

    /// 前回トークン以降の差分を取得する。token が nil なら現時点のトークンを確立して差分は空。
    func changes(since token: String?) async throws -> RemoteChanges
}
