import Foundation
import SwiftEffectInference
import SwiftSyntax
import Testing

@testable import SwiftInferCore

/// **Census with a standing verdict — read this header before adding an
/// allowlist of known-pure operations to `PurityInferrer`.** Same form as
/// `PurityRefutationCensusMeasuredTests`, whose corpus and taxonomy it reuses
/// wholesale, and for the same reason: the build is only warranted if the
/// measurement comes back a particular way.
///
/// ## The question
///
/// `PurityInferrer` documents *"any doubt refutes"* and its marker sets *"err
/// toward flagging"*. That is true of the tokens they **recognise**. There is no
/// allowlist, so a call to a name in neither marker set refutes nothing and the
/// caller stays `.pure`.
///
/// The error direction is the opposite of the documented one, and the two are
/// not the same kind of mistake. `Date(timeIntervalSince1970:)` over-refutes
/// **deliberately** — the token scan cannot tell it from `Date()`, and
/// withholding `.pure` is the sound direction on the effect lattice. An
/// unrecognised callee under-refutes **accidentally**, and `.pure` is the
/// lattice bottom every downstream consumer trusts.
///
/// So, before building anything: **what does the current default actually
/// cost, and what would replacing it actually cost?** Three numbers, and the
/// third is the one that decides it.
///
/// 1. **Exposure** — how many non-refuted verdicts rest on at least one callee
///    this leaf never examined. This is the population that becomes item 29's
///    ignorance case the day the default flips.
/// 2. **Price** — how large a seed set of asserted-pure operations must be to
///    hold today's population, and how that size grows against coverage.
/// 3. **Base rate** — how many `.pure` verdicts are unsound *by this analyzer's
///    own lights*: the caller was called pure while calling a function the same
///    analyzer refutes, with a witness, in the same package.
///
/// The third is the item 40 question asked of item 30. An unchecked claim whose
/// measured error rate is zero is a narrower finding than an unsound one, and
/// the two warrant very different builds.
///
/// ## What this census cannot see, stated before the numbers
///
/// - **Call expressions only.** `x.count` runs a getter too, and admitting
///   property reads would widen the exposure by an amount not measured here.
///   Every exposure number below is therefore a **lower bound**.
/// - **Names, not symbols.** There is no IndexStore in any of the five packages
///   (open item 38), so package resolution is by bare name and overloads
///   collapse. The unsoundness list guards against that in the one direction it
///   matters: a name counts as a refuted callee only when **every** declaration
///   carrying it is refuted with a witness.
/// - **One package.** A callee in a sibling repo is `unrecognised` here and
///   would be resolvable to a build that could see it. That is attrition on the
///   price, not on the exposure.
@Suite("Census — what does an unrecognised callee cost?")
struct PurityAllowlistCensusMeasuredTests {

    // The taxonomy, the collector and the seed-set arithmetic are in
    // `PurityAllowlistCensusMeasuredTests+Support.swift`, split out for the
    // 400-line file cap only.

    // MARK: - The corpus

    /// Reused verbatim from the item 29 census: every function under `Sources/`
    /// collected with `FunctionScannerVisitor`'s own traversal rules. Sharing
    /// the static shares the parse — this suite adds a body walk per subject,
    /// not a second scan of the tree.
    typealias Subject = PurityRefutationCensusMeasuredTests.Subject

    static var corpus: [Subject] { PurityRefutationCensusMeasuredTests.corpus }

    static var verdicts: [PurityVerdict] { PurityRefutationCensusMeasuredTests.verdicts }

    /// Every function name declared in the corpus, and — separately — the names
    /// whose declarations are **all** refuted **and** carry a witness.
    ///
    /// The `all` is load-bearing. Under name-keyed resolution a single pure
    /// overload is enough to make a caller's `.pure` verdict defensible, so a
    /// name with any pure, partial, or ignorance-refuted declaration is excluded
    /// from the unsoundness list. The list is a set of positive claims and
    /// cannot afford the approximation the exposure numbers can.
    struct DeclaredNames {
        let all: Set<String>
        let refutedWithWitness: Set<String>
        let causes: [String: Set<PurityRefutationCensusMeasuredTests.RefutationCause>]
    }

    static let declaredNames: DeclaredNames = {
        let attributor = PurityRefutationCensusMeasuredTests.Attributor()
        var witnessedByName: [String: [Bool]] = [:]
        var causesByName: [String: Set<PurityRefutationCensusMeasuredTests.RefutationCause>] = [:]
        for (subject, verdict) in zip(corpus, verdicts) {
            let causes = verdict == .refuted ? attributor.causes(of: subject.function) : []
            witnessedByName[subject.name, default: []].append(causes.contains(where: \.isWitness))
            causesByName[subject.name, default: []].formUnion(causes)
        }
        let refuted = witnessedByName.filter { $0.value.allSatisfy(\.self) }
        return DeclaredNames(
            all: Set(witnessedByName.keys),
            refutedWithWitness: Set(refuted.keys),
            causes: causesByName
        )
    }()

    /// One profile per subject whose purity was **not** refuted — the population
    /// item 30 is about. `.pureButPartial` is kept and reported separately: its
    /// `throwsOnlyItsOwnErrors` gate already refuses any `try` into a callee, so
    /// it is a different exposure and averaging the two would hide that.
    static let profiles: [CallProfile] = zip(corpus, verdicts)
        .filter { $0.1 != .refuted }
        .map { subject, verdict in
            let collector = CensusCalleeCollector(viewMode: .sourceAccurate)
            if let body = subject.function.body { collector.walk(body) }
            let markers = PurityRefutationCensusMeasuredTests.Attributor.sideEffectMarkers
                .union(PurityRefutationCensusMeasuredTests.Attributor.nondeterministicMarkers)
            var byOrigin: [CalleeOrigin: Set<Callee>] = [:]
            for callee in collector.callees {
                let origin: CalleeOrigin
                if markers.contains(callee.name) {
                    origin = .marker
                } else if collector.nestedFunctionNames.contains(callee.name) {
                    origin = .nested
                } else if declaredNames.all.contains(callee.name) {
                    origin = .package
                } else {
                    origin = .unrecognised
                }
                byOrigin[origin, default: []].insert(callee)
            }
            return CallProfile(subject: subject, verdict: verdict, byOrigin: byOrigin)
        }

    static var pureProfiles: [CallProfile] { profiles.filter { $0.verdict == .pure } }

    /// **The base rate.** A `.pure` subject calling a package function that this
    /// same analyzer refutes with a witness — the caller was vouched for while
    /// calling something the oracle itself says is impure, non-total or async.
    ///
    /// **Free-shape callees only, and the exclusion is the finding it looks
    /// like a caveat for.** Name-keyed resolution cannot survive the member
    /// shape: `xs.sorted()` is the stdlib method, and this package happens to
    /// declare a `sorted(in:)` that reads `FileManager` and is duly refuted, so
    /// every `.sorted()` in the corpus reads as a call into an impure package
    /// function. Same for `.fileExists`, `.standardOutput`. Admitting the member
    /// shape produced 150 candidates of which the overwhelming majority were
    /// that collision. A bare `foo(…)` resolves to something visible in the
    /// file's own scope, which is a claim name-keying can nearly support — and
    /// the survivors are spot-checked by hand, listed in the measurements doc.
    static let unsound: [(profile: CallProfile, callees: [String])] = pureProfiles.compactMap {
        let refuting = $0.packageCallees
            .filter { $0.shape == .free && declaredNames.refutedWithWitness.contains($0.name) }
            .map(\.name)
        return refuting.isEmpty ? nil : ($0, refuting.sorted())
    }

    /// The member-shape count the line above refuses to use, kept so the census
    /// can print the size of what it discarded rather than merely asserting it
    /// was noise.
    static let unsoundIfMemberShapeAdmitted: Int = pureProfiles.filter {
        $0.packageCallees.contains { declaredNames.refutedWithWitness.contains($0.name) }
    }.count

    /// **The finding this census was not looking for.** A marker in a *default
    /// argument* is invisible: `bodyHasRefutingMarker` is handed
    /// `function.body`, and a default value lives in the signature. So
    /// `func bridges(…, now: Date = Date()) -> [BridgeSuggestion]` reads the
    /// clock on every call that omits the argument and is judged `.pure`.
    ///
    /// Scanned over the **default-value expressions only**, never the whole
    /// signature: `func f(_ d: Date)` mentions the `Date` marker in a parameter
    /// *type* and is perfectly pure — taking a value is not reading a clock. A
    /// whole-signature scan would report that as a defect and it is not one.
    static let markerInDefaultArgument: [(subject: Subject, markers: [String])] = {
        let markers = PurityRefutationCensusMeasuredTests.Attributor.sideEffectMarkers
            .union(PurityRefutationCensusMeasuredTests.Attributor.nondeterministicMarkers)
        return profiles.compactMap { profile in
            let found = profile.subject.function.signature.parameterClause.parameters
                .compactMap(\.defaultValue?.value)
                .flatMap { $0.tokens(viewMode: .sourceAccurate).map(\.text) }
                .filter(markers.contains)
            return found.isEmpty ? nil : (profile.subject, Array(Set(found)).sorted())
        }
    }()

    // MARK: - The control

    /// A non-refuted body cannot contain a marker token — that is what the
    /// marker sets *do*. Measuring zero here is what tells a reader the callee
    /// classification is wired to the same names the verdict was computed from,
    /// rather than to a set that has drifted.
    ///
    /// Without it, "the unrecognised bucket is large" is indistinguishable from
    /// a classifier that puts everything in it.
    @Test("no non-refuted body calls a marker — the classification is wired to the real sets")
    func markerOriginIsUnreachable() {
        let offenders = Self.profiles.filter { !($0.byOrigin[.marker] ?? []).isEmpty }
        #expect(
            offenders.isEmpty,
            "\(offenders.count) non-refuted subjects call a marker: \(offenders.prefix(5).map(\.subject.name))"
        )
    }

    /// The population is the one the item 29 census divided, minus its refuted
    /// half. If these stop agreeing, one of the two suites is reading a corpus
    /// the other is not.
    @Test("the profiled population is exactly the non-refuted half of the item 29 corpus")
    func populationAgreesWithTheRefutationCensus() {
        let refutedCount = Self.verdicts.filter { $0 == .refuted }.count
        #expect(Self.profiles.count == Self.corpus.count - refutedCount)
        #expect(Self.corpus.count > 2_000, "corpus is \(Self.corpus.count) functions")
    }

    // MARK: - The census

    /// Prints the whole census. Not an assertion — the assertions are in
    /// `PurityAllowlistCensusMeasuredTests+Verdict.swift`; this is what gets
    /// transcribed into the measurements doc, with the tree SHA.
    @Test("census — what the pure population rests on")
    func census() {
        print((Self.exposureLines + Self.priceLines + Self.baseRateLines).joined(separator: "\n"))
    }

    /// Number 1 — how many non-refuted verdicts rest on a callee never examined.
    static var exposureLines: [String] {
        var lines: [String] = ["corpus (Sources/, scanner traversal rules): \(Self.corpus.count) functions"]
        lines.append("non-refuted: \(Self.profiles.count)")
        for verdict in [PurityVerdict.pure, .pureButPartial] {
            lines.append("  \(verdict): \(Self.profiles.filter { $0.verdict == verdict }.count)")
        }

        lines.append("exposure — non-refuted subjects reaching at least one callee, by origin:")
        for origin in CalleeOrigin.allCases.sorted() {
            let count = Self.profiles.filter { !($0.byOrigin[origin] ?? []).isEmpty }.count
            lines.append("  \(origin.rawValue): \(count)")
        }
        let blocked = Self.profiles.filter { !$0.unrecognised.isEmpty }
        let calls = Self.profiles.filter { profile in
            CalleeOrigin.allCases.contains { !(profile.byOrigin[$0] ?? []).isEmpty }
        }
        lines.append("  (calls anything at all: \(calls.count))")
        lines.append("  blocked by >=1 unrecognised callee: \(blocked.count)")
        lines.append("  .pure only: \(Self.pureProfiles.filter { !$0.unrecognised.isEmpty }.count) "
            + "of \(Self.pureProfiles.count)")
        return lines
    }

    /// Number 2 — how large a seed set of asserted axioms must be to hold that
    /// population, under both readings of "hold".
    static var priceLines: [String] {
        var lines = ["price — distinct unrecognised callees, by shape:"]
        let distinct = Set(Self.profiles.flatMap(\.unrecognised))
        for shape in CallShape.allCases.sorted() {
            lines.append("  \(shape.rawValue): \(distinct.filter { $0.shape == shape }.count)")
        }
        lines.append("  total: \(distinct.count)")
        lines.append("  frequency-ordered seed set (touched = what a frequency table reports,")
        lines.append("  freed = subjects whose WHOLE unrecognised set is admitted):")
        for size in [10, 25, 50, 100, 200, 400] {
            let coverage = Self.coverage(ofTopMostFrequent: size, over: Self.profiles)
            lines.append("    top \(coverage.size): touched \(coverage.touched) · freed \(coverage.freed)")
        }
        lines.append("  greedy-with-recompute, axioms needed to free each decile of the blocked:")
        for step in Self.greedySeedSetSizes(freeingDecilesOf: Self.profiles) {
            lines.append("    \(step.decile)%: \(step.size.map(String.init) ?? "not reached")")
        }

        let suspect = Self.profiles.filter { profile in
            profile.packageCallees.contains { $0.shape == .member }
        }.count
        lines.append("  subjects whose `package` classification rests on a member-shape name: \(suspect)")
        return lines
    }

    /// Number 3 — how many `.pure` verdicts are unsound by this analyzer's own
    /// lights, plus the finding the census was not looking for.
    static var baseRateLines: [String] {
        var lines = ["base rate — .pure subjects calling a package function refuted WITH a witness:"]
        lines.append("  free-shape only (the usable number): \(Self.unsound.count)")
        lines.append("  if member-shape were admitted: \(Self.unsoundIfMemberShapeAdmitted)")
        for entry in Self.unsound.prefix(40) {
            let annotated = entry.callees.map { callee -> String in
                let causes = (Self.declaredNames.causes[callee] ?? [])
                    .sorted()
                    .map(\.rawValue)
                    .joined(separator: "+")
                return "\(callee) [\(causes)]"
            }
            lines.append("    \(entry.profile.subject.file):\(entry.profile.subject.name)"
                + " -> \(annotated.joined(separator: ", "))")
        }

        lines.append("second under-refutation — a marker in a DEFAULT ARGUMENT, which the body scan"
            + " never sees: \(Self.markerInDefaultArgument.count)")
        for entry in Self.markerInDefaultArgument.prefix(40) {
            lines.append("    \(entry.subject.file):\(entry.subject.name)"
                + " -> \(entry.markers.joined(separator: ", "))")
        }
        return lines
    }
}
