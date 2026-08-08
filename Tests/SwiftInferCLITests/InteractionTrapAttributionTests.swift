import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Attributing a verifier trap to the harness's invariant check or to the
/// subject's own code.
///
/// ``InteractionVerifyOutcomeParser`` maps every non-zero exit to
/// `.measuredDefaultFails`, defending it on the grounds that "the reducer
/// panicked under some action sequence, which IS a real signal." That holds for a
/// reducer — total over its action alphabet by construction — and is the open
/// question for a carrier whose methods carry preconditions of their own, where an
/// unguarded random sequence can trap for reasons that say nothing about the
/// invariant.
///
/// These tests pin the attribution, not a verdict. The verdict deliberately does
/// not move yet; see ``InteractionVerifyOutcomeParser/TrapOrigin``.
@Suite("Interaction verify — attributing a trap to the check or to the subject")
struct InteractionTrapAttributionTests {

    private static let marker = ActionSequenceStubEmitter.invariantViolationMarker

    // MARK: - Attribution

    @Test("the marker on stderr attributes the trap to the invariant check")
    func markerAttributesToInvariantCheck() {
        let stderr = """
            TRACE-CURRENT-SEQ: 7
            Precondition failed: \(Self.marker) Cardinality invariant violated
            """
        let result = InteractionVerifyOutcomeParser.parseRunOutput(
            binaryExitCode: 5, stdout: "", stderr: stderr
        )

        #expect(result.outcome == .measuredDefaultFails)
        #expect(result.trapOrigin == .invariantCheck)
        #expect(result.failingSequenceIndex == 7)
        #expect(result.detail?.contains("property refuted") == true)
    }

    @Test("a trap mid-sequence with no marker is attributed to the subject's code")
    func unmarkedTrapMidSequenceAttributesToSubject() {
        let stderr = """
            TRACE-CURRENT-SEQ: 3
            Fatal error: Index out of range
            """
        let result = InteractionVerifyOutcomeParser.parseRunOutput(
            binaryExitCode: 4, stdout: "", stderr: stderr
        )

        #expect(result.outcome == .measuredDefaultFails, "the verdict must NOT move yet")
        #expect(result.trapOrigin == .subjectCode)
        #expect(result.detail?.contains("not the invariant check") == true)
    }

    /// The honest third answer. Folding this into `.subjectCode` would inflate
    /// exactly the count the split exists to measure.
    @Test("a trap before any sequence is unattributable, not a subject trap")
    func trapBeforeFirstSequenceIsUnattributable() {
        let result = InteractionVerifyOutcomeParser.parseRunOutput(
            binaryExitCode: 4, stdout: "", stderr: "Fatal error: unexpectedly found nil"
        )

        #expect(result.trapOrigin == .unattributable)
        #expect(result.failingSequenceIndex == nil)
    }

    /// Absence of the marker is weak evidence, so it must never *alone* convict the
    /// subject. A harness that stopped emitting the marker would otherwise turn a
    /// corpus of real refutations into a corpus of "artifacts" — the conclusion
    /// this measurement is supposed to test, arrived at by a bug.
    @Test("attribution needs positive evidence, not just a missing marker")
    func missingMarkerAloneDoesNotConvictTheSubject() {
        #expect(
            InteractionVerifyOutcomeParser.attributeTrap(stderr: "", failingIndex: nil)
                == .unattributable
        )
        #expect(
            InteractionVerifyOutcomeParser.attributeTrap(stderr: "", failingIndex: 0)
                == .subjectCode
        )
    }

    @Test("a clean run carries no attribution")
    func cleanRunHasNoTrapOrigin() {
        let result = InteractionVerifyOutcomeParser.parseRunOutput(
            binaryExitCode: 0,
            stdout: "\(ActionSequenceStubEmitter.cleanOutcomeMarker) totalRuns=16 clean=16"
        )

        #expect(result.outcome == .measuredBothPass)
        #expect(result.trapOrigin == nil)
    }

    /// A launch failure already routes to `.measuredError` and never reaches
    /// attribution — pinned because that ordering is what keeps a dyld crash out
    /// of the split.
    @Test("a launch failure is still measuredError, with no attribution")
    func launchFailureIsNotAttributed() {
        let result = InteractionVerifyOutcomeParser.parseRunOutput(
            binaryExitCode: 1,
            stdout: "",
            stderr: "dyld[123]: Library not loaded: @rpath/libTesting.dylib"
        )

        #expect(result.outcome == .measuredError)
        #expect(result.trapOrigin == nil)
    }

    // MARK: - The guard that matters

    /// **Every family this emitter verifies must mark its check.** An unmarked
    /// check is not a cosmetic gap: its trap gets attributed to `.subjectCode`,
    /// so a genuine refutation is filed as a generator artifact — the
    /// false-negative direction, and invisible, because both still render as
    /// `.measuredDefaultFails`.
    ///
    /// Driven off `CaseIterable` rather than a hand-written list, so a family
    /// added later fails here instead of quietly joining the artifact pile.
    /// `outputDeterminism` is excluded because a different emitter verifies it;
    /// this one only traps to say it was misrouted, which is a harness bug and
    /// correctly unattributed.
    @Test(
        "every verified family marks its invariant check",
        arguments: InteractionInvariantFamily.allCases.filter { $0 != .outputDeterminism }
    )
    func everyFamilyMarksItsCheck(family: InteractionInvariantFamily) throws {
        let source = try ActionSequenceStubEmitter.emit(
            Self.inputs(invariant: Self.invariant(family: family))
        )

        let checks = source
            .components(separatedBy: "\n")
            .filter { $0.contains("precondition(") }
        try #require(!checks.isEmpty, "\(family.rawValue) emitted no check to attribute")

        for check in checks {
            #expect(
                check.contains(Self.marker),
                """
                \(family.rawValue) emits an unmarked `precondition`, so its trap will \
                be attributed to the subject and a real refutation will read as a \
                generator artifact:
                \(check.trimmingCharacters(in: .whitespaces))
                """
            )
        }
    }

    // MARK: - Fixtures

    private static func invariant(family: InteractionInvariantFamily) -> InteractionInvariantSuggestion {
        // Idempotence and unknown-action key on an action shorthand; the
        // state-predicate families key on a boolean over State.
        let predicate: String
        switch family {
        case .idempotence, .unknownActionIsNoOp:
            predicate = ".refresh"

        default:
            predicate = "state.count == state.items.count"
        }
        let canonical = InteractionInvariantSuggestion.identityCanonicalInput(
            family: family,
            reducerQualifiedName: "reduce",
            predicate: predicate
        )
        return InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            family: family,
            reducerQualifiedName: "reduce",
            reducerLocation: "Sources/MyApp/F.swift:1",
            stateTypeName: "AppState",
            actionTypeName: "AppAction",
            predicate: predicate,
            score: 30,
            tier: .possible,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: ISO8601DateFormatter().date(from: "2026-05-15T10:00:00Z")!
        )
    }

    private static func inputs(
        invariant: InteractionInvariantSuggestion
    ) -> ActionSequenceStubEmitter.Inputs {
        ActionSequenceStubEmitter.Inputs(
            candidate: ReducerCandidate(
                location: "Sources/MyApp/F.swift:1",
                enclosingTypeName: nil,
                functionName: "reduce",
                signatureShape: .stateActionReturnsState,
                stateTypeName: "AppState",
                actionTypeName: "AppAction",
                carrierKind: .elmStyle
            ),
            userModuleName: "MyApp",
            sequenceCount: 16,
            invariant: invariant
        )
    }
}
