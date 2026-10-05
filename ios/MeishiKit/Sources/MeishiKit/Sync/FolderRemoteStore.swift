import Foundation

/// ローカル/iCloud Drive フォルダを裏側にする `RemoteStore` 実装。
///
/// ユーザー自身が所有するフォルダ(端末内、または iCloud Drive 同期フォルダ)に
/// card.json と画像をそのまま置く。「データを預からない」方針に合致し、Google Drive
/// を使わないゼロ設定の同期経路になる。版管理と差分トークンのために、フォルダ直下に
/// 小さな索引ファイル `.sync-index.json` を持つ。
public actor FolderRemoteStore: RemoteStore {

    public nonisolated let displayName: String
    private let root: URL
    private let indexURL: URL

    private struct Index: Codable {
        var seq: Int = 0
        var rev: Int = 0
        var entries: [String: Entry] = [:]   // name -> Entry
        struct Entry: Codable {
            var id: String
            var revision: String
            var seq: Int
            var deleted: Bool
            var updatedAt: Date
        }
    }

    public init(root: URL, displayName: String = "フォルダ") throws {
        self.root = root
        self.displayName = displayName
        self.indexURL = root.appendingPathComponent(".sync-index.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    // MARK: - 索引の読み書き

    private func loadIndex() -> Index {
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder.iso8601.decode(Index.self, from: data) else {
            return Index()
        }
        return index
    }

    private func saveIndex(_ index: Index) throws {
        let data = try JSONEncoder.iso8601.encode(index)
        try data.write(to: indexURL, options: .atomic)
    }

    private func fileURL(_ name: String) -> URL { root.appendingPathComponent(name) }

    private func name(forId id: String, in index: Index) -> String? {
        index.entries.first { $0.value.id == id }?.key
    }

    // MARK: - RemoteStore

    public func list() async throws -> [RemoteFileMeta] {
        let index = loadIndex()
        return index.entries
            .filter { !$0.value.deleted }
            .map { RemoteFileMeta(id: $0.value.id, name: $0.key, revision: $0.value.revision,
                                  updatedAt: $0.value.updatedAt, deleted: false) }
            .sorted { $0.name < $1.name }
    }

    public func read(id: String) async throws -> Data {
        let index = loadIndex()
        guard let name = name(forId: id, in: index), index.entries[name]?.deleted == false else {
            throw RemoteError.notFound(id)
        }
        return try Data(contentsOf: fileURL(name))
    }

    @discardableResult
    public func write(name: String, data: Data, ifMatch: String?) async throws -> RemoteFileMeta {
        var index = loadIndex()
        if let existing = index.entries[name], !existing.deleted {
            if let expected = ifMatch, expected != existing.revision {
                throw RemoteConflictError(name: name, expected: expected, actual: existing.revision)
            }
            index.seq += 1; index.rev += 1
            var entry = existing
            entry.revision = "r\(index.rev)"; entry.seq = index.seq; entry.updatedAt = Date()
            index.entries[name] = entry
            try data.write(to: fileURL(name), options: .atomic)
            try saveIndex(index)
            return RemoteFileMeta(id: entry.id, name: name, revision: entry.revision,
                                  updatedAt: entry.updatedAt, deleted: false)
        } else {
            if let expected = ifMatch {
                throw RemoteConflictError(name: name, expected: expected, actual: "<absent>")
            }
            index.seq += 1; index.rev += 1
            let id = index.entries[name]?.id ?? UUID().uuidString
            let entry = Index.Entry(id: id, revision: "r\(index.rev)", seq: index.seq,
                                    deleted: false, updatedAt: Date())
            index.entries[name] = entry
            try data.write(to: fileURL(name), options: .atomic)
            try saveIndex(index)
            return RemoteFileMeta(id: id, name: name, revision: entry.revision,
                                  updatedAt: entry.updatedAt, deleted: false)
        }
    }

    public func delete(id: String) async throws {
        var index = loadIndex()
        guard let name = name(forId: id, in: index), var entry = index.entries[name] else {
            throw RemoteError.notFound(id)
        }
        index.seq += 1; index.rev += 1
        entry.deleted = true; entry.revision = "r\(index.rev)"; entry.seq = index.seq
        index.entries[name] = entry
        try? FileManager.default.removeItem(at: fileURL(name))
        try saveIndex(index)
    }

    public func changes(since token: String?) async throws -> RemoteChanges {
        let index = loadIndex()
        // token=nil(初回)はトークン確立のみで差分は返さない。
        guard let token, let sinceSeq = Int(token) else {
            return RemoteChanges(files: [], nextToken: String(index.seq))
        }
        let changed = index.entries
            .filter { $0.value.seq > sinceSeq }
            .sorted { $0.value.seq < $1.value.seq }
        let files = changed.map {
            RemoteFileMeta(id: $0.value.id, name: $0.key, revision: $0.value.revision,
                           updatedAt: $0.value.updatedAt, deleted: $0.value.deleted)
        }
        let next = changed.last?.value.seq ?? sinceSeq
        return RemoteChanges(files: files, nextToken: String(next))
    }
}

// MARK: - JSON(ISO8601)

extension JSONEncoder {
    static var iso8601: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
