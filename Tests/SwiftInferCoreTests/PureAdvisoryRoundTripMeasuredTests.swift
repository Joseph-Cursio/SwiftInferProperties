import Foundation
import SwiftEffectInference
import SwiftInferTemplates
import Testing

@testable import SwiftInferCore

/// **Experiment with a standing verdict — read this header before building a
/// read-back for the `pure` advisory.** Open item 35, whose premise is wrong
/// about the mechanism and right about the consequence, and the difference
/// decides what a fix would have to be.
///
/// ## The premise, and what is actually there
///
/// Item 35 says `discover --effect-annotations` recommends `/// @lint.effect
/// pure` lines and *"nothing reads them back — one tool talking to itself in
/// English."*
///
/// **The channel is not outbound-only.** `FunctionScannerVisitor` calls
/// `EffectAnnotationParser.parseEffect(declaration:)` on every declaration and
/// stores the result as `FunctionSummary.declaredEffect`, and templates
/// genuinely consume it: `IdempotenceTemplate` scores `.idempotent` at +15 and
/// vetoes `.nonIdempotent` and `.externallyIdempotent`, `ReplayIdempotenceTemplate`
/// dispatches on two of the tiers, and `EffectResolver` uses its presence to
/// decide whether to infer at all. Write `@lint.effect non_idempotent` and the
/// tool reads it, believes it, and withdraws a law.
///
/// **What is inert is `pure` specifically, and deliberately so.**
/// `declaredEffectSignal` has an explicit `case .observational, .pure: return
/// nil`, and its comment argues the point: *"`pure` is orthogonal (`x + 1` is
/// pure and not idempotent). Staying silent is the claim."* That reasoning is
/// correct for idempotence. The trouble is that no *other* template consumes it
/// either, so the deliberate silence of one template is indistinguishable from
/// the total silence of the catalog.
///
/// So the accurate statement is not *nothing reads it back*. It is **acting on
/// the advice changes nothing**, which is a sharper claim and is what this
/// experiment measures.
///
/// ## Why this matters after item 34
///
/// Item 34 measured that no template gates on `purityVerdict` — the *inferred*
/// signal has no path to a law. This is the same finding for the *declared*
/// signal, at the other end of the round trip. Together they say the purity
/// vocabulary is complete in both directions and consumed in neither, which is
/// the root cause items 31–34 kept running into from different sides.
@Suite("Experiment — does taking the `pure` advice change anything?")
struct PureAdvisoryRoundTripMeasuredTests {

    typealias Corpus = PartialPurityConsumerMeasuredTests.Corpus

    static var corpora: [Corpus] { PartialPurityConsumerMeasuredTests.corpora }

    /// The same summary with `declaredEffect` set to `.pure` — the state the
    /// corpus would be in if every author took the advisory's recommendation.
    static func withDeclaredPure(_ summary: FunctionSummary) -> FunctionSummary {
        FunctionSummary(
            name: summary.name,
            parameters: summary.parameters,
            returnTypeText: summary.returnTypeText,
            isThrows: summary.isThrows,
            isAsync: summary.isAsync,
            isMutating: summary.isMutating,
            isStatic: summary.isStatic,
            location: summary.location,
            containingTypeName: summary.containingTypeName,
            bodySignals: summary.bodySignals,
            qualifiedContainingTypeName: summary.qualifiedContainingTypeName,
            discoverableGroup: summary.discoverableGroup,
            invariantKeypath: summary.invariantKeypath,
            isInferredPure: summary.isInferredPure,
            isClockDeterministic: summary.isClockDeterministic,
            declaresUnknownEffect: summary.declaresUnknownEffect,
            isComputedProperty: summary.isComputedProperty,
            isInitializer: summary.isInitializer,
            docComment: summary.docComment,
            declaredEffect: .pure,
            inferredEffect: summary.inferredEffect,
            purityVerdict: summary.purityVerdict,
            bodyFingerprint: summary.bodyFingerprint
        )
    }

    struct Arms {
        let corpus: String
        let advised: Int
        let baseline: Int
        let adviceTaken: Int
        /// Control: the same substitution with `.nonIdempotent`, a tier the
        /// catalog demonstrably *does* consume. If this moves nothing either,
        /// the harness is not reaching the consumers and the `pure` result is
        /// void rather than zero.
        let controlNonIdempotent: Int
    }

    static func arms(for corpus: Corpus) throws -> Arms {
        let scanned = try FunctionScanner.scanCorpus(directory: corpus.root)
        let summaries = scanned.summaries
        // Exactly the population `EffectAnnotationAdvice+Build` recommends the
        // annotation for, minus anything already annotated — advising a
        // declaration that already carries a tier is not the round trip.
        let advisable = summaries.filter { $0.isInferredPure && $0.declaredEffect == nil }

        func discover(_ input: [FunctionSummary]) -> Int {
            TemplateRegistry.discover(
                in: input, identities: scanned.identities, typeDecls: scanned.typeDecls
            ).count
        }
        func key(_ summary: FunctionSummary) -> String {
            "\(summary.location.file):\(summary.location.line):\(summary.location.column)"
        }
        let advisableIDs = Set(advisable.map(key))

        return Arms(
            corpus: corpus.name,
            advised: advisable.count,
            baseline: discover(summaries),
            adviceTaken: discover(summaries.map {
                advisableIDs.contains(key($0)) ? withDeclaredPure($0) : $0
            }),
            controlNonIdempotent: discover(summaries.map {
                advisableIDs.contains(key($0)) ? Self.withDeclared(.nonIdempotent, $0) : $0
            })
        )
    }

    static func withDeclared(_ effect: Effect, _ summary: FunctionSummary) -> FunctionSummary {
        let pure = withDeclaredPure(summary)
        return FunctionSummary(
            name: pure.name, parameters: pure.parameters, returnTypeText: pure.returnTypeText,
            isThrows: pure.isThrows, isAsync: pure.isAsync, isMutating: pure.isMutating,
            isStatic: pure.isStatic, location: pure.location,
            containingTypeName: pure.containingTypeName, bodySignals: pure.bodySignals,
            qualifiedContainingTypeName: pure.qualifiedContainingTypeName,
            discoverableGroup: pure.discoverableGroup, invariantKeypath: pure.invariantKeypath,
            isInferredPure: pure.isInferredPure, isClockDeterministic: pure.isClockDeterministic,
            declaresUnknownEffect: pure.declaresUnknownEffect,
            isComputedProperty: pure.isComputedProperty, isInitializer: pure.isInitializer,
            docComment: pure.docComment, declaredEffect: effect,
            inferredEffect: pure.inferredEffect, purityVerdict: pure.purityVerdict,
            bodyFingerprint: pure.bodyFingerprint
        )
    }

    static let measured: [Arms] = corpora.compactMap { try? arms(for: $0) }

    // MARK: - The verdict

    /// The control. `.nonIdempotent` is a tier `IdempotenceTemplate` vetoes on,
    /// so substituting it must move the count. Without this, "taking the advice
    /// changes nothing" is indistinguishable from a harness that never reached a
    /// template — which is exactly the failure mode item 34's corpus stub had.
    @Test("the declared-effect channel is reachable by this harness")
    func theChannelIsReachable() {
        #expect(!Self.measured.isEmpty, "no corpus scanned")
        #expect(Self.measured.allSatisfy { $0.advised > 0 }, "no corpus has an advisable population")
        let moved = Self.measured.filter { $0.controlNonIdempotent != $0.baseline }
        #expect(
            !moved.isEmpty,
            """
            Substituting `.nonIdempotent` — a tier the catalog demonstrably vetoes on — moved \
            nothing on any corpus. The `pure` result below is therefore void, not zero.
            """
        )
    }

    /// **The verdict: taking the advice changes nothing.** Every function the
    /// advisory would annotate, annotated, on three corpora — and the suggestion
    /// count does not move.
    ///
    /// The day this stops holding, some template has learned to consume declared
    /// purity and item 35 is worth re-opening.
    @Test("annotating every advised function changes no suggestion")
    func takingTheAdviceChangesNothing() {
        for arm in Self.measured {
            #expect(
                arm.adviceTaken == arm.baseline,
                """
                \(arm.corpus): annotating \(arm.advised) advised functions moved the count \
                \(arm.baseline) → \(arm.adviceTaken). Something now consumes declared purity — \
                re-read docs/measurements/pure-advisory-round-trip.md.
                """
            )
        }
    }

    @Test("experiment — the pure advisory's round trip")
    func experiment() {
        var lines: [String] = []
        for arm in Self.measured {
            lines.append("\(arm.corpus):")
            lines.append("  functions the advisory would annotate: \(arm.advised)")
            lines.append("  suggestions — baseline \(arm.baseline)"
                + " · advice taken \(arm.adviceTaken) (\(arm.adviceTaken - arm.baseline))"
                + " · control .nonIdempotent \(arm.controlNonIdempotent)"
                + " (\(arm.controlNonIdempotent - arm.baseline))")
        }
        print(lines.joined(separator: "\n"))
    }
}
