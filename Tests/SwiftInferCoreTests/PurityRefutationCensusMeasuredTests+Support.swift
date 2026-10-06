import Foundation
import SwiftEffectInference
import SwiftParser
import SwiftSyntax

@testable import SwiftInferCore

/// The frozen taxonomy and the re-derived refuters for
/// `PurityRefutationCensusMeasuredTests`. Split out only for the 400-line file
/// cap; the reasoning that governs both lives in that suite's header.
extension PurityRefutationCensusMeasuredTests {

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

        /// A marker or a trap in a **default argument** — code the function runs
        /// on exactly the calls that omit it. **Witness**: it names the
        /// construct, it is just not inside the braces.
        ///
        /// Added 2026-08-17 when `PurityInferrer` learned to scan default values
        /// (open item 41). The census that found the hole is
        /// `PurityAllowlistCensusMeasuredTests`; this cause is what keeps the
        /// **attribution** honest afterwards, because without it the 15 rows the
        /// fix moved arrive here refuted-but-unattributed and read as ignorance —
        /// which is the opposite of what they are.
        case markerInDefault

        /// Constructing a type whose construction runs a refuter — a stored property's default,
        /// an initializer's body or omitted default, a superclass's construction — in the body or
        /// in a default value. **Witness**: it names the type and the line that runs
        /// (SEI `ConstructionFacts`, wired in 2026-10-06).
        ///
        /// **Consulted, not re-derived**, on `NondeterminismSources`' precedent: the resolution
        /// is internal to SEI (`refutation(constructingIn:)`), and ~1,400 lines re-derived would be
        /// the drift this file exists to catch. So it is read off SEI's **first** witness — and
        /// that makes this cause's tally a **LOWER BOUND**. SEI checks construction after the
        /// markers, the file reads and the nondeterminism classifier, so a function that both
        /// reads the clock and constructs a refuted type is counted under `marker` alone. The
        /// witness/ignorance SPLIT stays exact: a construction hidden behind another witness is
        /// a row that is witness-bearing either way.
        case construction

        /// `throws`, and the body `try`s into a callee this leaf cannot see.
        /// **Ignorance, actionable** — there is a callee to name.
        case propagatedTry

        /// Does this cause point at something in the source?
        var isWitness: Bool {
            switch self {
            case .reducerEffect, .asyncSignature, .marker, .nonTotal, .markerInDefault, .construction:
                return true

            case .noBody, .propagatedTry:
                return false
            }
        }

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// The refuters, re-derived from `PurityInferrer` because they are `private`
    /// there. Guarded by `verdictAgreesWithSoundPurity` over the whole corpus.
    struct Attributor {
        /// `PurityInferrer.sideEffectMarkers`.
        ///
        /// **`FileHandle` / `Process` / `Pipe` joined at SEI `3ea25f2`**, which
        /// closed the non-throwing half of the I/O hole: `throwsOnlyItsOwnErrors`
        /// only ever covered *throwing* functions, and
        /// `FileHandle.standardError.write(_:)` does not throw. `String` and
        /// `Data` are deliberately still absent — matched by bare identifier they
        /// would refute nearly everything.
        ///
        /// **The file-system read members joined at SEI `fff33cf`**, which closed
        /// the case the sentence above used to end with: `String(contentsOf:)`
        /// and `Data(contentsOf:)` throw, so the `try` gate was said to reach
        /// them — true only while the throw propagates, and `try?` swallows it.
        ///
        /// **`contentsOf` is deliberately not here, and must not be added.** SEI
        /// carried it as a bare token from `fff33cf` to `23d1dab`, where it also
        /// matched `append(contentsOf:)` and refuted every function that appends
        /// one collection to another — 43 of this corpus's functions. It is
        /// matched on the callee instead; see `CensusFileReadChecker`.
        static let sideEffectMarkers: Set<String> = [
            "print", "NSLog", "FileManager", "URLSession", "UserDefaults",
            "NotificationCenter", "DispatchQueue",
            "FileHandle", "Process", "Pipe",
            "resourceValues", "checkResourceIsReachable", "checkPromisedItemIsReachable",
            "startAccessingSecurityScopedResource", "stopAccessingSecurityScopedResource",
            "contentsOfFile", "contentsOfDirectory"
        ]

        /// `PurityInferrer.nondeterministicMarkers`.
        static let nondeterministicMarkers: Set<String> = [
            "arc4random", "arc4random_uniform", "drand48", "CFAbsoluteTimeGetCurrent",
            "random", "randomElement", "shuffled",
            "Date", "UUID"
        ]

        /// Injected so the control can truncate it.
        let markers: Set<String>

        /// The census's configured inferrer, consulted for the construction cause only.
        /// **Required**: an Attributor with no table would file every construction-refuted row as
        /// ignorance while `verdictAgreesWithSoundPurity` stayed green — the guard is blind to a
        /// refuter that only fires on already-refuted rows, which is what
        /// `constructionBlindReplicaIsDetected` demonstrates.
        let inferrer: PurityInferrer

        init(markers: Set<String> = sideEffectMarkers.union(nondeterministicMarkers), inferrer: PurityInferrer) {
            self.markers = markers
            self.inferrer = inferrer
        }

        /// Whether SEI's first witness for `function` is a construction — in the body, or in a
        /// default value. Every other witness answers `false`, so a drifted marker set still
        /// surfaces as a verdict mismatch rather than being consulted away.
        func constructionWitness(of function: FunctionDeclSyntax) -> Bool {
            switch inferrer.refutation(for: function) {
            case .refutingConstruction, .refutingDefaultArgument(_, cause: .refutingConstruction): true
            default: false
            }
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
            if hasRefutingDefault(function.signature) { causes.insert(.markerInDefault) }
            if constructionWitness(of: function) { causes.insert(.construction) }
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
            guard !hasMarker(in: body), isTotal(body),
                  !hasRefutingDefault(function.signature),
                  !constructionWitness(of: function) else { return .refuted }
            guard function.signature.effectSpecifiers?.throwsClause != nil else { return .pure }
            return sawTry(in: body) ? .refuted : .pureButPartial
        }

        /// `PurityInferrer.hasRefutingDefaultArgument`. Default **values** only —
        /// a marker in a parameter *type* is not an impurity, and scanning the
        /// whole signature would refute `func f(_ d: Date)`, which is the shape
        /// dependency injection produces.
        /// **Routes through the same `hasMarker` as the body**, because SEI's does:
        /// `hasRefutingDefaultArgument` calls `hasRefutingMarker(in:)`, so the
        /// classifier half of the union reaches default values too. Scanning the
        /// value only — a marker in a parameter *type* is not an impurity, and
        /// scanning the whole signature would refute `func f(_ d: Date)`, the
        /// shape dependency injection produces.
        private func hasRefutingDefault(_ signature: FunctionSignatureSyntax) -> Bool {
            signature.parameterClause.parameters.contains { parameter in
                guard let value = parameter.defaultValue?.value else { return false }
                let checker = CensusTotalityChecker(viewMode: .sourceAccurate)
                checker.walk(value)
                return hasMarker(in: value) || !checker.isTotal
            }
        }

        /// `PurityInferrer.hasRefutingMarker` — **two passes unioned, as of SEI
        /// `3ea25f2`**, and the union is the point rather than an optimisation.
        ///
        /// The token scan is broad and shape-blind; `NondeterminismSources` is
        /// narrow and shape-aware, knowing the monotonic clocks, the
        /// clock-acquisition types and the ambient-environment properties that no
        /// token names. Neither subsumes the other, and *replacing* the token set
        /// with the classifier would relax the gate — the classifier reads
        /// `Date(timeIntervalSince1970:)` as deterministic, where the token set
        /// over-refutes `Date` on purpose. Either one refuting is enough.
        ///
        /// The classifier is **consulted, not re-derived**, unlike every other
        /// refuter in this Attributor: `NondeterminismSources` is `public`, and a
        /// fourth hand-rolled copy of "does this reach for ambient time" is
        /// exactly the drift that type was extracted to end.
        /// `PurityInferrer.isMarkerPosition`, re-derived (SEI `caa37ca`): a marker
        /// is an identifier, and not a key path's component. The text of a string
        /// literal is not code — `"Date"` names nothing — and a key-path component
        /// names a property, where no marker is one. Every token scan in these
        /// censuses goes through this, so they cannot disagree about it.
        static func isMarkerPosition(_ token: TokenSyntax) -> Bool {
            guard case .identifier = token.tokenKind else { return false }
            if let reference = token.parent?.as(DeclReferenceExprSyntax.self),
               reference.parent?.is(KeyPathPropertyComponentSyntax.self) == true {
                return false
            }
            return true
        }

        private func hasMarker(in syntax: some SyntaxProtocol) -> Bool {
            let tokenHit = syntax.tokens(viewMode: .sourceAccurate)
                .contains { markers.contains($0.text) && Self.isMarkerPosition($0) }
            if tokenHit { return true }
            let fileRead = CensusFileReadChecker(viewMode: .sourceAccurate)
            fileRead.walk(syntax)
            if fileRead.sawFileRead { return true }
            let checker = CensusNondeterminismChecker(viewMode: .sourceAccurate)
            checker.walk(syntax)
            return checker.sawSource
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
}

// MARK: - Replicated checkers

/// `PurityInferrer.NondeterminismChecker`, re-derived — but note what is and is
/// not copied here. The *walk* is replicated; the *answer* is not. Every `source`
/// question goes to `NondeterminismSources`, the public shared classifier, so
/// this file cannot drift from SEI on which forms count as nondeterminism.
///
/// Both overloads are needed and a call-only walk is not enough:
/// `source(of: FunctionCallExprSyntax)` catches `ContinuousClock()`,
/// `mach_absolute_time()` and `DispatchTime.now()`, while
/// `source(of: MemberAccessExprSyntax)` catches the property forms —
/// `SuspendingClock.now`, `Locale.current`, `TimeZone.current` — which are not
/// calls at all.
final class CensusNondeterminismChecker: SyntaxVisitor {
    private(set) var sawSource = false

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if NondeterminismSources.source(of: node) != nil { sawSource = true }
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        if NondeterminismSources.source(of: node) != nil { sawSource = true }
        return .visitChildren
    }
}

/// `PurityInferrer.TotalityChecker`, re-derived. See the suite header for why a
/// copy here is safe.
final class CensusTotalityChecker: SyntaxVisitor {
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
final class CensusTryChecker: SyntaxVisitor {
    private(set) var sawTry = false

    override func visit(_: TryExprSyntax) -> SyntaxVisitorContinueKind {
        sawTry = true
        return .skipChildren
    }
}

/// Collects function decls with `FunctionScannerVisitor`'s traversal rules:
/// nested functions and protocol requirements are both out of the population the
/// shipped scan summarises.
final class CensusFunctionCollector: SyntaxVisitor {
    private(set) var functions: [FunctionDeclSyntax] = []
    /// Accessor blocks by property name, for the computed-property half. Keyed
    /// by name rather than re-derived from `makeSummary(fromComputedProperty:)`'s
    /// filter — the caller intersects with the shipped scan's own names and
    /// asserts the intersection is total, so a divergence is reported rather
    /// than silently narrowing the population.
    private(set) var accessorsByName: [String: AccessorBlockSyntax] = [:]

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        functions.append(node)
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            if let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
               let accessor = binding.accessorBlock {
                accessorsByName[pattern.identifier.text] = accessor
            }
        }
        return .visitChildren
    }

    override func visit(_: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }
}

/// `PurityInferrer.FileReadChecker`, re-derived — a file read spelled
/// `SomeType(contentsOf:)`.
///
/// Shape-aware rather than a token, and that is the whole point of it. SEI
/// carried `contentsOf` in `sideEffectMarkers` between `fff33cf` and `23d1dab`,
/// where the bare token also matched `append(contentsOf:)`; matching the callee
/// separates `String(contentsOf: url)` from `array.append(contentsOf: other)`.
final class CensusFileReadChecker: SyntaxVisitor {

    private static let fileReadingTypes: Set<String> = [
        "String", "Data", "NSString", "NSData", "NSDictionary", "NSArray"
    ]

    private(set) var sawFileRead = false

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let callee = node.calledExpression.as(DeclReferenceExprSyntax.self),
              Self.fileReadingTypes.contains(callee.baseName.text),
              node.arguments.contains(where: { $0.label?.text == "contentsOf" })
        else { return .visitChildren }
        sawFileRead = true
        return .visitChildren
    }
}
