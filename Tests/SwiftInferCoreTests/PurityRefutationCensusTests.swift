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
struct PurityRefutationCensusTests {

    // MARK: - The frozen taxonomy

    /// One reason `SoundPurity.verdict(for:)` can answer `.refuted`, read off
    /// its `guard`s in order. A function may satisfy several — they are
    /// collected as a *set*, never reduced to a "primary", because the two
    /// body-level refuters share a single `guard` and the code therefore states
    /// no precedence between them.
    enum RefutationCause: String, CaseIterable, Comparable {
        /// `ReducerPurityAnalyzer` refuted: a TCA/concurrency effect signal
        /// (`Effect` / `Task` / `await` / `.run` / `.send` / …) or a write to
        /// static or `Self` state. **Witness** — it names the construct.
        case reducerEffect

        /// No body to inspect. **Ignorance, inert.**
        case noBody

        /// The signature declares `async`. **Witness.**
        case asyncSignature

        /// A side-effect or nondeterminism marker token appears in the body.
        /// **Witness.**
        case marker

        /// A force-unwrap, `try!`, `as!`, or a trap call. **Witness.**
        case nonTotal

        /// `throws`, and the body `try`s into a callee this leaf cannot see.
        /// **Ignorance, actionable** — there is a callee to name.
        case propagatedTry

        /// Does this cause point at something in the source?
        var isWitness: Bool {
            switch self {
            case .reducerEffect, .asyncSignature, .marker, .nonTotal: return true
            case .noBody, .propagatedTry: return false
            }
        }

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// The refuters, re-derived from `PurityInferrer` because they are `private`
    /// there. Guarded by `verdictAgreesWithSoundPurity` over the whole corpus.
    struct Attributor {
        /// `PurityInferrer.sideEffectMarkers`.
        static let sideEffectMarkers: Set<String> = [
            "print", "NSLog", "FileManager", "URLSession", "UserDefaults",
            "NotificationCenter", "DispatchQueue"
        ]

        /// `PurityInferrer.nondeterministicMarkers`.
        static let nondeterministicMarkers: Set<String> = [
            "arc4random", "arc4random_uniform", "drand48", "CFAbsoluteTimeGetCurrent",
            "random", "randomElement", "shuffled",
            "Date", "UUID"
        ]

        /// Injected so the control can truncate it.
        let markers: Set<String>

        init(markers: Set<String> = sideEffectMarkers.union(nondeterministicMarkers)) {
            self.markers = markers
        }

        /// Every cause that holds of `function`, independent of the order the
        /// real implementation would short-circuit in.
        func causes(of function: FunctionDeclSyntax) -> Set<RefutationCause> {
            var causes: Set<RefutationCause> = []
            if ReducerPurityAnalyzer.analyze(function) != .pure { causes.insert(.reducerEffect) }
            guard let body = function.body else {
                causes.insert(.noBody)
                return causes
            }
            if function.signature.effectSpecifiers?.asyncSpecifier != nil {
                causes.insert(.asyncSignature)
            }
            if hasMarker(in: body) { causes.insert(.marker) }
            if !isTotal(body) { causes.insert(.nonTotal) }
            if function.signature.effectSpecifiers?.throwsClause != nil, sawTry(in: body) {
                causes.insert(.propagatedTry)
            }
            return causes
        }

        /// The verdict these causes imply, re-assembled in
        /// `SoundPurity.verdict(for:)`'s exact order. Compared against the real
        /// answer on every function in the corpus — that comparison is the whole
        /// warrant for the replication above.
        func reassembledVerdict(of function: FunctionDeclSyntax) -> PurityVerdict {
            guard ReducerPurityAnalyzer.analyze(function) == .pure else { return .refuted }
            guard let body = function.body else { return .refuted }
            guard function.signature.effectSpecifiers?.asyncSpecifier == nil else { return .refuted }
            guard !hasMarker(in: body), isTotal(body) else { return .refuted }
            guard function.signature.effectSpecifiers?.throwsClause != nil else { return .pure }
            return sawTry(in: body) ? .refuted : .pureButPartial
        }

        private func hasMarker(in body: CodeBlockSyntax) -> Bool {
            body.tokens(viewMode: .sourceAccurate).contains { markers.contains($0.text) }
        }

        private func isTotal(_ body: CodeBlockSyntax) -> Bool {
            let checker = CensusTotalityChecker(viewMode: .sourceAccurate)
            checker.walk(body)
            return checker.isTotal
        }

        private func sawTry(in body: CodeBlockSyntax) -> Bool {
            let checker = CensusTryChecker(viewMode: .sourceAccurate)
            checker.walk(body)
            return checker.sawTry
        }
    }

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

    static let packageRoot: URL = URL(fileURLWithPath: #filePath, isDirectory: false)
        .deletingLastPathComponent()   // SwiftInferCoreTests/
        .deletingLastPathComponent()   // Tests/
        .deletingLastPathComponent()   // SwiftInferProperties/

    static let packageSourcesRoot: URL = packageRoot.appendingPathComponent("Sources")

    /// The refuted subjects, each with the full set of causes that hold of it.
    static let refuted: [(subject: Subject, causes: Set<RefutationCause>)] = {
        let attributor = Attributor()
        return corpus
            .filter { SoundPurity.verdict(for: $0.function) == .refuted }
            .map { ($0, attributor.causes(of: $0.function)) }
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
        for subject in Self.corpus {
            let real = SoundPurity.verdict(for: subject.function)
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
        let mismatches = Self.corpus.filter {
            SoundPurity.verdict(for: $0.function) != truncated.reassembledVerdict(of: $0.function)
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

    // MARK: - The census

    /// Prints the whole census. Not an assertion — the assertions are below; this
    /// is what gets transcribed into the measurements doc, with the tree SHA.
    @Test("census — the refuted bucket, split by cause")
    func census() {
        var lines: [String] = []
        lines.append("corpus (Sources/, scanner traversal rules): \(Self.corpus.count) functions")
        let verdicts = Dictionary(grouping: Self.corpus) { SoundPurity.verdict(for: $0.function) }
        for verdict in [PurityVerdict.pure, .pureButPartial, .refuted] {
            lines.append("  \(verdict): \(verdicts[verdict]?.count ?? 0)")
        }
        lines.append("refuted, by cause (a function may carry several):")
        for cause in RefutationCause.allCases.sorted() {
            let count = Self.refuted.filter { $0.causes.contains(cause) }.count
            lines.append("  \(cause.rawValue) [\(cause.isWitness ? "witness" : "ignorance")]: \(count)")
        }
        let witnessBearing = Self.refuted.filter { $0.causes.contains(where: \.isWitness) }.count
        let ignoranceOnly = Self.refuted.count - witnessBearing
        let actionable = Self.refuted.filter {
            !$0.causes.contains(where: \.isWitness) && $0.causes.contains(.propagatedTry)
        }.count
        lines.append("witness-bearing: \(witnessBearing)")
        lines.append("ignorance-only:  \(ignoranceOnly)  (of which actionable: \(actionable))")
        lines.append("distinct cause sets:")
        let bySet = Dictionary(grouping: Self.refuted) { $0.causes.sorted().map(\.rawValue).joined(separator: "+") }
        for (set, rows) in bySet.sorted(by: { $0.value.count > $1.value.count }) {
            lines.append("  \(set): \(rows.count)")
        }
        // Computed properties never reach `SoundPurity` at all — they are built
        // by `makeSummary(fromComputedProperty:)`, which passes no verdict and
        // so takes `FunctionSummary.init`'s `.refuted` default. They are not in
        // `corpus` (that walks function decls); counted here because they land
        // in the same bucket downstream reads.
        let summaries = (try? FunctionScanner.scan(directory: Self.packageSourcesRoot)) ?? []
        let computed = summaries.filter(\.isComputedProperty)
        lines.append("summaries scanned: \(summaries.count)")
        lines.append("  computed properties (verdict never computed, defaults .refuted): \(computed.count)")
        lines.append("  of those, isInferredPure == true: \(computed.filter(\.isInferredPure).count)")
        print(lines.joined(separator: "\n"))
    }
}

// MARK: - Replicated checkers

/// `PurityInferrer.TotalityChecker`, re-derived. See the suite header for why a
/// copy here is safe.
private final class CensusTotalityChecker: SyntaxVisitor {
    private(set) var isTotal = true

    private static let trapFunctions: Set<String> = [
        "fatalError", "preconditionFailure", "precondition",
        "assert", "assertionFailure"
    ]

    override func visit(_: ForceUnwrapExprSyntax) -> SyntaxVisitorContinueKind {
        isTotal = false
        return .skipChildren
    }

    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        if node.questionOrExclamationMark?.text == "!" { isTotal = false }
        return .visitChildren
    }

    override func visit(_ node: AsExprSyntax) -> SyntaxVisitorContinueKind {
        if node.questionOrExclamationMark?.text == "!" { isTotal = false }
        return .visitChildren
    }

    override func visit(_ node: UnresolvedAsExprSyntax) -> SyntaxVisitorContinueKind {
        if node.questionOrExclamationMark?.text == "!" { isTotal = false }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let callee = node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
           Self.trapFunctions.contains(callee) {
            isTotal = false
        }
        return .visitChildren
    }
}

/// `PurityInferrer.TryExpressionChecker`, re-derived.
private final class CensusTryChecker: SyntaxVisitor {
    private(set) var sawTry = false

    override func visit(_: TryExprSyntax) -> SyntaxVisitorContinueKind {
        sawTry = true
        return .skipChildren
    }
}

/// Collects function decls with `FunctionScannerVisitor`'s traversal rules:
/// nested functions and protocol requirements are both out of the population the
/// shipped scan summarises.
private final class CensusFunctionCollector: SyntaxVisitor {
    private(set) var functions: [FunctionDeclSyntax] = []

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        functions.append(node)
        return .skipChildren
    }

    override func visit(_: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }
}
