import Foundation
import PropertyLawKit
@testable import SwiftInferCore
import Testing

// Banked from the `prove-then-show` survey (`docs/measurements/roadtest-self-dogfood-2026-08-08.md`
// §8): the `idempotence` picks the survey **Proved** and that nothing in the repo pinned.
// Every subject below had example-based tests; **none had the law asserted anywhere** — a
// `grep` for the double-application shape returned zero hits for all four string helpers.
//
// **And one of the survey's Proven verdicts is WRONG.** `booleanStem` is not idempotent, and
// this suite pins the refutation rather than the law. See the last section — it is the most
// important thing here, and it was found by reading the code, not by running the tool.
@Suite("Survey-banked — idempotence laws the survey proved, and one it got wrong")
struct SurveyedIdempotencePropertyTests {

    // MARK: - Generator
    //
    // Type-name and identifier shapes, drawn deliberately to look like the domain these
    // helpers actually operate on. That is the whole lesson of the `booleanStem` section
    // below: the survey's derived `String` generator draws things like `"XO8hGC"`, which
    // never resemble a Swift identifier and so never reach the branches that matter.

    private static let identifiers = [
        "Complex<Double>", "Array<Int>", "Foo", "", "T",
        "exp(_:)", "merge(_:)", "isLoading", "hasShownAlert", "Optional<Int>?", "String?"
    ]

    private static let nameGen = Gen.element(of: identifiers).map { $0! }

    // MARK: - The laws that genuinely hold

    /// A **fifth** spelling of the generic strip, and one the §3 same-name census missed
    /// because it is named `stripGenericParameters` rather than `strippingGenericParameters`.
    /// It is also stricter than the other four: it requires a trailing `>`, so `"Foo<"` is
    /// returned untouched where `CarrierKindResolver` would strip it. Pinned on its own terms
    /// rather than folded into the differential suite, because it is deliberately not the
    /// same function.
    @Test("FloatingPointEquatableTypes.stripGenericParameters is idempotent")
    func stripGenericParametersIsIdempotent() async {
        await propertyCheck(input: Self.nameGen) { name in
            let once = FloatingPointEquatableTypes.stripGenericParameters(name)
            #expect(FloatingPointEquatableTypes.stripGenericParameters(once) == once)
        }
    }

    /// The postcondition that makes the law above mean something: a stripped name carries no
    /// generic argument list. Idempotence alone is satisfied by a function that strips nothing.
    @Test("a fully stripped name has no generic argument list")
    func stripGenericParametersRemovesTheList() async {
        await propertyCheck(input: Self.nameGen) { name in
            let stripped = FloatingPointEquatableTypes.stripGenericParameters(name)
            if name.hasSuffix(">") {
                #expect(!stripped.contains("<"), "\"\(name)\" kept its parameter list")
            }
        }
    }

    @Test("SeedFocus.functionBaseName is idempotent")
    func functionBaseNameIsIdempotent() async {
        await propertyCheck(input: Self.nameGen) { name in
            let once = SeedFocus.functionBaseName(name)
            #expect(SeedFocus.functionBaseName(once) == once)
            #expect(!once.contains("("), "the parameter-label suffix must be gone")
        }
    }

    /// `stripOptional` loops while the suffix matches, so it removes `??` and `!?` fully.
    /// That loop is exactly what makes idempotence true here and false for `booleanStem`
    /// below — the same author, the same file, two different decisions about repetition.
    @Test("ViewModelNameHeuristics.stripOptional is idempotent")
    func stripOptionalIsIdempotent() async {
        let optionals = Self.identifiers + ["Int??", "String!", "Foo?!", "Bar!!"]
        await propertyCheck(input: Gen.element(of: optionals).map { $0! }) { type in
            let once = ViewModelNameHeuristics.stripOptional(type)
            #expect(ViewModelNameHeuristics.stripOptional(once) == once)
            #expect(!once.hasSuffix("?") && !once.hasSuffix("!"))
        }
    }

    // MARK: - `updated(from:)` — a right-biased merge
    //
    // `receiver.updated(from: incoming)` takes most columns from `incoming` but keeps the
    // identity columns from `receiver`. Idempotence is the law the survey proved; the
    // identity-preservation law below is the one that would actually catch a mistake, since
    // taking `identityHash` from the argument would STILL be idempotent while silently
    // re-keying every index row. The control confirms exactly that split.

    private static func entry(hash: String, score: Int, firstSeen: String) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: hash,
            templateName: "idempotence",
            typeName: "Foo",
            score: score,
            tier: score >= 70 ? "Strong" : "Likely",
            primaryFunctionName: "normalize(_:)",
            location: "/Module.swift:1",
            firstSeenAt: firstSeen,
            lastSeenAt: "2026-08-08T00:00:00Z"
        )
    }

    private static let scoreGen = Gen.element(of: [20, 35, 50, 70, 90]).map { $0! }

    @Test("SemanticIndexEntry.updated(from:) is idempotent")
    func semanticEntryUpdateIsIdempotent() async {
        await propertyCheck(input: Self.scoreGen, Self.scoreGen) { mine, theirs in
            let receiver = Self.entry(hash: "0xAAA", score: mine, firstSeen: "2026-01-01T00:00:00Z")
            let incoming = Self.entry(hash: "0xBBB", score: theirs, firstSeen: "2026-06-01T00:00:00Z")
            let once = receiver.updated(from: incoming)
            #expect(once.updated(from: incoming) == once)
        }
    }

    /// **The refutable half.** The identity columns come from the receiver, never the
    /// argument — `identityHash` is what every decision, skip marker and accept record keys
    /// on, and `firstSeenAt` is the only column that would be lost forever if overwritten.
    @Test("updated(from:) keeps the receiver's identity and first-seen columns")
    func semanticEntryUpdatePreservesIdentity() async {
        await propertyCheck(input: Self.scoreGen, Self.scoreGen) { mine, theirs in
            let receiver = Self.entry(hash: "0xAAA", score: mine, firstSeen: "2026-01-01T00:00:00Z")
            let incoming = Self.entry(hash: "0xBBB", score: theirs, firstSeen: "2026-06-01T00:00:00Z")
            let merged = receiver.updated(from: incoming)
            #expect(merged.identityHash == "0xAAA", "identity must not come from the argument")
            #expect(merged.firstSeenAt == "2026-01-01T00:00:00Z", "first-seen must not move forward")
            #expect(merged.score == theirs, "the re-scan is authoritative for the score")
        }
    }

    // MARK: - The survey got this one WRONG
    //
    // `booleanStem` strips ONE prefix from `["isshowing", "is", "has", "show", "should",
    // "did", "will"]`. Applying it twice strips a second one whenever the stem itself starts
    // with another prefix — and English names do that constantly:
    //
    //     isShowing     -> showing    -> ing
    //     hasShown      -> shown      -> n
    //     willShowAlert -> showalert  -> alert
    //
    // **The survey reported this law Proven.** The derived `String` generator draws values
    // like `"XO8hGC"` and `"uvYUbS"` — the literal counterexamples §8.4 captured — which never
    // begin with an English boolean prefix, so the failing branch was unreachable in the
    // generated domain. This is the standing rule in the sharpest form it has taken here:
    // *`measured-bothPass` means no counterexample in the generated domain, not that the
    // property holds.*
    //
    // **It is a false law, not a defect.** Both call sites
    // (`ViewModelInteractionAnalyzer:177`, `ViewModelInvariantResolvers:33`) apply it once to
    // a raw property name, and the docstring says one strip by design. So this suite pins the
    // NON-idempotence: the behaviour is correct, and a future "fix" that looped — making the
    // law true — would silently turn `isShowingSheet` into `sheet` and change what every
    // view-model invariant keys on.
    @Test("booleanStem is deliberately NOT idempotent — the survey's Proven verdict is false")
    func booleanStemIsNotIdempotent() {
        let witnesses = ["isShowing", "hasShown", "willShowAlert", "isShowSheet"]
        for name in witnesses {
            let once = ViewModelNameHeuristics.booleanStem(name)
            let twice = ViewModelNameHeuristics.booleanStem(once)
            #expect(
                once != twice,
                Comment(rawValue:
                    "\"\(name)\" now survives double application (\(once) -> \(twice)). If "
                    + "booleanStem was deliberately made idempotent, delete this test and "
                    + "update roadtest §8.2 — but check both call sites first: they strip one "
                    + "prefix from a raw property name, and looping changes what the "
                    + "view-model invariants key on.")
            )
        }
    }

    /// One strip, and only one — stated positively so the suite says what the function *does*
    /// rather than only what it is not.
    @Test("booleanStem strips exactly one prefix")
    func booleanStemStripsExactlyOnePrefix() {
        #expect(ViewModelNameHeuristics.booleanStem("isShowing") == "showing")
        #expect(ViewModelNameHeuristics.booleanStem("hasShown") == "shown")
        #expect(ViewModelNameHeuristics.booleanStem("loading") == "loading")
        // `count > prefix.count` guard: an exact match is not stripped to empty.
        #expect(ViewModelNameHeuristics.booleanStem("is") == "is")
    }
}
