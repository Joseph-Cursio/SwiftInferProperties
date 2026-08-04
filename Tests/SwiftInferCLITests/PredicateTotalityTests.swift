import Foundation
@testable import SwiftInferCLI
@testable import SwiftInferCore
import Testing

/// The `predicate` composer and the trap branch that keeps its findings from being misfiled.
///
/// Totality is the only verifiable law that fails by **trap** rather than by assertion. Twelve of
/// the thirteen other composers can report a counterexample because a failed comparison is an
/// ordinary value; this one cannot, because the process is gone. Everything here exists to make
/// that one difference survive `VerifyResult.parse`.
@Suite("Predicate totality — composer and trap recovery")
struct PredicateTotalityTests {

    // MARK: - The template is in the vocabulary

    /// `predicate` was live in the index and **absent from the enum** — the documented
    /// `TemplateName` trap. Being verifiable means being in this list.
    @Test func predicateIsVerifiable() {
        #expect(TemplateName.verifiable.contains(.predicate))
        #expect(TemplateName.predicate.rawValue == "predicate")
    }

    /// **It must stay OUT of the algebraic set.** `defaultPassSection` falls through to
    /// `algebraicLawPass` for everything in that list, so including `predicate` would route totality
    /// into a switch that cannot compose it — and the `unsupportedTemplate` error names this very
    /// set, so it would advertise a template it cannot handle.
    @Test func predicateIsNotAnAlgebraicLaw() {
        #expect(!TemplateName.strategistAlgebraicLaws.contains(.predicate))
    }

    // MARK: - What the composer emits

    private func composed() throws -> String {
        try StrategistDispatchEmitter.composePredicatePass(
            inputs: .init(
                carrier: "String",
                typeShape: nil,
                template: "predicate",
                functionCalls: ["isEmptyPath"],
                extraImports: [],
                seedHex: .init(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
                trialBudget: .small,
                allShapes: [:],
                isInstanceMethod: false,
                isMutatingMethod: false,
                isNullary: false,
                returnsSelfType: false,
                isComputedProperty: false,
                parameterCount: 1
            ),
            recipe: .init(
                expression: "Gen<String>.string()",
                carrierTypeName: "String",
                imports: []
            )
        )
    }

    /// The marker must precede the call. After it, a trap discards the very thing it exists to
    /// record — so ordering is the whole mechanism, not a formatting preference.
    @Test func theInputMarkerIsPrintedBeforeTheCall() throws {
        let source = try composed()
        let markerAt = try #require(source.range(of: "VERIFY_TRIAL_INPUT:"))
        let callAt = try #require(source.range(of: "isEmptyPath(candidate)"))
        #expect(markerAt.lowerBound < callAt.lowerBound,
                "the input marker must be printed BEFORE the call it describes")
    }

    @Test func theResultIsDeliberatelyDiscarded() throws {
        #expect(try composed().contains("_ = isEmptyPath(candidate)"),
                "totality is satisfied by returning; binding the value would imply it is checked")
    }

    /// No `!=` oracle: there is nothing to compare. A composer that grew one would be checking
    /// something the law does not claim.
    @Test func thereIsNoComparisonOracle() throws {
        let source = try composed()
        #expect(!source.contains("VERIFY_DEFAULT_RESULT: FAIL"),
                "totality cannot fail by comparison — only by trap")
    }

    @Test func aSurvivingRunReportsPass() throws {
        let source = try composed()
        #expect(source.contains("VERIFY_DEFAULT_RESULT: PASS"))
        #expect(source.contains("VERIFY_DEFAULT_TRIALS:"))
    }

    // MARK: - Trap recovery

    private func trapped(stdout: String, stderr: String = "", exitCode: Int32 = 4) -> VerifyOutcome {
        VerifyResultParser.parse(
            .init(exitCode: exitCode, stdout: stdout, stderr: stderr)
        )
    }

    /// The point of the whole exercise: a trap with a trial marker is a **refutation**, not an error.
    @Test func aTrapWithATrialMarkerIsARefutation() {
        let outcome = trapped(
            stdout: "VERIFY_TRIAL_CARRIER: String\nVERIFY_TRIAL_INDEX: 7\nVERIFY_TRIAL_INPUT: \"\"\n",
            stderr: "Swift runtime failure: Can't take a prefix of negative length\n"
        )
        guard case let .defaultFails(detail) = outcome else {
            Issue.record("expected .defaultFails, got \(outcome)")
            return
        }
        #expect(detail.input == "\"\"")
        #expect(detail.trial == 7)
        #expect(detail.forwardResult == "trapped")
        #expect(detail.inverseResult.contains("Swift runtime failure"))
    }

    /// **A trap with no trial marker stays an error.** Twelve other composers can trap, and for them
    /// a trap really is evidence about the generator's domain rather than about the law. Claiming a
    /// refutation there would invent a counterexample for a property that was never evaluated.
    @Test func aTrapWithoutATrialMarkerIsStillAnError() {
        let outcome = trapped(stdout: "some unrelated output\n", stderr: "Fatal error: overflow\n")
        guard case .error = outcome else {
            Issue.record("a trap with no totality marker must remain .error, got \(outcome)")
            return
        }
    }

    /// A clean exit is unaffected — the branch is gated on the trap, not merely on the marker.
    @Test func markersOnASuccessfulRunDoNotFabricateAFailure() {
        let outcome = trapped(
            stdout: """
            VERIFY_TRIAL_INDEX: 99
            VERIFY_TRIAL_INPUT: "abc"
            VERIFY_DEFAULT_RESULT: PASS
            VERIFY_DEFAULT_TRIALS: 100
            VERIFY_EDGE_RESULT: PASS
            VERIFY_EDGE_TRIALS: 20
            VERIFY_EDGE_SAMPLED: 0
            """,
            exitCode: 0
        )
        guard case .bothPass = outcome else {
            Issue.record("expected .bothPass, got \(outcome)")
            return
        }
    }

    /// The runtime message is best-effort; its absence must not cost the counterexample, which is
    /// the part a reader actually needs.
    @Test func aMissingRuntimeMessageStillYieldsTheInput() {
        let outcome = trapped(stdout: "VERIFY_TRIAL_CARRIER: Int\nVERIFY_TRIAL_INPUT: 0\n")
        guard case let .defaultFails(detail) = outcome else {
            Issue.record("expected .defaultFails, got \(outcome)")
            return
        }
        #expect(detail.input == "0")
        #expect(detail.trial == -1, "an absent index decodes to -1 rather than failing the parse")
    }

    /// **The narrowing, and the run that forced it.** A trap on a memberwise-derived struct is
    /// evidence about the GENERATOR, not the law: the value assembled is one no code path could
    /// construct, so the function was never handed an input its domain admits.
    ///
    /// This is not hypothetical. The branch shipped without a carrier gate, and the first live
    /// survey reported `isWorthSurfacingBelowCut` refuted on a `Suggestion` carrying
    /// `score.total: 2524929203861660948` and a negative source column.
    @Test func aTrapOnANonScalarCarrierIsNotARefutation() {
        let outcome = trapped(
            stdout: "VERIFY_TRIAL_CARRIER: Suggestion\nVERIFY_TRIAL_INPUT: Suggestion(score: 2524929203861660948)\n",
            stderr: "Swift runtime failure: arithmetic overflow\n"
        )
        guard case .error = outcome else {
            Issue.record("a struct carrier's trap must stay .error, got \(outcome)")
            return
        }
    }

    /// The scalars where a trap DOES refute: the generator inhabits the whole type, so any value it
    /// produces is one the function genuinely had to handle.
    @Test func everyDomainCompleteScalarRefutes() {
        for carrier in ["Int", "Int8", "UInt64", "Double", "Float", "Bool", "String", "Character"] {
            let outcome = trapped(
                stdout: "VERIFY_TRIAL_CARRIER: \(carrier)\nVERIFY_TRIAL_INPUT: v\n"
            )
            guard case .defaultFails = outcome else {
                Issue.record("\(carrier) is domain-complete; its trap should refute")
                continue
            }
        }
    }

    /// A marker-bearing trap with no carrier line cannot be judged, so it stays an error rather
    /// than defaulting to the generous reading.
    @Test func aMissingCarrierMarkerIsNotAssumedScalar() {
        let outcome = trapped(stdout: "VERIFY_TRIAL_INPUT: 0\n")
        guard case .error = outcome else {
            Issue.record("without a carrier the branch must not claim a refutation")
            return
        }
    }

    /// The composer must actually print what the parser requires — the two halves of this mechanism
    /// live in different files and nothing else joins them.
    ///
    /// **Asserts the resolved NAME, not the marker prefix.** The prefix-only version of this test
    /// passed green while the composer emitted `\(escapedCarrierMarker)` — a compose-time value
    /// escaped as if it were a runtime one, so the generated source referenced a variable that
    /// does not exist there and all 114 indexed entries failed to build. The marker was present in
    /// every one of them; only its argument was wrong. A check that stops at the prefix cannot see
    /// the half of this contract that carries the information.
    @Test func theComposerPrintsTheCarrierTheParserNeeds() throws {
        let source = try composed()
        #expect(source.contains("VERIFY_TRIAL_CARRIER: String"))
        #expect(
            !source.contains(escapedCarrierMarker),
            "the carrier is known at compose time; escaping it emits a dangling reference"
        )
    }

    /// Spelled as a computed value so this file contains no literal backslash-paren that a later
    /// reader could mistake for the bug itself.
    private var escapedCarrierMarker: String { #"\(carrierName)"# }

    /// Signals arrive both raw and as `128 + n` depending on the shell in between; `trapReason`
    /// accepts either, and this branch inherits that.
    @Test func bothSignalEncodingsAreRecognised() {
        for code in [Int32(4), Int32(132)] {
            let outcome = trapped(stdout: "VERIFY_TRIAL_CARRIER: Int\nVERIFY_TRIAL_INPUT: x\n", exitCode: code)
            guard case .defaultFails = outcome else {
                Issue.record("exit \(code) should be recognised as a trap")
                continue
            }
        }
    }

    // MARK: - n-ary totality

    /// A predicate of two parameters needs **two** generated values. Until 2026-08-03 the composer
    /// had one type and emitted one argument, and 19 of 126 `predicate` entries failed to compile
    /// with `missing argument for parameter #2`.
    @Test func anNaryPredicateDrawsOneValuePerParameter() throws {
        let source = try composedNary(types: ["String", "Int"])
        #expect(source.contains("generator0"))
        #expect(source.contains("generator1"))
        #expect(source.contains("let candidate0 = generator0.run(using: &rng)"))
        #expect(source.contains("let candidate1 = generator1.run(using: &rng)"))
        #expect(source.contains("(candidate0, candidate1)"))
    }

    /// One marker still names the whole counterexample. The parser reads a single
    /// `VERIFY_TRIAL_INPUT` line and must not have to know the law's arity to read it.
    @Test func theInputMarkerCarriesEveryArgumentAsOneTuple() throws {
        let source = try composedNary(types: ["String", "Int"])
        let marker = source.split(separator: "\n").first { $0.contains("VERIFY_TRIAL_INPUT") }
        #expect(marker?.contains("(candidate0, candidate1)") == true)
    }

    /// **A unary law must emit exactly what it emitted before.** The n-ary path cannot be allowed
    /// to rewrite the 54 laws that already run — so the single-carrier branch is byte-identical,
    /// which is asserted rather than assumed.
    @Test func aUnaryLawIsUnchangedByTheNaryPath() throws {
        let source = try composed()
        #expect(source.contains("let defaultGenerator: Generator<String, some SendableSequenceType>"))
        #expect(source.contains("let candidate = defaultGenerator.run(using: &rng)"))
        #expect(!source.contains("generator0"))
    }

    /// A signature that is only half-recorded falls back rather than guessing. An index written
    /// before the field existed has no types at all; a count that disagrees with `parameterCount`
    /// means labels and types came from different places. Either way the old behaviour fails to
    /// compile with a message naming the missing argument, which is more use than a wrong
    /// generator failing somewhere else.
    @Test func aPartiallyRecordedSignatureFallsBackToTheCarrier() throws {
        // Two labels, one recorded type — disagreement.
        let source = try composedNary(types: ["String"], parameterCount: 2)
        #expect(source.contains("defaultGenerator"))
        #expect(!source.contains("generator0"))
    }

    // MARK: - The receiver is an implicit parameter

    /// `receiverCallExpression` renders an instance method as `{ $0.method($1) }`, so the closure
    /// takes `parameters + 1` values. Supplying one per *declared* parameter is short by exactly
    /// one — `missing argument for parameter #2`, for **7 of 126** entries measured 2026-08-03.
    ///
    /// All 7 survived the cross-module import fix because each had been failing on a missing type
    /// first: a refuter that fires first hides every refuter behind it.
    @Test func anInstanceMethodDrawsAValueForItsReceiver() throws {
        // Stdlib types so the shape universe is not what is under test — `resolveRecipe`
        // handles a `RawType` without one, and the claim here is about ARITY.
        let source = try composedNary(types: ["Int"], receiver: "Bool")
        #expect(source.contains("Generator<Bool, some SendableSequenceType>"))
        #expect(source.contains("Generator<Int, some SendableSequenceType>"))
        #expect(source.contains("(candidate0, candidate1)"))
    }

    /// The receiver's type is the DECLARING type, not the carrier. On
    /// `ReducerPin.matches(_ c: ReducerCandidate)` those differ, and using the carrier would draw
    /// two values of the same wrong type — which still compiles for a same-typed method and so
    /// would pass unnoticed.
    @Test func theReceiverTypeIsTheDeclaringTypeNotTheCarrier() throws {
        // The recipe's carrier is `String`; the receiver is `Bool`. If the composer reached for
        // the carrier instead of the declaring type, generator0 would be a String.
        let source = try composedNary(types: ["Int"], receiver: "Bool")
        #expect(source.contains("generator0: Generator<Bool"), "receiver comes first, and is the declaring type")
    }

    /// Gated to match `receiverCallExpression` exactly: a mutating method falls back to the
    /// positional trampoline and has NO receiver argument, so widening the gate to
    /// `isInstanceMethod` alone would break the shape this was meant to fix.
    @Test func aMethodWithNoReceiverArgumentDrawsOnlyItsParameters() throws {
        let source = try composedNary(types: ["String"], receiver: nil)
        #expect(source.contains("defaultGenerator"))
        #expect(!source.contains("generator0"))
    }

    private func composedNary(
        types: [String],
        parameterCount: Int? = nil,
        receiver: String? = nil
    ) throws -> String {
        try StrategistDispatchEmitter.composePredicatePass(
            inputs: .init(
                carrier: "String",
                typeShape: nil,
                template: "predicate",
                functionCalls: ["subject"],
                extraImports: [],
                seedHex: .init(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
                trialBudget: .small,
                allShapes: [:],
                isInstanceMethod: false,
                isMutatingMethod: false,
                isNullary: false,
                returnsSelfType: false,
                isComputedProperty: false,
                parameterCount: parameterCount ?? types.count,
                parameterTypeNames: types,
                receiverTypeName: receiver
            ),
            recipe: .init(
                expression: "Gen<String>.string()",
                carrierTypeName: "String",
                imports: []
            )
        )
    }
}
