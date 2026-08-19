import Foundation
import Testing

@testable import SwiftInferCore
@testable import SwiftInferTemplates

/// **Can the tool name the caller a `private`-subject law should be lifted to?**
///
/// `docs/measurements/roadtest-self-dogfood-2026-08-08.md` §2 settled the *design* on
/// 2026-08-08 and could not build it: *"What would help is a caveat that names the nearest
/// reachable caller, turning 'you cannot test this' into 'state it on
/// `lookupSuggestion`'."* — **not a gate, not a demotion, not a veto**, which is why
/// `subjectNotVisibleToTests` carries weight 0.
///
/// It sat because callers were unresolvable: open item 38, no IndexStore, so
/// `swift-syntax` cannot answer who calls what. **`calledFreeFunctionNames` changed that
/// on 2026-08-18** — added for `PackagePurityJoin`, and inverting it gives a caller index.
///
/// ## Why same-file is SOUND here, not a heuristic
///
/// `private` and `fileprivate` are file-scoped in Swift. **A caller of a `private` helper
/// must be in the same file**, so restricting the search there is a consequence of the
/// language rather than a guess — and it removes almost all of the name-collision risk
/// that makes a reverse name index dangerous. `normalize` in another type cannot be a
/// caller of this one.
///
/// ## What this measures, and what it deliberately does not
///
/// **Reach only.** A caveat moves **zero** survey rows by construction — it is
/// explainability, not a law, and the 204 visibility declines stay declined. Scoring this
/// as throughput would be the mistake; PRD §4.5 makes explainability a first-class output
/// and this is that.
///
/// The cap is **member calls**: `self.foo()` and `x.foo()` are not collected, deliberately,
/// because without an index `encode` on one type cannot be told from `encode` on another.
/// The worked example resolves only because its helpers are `static` and called
/// unqualified. **How much of the population that costs is the number this census exists
/// to produce.**
@Suite("Census — can a lifted law name its caller?", .serialized)
struct LiftCallerReachMeasuredTests {

    @Test("control — the restricted population and the caller index are both non-empty")
    func theInstrumentReaches() throws {
        let reading = try #require(Self.reading)
        #expect(reading.restricted > 50, "only \(reading.restricted) restricted functions — did the scan run?")
        #expect(reading.callersIndexed > 100, """
        Only \(reading.callersIndexed) functions record a free-shape callee. \
        `calledFreeFunctionNames` is not being populated, so every zero below is the \
        instrument's rather than the corpus's.
        """)
    }

    @Test("census — how many restricted subjects can name a visible caller")
    func census() throws {
        let reading = try #require(Self.reading)
        print("""
        LIFT-CALLER REACH — \(reading.restricted) restricted (private/fileprivate) functions
          with >=1 same-file caller found:        \(reading.withAnyCaller)
          …of those, >=1 caller VISIBLE to tests: \(reading.withVisibleCaller)
          …unambiguous (one caller only):         \(reading.withSingleVisibleCaller)
          no caller found at all:                 \(reading.withoutCaller)

        SUGGESTIONS declined for visibility:      \(reading.suggestionsOnRestricted)
          …that could name a visible caller:      \(reading.suggestionsWithVisibleCaller)
        """)
        for row in reading.samples.prefix(12) { print("    \(row)") }
    }
}
