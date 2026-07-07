import ArgumentParser
import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// V2.0 M1.A — `swift-infer discover-reducers` subcommand surface.
///
/// **What it does.** Scans `Sources/<target>/` for functions whose
/// signature matches one of the three canonical reducer shapes (PRD
/// §6.2). Prints one line per detected reducer plus a tail summary.
/// The list is sorted by `(location, functionName)` for byte-stable
/// output across runs.
///
/// **V2.0 M1.A scope.** Listing only — no interactive triage, no
/// scoring, no verify, no persistence. Downstream pipelines (M2's
/// Action-sequence generator, M3's in-process verify, M4–M7's
/// interaction-template families) consume the candidate list via
/// `ReducerDiscoverer.discover(directory:)` directly; the subcommand
/// is the human-driven gesture for "what does the tool see?".
///
/// **Why a separate subcommand rather than `discover --reducers`.**
/// The §3.6 framing suggests folding into the existing `discover`
/// subcommand. M1.A picks a separate subcommand because:
///   - `discover` is rooted around algebraic-suggestion emission; a
///     `--reducers` mode that produces a structurally-different
///     output type (a flat candidate list, not scored suggestions)
///     would force a branch deep in `Discover.run`.
///   - Discovery and template-scoring naturally separate as v2.0
///     matures (M4+ scoring runs against the discovery output —
///     two stages, not one).
/// Folding into `discover` later, if desired, is non-breaking — the
/// hyphenated form can stay as an alias.
extension SwiftInferCommand {

    public struct DiscoverReducers: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "discover-reducers",
            abstract: "List functions matching the three canonical "
                + "reducer signatures (PRD v2.0 §6.2) under "
                + "Sources/<target>/. Opt-in / human-driven; foundation "
                + "for v2.0 M2+ interaction-invariant inference."
        )

        @Option(
            name: .long,
            help: """
            Name of the SwiftPM target to scan. Resolved to \
            Sources/<target>/ relative to the working directory — \
            mirrors `swift-infer discover --target`.
            """
        )
        public var target: String

        @Option(
            name: .long,
            help: """
            Optional `--reducer <typeName>.<funcName>` (or just \
            `<funcName>` for free functions) pin. When present, the \
            output is filtered to the single matching candidate; \
            zero or multiple matches are an error (PRD §6.5 — never \
            silently pick one). Module-prefixed pins (e.g. \
            `MyModule.Inbox.body`) defer to v2.0 M2+ when multi-\
            module plumbing lands.
            """
        )
        public var reducer: String?

        public init() { /* no-op */ }

        public func run() async throws {
            let directory = URL(fileURLWithPath: "Sources").appendingPathComponent(target)
            let rendered = try Self.runPipeline(directory: directory, pinRaw: reducer)
            print(rendered, terminator: "")
        }

        /// V2.0 M1.A — pure-ish pipeline entry. Tests drive it without
        /// going through the AsyncParsableCommand shell. Returns the
        /// rendered summary string; the CLI's `run()` just prints it.
        ///
        /// V2.0 M1.C — extended with an optional `--reducer` pin
        /// (`pinRaw`). When provided, the discovered candidate list is
        /// filtered via `ReducerPin.matches(_:)` and zero / multiple
        /// matches throw a clear error (never silently pick one).
        static func runPipeline(
            directory: URL,
            pinRaw: String? = nil
        ) throws -> String {
            let candidates = try ReducerDiscoverer.discover(directory: directory)
            guard let pinRaw else {
                // PROTOTYPE — also surface SwiftUI MVVM view-model carriers
                // (@Observable / ObservableObject) and their action alphabet.
                // A view model is a reducer in disguise (stored props = State,
                // each mutating method = an Action), which the signature scan
                // can't see. Appended as a separate section.
                let viewModels = try ViewModelDiscoverer.discover(directory: directory)
                // PROTOTYPE — also surface SwiftSyntax lint-rule visitor
                // carriers (issue-accumulating `SyntaxVisitor` subclasses).
                // Recognition only (slice 1): no invariant is emitted — see
                // docs/rule-visitor-carrier-scoping.md.
                let ruleVisitors = try RuleVisitorDiscoverer.discover(directory: directory)
                // PROTOTYPE — also surface value-semantics carriers: structs
                // holding reference-backed storage (a closure / mutable
                // container / corpus class), through which a "value" can leak
                // shared mutable state. Recognition only (slice 2): no invariant
                // is emitted yet — see docs/valuesemantic-build-plan.md.
                let valueSemantics = try ValueSemanticDiscoverer.discover(directory: directory)
                // PROTOTYPE — also surface defensive-copy carriers: classes that
                // vend a copy()/clone() (Ch. 9 §9.3). Recognition only.
                let defensiveCopies = try DefensiveCopyDiscoverer.discover(directory: directory)
                // PROTOTYPE — also surface identity-stability carriers: Hashable
                // classes whose == / hash may read mutable state (Ch. 9 §9.3.3).
                let stableIdentities = try StableIdentityDiscoverer.discover(directory: directory)
                // PROTOTYPE — also surface convention-recognized VIPER/MVP roles
                // (`*Presenter` / `*Interactor`): a presenter is a view model
                // minus @Observable — stored state + mutating methods + injected
                // protocol collaborators (one of which is the assertable output
                // sink). See docs/stateful-role-discoverer-design.md.
                let conventionRoles = try ConventionRoleDiscoverer.discover(directory: directory)
                return renderSummary(candidates: candidates)
                    + "\n" + renderViewModelSummary(viewModels)
                    + "\n" + renderRuleVisitorSummary(ruleVisitors)
                    + "\n" + renderValueSemanticSummary(valueSemantics)
                    + "\n" + renderDefensiveCopySummary(defensiveCopies)
                    + "\n" + renderStableIdentitySummary(stableIdentities)
                    + "\n" + renderConventionRoleSummary(conventionRoles)
            }
            let pin = try ReducerPin.parse(pinRaw)
            let matched = candidates.filter { pin.matches($0) }
            switch matched.count {
            case 0:
                throw DiscoverReducersError.pinNoMatch(raw: pinRaw)

            case 1:
                return renderSummary(candidates: matched)

            default:
                throw DiscoverReducersError.pinAmbiguous(
                    raw: pinRaw,
                    matches: matched.map(\.qualifiedName)
                )
            }
        }

        /// V2.0 M1.A — summary text emitted to stdout. One line per
        /// reducer plus a tail summary. Byte-stable for tests:
        /// candidates are sorted by `(location, functionName)`, and
        /// the location uses the file path verbatim from
        /// `ReducerDiscoverer`.
        static func renderSummary(candidates: [ReducerCandidate]) -> String {
            if candidates.isEmpty {
                return "swift-infer discover-reducers: no reducer-shaped functions detected.\n"
            }
            let sorted = candidates.sorted { lhs, rhs in
                if lhs.location != rhs.location { return lhs.location < rhs.location }
                return lhs.functionName < rhs.functionName
            }
            var lines: [String] = []
            let suffix = sorted.count == 1 ? "" : "s"
            lines.append(
                "swift-infer discover-reducers — detected \(sorted.count) "
                    + "reducer-shaped function\(suffix):"
            )
            lines.append("")
            for candidate in sorted {
                lines.append(
                    "  \(candidate.location)  \(candidate.qualifiedName)  "
                        + "signature:\(candidate.signatureShape.rawValue)  "
                        + "carrier:\(candidate.carrierKind.rawValue)  "
                        + "state:\(candidate.stateTypeName)  action:\(candidate.actionTypeName)"
                )
                lines.append(contentsOf: renderReducerInteractionCandidates(candidate))
            }
            return lines.joined(separator: "\n") + "\n"
        }

        /// PROTOTYPE — the Redux-distinctive candidate interaction invariants
        /// (`determinism`, `unknownActionIsNoOp`) surfaced over a `.redux`-family
        /// reducer. All unverified (`Possible`); a witness strategy that
        /// constructs the reducer's State and drives an action would measure
        /// them. TCA reducers surface nothing here by design.
        private static func renderReducerInteractionCandidates(
            _ candidate: ReducerCandidate
        ) -> [String] {
            let invariants = ReducerInteractionAnalyzer.analyze(candidate)
            guard !invariants.isEmpty else { return [] }
            var lines = [
                "    candidate interaction invariants "
                    + "(\(invariants.count), unverified — Possible):"
            ]
            for invariant in invariants {
                lines.append(
                    "      - [\(invariant.kind.rawValue)] "
                        + "\(invariant.subjects.joined(separator: ", "))  —  \(invariant.rationale)"
                )
            }
            return lines
        }

        /// PROTOTYPE — renders the `@Observable` / `ObservableObject`
        /// view-model carriers + their action alphabet. One block per view
        /// model: location, observability kind, the State field names, and
        /// each detected action (with `async`/`throws` and a `(transitive)`
        /// marker for methods that mutate only by driving another action).
        static func renderViewModelSummary(_ candidates: [ViewModelCandidate]) -> String {
            if candidates.isEmpty {
                return "swift-infer discover-reducers: no @Observable / "
                    + "ObservableObject view-model carriers detected.\n"
            }
            let suffix = candidates.count == 1 ? "" : "s"
            var lines: [String] = [
                "swift-infer discover-reducers — detected \(candidates.count) "
                    + "view-model carrier\(suffix) (@Observable / ObservableObject):",
                ""
            ]
            for viewModel in candidates {
                lines.append(contentsOf: renderViewModel(viewModel))
            }
            return lines.joined(separator: "\n") + "\n"
        }

        private static func renderViewModel(_ viewModel: ViewModelCandidate) -> [String] {
            let kind = viewModel.observability == .observableMacro
                ? "@Observable" : "ObservableObject"
            let fieldNames = viewModel.stateFields.map(\.name).joined(separator: ", ")
            var lines = [
                "  \(viewModel.location)  \(viewModel.typeName)  [\(kind)]",
                "    state (\(viewModel.stateFields.count)): \(fieldNames)"
            ]
            if !viewModel.excludedFields.isEmpty {
                let excluded = viewModel.excludedFields
                    .map { "\($0.name) [\($0.reason.rawValue)]" }
                    .joined(separator: ", ")
                lines.append("    excluded (\(viewModel.excludedFields.count)): \(excluded)")
            }
            if viewModel.actions.isEmpty {
                lines.append("    actions: (none detected)")
                return lines
            }
            lines.append("    action alphabet (\(viewModel.actions.count)):")
            for action in viewModel.actions {
                let async = action.isAsync ? " async" : ""
                let throwsText = action.isThrows ? " throws" : ""
                let transitive = action.mutatesStateDirectly ? "" : "  (transitive)"
                lines.append("      - \(action.signature)\(async)\(throwsText)\(transitive)")
            }
            lines.append(contentsOf: renderInteractionCandidates(viewModel))
            return lines
        }

        /// PROTOTYPE — renders the SwiftSyntax lint-rule visitor carriers
        /// (issue-accumulating `SyntaxVisitor` subclasses). One block per
        /// visitor: location, the inherited base/conformance, the syntax-node
        /// types it visits, and the rule identifiers it emits. Recognition
        /// only (slice 1) — no candidate invariant is surfaced, by design:
        /// the carrier's generic law (detection determinism) is near-always
        /// true and would flood `.possible`. See
        /// `docs/rule-visitor-carrier-scoping.md`.
        static func renderRuleVisitorSummary(_ candidates: [RuleVisitorCandidate]) -> String {
            if candidates.isEmpty {
                return "swift-infer discover-reducers: no SwiftSyntax lint-rule "
                    + "visitor carriers detected.\n"
            }
            let suffix = candidates.count == 1 ? "" : "s"
            var lines: [String] = [
                "swift-infer discover-reducers — detected \(candidates.count) "
                    + "lint-rule visitor carrier\(suffix) "
                    + "(SwiftSyntax issue-accumulators):",
                ""
            ]
            for visitor in candidates {
                lines.append(contentsOf: renderRuleVisitor(visitor))
            }
            return lines.joined(separator: "\n") + "\n"
        }

        private static func renderRuleVisitor(_ visitor: RuleVisitorCandidate) -> [String] {
            let base = visitor.inheritedTypes.isEmpty
                ? "" : "  [\(visitor.inheritedTypes.joined(separator: ", "))]"
            var lines = [
                "  \(visitor.location)  \(visitor.typeName)\(base)",
                "    visits (\(visitor.visitedNodeTypes.count)): "
                    + visitor.visitedNodeTypes.joined(separator: ", ")
            ]
            if !visitor.emittedRuleNames.isEmpty {
                lines.append(
                    "    emits rules (\(visitor.emittedRuleNames.count)): "
                        + visitor.emittedRuleNames.joined(separator: ", ")
                )
            }
            return lines
        }

        /// PROTOTYPE — renders value-semantics carriers: structs holding
        /// reference-backed storage (a closure / mutable container / corpus
        /// class) through which a copy could leak shared mutable state. One
        /// block per struct: location + Equatability note, the reference-backed
        /// members (with why each qualifies), and the mutation surface.
        /// Recognition only (slice 2) — no invariant is emitted yet. See
        /// docs/valuesemantic-build-plan.md.
        static func renderValueSemanticSummary(_ candidates: [ValueSemanticCandidate]) -> String {
            if candidates.isEmpty {
                return "swift-infer discover-reducers: no value-semantics "
                    + "carriers detected.\n"
            }
            let suffix = candidates.count == 1 ? "" : "s"
            var lines: [String] = [
                "swift-infer discover-reducers — detected \(candidates.count) "
                    + "value-semantics carrier\(suffix) (reference-backed structs):",
                ""
            ]
            for candidate in candidates {
                lines.append(contentsOf: renderValueSemantic(candidate))
            }
            return lines.joined(separator: "\n") + "\n"
        }

        private static func renderValueSemantic(_ candidate: ValueSemanticCandidate) -> [String] {
            let note = candidate.equatability == .equatable
                ? "" : "  [not verify-ready: \(candidate.equatability)]"
            let members = candidate.referenceBackedMembers
                .map { "\($0.name): \($0.typeName) [\($0.kind.rawValue)]" }
                .joined(separator: ", ")
            let surface = candidate.mutationSurface
                .map { $0.isMutating ? $0.name : "\($0.name) (non-mutating)" }
                .joined(separator: ", ")
            let origin = "\(candidate.location.file):\(candidate.location.line)"
            return [
                "  \(origin)  \(candidate.typeName)\(note)",
                "    reference-backed members "
                    + "(\(candidate.referenceBackedMembers.count)): \(members)",
                "    mutation surface (\(candidate.mutationSurface.count)): \(surface)"
            ]
        }

        /// PROTOTYPE — the candidate interaction invariants surfaced over a
        /// view model's action alphabet + State surface. All unverified
        /// (`Possible`); a future witness strategy that constructs the view
        /// model would measure them.
        private static func renderInteractionCandidates(
            _ viewModel: ViewModelCandidate
        ) -> [String] {
            let invariants = ViewModelInteractionAnalyzer.analyze(viewModel)
            guard !invariants.isEmpty else { return [] }
            var lines = [
                "    candidate interaction invariants "
                    + "(\(invariants.count), unverified — Possible):"
            ]
            for invariant in invariants {
                lines.append(
                    "      - [\(invariant.family.rawValue)] "
                        + "\(invariant.subjects.joined(separator: ", "))  —  \(invariant.rationale)"
                )
            }
            return lines
        }
    }
}

/// V1.C — errors thrown by the `discover-reducers` pipeline. Hoisted
/// to file scope (rather than nested under
/// `SwiftInferCommand.DiscoverReducers`) to satisfy SwiftLint's
/// `nesting` 1-level cap — same posture as `VerifyError` and
/// `AcceptCheckResult`. Public so tests can pattern-match on the case
/// rather than the rendered text.
public enum DiscoverReducersError: Error, CustomStringConvertible, Equatable {
    case pinNoMatch(raw: String)
    case pinAmbiguous(raw: String, matches: [String])

    public var description: String {
        switch self {
        case let .pinNoMatch(raw):
            return "swift-infer discover-reducers: no reducer matches pin '\(raw)'."

        case let .pinAmbiguous(raw, matches):
            return "swift-infer discover-reducers: pin '\(raw)' is ambiguous — "
                + "matches \(matches.count) reducers: \(matches.joined(separator: ", ")). "
                + "Lengthen the pin (add a type prefix) to disambiguate."
        }
    }
}
