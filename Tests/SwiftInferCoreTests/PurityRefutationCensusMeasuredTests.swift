import Foundation
import SwiftEffectInference
import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftInferCore

/// **Census with a standing verdict — read this header before building anything
/// that ranks, reports on, or unblocks the `PurityVerdict.refuted` bucket.**
/// Same form as `DomainTransferSignalExperimentTests` and
/// `TriviaInsensitivityExperimentTests`: a test file whose job is to hold a
/// measured answer that no doc restates.
///
/// ## The question
///
/// `PurityVerdict.refuted`'s own doc says it means *"an impurity or
/// nondeterminism refuter fired, **or** the shape could not be inspected at
/// all."* Those are different facts and only the first is a finding. The second
/// is the analyzer reporting its own blindness in the same token it reports
/// evidence with.
///
/// So: **of the `.refuted` verdicts this repo's own scan produces, how many
/// carry a witness and how many are ignorance?** The answer decides whether a
/// blocking-callee index, a leverage ranking, or a parameterised-purity analysis
/// are worth building at all. If ignorance is a rounding error there is no
/// bucket to rank; if it is most of them, it is the largest unread population in
/// the toolchain.
///
/// The 2026-08-04 figure — 2,206 `.pure` / 35 `.pureButPartial` / 259 `.refuted`
/// of 2,500 — is **deliberately not reused**. It was taken on a different binary
/// and a smaller tree, and it is the *undivided* number this census exists to
/// divide.
///
/// ## The taxonomy, frozen before the run
///
/// Read off `PurityInferrer.verdict(for:)` and `SoundPurity.verdict(for:)` — one
/// cause per `guard`, not invented for this census. See `RefutationCause`.
///
/// **A witness is a named construct present in the source.** `print`, `Date()`,
/// a force-unwrap, an `await`. The analyzer can point at it. A witness may still
/// be a *wrong* refutation — `Date(timeIntervalSince1970:)` is deterministic and
/// is refuted anyway, deliberately — but it is a claim about the code.
///
/// **Ignorance is the absence of a witness.** Nothing in the body refutes
/// purity; the analyzer withheld `.pure` because it could not see far enough.
/// Two shapes, and they are not equally useful:
///
/// - `.propagatedTry` — **actionable ignorance.** The body says `try` into a
///   callee this leaf cannot resolve. There is a named callee behind it, so a
///   cross-file join or an annotation can settle it.
/// - `.noBody` — **inert ignorance.** A protocol requirement has no body and
///   never will. Nothing can unblock it.
///
/// A leverage ranking's denominator is the actionable half alone, which is the
/// first thing this census is for.
///
/// ## The verdict
///
/// Asserted below rather than described, so it cannot drift. Exact counts and
/// their provenance are in `docs/measurements/purity-refuted-bucket-census.md`.
///
/// ## Why the replication is trustworthy
///
/// `PurityInferrer`'s refuters are `private`, so attributing a cause means
/// re-deriving them here. That would normally be a drift trap. It is not one,
/// because `verdictAgreesWithSoundPurity` re-assembles a **whole verdict** out
/// of the replicated pieces and asserts it equals `SoundPurity.verdict(for:)`
/// for **every function in the corpus**. A marker this file is missing, a marker
/// it has spuriously, a totality rule that moved — each shows up as a mismatch
/// on some real function and voids the census loudly instead of quietly
/// misattributing it. `truncatedMarkerSetIsDetected` is the control: it removes
/// one marker and watches the guard fire.
@Suite("Census — what is actually inside PurityVerdict.refuted?")
struct PurityRefutationCensusMeasuredTests {

    // The frozen taxonomy — `RefutationCause` and `Attributor` — is in
    // `PurityRefutationCensusMeasuredTests+Support.swift`, split out for the
    // 400-line file cap only.

    // MARK: - The corpus

    /// One scanned function: the decl the verdict was computed from, and where.
    struct Subject {
        let function: FunctionDeclSyntax
        let file: String
        let name: String
    }

    /// Every function declaration under `Sources/`, collected with
    /// `FunctionScannerVisitor`'s own traversal rules — protocol bodies skipped
    /// (requirements are never summarised) and nested functions skipped
    /// (`visit(FunctionDeclSyntax)` returns `.skipChildren`). Matching those
    /// rules is what makes this denominator the same population the shipped scan
    /// produces `purityVerdict` for.
    static let corpus: [Subject] = {
        var subjects: [Subject] = []
        for file in SwiftSourceFiles.sorted(in: packageSourcesRoot) {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let collector = CensusFunctionCollector(viewMode: .sourceAccurate)
            collector.walk(Parser.parse(source: source))
            let relative = file.path.replacingOccurrences(of: packageRoot.path + "/", with: "")
            subjects.append(contentsOf: collector.functions.map {
                Subject(function: $0, file: relative, name: $0.name.text)
            })
        }
        return subjects
    }()

    static let packageRoot = URL(fileURLWithPath: #filePath, isDirectory: false)
        .deletingLastPathComponent()   // SwiftInferCoreTests/
        .deletingLastPathComponent()   // Tests/
        .deletingLastPathComponent()   // SwiftInferProperties/

    static let packageSourcesRoot: URL = packageRoot.appendingPathComponent("Sources")

    /// `SoundPurity.verdict(for:)` once per subject, in corpus order. Every test
    /// below reads this rather than recomputing — the verdict walks the body, so
    /// three tests asking separately is three body walks per function.
    static let verdicts: [PurityVerdict] = corpus.map { SoundPurity.verdict(for: $0.function) }

    /// The refuted subjects, each with the full set of causes that hold of it.
    static let refuted: [(subject: Subject, causes: Set<RefutationCause>)] = {
        let attributor = Attributor()
        return zip(corpus, verdicts)
            .filter { $0.1 == .refuted }
            .map { ($0.0, attributor.causes(of: $0.0.function)) }
    }()

    // MARK: - The warrant

    /// **The replication is verified, not asserted.** Re-assembling the verdict
    /// out of the pieces this file re-derived must reproduce `SoundPurity`'s
    /// answer on every single function in the corpus. Any drift in SEI's marker
    /// sets, totality rules, or guard order lands here as a named mismatch and
    /// voids the census rather than silently misattributing a cause.
    @Test("the replicated refuters reproduce SoundPurity on every function in Sources/")
    func verdictAgreesWithSoundPurity() {
        let attributor = Attributor()
        var mismatches: [String] = []
        for (subject, real) in zip(Self.corpus, Self.verdicts) {
            let replicated = attributor.reassembledVerdict(of: subject.function)
            if real != replicated {
                mismatches.append("\(subject.file):\(subject.name) real=\(real) replicated=\(replicated)")
            }
        }
        #expect(
            mismatches.isEmpty,
            """
            The cause attribution below no longer matches the shipped refuters, so every \
            number this file reports is void until it is re-derived from PurityInferrer. \
            First 10 of \(mismatches.count): \(mismatches.prefix(10).joined(separator: " | "))
            """
        )
    }

    /// The control for the guard above — remove one marker and watch it fire.
    /// Without this, "zero mismatches" is indistinguishable from a comparison
    /// that cannot fail.
    @Test("a truncated marker set is detected as a mismatch")
    func truncatedMarkerSetIsDetected() {
        let full = Attributor.sideEffectMarkers.union(Attributor.nondeterministicMarkers)
        let truncated = Attributor(markers: full.subtracting(["print"]))
        let mismatches = zip(Self.corpus, Self.verdicts).filter {
            $0.1 != truncated.reassembledVerdict(of: $0.0.function)
        }
        #expect(!mismatches.isEmpty, "dropping `print` from the marker set must be detectable")
    }

    /// The corpus is the population it claims to be — large enough that the
    /// proportions below are not noise, and every refuted subject carries at
    /// least one attributed cause. An unattributed refutation would mean the
    /// taxonomy is incomplete, which is a finding in itself.
    @Test("every refutation is attributed to at least one frozen cause")
    func everyRefutationIsAttributed() {
        #expect(Self.corpus.count > 2_000, "corpus is \(Self.corpus.count) functions")
        let unattributed = Self.refuted.filter(\.causes.isEmpty)
        #expect(
            unattributed.isEmpty,
            "unattributed: \(unattributed.map { "\($0.subject.file):\($0.subject.name)" }.prefix(10))"
        )
    }

    // MARK: - The verdict

    /// Derived once, read by every assertion below.
    struct Split {
        let refuted: Int
        let witnessBearing: Int
        let ignoranceOnly: Int
        /// Ignorance-only rows with a callee to name.
        let actionable: Int
        /// Rows carrying `.propagatedTry` **at all**, witness-bearing included —
        /// i.e. what a decline-reason tally would report.
        let propagatedTryTotal: Int
        let noBody: Int
    }

    static let split: Split = {
        let witnessBearing = refuted.filter { $0.causes.contains(where: \.isWitness) }.count
        return Split(
            refuted: refuted.count,
            witnessBearing: witnessBearing,
            ignoranceOnly: refuted.count - witnessBearing,
            actionable: refuted.filter {
                !$0.causes.contains(where: \.isWitness) && $0.causes.contains(.propagatedTry)
            }.count,
            propagatedTryTotal: refuted.filter { $0.causes.contains(.propagatedTry) }.count,
            noBody: refuted.filter { $0.causes.contains(.noBody) }.count
        )
    }()

    /// **The answer to item 29: ignorance is the MAJORITY of the bucket, not a
    /// rounding error.** Measured 2026-08-17 — 152 of 284 refutations name
    /// nothing in the source at all. The consequence is that the bucket is worth
    /// reading, so the *measurement* precondition on items 30–33 is discharged in
    /// the direction that permits them.
    ///
    /// Asserted as an inequality rather than as `152`, because the corpus is this
    /// repo's own `Sources/` and grows every commit. The exact counts and the
    /// tree they were taken on are in the measurements doc. What must not drift
    /// is the *direction*: the day witnesses become the majority, the argument
    /// for ranking this bucket is gone and this test is where that shows up.
    @Test("ignorance outnumbers witnesses in the refuted bucket")
    func ignoranceIsTheMajority() {
        #expect(
            Self.split.ignoranceOnly > Self.split.witnessBearing,
            """
            \(Self.split.ignoranceOnly) ignorance-only vs \(Self.split.witnessBearing) \
            witness-bearing of \(Self.split.refuted). If this has flipped, re-read \
            docs/measurements/purity-refuted-bucket-census.md before ranking anything.
            """
        )
    }

    /// **Every ignorance-only refutation is actionable, because `.noBody` is
    /// unreachable here.** `PurityVerdict.refuted`'s doc offers "the shape could
    /// not be inspected at all" as half its meaning, and this consumer can never
    /// produce it: `FunctionScannerVisitor` returns `.skipChildren` on
    /// `ProtocolDeclSyntax`, so body-less requirements are not summarised at all,
    /// and a body-less function decl outside a protocol does not exist in Swift.
    ///
    /// This matters for scoping, not just for tidiness: it means the ignorance
    /// half needs no triage step. Everything in it has a callee to name.
    @Test("the inert ignorance case is unreachable through this scanner")
    func noBodyIsUnreachable() {
        #expect(Self.split.noBody == 0, "\(Self.split.noBody) body-less subjects reached the census")
        #expect(
            Self.split.actionable == Self.split.ignoranceOnly,
            "\(Self.split.actionable) actionable of \(Self.split.ignoranceOnly) ignorance-only"
        )
    }

    /// **A decline-reason tally over-reports the leverage ceiling, and this is by
    /// how much.** `.propagatedTry` holds of 219 rows; only 152 of them are
    /// *blocked* by it — the other 67 carry a witness as well, so resolving every
    /// callee in the toolchain would still leave them refuted.
    ///
    /// This is the standing "state a gain as ROWS MOVED, never LAWS GAINED" rule
    /// arriving in a new place, and it is the specific arithmetic error a
    /// blocking-callee report would ship if it counted causes instead of rows.
    @Test("the propagated-try tally exceeds the rows it could actually move")
    func declineReasonTallyOverReportsLeverage() {
        #expect(
            Self.split.propagatedTryTotal > Self.split.actionable,
            """
            \(Self.split.propagatedTryTotal) rows carry propagatedTry but only \
            \(Self.split.actionable) are blocked by it alone.
            """
        )
    }

    /// **A third population is in the bucket that neither half of the taxonomy
    /// describes: verdicts nobody computed.** `makeSummary(fromComputedProperty:)`
    /// passes no `purityVerdict`, so all 180 read-only computed properties under
    /// `Sources/` take `FunctionSummary.init`'s `.refuted` default — while being
    /// handed `isInferredPure: true` unconditionally, which the field's own doc
    /// says is impossible (*"`isInferredPure` is `purityVerdict == .pure`"*).
    ///
    /// So the bucket a consumer sees is not 284 but 464, and 39% of it is a
    /// question that was never asked. Any ranking built over `purityVerdict`
    /// without excluding these is ranking a default.
    ///
    /// **The unchecked `true` has cost nothing measured here** — see the
    /// measurements doc: `PurityInferrer.isPure(_ accessor:)` refutes 0 of the
    /// 180, so no false `pure` advisory has been emitted on this corpus. It is a
    /// latent unsoundness with a zero base rate, not a live wrong answer, and it
    /// is reported that way deliberately.
    @Test("computed properties occupy the refuted bucket without a verdict")
    func computedPropertiesTakeTheDefaultVerdict() throws {
        let summaries = try FunctionScanner.scan(directory: Self.packageSourcesRoot)
        let computed = summaries.filter(\.isComputedProperty)
        let withComputedVerdict = computed.filter { $0.purityVerdict != .refuted }.count
        let notFlaggedPure = computed.filter { !$0.isInferredPure }.count
        #expect(!computed.isEmpty)
        #expect(
            withComputedVerdict == 0,
            "\(withComputedVerdict) computed properties now carry a verdict — update the census doc"
        )
        #expect(
            notFlaggedPure == 0,
            "the unconditional `isInferredPure: true` has changed — update the census doc"
        )
    }

    /// **The cost of the unchecked claim above, measured rather than assumed.**
    /// `PurityInferrer.isPure(_ accessor:)` is the oracle a computed property's
    /// getter should be put through, and it exists — it is simply not called. Run
    /// it over the same 180 and it refutes **none** of them.
    ///
    /// So the defect has emitted no false `/// @lint.effect pure` advisory on
    /// this corpus. Reporting it as "the advisory is unsound" without this number
    /// would be manufacturing a defect that is not there — the second of the two
    /// ways this repo has recorded doing that. What is true is narrower and still
    /// worth fixing: the claim is unchecked, and its base rate here is zero.
    ///
    /// The day this stops being zero, the advisory is emitting a wrong `pure` and
    /// this test says so.
    @Test("the unchecked purity claim on computed properties costs nothing measured here")
    func computedPropertyAdviceIsAccidentallyCorrect() throws {
        let summaries = try FunctionScanner.scan(directory: Self.packageSourcesRoot)
        // Keyed by (file, name), not by name alone — a bare-name key silently
        // collapses same-named properties in different files, which would shrink
        // the denominator without saying so.
        let computedKeys = Set(summaries.filter(\.isComputedProperty).map {
            "\(URL(fileURLWithPath: $0.location.file).lastPathComponent)#\($0.name)"
        })
        let inferrer = PurityInferrer()
        var matched: Set<String> = []
        var refutedByOracle: [String] = []
        for file in SwiftSourceFiles.sorted(in: Self.packageSourcesRoot) {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let collector = CensusFunctionCollector(viewMode: .sourceAccurate)
            collector.walk(Parser.parse(source: source))
            for (name, accessor) in collector.accessorsByName {
                let key = "\(file.lastPathComponent)#\(name)"
                guard computedKeys.contains(key) else { continue }
                matched.insert(key)
                if !inferrer.isPure(accessor) { refutedByOracle.append(key) }
            }
        }
        #expect(
            matched == computedKeys,
            "matched \(matched.count) accessors for \(computedKeys.count) computed-property summaries"
        )
        #expect(
            refutedByOracle.isEmpty,
            """
            The advisory is now emitting `pure` for a getter its own oracle refutes: \
            \(refutedByOracle.prefix(10).joined(separator: ", ")). This is no longer a \
            latent defect — fix makeSummary(fromComputedProperty:).
            """
        )
    }

    // MARK: - The census

    /// Prints the whole census. Not an assertion — the assertions are above; this
    /// is what gets transcribed into the measurements doc, with the tree SHA.
    @Test("census — the refuted bucket, split by cause")
    func census() throws {
        var lines: [String] = []
        lines.append("corpus (Sources/, scanner traversal rules): \(Self.corpus.count) functions")
        let byVerdict = Dictionary(grouping: Self.verdicts) { $0 }
        for verdict in [PurityVerdict.pure, .pureButPartial, .refuted] {
            lines.append("  \(verdict): \(byVerdict[verdict]?.count ?? 0)")
        }
        lines.append("refuted, by cause (a function may carry several):")
        for cause in RefutationCause.allCases.sorted() {
            let count = Self.refuted.filter { $0.causes.contains(cause) }.count
            lines.append("  \(cause.rawValue) [\(cause.isWitness ? "witness" : "ignorance")]: \(count)")
        }
        lines.append("witness-bearing: \(Self.split.witnessBearing)")
        lines.append("ignorance-only:  \(Self.split.ignoranceOnly)  (actionable: \(Self.split.actionable))")
        lines.append("distinct cause sets:")
        let bySet = Dictionary(grouping: Self.refuted) {
            $0.causes.sorted().map(\.rawValue).joined(separator: "+")
        }
        for (set, rows) in bySet.sorted(by: { $0.value.count > $1.value.count }) {
            lines.append("  \(set): \(rows.count)")
        }
        let summaries = try FunctionScanner.scan(directory: Self.packageSourcesRoot)
        let computed = summaries.filter(\.isComputedProperty)
        lines.append("summaries scanned: \(summaries.count)")
        lines.append("  computed properties (verdict never computed, defaults .refuted): \(computed.count)")
        lines.append("  of those, isInferredPure == true: \(computed.filter(\.isInferredPure).count)")
        print(lines.joined(separator: "\n"))
    }
}
