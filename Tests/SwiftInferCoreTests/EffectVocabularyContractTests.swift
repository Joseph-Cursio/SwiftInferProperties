import SwiftEffectInference
@testable import SwiftInferCore
import SwiftParser
import SwiftSyntax
import Testing

/// Open item 4, closed for the names this repo actually depends on.
///
/// **Why this became urgent on 2026-08-04.** Until step 1 of item 17, swift-infer
/// consumed exactly one word of SwiftIdempotency's vocabulary
/// (`@ClockDeterministic`) and a rename would have cost an async relaxation. Now
/// `IdempotenceTemplate` **vetoes** on `@NonIdempotent` and
/// `@ExternallyIdempotent`, so a rename upstream does not fail loudly — it
/// silently stops suppressing a false law, and a suppressed-then-unsuppressed
/// suggestion is indistinguishable from a codebase that never annotated
/// anything. That is item 4's stated failure mode ("a rename fails as a
/// *missing* annotation"), now with teeth.
///
/// **What this can and cannot assert.** SwiftInferProperties does not depend on
/// SwiftIdempotency — deliberately, since the doc-comment spelling needs no
/// dependency and the attribute spelling is recognised by *name*, not by type.
/// So this cannot import the macros and compare symbols. What it can do is pin
/// **the exact spellings this repo's behaviour is keyed to**, so that changing
/// one is a test failure here rather than a silent behaviour change. The
/// cross-repo half — asserting these equal SwiftIdempotency's shipped macro
/// names — needs a fixture or a checked-in manifest and is still open.
@Suite("Effect vocabulary — the names this repo's behaviour is keyed to")
struct EffectVocabularyContractTests {

    /// The spellings, written out rather than derived. Deriving them from
    /// `AttributeRecognition.default` would make the test pass by construction
    /// and assert nothing — the same defect `KitCoverageDriftTests` had when it
    /// checked suite granularity and missed 13 false law-level claims.
    @Test("AttributeRecognition.default recognises exactly the five expected names")
    func defaultRecognitionSetIsPinned() {
        let recognition = EffectAnnotationParser.AttributeRecognition.default
        #expect(recognition.idempotent == ["Idempotent"])
        #expect(recognition.nonIdempotent == ["NonIdempotent"])
        #expect(recognition.observational == ["Observational"])
        #expect(recognition.externallyIdempotent == ["ExternallyIdempotent"])
        #expect(recognition.pure == ["Pure"])
    }

    /// The behavioural half, and the one that would actually catch a rename.
    ///
    /// A contents-only check passes straight through a *reachability* defect —
    /// the set can be correct while nothing consults it. This parses real source
    /// and asserts the effect comes out, which is the check
    /// `docs/design-internal/open-threads.md` says the coverage guard was missing.
    @Test(
        "Each attribute spelling round-trips from source to the effect it claims",
        arguments: [
            ("@Idempotent", Effect.idempotent),
            ("@NonIdempotent", Effect.nonIdempotent),
            ("@Observational", Effect.observational),
            ("@Pure", Effect.pure)
        ]
    )
    func attributeSpellingReachesTheEffect(spelling: String, expected: Effect) {
        let summaries = FunctionScanner.scanCorpus(
            source: """
            enum Host {
                \(spelling)
                static func subject(_ text: String) -> String { text }
            }
            """,
            file: "Contract.swift"
        ).summaries
        #expect(summaries.first?.declaredEffect == expected)
    }

    /// `@ExternallyIdempotent(by:)` carries a payload, so it is checked apart
    /// from the bare markers: the key parameter is what makes the tier mean
    /// "idempotent only through THIS argument", and dropping it would silently
    /// turn a keyed claim into a documentary one.
    @Test("@ExternallyIdempotent carries its dedup key through to the effect")
    func externallyIdempotentKeySurvives() {
        let summaries = FunctionScanner.scanCorpus(
            source: """
            enum Host {
                @ExternallyIdempotent(by: "requestID")
                static func charge(_ text: String) -> String { text }
            }
            """,
            file: "Contract.swift"
        ).summaries
        #expect(summaries.first?.declaredEffect == .externallyIdempotent(keyParameter: "requestID"))
    }

    /// The dependency-free spelling. This is the one a project can use without
    /// adopting SwiftIdempotency at all, so it is the spelling most likely to be
    /// what a real user's code carries — and it is keyed to a *token*
    /// (`@lint.effect idempotent`), not an attribute name, so it can rot
    /// independently of the set above.
    @Test(
        "Each doc-comment spelling round-trips too",
        arguments: [
            ("idempotent", Effect.idempotent),
            ("non_idempotent", Effect.nonIdempotent),
            ("observational", Effect.observational),
            ("pure", Effect.pure)
        ]
    )
    func docCommentSpellingReachesTheEffect(token: String, expected: Effect) {
        let summaries = FunctionScanner.scanCorpus(
            source: """
            enum Host {
                /// @lint.effect \(token)
                static func subject(_ text: String) -> String { text }
            }
            """,
            file: "Contract.swift"
        ).summaries
        #expect(summaries.first?.declaredEffect == expected)
    }

    /// `@ClockDeterministic` is the name item 4 was originally written about, and
    /// it is the one that is **neither configurable nor in the set above** — SEI
    /// keeps it out of `AttributeRecognition` on purpose (it is a determinism
    /// claim, not an effect tier) and resolves it through a bespoke function. So
    /// nothing else in this file covers it, and a rename upstream would land on
    /// the async relaxation with no test anywhere objecting.
    @Test("@ClockDeterministic still reaches isClockDeterministic, in both spellings")
    func clockDeterminismSpellingsSurvive() {
        for spelling in ["@ClockDeterministic", "/// @lint.determinism clock_deterministic"] {
            let summaries = FunctionScanner.scanCorpus(
                source: """
                enum Host {
                    \(spelling)
                    static func refresh(_ text: String) async -> String { text }
                }
                """,
                file: "Contract.swift"
            ).summaries
            #expect(summaries.first?.isClockDeterministic == true, "spelling: \(spelling)")
        }
    }

    /// **This is the rename, simulated** — and it is the assertion that makes the
    /// file a guard rather than a description. A near-miss spelling produces
    /// `nil`, exactly as a *missing* annotation does, which is item 4's failure
    /// mode written as a test: if SwiftIdempotency renamed `@NonIdempotent`
    /// tomorrow, this is the shape the veto would silently take, and the
    /// round-trip tests above would go red.
    @Test(
        "A near-miss spelling claims NOTHING — indistinguishable from unannotated",
        arguments: ["@Idempotant", "@Idempotent2", "@NonIdempotentt", "@Idempotency"]
    )
    func misspelledAttributeIsSilent(spelling: String) {
        let summaries = FunctionScanner.scanCorpus(
            source: """
            enum Host {
                \(spelling)
                static func subject(_ text: String) -> String { text }
            }
            """,
            file: "Contract.swift"
        ).summaries
        // Not "wrong effect" — NO effect. The tool cannot tell a renamed marker
        // from a codebase that never annotated anything, which is precisely why
        // the spellings above have to be pinned somewhere.
        #expect(summaries.first?.declaredEffect == nil, "spelling: \(spelling)")
    }

    /// The negative control, and the reason the rest of the file is not
    /// vacuous: an unannotated declaration must produce `nil`, not a default.
    /// Without this, every assertion above would still pass if the parser
    /// started returning a fixed effect for everything.
    @Test("An unannotated declaration claims nothing")
    func unannotatedClaimsNothing() {
        let summaries = FunctionScanner.scanCorpus(
            source: """
            enum Host {
                static func subject(_ text: String) -> String { text }
            }
            """,
            file: "Contract.swift"
        ).summaries
        #expect(summaries.first?.declaredEffect == nil)
        #expect(summaries.first?.isClockDeterministic == false)
    }
}
