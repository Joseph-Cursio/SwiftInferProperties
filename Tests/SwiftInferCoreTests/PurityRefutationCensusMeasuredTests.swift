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

    /// **The answer to item 29, and it MOVED on 2026-08-17 — the same day, by a
    /// fix the census itself provoked.**
    ///
    /// As first measured, ignorance was the majority: 152 ignorance-only against
    /// 132 witness-bearing, of 284. That is what discharged the measurement
    /// precondition on items 30–33 in the direction that permits them.
    ///
    /// Then item 41 landed — `PurityInferrer` learned that a **default argument**
    /// is code the function runs — and the split became **135 ignorance-only
    /// against 164 witness-bearing, of 299**. Witnesses are now the majority. Two
    /// separate movements, and the second is the interesting one:
    ///
    /// - **15 rows are newly refuted**, having previously been judged `.pure`
    ///   while defaulting a parameter to `Date()` or a `FileManager` read.
    /// - **17 rows were already refuted and already counted as *rankable
    ///   ignorance*.** They carry `propagatedTry` **and** an impure default, so
    ///   no annotation on any blocked callee could ever have freed them. They
    ///   were never in the population item 31 is about.
    ///
    /// **So the rankable ceiling is 135, not 152**, and the correction came from
    /// closing an unrelated hole rather than from re-reading the ranking. That is
    /// item 32's warning arriving a third time: a bucket's *size* is not its
    /// leverage, and every refuter added anywhere shrinks it again.
    ///
    /// **The direction assertion is kept, inverted, and re-argued.** This test's
    /// previous form said the day witnesses became the majority, the argument for
    /// ranking the bucket was gone. That was too strong, and saying so is the
    /// honest correction rather than quietly relaxing the bound: what the
    /// majority claim ever supported was *the bucket is not a rounding error*,
    /// and 135 of 299 — 45%, all of it actionable, `noBody` still 0 — is not a
    /// rounding error. What it no longer supports is *most of the bucket is
    /// unread*, which is the stronger sentence items 31–33 were sold on. The
    /// assertion below is now the weaker, true one, with the stronger one
    /// recorded above as having been measured and lost.
    @Test("ignorance is a large minority of the refuted bucket, and all of it actionable")
    func ignoranceIsNotARoundingError() {
        #expect(
            Self.split.ignoranceOnly * 3 > Self.split.refuted,
            """
            \(Self.split.ignoranceOnly) ignorance-only of \(Self.split.refuted) refuted \
            (\(Self.split.witnessBearing) witness-bearing). Below a third, the bucket stops \
            being worth ranking at all — re-read \
            docs/measurements/purity-refuted-bucket-census.md before building over it.
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
        // The computed-property half, which reaches the same bucket by a
        // different route. Before 2026-08-17 every one of these was `.refuted`
        // by an initialiser default while claiming `isInferredPure`; both halves
        // are printed so the bucket a CONSUMER sees can be read off directly,
        // rather than inferred from the function census above.
        let summaries = try FunctionScanner.scan(directory: Self.packageSourcesRoot)
        let computed = summaries.filter(\.isComputedProperty)
        let computedRefuted = computed.filter { $0.purityVerdict == .refuted }.count
        lines.append("summaries scanned: \(summaries.count)")
        lines.append("  computed properties: \(computed.count)")
        lines.append("    .pure: \(computed.count - computedRefuted) · .refuted: \(computedRefuted)")
        lines.append("bucket a consumer reads (.refuted over all summaries): \(Self.split.refuted + computedRefuted)")
        print(lines.joined(separator: "\n"))
    }
}
