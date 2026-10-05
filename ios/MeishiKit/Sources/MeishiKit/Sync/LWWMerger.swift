import Foundation

/// マージで「負けた」フィールド値。サイレントなデータロスを防ぐため、
/// UI が名刺詳細の「編集履歴」に残せるよう呼び出し側へ返す(§5.3)。
public struct FieldConflict: Equatable, Sendable {
    public var field: String
    public var losingValue: JSONValue
    public var losingTimestamp: Date
    public var winningValue: JSONValue
    public var winningTimestamp: Date

    public init(field: String, losingValue: JSONValue, losingTimestamp: Date,
                winningValue: JSONValue, winningTimestamp: Date) {
        self.field = field
        self.losingValue = losingValue
        self.losingTimestamp = losingTimestamp
        self.winningValue = winningValue
        self.winningTimestamp = winningTimestamp
    }
}

/// マージ結果。
public struct MergeResult: Equatable, Sendable {
    public var document: CardDocument
    public var conflicts: [FieldConflict]
}

/// フィールド単位 Last-Write-Wins マージ(§5.3)。
///
/// 同一名刺(同じ id)の2版を、フィールドごとに新しい `t` を採用して統合する。
/// 時計ずれ対策として、`t` が同時刻のときは `revision` の大きい方を優先し、
/// それでも並ぶ場合は device_id の辞書順で決定論的に決める。
public enum LWWMerger {

    public enum MergeError: Error, Equatable {
        case idMismatch(String, String)
    }

    public static func merge(_ a: CardDocument, _ b: CardDocument) throws -> MergeResult {
        guard a.id == b.id else { throw MergeError.idMismatch(a.id, b.id) }

        // レコード全体の「新しい方」。updated_at → revision → device_id で決定論的に決める。
        let aWins = documentRank(a) >= documentRank(b)
        let newer = aWins ? a : b
        let older = aWins ? b : a

        // フィールド単位LWW。両版に現れる全フィールド名を対象にする。
        var mergedFields: [String: CardField] = [:]
        var conflicts: [FieldConflict] = []
        // 作成時刻。負けた値がこれより後=「作成後に実際に編集された」ものだけを競合として残し、
        // 一方だけが編集した(相手は初期値のまま)ケースを履歴ノイズにしない。
        let earliestCreated = min(a.createdAt, b.createdAt)
        let names = Set(a.fields.keys).union(b.fields.keys)
        for name in names {
            let fa = a.fields[name]
            let fb = b.fields[name]
            switch (fa, fb) {
            case let (.some(x), .some(y)):
                let pick = fieldRank(x, doc: a) >= fieldRank(y, doc: b) ? x : y
                let lose = fieldRank(x, doc: a) >= fieldRank(y, doc: b) ? y : x
                mergedFields[name] = pick
                // 値が食い違い、負けた側が非null、かつ負けた値が作成後に編集されたものだけ残す。
                if pick.v != lose.v, !lose.v.isNull, lose.t > earliestCreated {
                    conflicts.append(FieldConflict(
                        field: name,
                        losingValue: lose.v, losingTimestamp: lose.t,
                        winningValue: pick.v, winningTimestamp: pick.t
                    ))
                }
            case let (.some(x), .none):
                mergedFields[name] = x
            case let (.none, .some(y)):
                mergedFields[name] = y
            case (.none, .none):
                break
            }
        }

        // 画像は内容アドレス(sha256)で和集合。新しい版の並び順を優先する。
        var mergedImages = newer.images
        let known = Set(mergedImages.map { $0.sha256 })
        for img in older.images where !known.contains(img.sha256) {
            mergedImages.append(img)
        }

        // 未知トップレベルキーはキー単位で統合し、衝突は新しい版を採用。
        var mergedUnknown = older.unknown
        for (k, v) in newer.unknown { mergedUnknown[k] = v }

        let merged = CardDocument(
            schemaVersion: newer.schemaVersion,
            id: a.id,
            revision: max(a.revision, b.revision),
            deviceId: newer.deviceId,
            fields: mergedFields,
            tags: newer.tags,               // タグ配列はレコード単位LWW(per-tag時刻を持たない設計)
            ocrFulltext: newer.ocrFulltext ?? older.ocrFulltext,
            images: mergedImages,
            createdAt: min(a.createdAt, b.createdAt),
            updatedAt: max(a.updatedAt, b.updatedAt),
            deletedAt: newer.deletedAt,     // 削除/復元は updated_at の新しい版に従う
            mergedInto: newer.mergedInto ?? older.mergedInto,
            unknown: mergedUnknown
        )

        return MergeResult(document: merged, conflicts: conflicts.sorted { $0.field < $1.field })
    }

    // レコード全体の順位。大きいほど新しい。
    private static func documentRank(_ d: CardDocument) -> Rank {
        Rank(time: d.updatedAt, revision: d.revision, deviceId: d.deviceId)
    }

    // フィールドの順位。t → 所属ドキュメントの revision → device_id。
    private static func fieldRank(_ f: CardField, doc: CardDocument) -> Rank {
        Rank(time: f.t, revision: doc.revision, deviceId: doc.deviceId)
    }

    private struct Rank: Comparable {
        let time: Date
        let revision: Int
        let deviceId: String
        static func < (l: Rank, r: Rank) -> Bool {
            if l.time != r.time { return l.time < r.time }
            if l.revision != r.revision { return l.revision < r.revision }
            return l.deviceId < r.deviceId
        }
    }
}
