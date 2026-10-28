import XCTest
import GRDB

// Book1 -> Author
// Book1 -> Book1 (parent)
//
// The table name ends with a digit, so the name GRDB generates for an
// unnamed alias on it (digitless radical + index: "book" + 1) can be spelled
// like the table name itself.
private struct Author: TableRecord {
    static let databaseTableName = "author"
}

private struct Book1: TableRecord {
    static let databaseTableName = "book1"
    static let author = belongsTo(Author.self, using: ForeignKey(["authorId"]))
    static let parent = belongsTo(Book1.self, key: "parent", using: ForeignKey(["parentId"]))
}

/// Tests for conflicts between user-defined table aliases and the aliases
/// that GRDB generates, when a table name ends with a digit.
///
/// Mirrors `AssociationTableAliasTestsSQLTests.testUserInducedNameConflict`,
/// with a table named `book1` instead of `a`.
class AssociationTableAliasDigitSuffixTests: GRDBTestCase {

    override func setup(_ dbWriter: some DatabaseWriter) throws {
        try dbWriter.write { db in
            try db.create(table: "author") { t in
                t.primaryKey("id", .integer)
                t.column("name", .text)
            }
            try db.create(table: "book1") { t in
                t.primaryKey("id", .integer)
                t.column("authorId", .integer).references("author")
                t.column("parentId", .integer).references("book1")
                t.column("title", .text)
            }
            try db.execute(sql: """
                INSERT INTO author (id, name) VALUES (1, 'Herman Melville');
                INSERT INTO book1 (id, authorId, parentId, title) VALUES (1, 1, NULL, 'Moby-Dick');
                INSERT INTO book1 (id, authorId, parentId, title) VALUES (2, 1, 1, 'Pierre');
                """)
        }
    }

    // Book1.include(Author.aliased("book1"))
    func testUserAliasSpelledLikeDigitSuffixedTableName() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            let authorAlias = TableAlias(name: "book1")
            let request = Book1
                .including(required: Book1.author.aliased(authorAlias))
                .order(Column("id"))
            try assertEqualSQL(db, request, """
                SELECT "book2".*, "book1".* \
                FROM "book1" "book2" \
                JOIN "author" "book1" ON "book1"."id" = "book2"."authorId" \
                ORDER BY "book2"."id"
                """)

            let rows = try Row.fetchAll(db, request)
            XCTAssertEqual(rows.count, 2)
            XCTAssertEqual(rows[0]["title"], "Moby-Dick")
            XCTAssertEqual(rows[0].scopes["author"]!, ["id": 1, "name": "Herman Melville"])
            XCTAssertEqual(rows[1]["title"], "Pierre")
            XCTAssertEqual(rows[1].scopes["author"]!, ["id": 1, "name": "Herman Melville"])
        }
    }

    // Book1.include(Author.aliased("BOOK1"))
    func testUserAliasSpelledLikeDigitSuffixedTableNameIgnoringCase() throws {
        // SQLite identifiers are case-insensitive: "BOOK1" and "book1"
        // name the same table in a FROM clause.
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            let authorAlias = TableAlias(name: "BOOK1")
            let request = Book1
                .including(required: Book1.author.aliased(authorAlias))
                .order(Column("id"))
            try assertEqualSQL(db, request, """
                SELECT "book2".*, "BOOK1".* \
                FROM "book1" "book2" \
                JOIN "author" "BOOK1" ON "BOOK1"."id" = "book2"."authorId" \
                ORDER BY "book2"."id"
                """)

            let rows = try Row.fetchAll(db, request)
            XCTAssertEqual(rows.count, 2)
            XCTAssertEqual(rows[0].scopes["author"]!, ["id": 1, "name": "Herman Melville"])
        }
    }

    // Book1.aliased("book1").include(Book1.parent)
    func testSelfJoinWithUserAliasSpelledLikeDigitSuffixedTableName() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            let bookAlias = TableAlias(name: "book1")
            let request = Book1
                .aliased(bookAlias)
                .including(required: Book1.parent)
            try assertEqualSQL(db, request, """
                SELECT "book1".*, "book2".* \
                FROM "book1" \
                JOIN "book1" "book2" ON "book2"."id" = "book1"."parentId"
                """)

            let rows = try Row.fetchAll(db, request)
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows[0]["title"], "Pierre")
            XCTAssertEqual(rows[0].scopes["parent"]!["title"], "Moby-Dick")
        }
    }

    // Control: without a user alias, a self join on a digit-suffixed table
    // is already disambiguated.
    func testSelfJoinOnDigitSuffixedTableName() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            let request = Book1.including(required: Book1.parent)
            try assertEqualSQL(db, request, """
                SELECT "book1".*, "book2".* \
                FROM "book1" \
                JOIN "book1" "book2" ON "book2"."id" = "book1"."parentId"
                """)

            let rows = try Row.fetchAll(db, request)
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows[0]["title"], "Pierre")
            XCTAssertEqual(rows[0].scopes["parent"]!["title"], "Moby-Dick")
        }
    }
}

// Edition1 -> Writer
// Edition1 -> Country
//
// No two tables share a column name, so SQLite accepts a FROM clause that
// names two tables "edition1", and expands "edition1".* to the columns of
// both. The query then succeeds, and the row scopes are misaligned.
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

class AssociationTableAliasDigitSuffixDisjointColumnsTests: GRDBTestCase {
    
    override func setup(_ dbWriter: some DatabaseWriter) throws {
        try dbWriter.write { db in
            try db.create(table: "writer") { t in
                t.primaryKey("writerPk", .integer)
                t.column("name", .text)
            }
            try db.create(table: "country") { t in
                t.primaryKey("code", .text)
                t.column("countryName", .text)
            }
            try db.create(table: "edition1") { t in
                t.primaryKey("editionPk", .integer)
                t.column("writerId", .integer).references("writer")
                t.column("countryCode", .text).references("country")
                t.column("title", .text)
            }
            try db.execute(sql: """
                INSERT INTO writer (writerPk, name) VALUES (1, 'Herman Melville');
                INSERT INTO country (code, countryName) VALUES ('US', 'United States');
                INSERT INTO edition1 (editionPk, writerId, countryCode, title) VALUES (10, 1, 'US', 'Moby-Dick');
                """)
        }
    }
    
    // Edition1.include(Country).include(Writer.aliased("edition1"))
    func testUserAliasSpelledLikeDigitSuffixedTableNameDoesNotMisalignScopes() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            let writerAlias = TableAlias(name: "edition1")
            let request = Edition1
                .including(required: Edition1.country)
                .including(required: Edition1.writer.aliased(writerAlias))
            try assertEqualSQL(db, request, """
                SELECT "edition2".*, "country".*, "edition1".* \
                FROM "edition1" "edition2" \
                JOIN "country" ON "country"."code" = "edition2"."countryCode" \
                JOIN "writer" "edition1" ON "edition1"."writerPk" = "edition2"."writerId"
                """)
            
            let row = try XCTUnwrap(Row.fetchOne(db, request))
            XCTAssertEqual(row.unscoped, ["editionPk": 10, "writerId": 1, "countryCode": "US", "title": "Moby-Dick"])
            XCTAssertEqual(row.scopes["country"]!, ["code": "US", "countryName": "United States"])
            XCTAssertEqual(row.scopes["writer"]!, ["writerPk": 1, "name": "Herman Melville"])
        }
    }
}
