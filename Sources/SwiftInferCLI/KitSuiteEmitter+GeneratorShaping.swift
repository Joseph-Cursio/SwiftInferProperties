import Foundation

// Split out of `KitSuiteEmitter.swift` 2026-08-08, when the §3a bisect record pushed that file
// past the 400-line cap — the `Signal+Kind.swift` precedent, applied to a file that already had
// a `+Assemble` split. The rationale travels with the decision rather than being trimmed: every
// comment here records a measurement, and two of them (the ±10_000 bound and the zip cap) are
// the only surviving record of why a constant has the value it does.
extension KitSuiteEmitter {

    /// **Bound the derived numeric leaves, because an aggregating carrier traps.**
    ///
    /// `GeneratorExpressionEmitter` emits `Gen<Int>.int()`, which draws the FULL `Int` range.
    /// That is correct for a law about one value and fatal for a carrier that sums its
    /// members: `Score.init(signals:)` does `.reduce(0, +)` over up to eight weights, so a
    /// full-range draw overflows and the process dies with **SIGTRAP** — measured, as an
    /// `exited with unexpected signal code 5` that killed the whole run rather than failing
    /// one test.
    ///
    /// ±10_000 is not a new invention: it is the bound the verify path already draws from,
    /// for the same reason, recorded in the multiplicative-homomorphism warning
    /// (*"MIND OVERFLOW … the property must be checked over a BOUNDED domain (the verifier
    /// draws from ±10_000)"*). Matching it keeps one answer to the question in the repo.
    ///
    /// **The trade is real and worth naming**: a bounded draw cannot find an overflow bug at
    /// the numeric extremes. That is the same call the verifier already made — a law about
    /// sign or measure logic is reachable in ±10_000; one about `Int.max` is not.
    static func boundingNumerics(_ expression: String) -> String {
        expression
            .replacingOccurrences(of: "Gen<Int>.int()", with: "Gen<Int>.int(in: -10_000...10_000)")
            .replacingOccurrences(of: "Gen<UInt64>.uint64()", with: "Gen<UInt64>.uint64(in: 0...10_000)")
    }

    /// **Nesting depth at which the emitted generator stops being worth it.**
    ///
    /// Passing the whole-module resolver took derivation from 51% to 78% of carriers, but
    /// composed generators nest: a type whose members are themselves user types emits
    /// `zip(zip(zip(...)))`, and Swift's type checker is superlinear in that nesting. Measured
    /// on `SwiftInferCore`: expressions reached **8 nested `zip(`s and 1,935 characters**, and
    /// the build failed with *"the compiler is unable to type-check this expression in
    /// reasonable time"*.
    ///
    /// This repo has been bitten by exactly that before — a 12-arm `+` chain that compiled
    /// locally and tripped CI's type-check timeout, silently failing every push for eight
    /// commits (`bbd634c`). A generated file that compiles on the author's machine and not on
    /// the reviewer's is worse than one that admits the limit up front.
    ///
    /// ## BISECTED 2026-08-08 (plan §3a) — 4 → 13, and **nothing failed anywhere**
    ///
    /// The plan asked for the bisect because 4 was empirical, not derived: 8 failed, 4
    /// compiled, and nothing in between was tried, so derivation rate was being measured
    /// against an arbitrary constant. The bisect was run two ways and the constant's premise
    /// did not survive either.
    ///
    /// - **Synthetic ladders**, built so the boundary is found by construction rather than by
    ///   whatever a corpus happens to contain. A wide-and-deep ladder (each rung wraps the
    ///   previous and adds four mixed-type members) reached **13 nested `zip(`s and 2,412
    ///   characters** and compiled, with **no expression over 200 ms** under
    ///   `-warn-long-expression-type-checking`. A separate flat ladder confirmed a
    ///   **15-argument variadic `zip`** is fine.
    /// - **The real corpus.** Emitted for `SwiftInferCore` with the cap lifted: 0 compile
    ///   errors, **191/191 tests green**, deepest expression 5.
    ///
    /// **Measured cost of the old value: 2 emitted suites out of 241**, across seven corpora
    /// (this repo, five swift-collections modules, swift-argument-parser) — both in
    /// `SwiftInferCore`, both at nesting 5, and both verified to compile and pass. That is the
    /// same near-no-op shape `ProtocolCoverageAudit` measured for the coverage veto.
    ///
    /// **The value is now the deepest verified-compiling nesting, and it is a backstop rather
    /// than a measured cliff** — no nesting was found that fails, so there is no cliff to
    /// place it at. It still bounds unbounded composition, which is what a generated file
    /// owes a reviewer.
    ///
    /// ## The pathology is real and this guard cannot see it
    ///
    /// One expression in the same run took **26,209 ms to type-check** — two orders of
    /// magnitude past anything the ladders produced. Its `zip(` count is **1**. It is
    /// `StateSurface`, an enum, emitted as `Gen.oneOf(…)` with `.eraseToAny()` over
    /// heterogeneous arms. No value of this constant gates it, at 4 or at 13.
    ///
    /// So nesting is not what costs; **`oneOf` + `eraseToAny` arity is**, on this evidence.
    /// Deliberately NOT fixed here by inventing a second threshold — one measurement is a
    /// data point, not a curve, and a guard fitted to a single witness is how the first
    /// arbitrary constant happened. Filed as an open item in the plan instead.
    static let maximumZipNesting = 13

    /// Non-nil when the expression is too complex to emit as live code.
    static func typeCheckerOverrun(_ expression: String) -> String? {
        let nesting = expression.components(separatedBy: "zip(").count - 1
        guard nesting > maximumZipNesting else { return nil }
        return "Generator DERIVES, but the composed expression nests \(nesting) `zip`s "
            + "(limit \(maximumZipNesting)) and risks a compiler type-check timeout. Emitted "
            + "commented out rather than shipped as a build failure. Provide `static func "
            + "gen() -> Generator<T, some SendableSequenceType>` to replace the composition "
            + "with something the type checker can handle."
    }

    /// Skip `Hashable.distribution` for a `CaseIterable` enum, and nothing else.
    ///
    /// **Measured, not anticipated.** Running the first generated file, `KnownProperty` and
    /// `TemplateName` were the only two failures of 126: *"1000 samples produced only 25
    /// unique hashValues (ratio 0.025)"*. The law is right and the type is right — the
    /// generator draws from `allCases`, so the domain is the case list and 1000 trials
    /// cannot produce more distinct hashes than there are cases. No generator fixes it.
    ///
    /// Scoped to `.caseIterable` deliberately. On a wide domain a bad `hash(into:)` really
    /// does show up as clustering, so suppressing `distribution` everywhere would trade a
    /// real signal for a green run — the exact bargain `fixtures/toolchain-coverage` warns
    /// against when it says a reader who narrows a generator "should not widen it to silence
    /// the distribution law".
    ///
    /// The kit records a swift-testing Issue for a Heuristic violation even though
    /// `EnforcementMode.default` does not throw, so an assertion tightened to Strict is not
    /// enough on its own — the suppression is what keeps the emitted suite green.
    static func options(_ conformance: String, isCaseIterable: Bool) -> String {
        // **The `elementSameResult:` overload, always, for the Sequence chain.**
        //
        // The default overload requires `Value.Element: Equatable`, and a dictionary-shaped
        // carrier's Element is a TUPLE — `(key: Key, value: Value)` — which cannot conform to
        // a protocol. Measured: `OrderedDictionary`, `OrderedDictionary.Elements` and
        // `_Bitmap` all failed with "cannot conform to 'Equatable'".
        //
        // The kit shipped these overloads for exactly this (its own note calls it "a missing
        // conformance can be a harness problem, not a type problem"). Passing
        // `{ $0 == $1 }` unconditionally is strictly more permissive than the default: it
        // compiles for any Equatable element AND for a tuple of Equatables, since Swift
        // defines `==` on tuples up to six members. A carrier whose Element is neither would
        // not have compiled under the default overload either.
        if conformance == "Sequence" || conformance == "Collection" {
            return ",\n                        elementSameResult: { $0 == $1 }"
        }
        guard isCaseIterable, conformance == "Hashable" else { return "" }
        return """
        ,
                        options: LawCheckOptions(suppressions: [
                            // A CaseIterable domain cannot fill 1000 trials with distinct
                            // hashes; the law is degenerate here by construction, not failing.
                            .skip(
                                LawIdentifier(protocolName: "Hashable", lawName: "distribution"),
                                reason: "domain is `allCases` — fewer values than trials"
                            )
                        ])
        """
    }
}
