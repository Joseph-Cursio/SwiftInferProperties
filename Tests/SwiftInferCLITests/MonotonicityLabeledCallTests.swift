import Foundation
import SwiftInferCore
import Testing

@testable import SwiftInferCLI

/// **`liftedOrMonotonicityCalls` was the one resolver arm that never wrapped a labelled
/// call, and nothing said so for the life of the feature.**
///
/// V1.149 added `labeledCallExpression` — a function with external argument labels cannot
/// be called positionally, so the stub gets a trampoline closure — and
/// `singleCallResolved` routes every other template through it. This arm went on rendering
/// the bare reference with `CallExpressionShape.render` and handing it to a composer that
/// applies positionally, so `wordCount(forScale:)` emitted `wordCount(valueA)`.
///
/// **Measured on `swift-collections` @ `899809d3`**: 7 of 64 `monotonicity` rows failed to
/// build with `missing argument label` — `'forScale:'` ×5, `'forOffset:'`, `'remaining:'`.
/// Two more on OpenAPIKit, recorded there as a single line in an error histogram
/// (`docs/measurements/monotonicity-verify-reach.md` §5, §7).
///
/// ⚠ **The blast radius is TWO templates, `monotonicity` and `idempotence-lifted` — not the
/// catalogue.** Row 73 first claimed the defect was template-independent; reading the
/// resolver refuted that, and the census the row demanded as its first step would have
/// sized a population only these two draw from.
///
/// **`LabeledCallExpressionTests` already covers the helper.** What was missing is that
/// this arm CALLS it — a helper can be correct and unreached, which is what happened.
@Suite("Monotonicity resolution — the labelled call reaches the composer")
struct MonotonicityLabeledCallTests {

    private typealias VerifyCLI = SwiftInferCommand.Verify

    private static func entry(
        template: String = "monotonicity",
        primary: String = "wordCount(forScale:)"
    ) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: "0x518A359C0574816B",
            templateName: template,
            typeName: "Int",
            score: 30,
            tier: "Possible",
            primaryFunctionName: primary,
            location: "/Module.swift:1",
            firstSeenAt: "2026-05-11T00:00:00Z",
            lastSeenAt: "2026-05-11T00:00:00Z"
        )
    }

    /// **The regression.** Element 0 is what the value composer applies positionally as
    /// `\(call)(valueA)`, so it must carry the label or the stub does not compile.
    @Test("a labelled monotonicity subject resolves to a trampoline closure")
    func labelledSubjectWraps() {
        let resolved = VerifyCLI.liftedOrMonotonicityCalls(
            entry: Self.entry(),
            typeQualifier: "_HashTable",
            funcName: "wordCount"
        )
        #expect(
            resolved.expressions.first == "{ _HashTable.wordCount(forScale: $0) }",
            "the value composer applies element 0 positionally — an unwrapped reference emits `wordCount(valueA)`"
        )
    }

    /// `idempotence-lifted` shares the arm and applies its call positionally too.
    @Test("idempotence-lifted gets the same wrapping")
    func liftedSubjectWraps() {
        let resolved = VerifyCLI.liftedOrMonotonicityCalls(
            entry: Self.entry(template: "idempotence-lifted", primary: "normalize(in:)"),
            typeQualifier: "Engine",
            funcName: "normalize"
        )
        #expect(resolved.expressions == ["{ Engine.normalize(in: $0) }"])
    }

    /// **The OC composer's input, which the wrapping could have broken.** It reads a method
    /// name off the call with `split(".").last`, and a closure literal answers that with
    /// `$0) }`. Monotonicity therefore carries a third element — the RAW reference — and
    /// the composer takes that one.
    @Test("monotonicity carries the raw call for the OC composer to read a method name off")
    func rawCallSurvivesForTheOCComposer() throws {
        let resolved = VerifyCLI.liftedOrMonotonicityCalls(
            entry: Self.entry(primary: "index(after:)"),
            typeQualifier: "Deque",
            funcName: "index"
        )
        // **Indexed through `#require`, never subscripted directly.** A regression here
        // drops the array to two elements, and `expressions[2]` would then TRAP —
        // `Index out of range`, signal 5, taking the whole test process down and masking
        // every suite behind it. Verified by reverting the fix: the first version of this
        // test crashed the runner instead of reporting. A guard that traps reports nothing
        // about what it was guarding, which is this session's own finding about laws.
        try #require(
            resolved.expressions.count == 3,
            "monotonicity must carry [labelled, primaryFunctionName, raw] — the OC composer reads element 2"
        )
        #expect(resolved.expressions[1] == "index(after:)", "the un-stripped name carries the label")
        #expect(resolved.expressions[2] == "Deque.index", "the raw reference, for split(\".\").last")
        let methodName = resolved.expressions[2].split(separator: ".").last.map(String.init)
        #expect(methodName == "index", "reading the method name off element 0 would give `$0) }`")
    }

    /// **A labelless subject is byte-identical to before the fix**, which is what makes this
    /// safe for every existing stdlib-carrier stub. `labeledCallExpression` returns the
    /// reference unchanged when every label is `_`, so element 0 and the raw element agree.
    @Test("a labelless subject is unchanged")
    func labellessSubjectUnchanged() throws {
        let resolved = VerifyCLI.liftedOrMonotonicityCalls(
            entry: Self.entry(primary: "magnitude(_:)"),
            typeQualifier: "Int",
            funcName: "magnitude"
        )
        #expect(resolved.expressions.first == "Int.magnitude")
        try #require(resolved.expressions.count == 3)
        #expect(resolved.expressions[2] == "Int.magnitude")
    }
}
