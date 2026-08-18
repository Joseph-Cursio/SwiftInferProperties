import Foundation
import SwiftEffectInference
import SwiftInferTemplates
import Testing

@testable import SwiftInferCore

/// **Experiment with a standing verdict — read this header before building a
/// consumer for `PurityVerdict.pureButPartial`.** Open item 34, which item 31's
/// census promoted from a loose end to a precondition for items 31–33.
///
/// ## What item 34 actually asks
///
/// `.pureButPartial` means *deterministic wherever it is defined* — it throws,
/// so it has no answer on part of its domain, but it passed every impurity and
/// nondeterminism refuter. `SoundPurity`'s doc records that **nothing consumes
/// it**, deliberately: the one live consumer of the purity signal is the
/// `/// @lint.effect pure` advisory, and a partial function cannot honestly take
/// that annotation.
///
/// The row asks for *"a consumer that can narrow a law's domain to the
/// non-throwing inputs."* Before building one, two facts had to be established.
///
/// ## Fact one — purity gates no law, but `throws` gates several
///
/// `isInferredPure` is read in exactly **one** place in the shipped sources
/// (`EffectAnnotationAdvice+Build`), and `purityVerdict` is read in none. No
/// template consults either; the ones that care about effects gate on
/// `declaredEffect`, which is the linter's *annotation*, not this inference.
///
/// **`isThrows`, however, is a hard gate in at least eight places** —
/// `InvolutionTemplate`, `HomomorphismTemplate`, `EquivalenceRelationTemplate`,
/// `CaseIterableMappingTemplate`, `SetRelationModelPairing`,
/// `OverridePrecedenceTemplate`, and two TestLifter detectors that name the
/// decline (`.producerThrows`, `.predicateThrows`).
///
/// So the shape of item 34 is not *"give the advisory something to say"*. It is
/// *"`.pureButPartial` is the licence to relax a `throws` gate that eight
/// templates apply unconditionally."* That is a much better item than the one
/// filed, and it is the first in this sequence whose leverage would land in law
/// emission rather than in an advisory nobody reads.
///
/// ## Fact two — what relaxing that gate would actually buy
///
/// Measured below, and the instrument is deliberately generous.
///
/// **Masking `isThrows` is an upper bound, not the build.** A real
/// domain-narrowed law would emit `try?` and compare optionals; masking makes
/// the templates emit a law that calls `f(x)` bare, which would not compile.
/// What the arms measure is therefore *how many candidates the gate is holding
/// back* — the ceiling — in the same sense that a decline-reason tally is a
/// ceiling on what a fix frees. The standing ratio on that is ~5:1 against.
///
/// Three arms, because the decomposition is the finding:
///
/// - **baseline** — the shipped answer.
/// - **partial** — `isThrows` masked on `.pureButPartial` summaries only. This
///   is item 34's own ceiling.
/// - **allThrowing** — `isThrows` masked on *every* throwing summary. The gate's
///   total ceiling, whatever the purity verdict. The gap between this and
///   `partial` is what the purity distinction is buying; if they are equal, the
///   verdict is not doing any work and a cheaper signal would serve.
/// **Named `…MeasuredTests` on purpose, though it is an experiment.** The name
/// is what `SUBPROCESS_RE` matches, and this suite parses three corpora and runs
/// discovery six times — ~110s. Left as `…ExperimentTests` it ran in the fast
/// path *and* in batch2, taking the developer loop from ~50s to ~172s. The
/// sibling censuses carry the same suffix for the same reason.
@Suite("Experiment — is there anything for a .pureButPartial consumer to consume?")
struct PartialPurityConsumerMeasuredTests {

    /// A corpus to run all three arms over. Two, because this repo's own
    /// `Sources/` is CLI code and the throws-gated templates are algebraic —
    /// measuring only here would answer a question about command plumbing.
    struct Corpus {
        let name: String
        let root: URL
    }

    static let packageRoot = PurityRefutationCensusMeasuredTests.packageRoot

    /// **`fixtures/cycle27-surface/Sources` is NOT the v1 corpus**, and pointing
    /// an arm there is the mistake this comment exists to stop the next person
    /// repeating. That target is an empty stub whose only job is to give SwiftPM
    /// something to resolve dependencies into; its own `Stub.swift` says so. The
    /// corpus is the **resolved checkouts**, which is where `swift-infer index`
    /// reads too. Scanning the stub returns 0 summaries and 0 suggestions, which
    /// reads exactly like a measured zero and is not one.
    static let corpora: [Corpus] = [
        Corpus(name: "self (Sources/, CLI)", root: packageRoot.appendingPathComponent("Sources")),
        Corpus(
            name: "swift-collections/OrderedCollections (v1 corpus, third-party)",
            root: packageRoot.appendingPathComponent(
                "fixtures/cycle27-surface/.build/checkouts/swift-collections/Sources/OrderedCollections"
            )
        ),
        Corpus(
            name: "SwiftPropertyLaws (sibling library)",
            root: packageRoot
                .deletingLastPathComponent()
                .appendingPathComponent("SwiftPropertyLaws/Sources")
        )
    ]

    /// The same summary with `isThrows` forced to `false`. Every other field is
    /// carried across verbatim — a copy that quietly dropped `declaredEffect` or
    /// `bodySignals` would change the arms for reasons that have nothing to do
    /// with the gate under test.
    static func withThrowsMasked(_ summary: FunctionSummary) -> FunctionSummary {
        FunctionSummary(
            name: summary.name,
            parameters: summary.parameters,
            returnTypeText: summary.returnTypeText,
            isThrows: false,
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
            declaredEffect: summary.declaredEffect,
            inferredEffect: summary.inferredEffect,
            purityVerdict: summary.purityVerdict,
            bodyFingerprint: summary.bodyFingerprint
        )
    }

    struct Arms {
        let corpus: String
        let summaries: Int
        let throwing: Int
        let partial: Int
        let baseline: Int
        let gainedDescriptions: [String]
        let partialMasked: Int
        let allThrowingMasked: Int
    }

    static func arms(for corpus: Corpus) throws -> Arms {
        let scanned = try FunctionScanner.scanCorpus(directory: corpus.root)
        let summaries = scanned.summaries

        func suggestions(_ input: [FunctionSummary]) -> [Suggestion] {
            TemplateRegistry.discover(
                in: input, identities: scanned.identities, typeDecls: scanned.typeDecls
            )
        }
        func discover(_ input: [FunctionSummary]) -> Int { suggestions(input).count }

        let base = suggestions(summaries)
        let baseIdentities = Set(base.map(\.identity.normalized))
        let gained = suggestions(summaries.map {
            $0.isThrows ? withThrowsMasked($0) : $0
        }).filter { !baseIdentities.contains($0.identity.normalized) }

        return Arms(
            corpus: corpus.name,
            summaries: summaries.count,
            throwing: summaries.filter(\.isThrows).count,
            partial: summaries.filter { $0.purityVerdict == .pureButPartial }.count,
            baseline: base.count,
            gainedDescriptions: gained.map { "\($0.templateName) :: \($0.identity.normalized)" }.sorted(),
            partialMasked: discover(summaries.map {
                $0.purityVerdict == .pureButPartial ? withThrowsMasked($0) : $0
            }),
            allThrowingMasked: discover(summaries.map {
                $0.isThrows ? withThrowsMasked($0) : $0
            })
        )
    }

    static let measured: [Arms] = corpora.compactMap { try? arms(for: $0) }

    // MARK: - The verdict

    /// The instrument is not blind: masking `isThrows` on **every** throwing
    /// function must move *something*, or the arms below are measuring a
    /// pipeline that ignores the field and every number is meaningless.
    ///
    /// This is the control that item 34's verdict rests on. A `.pureButPartial`
    /// ceiling of zero means one thing if the gate is real and quite another if
    /// the harness never reached the templates.
    @Test("the throws gate is reachable by this harness at all")
    func theGateIsReachable() {
        #expect(!Self.measured.isEmpty, "no corpus scanned")
        // A corpus that scanned nothing is a broken arm, not a measured zero.
        let empty = Self.measured.filter { $0.summaries == 0 }
        #expect(empty.isEmpty, "scanned 0 summaries: \(empty.map(\.corpus))")
        let moved = Self.measured.filter { $0.allThrowingMasked != $0.baseline }
        #expect(
            !moved.isEmpty,
            """
            Masking `isThrows` on every throwing summary moved no suggestion on any corpus. \
            Either no template gates on it any more, or this harness is not reaching them — \
            in both cases item 34's ceiling below is void, not zero.
            """
        )
    }

    /// **Item 34's ceiling.** Asserted as a direction rather than an integer
    /// because both corpora grow; what must not drift is whether the
    /// `.pureButPartial` population is holding back a meaningful number of
    /// candidates.
    @Test("item 34's ceiling is a small fraction of the throws gate's total")
    func thePartialCeilingIsSmall() {
        for arm in Self.measured {
            let partialGain = arm.partialMasked - arm.baseline
            let totalGain = arm.allThrowingMasked - arm.baseline
            #expect(
                partialGain <= totalGain,
                "\(arm.corpus): partial arm gained \(partialGain), total gained \(totalGain)"
            )
        }
    }

    /// **The verdict, asserted so it cannot drift.** Across all corpora, the
    /// `throws` gate is holding back a handful of candidates, not a population.
    /// Measured 2026-08-17: 363 throwing functions over three corpora, of which
    /// 46 are `.pureButPartial`, and relaxing the gate **entirely** buys **+2**
    /// suggestions — both `subset` laws on one `private` CLI helper, of which
    /// item 34's population accounts for one.
    ///
    /// Bounded against the throwing population rather than stated as `2`, since
    /// all three corpora grow. The direction that matters: if relaxing this gate
    /// ever reaches even a tenth of the throwing functions, `.pureButPartial`
    /// becomes a signal worth consuming and item 34 should be re-opened.
    @Test("relaxing the throws gate reaches almost none of the throwing population")
    func theGateHoldsBackAlmostNothing() {
        for arm in Self.measured {
            let totalGain = arm.allThrowingMasked - arm.baseline
            #expect(
                totalGain * 10 < max(arm.throwing, 1),
                """
                \(arm.corpus): relaxing `throws` moved \(totalGain) suggestions against \
                \(arm.throwing) throwing functions. Item 34 was declined at a far lower ratio — \
                re-read docs/measurements/partial-purity-consumer-declined.md before building.
                """
            )
        }
    }

    @Test("experiment — what a .pureButPartial consumer could reach")
    func experiment() {
        var lines: [String] = []
        for arm in Self.measured {
            lines.append("\(arm.corpus):")
            lines.append("  summaries \(arm.summaries) · throwing \(arm.throwing) · pureButPartial \(arm.partial)")
            for gain in arm.gainedDescriptions { lines.append("  GAINED: \(gain)") }
            lines.append("  suggestions — baseline \(arm.baseline)"
                + " · partial-masked \(arm.partialMasked) (+\(arm.partialMasked - arm.baseline))"
                + " · all-throwing-masked \(arm.allThrowingMasked) (+\(arm.allThrowingMasked - arm.baseline))")
        }
        print(lines.joined(separator: "\n"))
    }
}
