# A generated table alias can take the name of a user alias when a table name ends with a digit

I found this while hand-checking functions that hand out unique names.

### What did you do?

I joined a table named `book1` and gave another alias in the same request the name `book1`. This is `AssociationTableAliasTestsSQLTests.testUserInducedNameConflict` with a table named `book1` instead of `a`:

```swift
// Book1: table "book1", belongsTo(Author.self, using: ForeignKey(["authorId"]))
let request = Book1.including(required: Book1.author.aliased(TableAlias(name: "book1")))
let rows = try Row.fetchAll(db, request)
```

The full test, with schema, rows and record types, is under *Demo Project*.

### What did you expect to happen?

GRDB renames the unnamed alias, as it does when the table is named `a`:

```sql
SELECT "book2".*, "book1".* FROM "book1" "book2" JOIN "author" "book1" ON "book1"."id" = "book2"."authorId"
```

### What happened instead?

The unnamed alias on `book1` is named `book1` too, and the statement fails to prepare:

```
SQLite error 1: ambiguous column name: main.book1.id - while executing `SELECT "book1".*, "book1".* FROM "book1" JOIN "author" "book1" ON "book1"."id" = "book1"."authorId"`
```

The same happens with a user alias `BOOK1` (SQLite ignores ASCII case in identifiers), and with the self-join `Book1.aliased(TableAlias(name: "book1")).including(required: Book1.parent)`, which gives `... FROM "book1" JOIN "book1" ON "book1"."id" = "book1"."parentId"`.

Prepare fails when the two FROM items that end up with the same name share a column name (`id` above). **If they share none, the statement runs, and the rows it returns can hold another table's columns in their scopes.** SQLite expands `"edition1".*` to the columns of both items, so the row adapters can slice the wrong columns. With `writer(writerPk, name)`, `country(code, countryName)` and `edition1(editionPk, writerId, countryCode, title)`:

```swift
let request = Edition1
    .including(required: Edition1.country)
    .including(required: Edition1.writer.aliased(TableAlias(name: "edition1")))
// SELECT "edition1".*, "country".*, "edition1".* FROM "edition1"
// JOIN "country" ON "country"."code" = "edition1"."countryCode"
// JOIN "writer" "edition1" ON "edition1"."writerPk" = "edition1"."writerId"
let row = try Row.fetchOne(db, request)!
row.scopes["country"] // [writerPk:1 name:"Herman Melville"]
row.scopes["writer"]  // [code:"US" countryName:"United States"]
```

The fetched row holds the columns of edition1, writer, country, edition1, writer, 14 in all. Only the two `edition1` items matter: with the sqlite3 CLI (3.53.2, and the system's 3.54.0), the statement still runs after adding a `title` column to `country`, and fails to prepare after adding one to `writer` (`ambiguous column name: main.edition1.title`).

### Cause

In `[TableAliasBase].resolvedNames` (`GRDB/QueryInterface/SQLGeneration/SQLGenerationContext.swift`), aliases are grouped by lowercased `identityName`. A group of one has its name inserted into `uniqueLowercaseNames`. A group of several does not. Its unnamed members are renamed `digitlessRadical + index`, and each candidate is checked only against `uniqueLowercaseNames`. Its user-named member keeps its name, which is never inserted. A collision takes three things:

1. A user alias spelled, in any case, like the table name of an unnamed alias in the same request, so that the two share a group.
2. A table name whose trailing digits, taken together, are a positive integer written without leading zeros, like `book1` or `book12`. Candidates are `book1`, `book2`, …, so `book0`, `book01` and `book010` never collide.
3. A counter for that name's radical (`book`) that reaches the number. It can be the group's own counter, or the counter of another ambiguous group with the same radical. Adding two unnamed joins on a table `book` to the first example can give `FROM "book1" "book3" JOIN "book" "book1" ... JOIN "author" "book1"`.

With a table named `a`, the candidates `a1`, `a2`, … can never be spelled `a`, which is why `testUserInducedNameConflict` passes.

### Proposed fix

Reserve the user name of an ambiguous group before any name is generated:

```diff
--- a/GRDB/QueryInterface/SQLGeneration/SQLGenerationContext.swift
+++ b/GRDB/QueryInterface/SQLGeneration/SQLGenerationContext.swift
@@ -271,6 +271,11 @@
                     group.countElements(where: \.hasUserName) < 2,
                     "ambiguous alias: \(group[0].identityName)")
                 ambiguousGroups.append(group)
+                if group.contains(where: \.hasUserName) {
+                    // The user name is used verbatim: reserve it, so that
+                    // no name generated below collides with it.
+                    uniqueLowercaseNames.insert(lowercaseName)
+                }
             } else {
                 uniqueLowercaseNames.insert(lowercaseName)
             }
```

Generation starts after the grouping loop, so user names from every group are reserved first. The group's unnamed members are renamed anyway, and the precondition allows at most one user name per group.

What I checked:

- Tests in GRDB's style, `Tests/GRDBTests/QueryInterface/Association/AssociationTableAliasDigitSuffixTests.swift`, with five cases: the three failures above, the disjoint-columns case, and a control (the self-join with no user alias). Without the fix 4 fail; with it all 5 pass. I can open a PR against `development` with the fix and these tests.
- The full `swift test`, with the fix, these five tests and the two under *Demo Project*, ran 2,884 tests: 31 skipped, 1 failure, `Issue1838Tests.test_interrupted_commit` (`("1") is not equal to ("0")`). It fails identically without the fix or the new tests (2,877 tests, same assertion). My guess, not checked, is that it depends on this machine's system SQLite.
- A copy of the function, with and without the fix, run on about 3 million generated lists of ASCII aliases, in every group order. With the fix, no two aliases got the same name (ignoring ASCII case). The output changed only where two had without it.

Limits:

- The fix also changes the SQL of one kind of request where nothing collides. Swift's `lowercased()` equates names that SQLite does not, since SQLite folds only ASCII case. A user alias `Ä1` on `author` with table `ä1` gave `FROM "ä1" JOIN "author" "Ä1"` before and `FROM "ä1" "ä2" JOIN "author" "Ä1"` after. Both run and return the same rows. This is the grouping GRDB already does for names without a digit: a user alias `Ä` with a table `ä` renames the table's alias to `ä1`, with or without the fix.
- The fix works within one `SQLGenerationContext`. A subquery resolves its own names without regard to the outer query's, and the fix does not change that. A correlated `exists()` on `Book1.including(required: Book1.parent)`, filtered on `outer[Column("authorId")]`, names its own tables `"book1"` and `"book2"`. With the outer alias named `book2`, the filter became `"book1"."authorId" = "book2"."authorId"` inside the subquery, and the request returned a row it should not. The same happens with a table named `book` (no digit) and an outer alias named `book1` or `book2`, and, with the table `book1`, with an unnamed outer alias (`TableAlias()`), whose filter became `"book1"."authorId" = "book1"."authorId"`. With the outer alias named `outer`, or an unnamed one on a table `book`, the result was right. This looks like a separate issue; I have not checked whether it is known.

### Environment

**GRDB flavor(s):** GRDB (system SQLite)
**SQLite version:** 3.54.0 (system)
**GRDB version:** `master` at 0d8cf958b4b66a0473ec6e6986eb9da462171da9 (v7.11.1 + 2 commits). `SQLGenerationContext.swift` is identical on `development` (6f64c72209c6b4d3e13074c104149e0d54ef4d30), and the patch applies there.
**Installation method:** SPM (`swift test`)
**Xcode version:** 27.1
**Swift version:** 6.4 (swiftlang-6.4.0.34.1)
**Platform(s) running GRDB:** macOS
**macOS version running Xcode:** 27.2

### Demo Project

Add this file to `Tests/GRDBTests/` and run `swift test --filter DigitSuffixedTableAliasTests`. Without the fix both tests fail with the errors and scopes above; with it both pass.

<details>
<summary>DigitSuffixedTableAliasTests.swift</summary>

```swift
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
```

</details>
