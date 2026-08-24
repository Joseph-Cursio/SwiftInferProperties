import Foundation
import PropertyLawCore
import Testing

@testable import SwiftInferCore

/// **A shape whose members are module-qualified must still derive a generator.**
///
/// This pins a *dependency's* behaviour, deliberately, because this package's output depends on
/// it and nothing here would otherwise notice it regressing.
///
/// The rule itself lives in SwiftPropertyLaws (`RawType`, `CompositeMemberParser`) and is tested
/// there. It was briefly implemented on this side as well — `StdlibTypeSpelling`, applied at
/// `toKitShape()` — and that copy is **deleted rather than kept as belt-and-braces**. Two
/// implementations of one rule drift, and PRD §11 is explicit that generator inference delegates
/// to the kit rather than being reimplemented here. What is kept is this: an assertion about the
/// behaviour, not a second copy of the mechanism.
///
/// **Why it matters.** `RawType(typeName:)` matched exactly, so `Swift.String` resolved to no
/// generator, its enclosing type became underivable, and the row reported `unsupported-carrier` —
/// a label claiming the carrier is exotic, about a `String`. Hand-written Swift almost never
/// writes that spelling; generated code writes nothing else. Measured on `MacPaw/OpenAI`
/// @ `a532be8`: **0 → 15 of 55 rows execute**, `codable-round-trip` member trees **0 → 16 of 28**.
/// See `docs/measurements/module-qualified-leaf-spelling.md`.
///
/// **Guarded by the pin, not by this file.** The floor lives in
/// `VerifierWorkdir.swiftPropertyLawsRequirement` (4.2.0) and `Package.swift`, which
/// `VerifierWorkdirKitPinTests` keeps equal. This suite fails if the pin ever resolves to a kit
/// without the rule — which is the failure a version floor cannot state on its own.
@Suite("Qualified spellings derive through the kit")
struct QualifiedSpellingDerivationTests {

    private static func shape(memberType: String) -> IndexedTypeShape {
        IndexedTypeShape(
            name: "Carrier",
            kind: .struct,
            inheritedTypes: ["Codable", "Hashable"],
            hasUserGen: false,
            storedMembers: [.init(name: "value", typeName: memberType)],
            hasUserInit: true,
            initializers: [
                .init(
                    parameters: [.init(label: "value", typeName: memberType)],
                    isFailable: false,
                    isThrowing: false
                )
            ],
            enumCases: []
        )
    }

    private static func derives(_ memberType: String) -> Bool {
        if case .todo = DerivationStrategist.strategy(for: shape(memberType: memberType).toKitShape()) {
            return false
        }
        return true
    }

    /// The exact shape that motivated the fix: a generated struct over a dictionary of
    /// qualified primitives (`Components.Schemas.Metadata`).
    @Test("a member typed with a qualified stdlib leaf derives")
    func qualifiedLeafDerives() {
        #expect(Self.derives("[String: Swift.String]"))
        #expect(Self.derives("Swift.String"))
        #expect(Self.derives("Swift.Int"))
        #expect(Self.derives("Swift.String?"))
        #expect(Self.derives("[Swift.Int]"))
    }

    /// The control: the bare spelling was never broken, and must not become so.
    @Test("the bare spelling still derives")
    func bareSpellingStillDerives() {
        #expect(Self.derives("String"))
        #expect(Self.derives("[String: String]"))
    }

    /// The negative that matters. A qualified CUSTOM type has no generator and must still be
    /// declined — a fix that made everything derive would pass the arms above and be far worse
    /// than the defect, since it would emit a stub naming a generator that does not exist.
    @Test("a qualified custom type is still declined")
    func qualifiedCustomTypeIsDeclined() {
        #expect(!Self.derives("Components.Schemas.Response"))
        #expect(!Self.derives("OpenAPIRuntime.OpenAPIObjectContainer"))
        #expect(!Self.derives("MyModule.String"))
    }
}
