import Foundation
import SwiftEffectInference
import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftInferCore

/// **Phase 0.5, step 1: can the soundness arm reach its own frozen prediction?**
///
/// The plan's §6.3 arm sandboxes the `.pure` population and asks which functions trip
/// a deny-by-default policy. The plan review froze a prediction for it — the **17
/// hand-checked rows** from `purity-unrecognised-callee-census.md` where a `.pure`
/// verdict calls a package function this same analyzer refutes with a witness, one of
/// them a subprocess spawn.
///
/// **A prediction the arm cannot execute is not a prediction.** §6.4 says the arm's
/// coverage *"must be estimated separately rather than inherited from 139-of-281"* —
/// the verify arm's carrier reach — because a purity probe needs only a **call**, not a
/// generator, so a degenerate argument suffices where a law needs a domain. Nobody had
/// taken that estimate. This is it, scoped to the rows that decide the arm's value.
///
/// ## What "reachable" means here, and what it deliberately does not
///
/// Three conditions, all decidable from a parse:
///
/// 1. **Visibility** — `public` or `internal` is reachable through `@testable`;
///    `private` and `fileprivate` are not.
/// 2. **Receiver** — a `static` method needs none. An instance method needs a
///    constructed `self`, which is the expensive half.
/// 3. **Arguments** — every parameter must be degenerately constructible, or defaulted.
///
/// **It does not establish that calling them is safe or meaningful.** A function that
/// reads a package manifest under a temp URL will return `nil` rather than do anything
/// interesting; whether the *probe* is informative is the sandbox's problem, not this
/// census's. What this settles is narrower and prior: whether the arm can invoke its
/// own answer key at all.
@Suite("Census — can the soundness arm reach its frozen 17-row prediction?", .serialized)
struct SoundnessArmReachCensusMeasuredTests {

    struct Row {
        let file: String
        let function: String
    }

    /// The frozen trip list, verbatim from `purity-unrecognised-callee-census.md`.
    ///
    /// Keyed by **file and name** rather than name alone, because `resolve` and `load`
    /// each match several declarations in this package — the name-collision hazard that
    /// has been the dominant defect in three measurements at this seam.
    static let tripList: [Row] = [
        Row(file: "ActionSequenceStubEmitter+PayloadConstructibility.swift", function: "compositionGenerator"),
        Row(file: "DependencyTypeShapes.swift", function: "scan"),
        Row(file: "Discover+PipelineSetup.swift", function: "resolvePipelineSetup"),
        Row(file: "MetricsCommand.swift", function: "loadAggregate"),
        Row(file: "MetricsCommand.swift", function: "loadImplicit"),
        Row(file: "MetricsInteractionCommand.swift", function: "loadDecisions"),
        Row(file: "MetricsRenderer+TimeToAdoption.swift", function: "timeToAdoptionSection"),
        Row(file: "SpeculativeRefactorRunner+Machinery.swift", function: "scanRestricted"),
        Row(file: "SpeculativeRefactorRunner+Machinery.swift", function: "snapshotOrReport"),
        Row(file: "TargetIsolation.swift", function: "dump"),
        Row(file: "VerifierWorkdir+Environment.swift", function: "macOSPlatformLine"),
        Row(file: "VerifierWorkdir+Products.swift", function: "renderTargetDependenciesBlock"),
        Row(file: "VerifierWorkdir.swift", function: "renderDependenciesBlock"),
        Row(file: "ViewModelArgumentGenerator.swift", function: "candidateValuesExpression"),
        Row(file: "EffectResolver.swift", function: "resolve"),
        Row(file: "KitEvidenceStore.swift", function: "load"),
        Row(file: "DrainedProcess.swift", function: "standardOutputViaEnv")
    ]

    struct Reach {
        /// A row the census could not resolve at all — reported distinctly from one it
        /// resolved and found private, because a lost row is a lost prediction.
        static func unreachable(_ row: Row) -> Self {
            Self(
                row: row,
                found: false,
                isPrivate: false,
                isStatic: false,
                parameters: [],
                blockingParameters: []
            )
        }

        let row: Row
        let found: Bool
        let isPrivate: Bool
        let isStatic: Bool
        let parameters: [String]
        let blockingParameters: [String]

        /// **Strictly** reachable: nothing at all to construct.
        var isReachable: Bool {
            found && !isPrivate && isStatic && blockingParameters.isEmpty
        }

        /// Reachable once the probe writes the cheap constructions — a `CaseIterable`
        /// case, a memberwise call on a struct of degenerate fields, or a conforming
        /// stub for a protocol. This is the figure that decides whether the arm can
        /// execute its answer key, because none of those is a research problem.
        var isReachableWithConstruction: Bool {
            guard found, !isPrivate, isStatic else { return false }
            return blockingParameters.allSatisfy {
                SoundnessArmReachCensusMeasuredTests.cost(of: $0) != .expensive
            }
        }
    }

    static let readings: [Reach] = tripList.map { row in
        let root = PurityRefutationCensusMeasuredTests.packageSourcesRoot
        guard let path = SwiftSourceFiles.sorted(in: root).first(where: { $0.lastPathComponent == row.file }),
              let text = try? String(contentsOf: path, encoding: .utf8) else {
            return Reach.unreachable(row)
        }
        let finder = NamedFunctionFinder(name: row.function, viewMode: .sourceAccurate)
        finder.walk(Parser.parse(source: text))
        guard let function = finder.found else {
            return Reach.unreachable(row)
        }
        let modifiers = function.modifiers.map(\.name.text)
        let parameters = function.signature.parameterClause.parameters
            .map(\.type.trimmedDescription)
        let blocking = function.signature.parameterClause.parameters.compactMap { parameter -> String? in
            // A defaulted parameter never has to be supplied.
            if parameter.defaultValue != nil { return nil }
            let type = parameter.type.trimmedDescription
            return Self.isDegenerate(type) ? nil : type
        }
        return Reach(
            row: row,
            found: true,
            isPrivate: modifiers.contains("private") || modifiers.contains("fileprivate"),
            isStatic: modifiers.contains("static") || modifiers.contains("class"),
            parameters: parameters,
            blockingParameters: blocking
        )
    }

    /// Types a probe can supply without constructing anything from the package.
    ///
    /// **Optionals are degenerate whatever they wrap** — `nil` is always available, and
    /// that alone unblocks three rows whose only non-stdlib parameter is optional.
    /// Collections are degenerate because empty is always available. This is the
    /// difference §6.4 names between a purity probe and a law: a law needs a *domain*, a
    /// probe needs one call.
    static func isDegenerate(_ type: String) -> Bool {
        if type.hasSuffix("?") { return true }
        if type.hasPrefix("[") { return true }
        if type.hasPrefix("Set<") { return true }
        if type.contains("->") { return true }
        return ["String", "Int", "Bool", "Double", "URL", "Data", "Character"].contains(type)
    }

    // MARK: - Controls

    /// **Every row resolves.** A row the census cannot find would silently read as
    /// unreachable, which is the same output a genuinely private function gives — and
    /// the trip list is the arm's answer key, so a lost row is a lost prediction.
    @Test("every row of the frozen trip list is found in Sources/")
    func everyRowResolves() {
        let missing = Self.readings.filter { !$0.found }.map { "\($0.row.file):\($0.row.function)" }
        #expect(missing.isEmpty, "trip-list rows no longer resolve: \(missing)")
    }

    /// The degeneracy rule admits what it should and refuses what it should not.
    /// Without this, "every parameter is degenerate" cannot be told from a rule that
    /// says yes to everything.
    @Test("the degeneracy rule distinguishes stdlib from package types")
    func degeneracyRuleIsDiscriminating() {
        for type in ["String", "URL", "[String]", "Set<String>", "UserPackageReference?", "(String) -> Void"] {
            #expect(Self.isDegenerate(type), "\(type) should be degenerate")
        }
        for type in ["ActionCaseInfo", "Decisions", "WorkdirMode", "FunctionSummary"] {
            #expect(Self.isDegenerate(type) == false, "\(type) should NOT be degenerate")
        }
    }

    /// The arm can reach a **majority** of its own prediction. Asserted as a direction
    /// rather than an integer, since the corpus moves — what matters is that the answer
    /// key is not mostly unexecutable, which would make the whole arm unfalsifiable.
    @Test("the soundness arm can reach most of its frozen prediction")
    func armReachesItsPrediction() {
        let strict = Self.readings.filter(\.isReachable).count
        let withConstruction = Self.readings.filter(\.isReachableWithConstruction).count
        #expect(
            withConstruction > strict,
            "the cheap-construction tier adds nothing over the strict one — the classifier is inert"
        )
        #expect(
            withConstruction * 2 > Self.readings.count,
            "only \(withConstruction) of \(Self.readings.count) rows are callable — the arm cannot test its own key"
        )
    }

    // MARK: - The census

    @Test("census — the trip list's reach")
    func census() {
        var lines: [String] = ["", "SOUNDNESS ARM REACH CENSUS", ""]
        var blockedBy: [String: Int] = [:]
        for reading in Self.readings {
            let verdict: String
            if !reading.found { verdict = "NOT FOUND" } else if reading.isPrivate {
                verdict = "private"
            } else if !reading.isStatic {
                verdict = "needs receiver"
            } else if !reading.blockingParameters.isEmpty {
                verdict = "needs \(reading.blockingParameters.joined(separator: ", "))"
            } else {
                verdict = "REACHABLE"
            }
            for blocker in reading.blockingParameters { blockedBy[blocker, default: 0] += 1 }
            lines.append("  \(reading.row.function.padding(toLength: 30, withPad: " ", startingAt: 0)) \(verdict)")
        }
        let strict = Self.readings.filter(\.isReachable).count
        let withConstruction = Self.readings.filter(\.isReachableWithConstruction).count
        lines.append("")
        lines.append("REACHABLE, nothing to construct:      \(strict) of \(Self.readings.count)")
        lines.append("REACHABLE, cheap construction only:   \(withConstruction) of \(Self.readings.count)")
        if !blockedBy.isEmpty {
            lines.append("blocking parameter types:")
            for (type, count) in blockedBy.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }) {
                lines.append("  \(count)x \(type) — \(Self.cost(of: type).rawValue)")
            }
        }
        print(lines.joined(separator: "\n"))
    }
}

/// The first function declaration in a file with a given name.
final class NamedFunctionFinder: SyntaxVisitor {

    private let name: String
    private(set) var found: FunctionDeclSyntax?

    init(name: String, viewMode: SyntaxTreeViewMode) {
        self.name = name
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if found == nil, node.name.text == name { found = node }
        return .visitChildren
    }
}
