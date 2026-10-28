import XCTest
import GRDB

private struct Author: TableRecord {
    static let databaseTableName = "author"
}

private struct Book1: TableRecord {
    static let databaseTableName = "book1"
    static let author = belongsTo(Author.self, using: ForeignKey(["authorId"]))
    static let parent = belongsTo(Book1.self, key: "parent", using: ForeignKey(["parentId"]))
}

private struct Writer: TableRecord {
    static let databaseTableName = "writer"
}

private struct Country: TableRecord {
    static let databaseTableName = "country"
}

private struct Edition1: TableRecord {
    static let databaseTableName = "edition1"
    static let writer = belongsTo(Writer.self, using: ForeignKey(["writerId"]))
    static let country = belongsTo(Country.self, using: ForeignKey(["countryCode"]))
}

final class DigitSuffixedTableAliasTests: XCTestCase {
    private func makeDatabase(_ sql: String) throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue()
        try dbQueue.write { db in try db.execute(sql: sql) }
        return dbQueue
    }

    private let books = """
        CREATE TABLE author (id INTEGER PRIMARY KEY, name TEXT);
        CREATE TABLE book1 (id INTEGER PRIMARY KEY, authorId INTEGER REFERENCES author(id),
                            parentId INTEGER REFERENCES book1(id), title TEXT);
        INSERT INTO author VALUES (1, 'Herman Melville');
        INSERT INTO book1 VALUES (1, 1, NULL, 'Moby-Dick'), (2, 1, 1, 'Pierre');
        """

    func testAliasSpelledLikeTheTableName() throws {
        try makeDatabase(books).read { db in
            for name in ["book1", "BOOK1"] {
                let request = Book1.including(required: Book1.author.aliased(TableAlias(name: name)))
                XCTAssertEqual(try Row.fetchAll(db, request).count, 2, name)
            }
            let selfJoin = Book1.aliased(TableAlias(name: "book1")).including(required: Book1.parent)
            XCTAssertEqual(try Row.fetchAll(db, selfJoin).count, 1)
        }
    }

    func testNoSharedColumnName() throws {
        let dbQueue = try makeDatabase("""
            CREATE TABLE writer (writerPk INTEGER PRIMARY KEY, name TEXT);
            CREATE TABLE country (code TEXT PRIMARY KEY, countryName TEXT);
            CREATE TABLE edition1 (editionPk INTEGER PRIMARY KEY, writerId INTEGER REFERENCES writer(writerPk),
                                   countryCode TEXT REFERENCES country(code), title TEXT);
            INSERT INTO writer VALUES (1, 'Herman Melville');
            INSERT INTO country VALUES ('US', 'United States');
            INSERT INTO edition1 VALUES (10, 1, 'US', 'Moby-Dick');
            """)
        try dbQueue.read { db in
            let request = Edition1
                .including(required: Edition1.country)
                .including(required: Edition1.writer.aliased(TableAlias(name: "edition1")))
            let row = try XCTUnwrap(Row.fetchOne(db, request))
            XCTAssertEqual(row.scopes["country"], ["code": "US", "countryName": "United States"])
            XCTAssertEqual(row.scopes["writer"], ["writerPk": 1, "name": "Herman Melville"])
        }
    }
}
