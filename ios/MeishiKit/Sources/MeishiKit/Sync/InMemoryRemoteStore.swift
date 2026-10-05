import Foundation

/// テスト用のインメモリ `RemoteStore` 偽実装。
///
/// 競合シナリオ(§5.3)を Drive 無しでユニットテストするための継ぎ目。
/// 名前でファイルを管理し、書き込みごとに revision と changes 用の
/// 単調増加トークンを進める。
public actor InMemoryRemoteStore: RemoteStore {

    public nonisolated let displayName: String

    private struct Entry {
        var meta: RemoteFileMeta
        var data: Data
        /// changes 順序付け用の単調増加シーケンス。
        var seq: Int
    }

    private var files: [String: Entry] = [:]   // name -> Entry
    private var idToName: [String: String] = [:]
    private var seqCounter = 0
    private var revCounter = 0

    public init(displayName: String = "In-Memory") {
        self.displayName = displayName
    }

    private func nextSeq() -> Int { seqCounter += 1; return seqCounter }
    private func nextRev() -> String { revCounter += 1; return "r\(revCounter)" }

    // MARK: RemoteStore

    public func list() async throws -> [RemoteFileMeta] {
        files.values
            .filter { !$0.meta.deleted }
            .map { $0.meta }
            .sorted { $0.name < $1.name }
    }

    public func read(id: String) async throws -> Data {
        guard let name = idToName[id], let entry = files[name], !entry.meta.deleted else {
            throw RemoteError.notFound(id)
        }
        return entry.data
    }

    @discardableResult
    public func write(name: String, data: Data, ifMatch: String?) async throws -> RemoteFileMeta {
        if let existing = files[name], !existing.meta.deleted {
            // 楽観ロック: 期待revisionが現行と食い違えば衝突。
            if let expected = ifMatch, expected != existing.meta.revision {
                throw RemoteConflictError(name: name, expected: expected, actual: existing.meta.revision)
            }
            var updated = existing
            updated.data = data
            updated.seq = nextSeq()
            updated.meta.revision = nextRev()
            updated.meta.updatedAt = Date()
            files[name] = updated
            return updated.meta
        } else {
            // ifMatch 指定があるのに対象が無い = 想定外(削除済みへの更新など)。
            if let expected = ifMatch {
                throw RemoteConflictError(name: name, expected: expected, actual: "<absent>")
            }
            let id = files[name]?.meta.id ?? UUID().uuidString
            let meta = RemoteFileMeta(id: id, name: name, revision: nextRev(), updatedAt: Date(), deleted: false)
            files[name] = Entry(meta: meta, data: data, seq: nextSeq())
            idToName[id] = name
            return meta
        }
    }

    public func delete(id: String) async throws {
        guard let name = idToName[id], var entry = files[name] else { throw RemoteError.notFound(id) }
        entry.meta.deleted = true
        entry.meta.revision = nextRev()
        entry.seq = nextSeq()
        entry.data = Data()
        files[name] = entry
    }

    public func changes(since token: String?) async throws -> RemoteChanges {
        let sinceSeq = token.flatMap(Int.init) ?? 0
        let changed = files.values
            .filter { $0.seq > sinceSeq }
            .sorted { $0.seq < $1.seq }
        let next = changed.last?.seq ?? sinceSeq
        // token=nil(初回)はトークン確立のみで差分は返さない仕様に合わせる。
        let files = token == nil ? [] : changed.map { $0.meta }
        return RemoteChanges(files: files, nextToken: String(token == nil ? seqCounter : next))
    }

    // MARK: - テスト補助

    /// 別端末からの書き込みを模す(ifMatch 無しの直接投入)。
    public func seed(name: String, data: Data) async {
        _ = try? await write(name: name, data: data, ifMatch: nil)
    }

    public func currentRevision(name: String) async -> String? {
        files[name].map { $0.meta.revision }
    }
}

public enum RemoteError: Error, Equatable, Sendable {
    case notFound(String)
}
