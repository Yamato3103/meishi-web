import Foundation

/// 最小の JSON 値型。
///
/// card.json のフィールド値(`v`)と、未知トップレベルキーのラウンドトリップ保持
/// (§10.1 の前方互換要件「未知フィールドは保持して書き戻す」)に用いる。
/// 数値と真偽値を厳密に区別できるよう、Foundation 変換を自前で持つ。
public indirect enum JSONValue: Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    /// JSONSerialization が生成する Foundation オブジェクトから取り込む。
    public init(foundation object: Any) {
        switch object {
        case let s as String:
            self = .string(s)
        case let n as NSNumber:
            // NSNumber は Bool と数値を型IDで区別する(true/false が 1/0 に化けるのを防ぐ)。
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                self = .bool(n.boolValue)
            } else {
                self = .number(n.doubleValue)
            }
        case is NSNull:
            self = .null
        case let arr as [Any]:
            self = .array(arr.map(JSONValue.init(foundation:)))
        case let dict as [String: Any]:
            self = .object(dict.mapValues(JSONValue.init(foundation:)))
        default:
            self = .null
        }
    }

    /// JSONSerialization に渡せる Foundation オブジェクトへ変換する。
    public func toFoundation() -> Any {
        switch self {
        case .string(let s): return s
        case .number(let d):
            // 整数値は整数として出力されるよう Int 化を試みる(例: 12.0 → 12)。
            if d.rounded() == d, abs(d) < 9.007e15 {
                return NSNumber(value: Int64(d))
            }
            return NSNumber(value: d)
        case .bool(let b): return NSNumber(value: b)
        case .null: return NSNull()
        case .array(let a): return a.map { $0.toFoundation() }
        case .object(let o): return o.mapValues { $0.toFoundation() }
        }
    }

    /// 文字列値を取り出す(文字列でなければ nil)。
    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// 真偽値を取り出す(真偽でなければ nil)。
    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// 履歴表示などに使う人間可読な文字列(null は nil)。
    public var displayText: String? {
        switch self {
        case .string(let s): return s
        case .bool(let b): return b ? "はい" : "いいえ"
        case .number(let d): return (d.rounded() == d && abs(d) < 9.007e15) ? String(Int64(d)) : String(d)
        case .null: return nil
        case .array, .object: return nil
        }
    }
}
