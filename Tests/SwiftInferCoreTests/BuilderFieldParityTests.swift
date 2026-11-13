import SwiftEffectInference
import Testing

@testable import SwiftInferCore

/// **Every copy-with builder on `FunctionSummary` must carry every field it does not
/// deliberately change.**
///
/// `FunctionSummary.init` has 23 parameters and 14 of them are **defaulted**, so a
/// builder that omits one compiles, runs, and silently substitutes the default.
/// `FunctionSummary+Builders.swift`'s own header names this failure — *"a builder that
/// forgets a field compiles silently"* — and it had happened, in the file that names it.
///
/// Found 2026-08-18 while adding a field, which is the only way a silent drop ever
/// surfaces: nothing fails, the value is simply the default afterwards.
///
/// ## Why `Mirror` rather than an enumerated list
///
/// A hand-written list of fields to check is the same artefact as the builder, with the
/// same failure mode — the next field is forgotten in both places, and the test then
/// certifies the bug. Reflecting over the value compares whatever fields exist *today*,
/// so a field added next year is covered on the day it lands without anyone remembering
/// this file.
///
/// The subject is deliberately **not** a realistic summary: `isComputedProperty` and
/// `isInitializer` are both true, which no scan would produce. This asserts field
/// *transport*, not semantics, and every field must differ from its default or the
/// comparison passes vacuously for that field.
@Suite("FunctionSummary builders — every field survives a copy")
struct BuilderFieldParityTests {

    /// Every field non-default, so no comparison below can pass by coincidence.
    static let populated = FunctionSummary(
        name: "subject",
        parameters: [],
        returnTypeText: "Int",
        isThrows: true,
        isAsync: true,
        isMutating: true,
        isStatic: true,
        location: SourceLocation(file: "F.swift", line: 7, column: 3),
        containingTypeName: "Inner",
        bodySignals: .empty,
        qualifiedContainingTypeName: "Outer.Inner",
        discoverableGroup: "group",
        invariantKeypath: "\\.value",
        isInferredPure: true,
        isClockDeterministic: true,
        declaresUnknownEffect: true,
        isComputedProperty: true,
        isInitializer: true,
        docComment: "doc",
        declaredEffect: .pure,
        inferredEffect: nil,
        purityVerdict: .pureButPartial,
        bodyFingerprint: "FEEDFACE",
        globalActor: "MainActor",
        declaresNonisolated: true,
        calledFreeFunctionNames: ["helper"],
        genericParameters: [TypeDecl.GenericParameter(name: "T", constraint: "Hashable")]
    )

    /// The one field `withInferredEffect` is allowed to change.
    static let intentionallyChanged: Set<String> = ["inferredEffect"]

    @Test("withInferredEffect changes only the inferred effect")
    func withInferredEffectCarriesEveryOtherField() {
        let copied = Self.populated.withInferredEffect(.pure)

        let before = Self.fields(of: Self.populated)
        let after = Self.fields(of: copied)

        #expect(before.keys.sorted() == after.keys.sorted(), "the copy has a different field set")

        for (label, value) in before where !Self.intentionallyChanged.contains(label) {
            #expect(after[label] == value, """
            `withInferredEffect` dropped or altered `\(label)`: \(value) → \
            \(after[label] ?? "<absent>"). Every parameter of `FunctionSummary.init` after \
            `bodySignals` is defaulted, so omitting one from a builder compiles and \
            substitutes the default — pass it through explicitly.
            """)
        }

        #expect(copied.inferredEffect == .pure, "the builder did not apply the effect it was given")
    }

    /// Found 2026-11-13, while measuring a wider join (`docs/measurements/purity-join-member-calls.md`): both
    /// builders dropped `globalActor`, `declaresNonisolated` and `genericParameters`, so a summary the join took
    /// back lost its isolation and its generics. The test above could not see it: it covered `withInferredEffect`
    /// only, and its subject left those three fields at their defaults.
    @Test("withPurityRetracted changes only the verdict and its collapse")
    func withPurityRetractedCarriesEveryOtherField() {
        let copied = Self.populated.withPurityRetracted()
        let before = Self.fields(of: Self.populated)
        let after = Self.fields(of: copied)
        #expect(before.keys.sorted() == after.keys.sorted(), "the copy has a different field set")
        for (label, value) in before where !["purityVerdict", "isInferredPure"].contains(label) {
            let copiedValue = after[label] ?? "<absent>"
            #expect(after[label] == value, "`withPurityRetracted` dropped `\(label)`: \(value) → \(copiedValue)")
        }
        #expect(copied.purityVerdict == .refuted)
        #expect(!copied.isInferredPure)
    }

    /// **The control.** If reflection stopped reaching the stored properties — a
    /// `Mirror` over an empty-looking value, a type that stops being a struct — every
    /// loop above would iterate nothing and pass. That is this repo's confident zero, so
    /// the denominator is asserted.
    ///
    /// The floor is far below the 23 fields present on 2026-08-18: it is a smoke alarm
    /// for reflection breaking, not a count to maintain.
    @Test("the reflection reaches a plausible number of fields")
    func theReflectionIsNotBlind() {
        let fields = Self.fields(of: Self.populated)
        #expect(fields.count >= 15, "reflection saw only \(fields.count) fields")
        #expect(fields["declaresUnknownEffect"] != nil, "the field that was dropped is not being read")
        #expect(fields["bodyFingerprint"] != nil)
        #expect(fields["qualifiedContainingTypeName"] != nil)
        #expect(fields["globalActor"] == "Optional(\"MainActor\")", "a field the builders once dropped is populated")
    }

    /// Stored properties as `label → rendered value`. Rendering rather than comparing
    /// `Any` because `Mirror` erases the type and most fields here are not `Equatable`
    /// through the erasure; a description is enough to catch a value reverting to its
    /// default, which is the failure being guarded.
    static func fields(of summary: FunctionSummary) -> [String: String] {
        var rendered: [String: String] = [:]
        for child in Mirror(reflecting: summary).children {
            guard let label = child.label else { continue }
            rendered[label] = String(describing: child.value)
        }
        return rendered
    }
}
