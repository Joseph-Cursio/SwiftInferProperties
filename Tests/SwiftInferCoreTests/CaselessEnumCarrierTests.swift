import Foundation
@testable import SwiftInferCore
import Testing

/// A caseless enum is a namespace, not a value — so `unsupported-carrier` is the wrong
/// answer for it. That reads as a generator gap and sends a reader to write
/// `static func gen() -> Generator<Namespace, _>`, a function that cannot return.
///
/// Swift forbids adding cases to an enum in an extension, so "enum with no cases" is a
/// provable statement about inhabitants rather than a guess about what the scan missed.
@Suite("Caseless enum carriers — a namespace has no values")
struct CaselessEnumCarrierTests {

    private func shape(
        _ name: String,
        kind: IndexedTypeShape.Kind,
        cases: [IndexedTypeShape.EnumCase] = [],
        members: [IndexedTypeShape.StoredMember] = []
    ) -> IndexedTypeShape {
        IndexedTypeShape(
            name: name,
            kind: kind,
            inheritedTypes: [],
            hasUserGen: false,
            storedMembers: members,
            hasUserInit: false,
            initializers: [],
            enumCases: cases
        )
    }

    /// The measured case: `SamplingSeed` is `enum SamplingSeed { struct Value …; static func … }`.
    @Test("a caseless enum is blocked, and the reason names it")
    func caselessEnumIsBlocked() {
        let reason = StructuralBlocker.caselessEnumCarrier(shape("SamplingSeed", kind: .enum))
        #expect(reason?.contains("SamplingSeed") == true)
        #expect(reason?.contains("caseless enum") == true)
    }

    /// **The arm that must not fire.** An enum WITH cases is an ordinary carrier the
    /// strategist derives via the Tier 4 `enumCases` path.
    @Test("an enum with cases is not blocked")
    func enumWithCasesIsNotBlocked() {
        let withCases = shape("Tier", kind: .enum, cases: [.init(name: "strong"), .init(name: "likely")])
        #expect(StructuralBlocker.caselessEnumCarrier(withCases) == nil)
    }

    /// A struct with no stored members is still a value — `struct Empty {}` has exactly one
    /// inhabitant. Only enums have the no-inhabitants property.
    @Test(
        "an empty struct, class or actor is NOT blocked — emptiness is not caselessness",
        arguments: [IndexedTypeShape.Kind.struct, .class, .actor]
    )
    func emptyNonEnumsAreNotBlocked(kind: IndexedTypeShape.Kind) {
        #expect(StructuralBlocker.caselessEnumCarrier(shape("Empty", kind: kind)) == nil)
    }

    /// No shape at all means no claim — an external carrier is a different question.
    @Test("a missing shape is not blocked")
    func missingShapeIsNotBlocked() {
        #expect(StructuralBlocker.caselessEnumCarrier(nil) == nil)
    }
}
