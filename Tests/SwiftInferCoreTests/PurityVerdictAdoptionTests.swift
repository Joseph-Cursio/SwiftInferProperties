import SwiftEffectInference
@testable import SwiftInferCore
import Testing

/// The three-state purity verdict, and the two-state answer it must keep
/// agreeing with.
///
/// Item 2's last piece. `SoundPurity.isPure` collapsed three states to two and
/// the third — `.pureButPartial` — was unrecoverable downstream, so nothing
/// could tell *"reads the clock"* from *"raises its own error"*. Both answered
/// `false`.
@Suite("SoundPurity — the verdict and its Bool collapse")
struct PurityVerdictAdoptionTests {

    private func summary(_ source: String) throws -> FunctionSummary {
        let summaries = FunctionScanner.scanCorpus(source: source, file: "V.swift").summaries
        return try #require(summaries.first)
    }

    /// The invariant that lets `isInferredPure` stay the field every current
    /// consumer reads. If these ever disagree, the advisory silently changes
    /// audience — which is the one thing this adoption promised not to do.
    @Test(
        "isInferredPure is exactly `purityVerdict == .pure`",
        arguments: [
            ("plainly pure", "func f(_ x: Int) -> Int { x * 2 }"),
            ("throws its own error", """
            func f(_ x: Int) throws -> Int {
                guard x > 0 else { throw E.bad }
                return x
            }
            """),
            ("propagates a callee's throw", """
            func f(_ path: String) throws -> String {
                try String(contentsOfFile: path, encoding: .utf8)
            }
            """),
            ("reads the clock", "func f() -> Date { Date() }"),
            ("async", "func f(_ x: Int) async -> Int { x }"),
            ("partial — force unwrap", "func f(_ x: Int?) -> Int { x! }"),
            // The computed-property route. It is here because for a month this
            // parameterisation had six cases and every one of them was a `func`,
            // while the ONE shape that broke the invariant was the one it never
            // entered: `makeSummary(fromComputedProperty:)` asserted
            // `isInferredPure: true` and passed no verdict, so all 180 computed
            // properties under `Sources/` read as pure AND refuted at once. A
            // guard that cannot reach the failing shape is green for the same
            // reason a guard that holds is — which is the standing "verify a
            // suppression by removing it" lesson, arriving through a different
            // door. Both polarities, so an oracle wired to a constant fails one
            // of them whichever constant it is wired to.
            ("computed property — pure", "struct S { var doubled: Int { 2 * 2 } }"),
            ("computed property — reads the clock", "struct S { var now: Date { Date() } }")
        ]
    )
    func boolIsTheCollapse(label: String, source: String) throws {
        let value = try summary(source)
        #expect(
            value.isInferredPure == (value.purityVerdict == .pure),
            "collapse broke on: \(label)"
        )
    }

    /// The state the collapse used to destroy, asserted absolutely — an
    /// agreement test alone would pass if BOTH sides called this `.refuted`.
    @Test("A function raising only its own errors is .pureButPartial, not .refuted")
    func ownErrorsAreDistinguished() throws {
        let value = try summary("""
        func parse(_ text: String) throws -> Int {
            guard let value = Int(text) else { throw E.bad }
            return value
        }
        """)
        #expect(value.purityVerdict == .pureButPartial)
        // …and the advisory audience is unchanged: it is still not `pure`, so
        // it is still not advised `/// @lint.effect pure`.
        #expect(value.isInferredPure == false)
    }

    /// The soundness line this project draws, and the reason admitting `throws`
    /// is not the relaxation it resembles.
    ///
    /// CLAUDE.md: *"Purity gates must not relax to reach a target. Removing the
    /// `throws` gate once re-admitted `Process`/`Pipe`/`FileHandle`/SQLite at
    /// once, with a subprocess-spawning function judged pure. A propagated `try`
    /// into a dependency is out of reach by design."* `.pureButPartial` requires
    /// **no `try` at all**, so that gate still holds — this pins it.
    @Test("A propagated `try` still refutes — the gate is not relaxed")
    func propagatedTryStillRefutes() throws {
        let value = try summary("""
        func load(_ path: String) throws -> String {
            try String(contentsOfFile: path, encoding: .utf8)
        }
        """)
        #expect(value.purityVerdict == .refuted)
        #expect(value.isInferredPure == false)
    }

    /// **The witness for the shape the unchecked claim admitted.** An agreement
    /// test cannot catch this on its own: before the fix, `isInferredPure` was
    /// `true` and `purityVerdict` was `.refuted` for this getter, so the two
    /// disagreed — but they disagreed for *every* computed property, pure ones
    /// included, so nothing distinguished a clock reader from a doubling.
    ///
    /// `var now: Date { Date() }` is the case `PurityInferrer.isPure(_
    /// accessor:)` documents as the reason a caller checking only *names* is not
    /// enough — it reads no mutable state at all, and only the marker scan
    /// refutes it. It would have been advised `/// @lint.effect pure`.
    ///
    /// Measured before the fix: 0 of the 180 computed properties in this repo
    /// were refuted by either oracle, so the constant had been accidentally
    /// correct and no wrong advisory ever shipped. That is why this test names a
    /// synthetic getter rather than a real one — the failing case is a shape the
    /// corpus does not currently contain, and waiting for it to appear was the
    /// alternative.
    @Test("a getter that reads the clock is not advised pure")
    func clockReadingGetterIsRefuted() throws {
        let value = try summary("struct S { var now: Date { Date() } }")
        #expect(value.isComputedProperty)
        #expect(value.purityVerdict == .refuted)
        #expect(value.isInferredPure == false)
    }

    /// The other polarity, so the fix is not just "refuse everything": an
    /// ordinary derived value keeps the verdict — and the advisory — it should.
    @Test("an ordinary derived value is still pure")
    func plainGetterStaysPure() throws {
        let value = try summary("struct S { var doubled: Int { count * 2 } }")
        #expect(value.isComputedProperty)
        #expect(value.purityVerdict == .pure)
        #expect(value.isInferredPure)
    }

    /// A summary nobody computed a verdict for must not read as pure.
    @Test("The default is .refuted, not .pure")
    func defaultIsRefuted() {
        let value = FunctionSummary(
            name: "f",
            parameters: [],
            returnTypeText: "Int",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "V.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        #expect(value.purityVerdict == .refuted)
        #expect(value.isInferredPure == false)
    }
}
