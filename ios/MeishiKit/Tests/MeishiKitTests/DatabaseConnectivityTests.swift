import XCTest
import GRDB
@testable import MeishiKit

/// M1-A の疎通確認: GRDB がリンクされ、DB に対してクエリが実行できることを保証する。
/// スキーマのテストは M1-B(マイグレーション導入)で追加する。
final class DatabaseConnectivityTests: XCTestCase {

    func testInMemoryDatabaseExecutesTrivialQuery() throws {
        let appDatabase = try AppDatabase.inMemory()

        let value = try appDatabase.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT 1")
        }

        XCTAssertEqual(value, 1)
    }

    func testSQLiteIsUsable() throws {
        let appDatabase = try AppDatabase.inMemory()

        let sqliteVersion = try appDatabase.writer.read { db in
            try String.fetchOne(db, sql: "SELECT sqlite_version()")
        }

        XCTAssertNotNil(sqliteVersion, "SQLite のバージョン文字列が取得できること")
    }
}
