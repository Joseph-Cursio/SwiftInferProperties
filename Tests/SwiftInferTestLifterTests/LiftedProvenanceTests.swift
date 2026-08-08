import Foundation
import SwiftInferCore
@testable import SwiftInferTestLifter
import Testing

/// A lifted row must name a file a reviewer can open.
///
/// Before this, every lifted row rendered `Lifted from <test-body>:0` — a placeholder and a
/// zero — while a source-derived row in the same output carried `file.swift:line`.
/// `Slicer` has no `SourceLocationConverter`, so the assertion's own location is unavailable
/// on every path that reaches `discover`, and the renderer printed the placeholder rather
/// than consulting `LiftedOrigin`, which has carried the enclosing test method's real file
/// and line since M3.2.
///
/// **This is not cosmetic, and the road test is the evidence.** It is what let the
/// package-wide test-lifting defect survive: a row citing `render(suggestion)` on
/// `SwiftInferKitEvidence` reads as a plausible finding until it says which file it came
/// from. That defect was found by noticing four byte-identical rows across six targets and
/// then grepping — not by reading output that could not say. It then blocked the follow-up
/// investigation too: proving that four newly-landed property suites were *not* being lifted
/// could not be done from the tool's output at all
/// (`docs/measurements/roadtest-self-dogfood-2026-08-08.md` §7.4).
///
/// A tool whose entire posture is human review must not emit a row a human cannot audit.
@Suite("Lifted provenance — every row names a file a reviewer can open")
struct LiftedProvenanceTests {

    // MARK: - Fixtures

    private static func origin(
        method: String = "testRoundTripsCleanly",
        file: String = "/repo/Tests/FooTests/FooTests.swift",
        line: Int = 42
    ) -> LiftedOrigin {
        LiftedOrigin(
            testMethodName: method,
            sourceLocation: SwiftInferCore.SourceLocation(file: file, line: line, column: 5)
        )
    }

    private static func detection(assertionLocation: SwiftInferCore.SourceLocation) -> DetectedRoundTrip {
        DetectedRoundTrip(
            forwardCallee: "encode",
            backwardCallee: "decode",
            inputBindingName: "input",
            recoveredBindingName: "recovered",
            assertionLocation: assertionLocation
        )
    }

    // MARK: - SourceLocation.isResolvable

    /// The predicate the whole fix turns on. A location is showable only when it names a real
    /// file at a real line; `<test-body>:0` and `<corpus>:0` name neither.
    @Test("the slicer placeholder is not resolvable")
    func placeholderIsNotResolvable() {
        #expect(!SwiftInferCore.SourceLocation.testBodyPlaceholder.isResolvable)
        #expect(!SwiftInferCore.SourceLocation(file: "<corpus>", line: 0, column: 0).isResolvable)
    }

    /// A line of 0 is unresolvable even with a real-looking path — the slicer's placeholder
    /// shape is `<file>:0`, and a caller that fixed only the file half would otherwise pass.
    @Test("a real path at line 0 is still not resolvable")
    func lineZeroIsNotResolvable() {
        #expect(!SwiftInferCore.SourceLocation(file: "/repo/Tests/A.swift", line: 0, column: 0).isResolvable)
    }

    @Test("a real file at a real line is resolvable")
    func realLocationIsResolvable() {
        #expect(SwiftInferCore.SourceLocation(file: "/repo/Tests/A.swift", line: 12, column: 1).isResolvable)
    }

    /// **The producer and the consumer share one constant.** `Slicer` emits
    /// `SourceLocation.testBodyPlaceholder` and the renderer recognises it by that same
    /// declaration. A guard that restated the literal would only check that two copies agree.
    @Test("the shared placeholder constant is the one the slicer emits")
    func placeholderConstantIsTheSlicersOwn() {
        #expect(SwiftInferCore.SourceLocation.testBodyPlaceholder.file == "<test-body>")
        #expect(SwiftInferCore.SourceLocation.testBodyPlaceholder.line == 0)
    }

    // MARK: - provenanceLine()

    /// The fallback that fixes the defect: an unresolvable assertion location resolves through
    /// the origin, naming the test file, line and method.
    @Test("an unresolvable assertion falls back to the origin's file, line and method")
    func fallsBackToOrigin() {
        let suggestion = LiftedSuggestion(
            templateName: "round-trip",
            crossValidationKey: CrossValidationKey(
                templateName: "round-trip", calleeNames: ["encode", "decode"]
            ),
            pattern: .roundTrip(
                Self.detection(assertionLocation: SwiftInferCore.SourceLocation.testBodyPlaceholder)
            ),
            origin: Self.origin()
        )
        let line = suggestion.provenanceLine()
        #expect(line.contains("/repo/Tests/FooTests/FooTests.swift:42"))
        #expect(line.contains("testRoundTripsCleanly"))
    }

    /// **The regression this suite exists for.** Whatever else changes, the placeholder must
    /// never reach a reader — it reads like a path and is not one.
    @Test("the placeholder never appears in rendered provenance")
    func placeholderNeverRendered() {
        for origin in [Self.origin(), nil] {
            let suggestion = LiftedSuggestion(
                templateName: "round-trip",
                crossValidationKey: CrossValidationKey(
                templateName: "round-trip", calleeNames: ["encode", "decode"]
            ),
                pattern: .roundTrip(
                    Self.detection(assertionLocation: SwiftInferCore.SourceLocation.testBodyPlaceholder)
                ),
                origin: origin
            )
            #expect(!suggestion.provenanceLine().contains("<test-body>"))
            #expect(!suggestion.provenanceLine().contains(":0"))
        }
    }

    /// With no origin either, the row says so in words rather than printing a fake path.
    /// Honest absence beats a plausible-looking placeholder — the same reason
    /// `DeferralFalsifierTests` reports `unavailable` instead of folding it into "absent".
    @Test("with neither location available, the row says so plainly")
    func statesAbsencePlainly() {
        let suggestion = LiftedSuggestion(
            templateName: "round-trip",
            crossValidationKey: CrossValidationKey(
                templateName: "round-trip", calleeNames: ["encode", "decode"]
            ),
            pattern: .roundTrip(
                Self.detection(assertionLocation: SwiftInferCore.SourceLocation.testBodyPlaceholder)
            ),
            origin: nil
        )
        #expect(suggestion.provenanceLine().contains("exact location unavailable"))
    }

    /// A resolvable assertion location still wins — the origin is a *fallback*, not a
    /// replacement. If a converter is ever threaded into `Slicer`, the more precise
    /// assertion line must take over without further change here.
    @Test("a resolvable assertion location is preferred over the origin")
    func assertionLocationWins() {
        let suggestion = LiftedSuggestion(
            templateName: "round-trip",
            crossValidationKey: CrossValidationKey(
                templateName: "round-trip", calleeNames: ["encode", "decode"]
            ),
            pattern: .roundTrip(
                Self.detection(
                    assertionLocation: SwiftInferCore.SourceLocation(
                        file: "/repo/Tests/FooTests/FooTests.swift", line: 99, column: 3
                    )
                )
            ),
            origin: Self.origin(line: 42)
        )
        let line = suggestion.provenanceLine()
        #expect(line.contains(":99"))
        #expect(!line.contains(":42"))
    }
}
