import Foundation
@testable import SwiftInferCore
import SwiftParser
import SwiftSyntax
import Testing

/// A property with `willSet` / `didSet` observers is STORED, and Swift puts it in the
/// synthesized memberwise initializer.
///
/// `storedMembers` skipped every binding with an accessor block, so an observed property
/// vanished from the shape and the derived generator called an initializer with one argument
/// missing. Measured on `Euclid.PathPoint` — `public var position: Vector { didSet { … } }`
/// beside three plain properties — worth 40 of the kit scaffold's compile errors.
@Suite("An observed property is stored, not computed")
struct ObservedPropertyIsStoredTests {

    private func members(_ source: String) -> [String] {
        let file = Parser.parse(source: source)
        for statement in file.statements {
            guard let structDecl = statement.item.as(StructDeclSyntax.self) else { continue }
            return MemberBlockInspector.storedMembers(in: structDecl.memberBlock).map(\.name)
        }
        return []
    }

    @Test("a didSet property is stored")
    func didSetIsStored() {
        #expect(members("""
        struct S {
            var position: Int { didSet { print(position) } }
            var other: Int
        }
        """) == ["position", "other"])
    }

    @Test("a willSet property is stored")
    func willSetIsStored() {
        #expect(members("""
        struct S {
            var a: Int { willSet { print(newValue) } }
        }
        """) == ["a"])
    }

    @Test("both observers together are stored")
    func bothObserversStored() {
        #expect(members("""
        struct S {
            var a: Int { willSet { } didSet { } }
        }
        """) == ["a"])
    }

    // MARK: - The negative arms: everything else stays computed

    @Test("an implicit-getter computed property is NOT stored")
    func implicitGetterIsComputed() {
        #expect(members("""
        struct S {
            var a: Int { 42 }
        }
        """).isEmpty)
    }

    @Test("an explicit get/set computed property is NOT stored")
    func getSetIsComputed() {
        #expect(members("""
        struct S {
            var a: Int { get { 1 } set { } }
        }
        """).isEmpty)
    }

    @Test("a get-only property is NOT stored")
    func getOnlyIsComputed() {
        #expect(members("""
        struct S {
            var a: Int { get { 1 } }
        }
        """).isEmpty)
    }

    /// `_modify` is the accessor that produced the previous misclassification in this family
    /// (`modify-accessor-misclassification.md`), so it is pinned here from the other side.
    @Test("a _modify coroutine is NOT stored")
    func modifyCoroutineIsComputed() {
        #expect(members("""
        struct S {
            var a: Int { get { 1 } _modify { } }
        }
        """).isEmpty)
    }

    @Test("a plain stored property is unaffected")
    func plainStoredUnaffected() {
        #expect(members("""
        struct S {
            var a: Int
            let b: String
        }
        """) == ["a", "b"])
    }
}
