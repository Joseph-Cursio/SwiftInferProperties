import Foundation
import PropertyLawCore
import SwiftInferCore
import SwiftInferTemplates

/// The docstring advisory's runnable reference oracle, built the way `accept` builds the
/// determinism stub — or the one-line reason it cannot be.
///
/// ## Why it goes through accept's machinery
///
/// The scaffold used to build its call from the function's bare name, draw from
/// `chooseGenerator` with no project-type resolver, and decline only when the function took no
/// parameters or returned nothing. On SwiftAssist @a89e6e46 none of the 88 scaffolds it printed
/// compiled. The determinism arm of accept states the same law, `f(args) == oracle(args)`, and
/// already had every safeguard, so the scaffold now asks the same questions in the same places:
///
/// - `SubjectCallPlan` spells the call — qualified, receiver first, `try?`, `await` — or names why
///   it cannot be spelled (mutating, `inout`, a closure parameter, a tuple result with no `==`, …);
/// - `GenericSubjectGate` and `UnequatableResultGate` decline what no generator or import fixes;
/// - the accept path's project-type resolver (`projectTypeGenerator` over `presentedShapes`)
///   draws project types, so `[Item]` and a memberwise receiver derive instead of `.gen()`.
///
/// ## Everything printed compiles, or it says why not
///
/// Each shape that cannot compile prints `── no runnable reference oracle: <reason>` in place of
/// the scaffold, so the reader is told the obstacle instead of handed a compile error in code they
/// did not write. A `private` subject names its remedy; an argument no generator derives names the
/// type and the resolver's own reason. Items that printed no scaffold before (no parameters, a
/// lifted-test reference, a `Void` result, no source suggestion) print nothing still.
extension SwiftInferCommand.Discover {

    /// What the reference oracle reads from the scan. Built once per `discover` run; the resolver
    /// is built the first time a generator is chosen, so a run whose advice prints no scaffold
    /// pays nothing for it.
    final class ReferenceOracleContext {
        let typeShapesByName: [String: TypeShape]
        let inheritedTypesByName: [String: Set<String>]
        let equalityOutsideInheritance: Set<String>
        let genericParametersByName: [String: [TypeDecl.GenericParameter]]
        let testVisibleTypeNames: Set<String>
        let typeAliases: [String: String]
        let actorTypeNames: Set<String>

        /// The scanned types' qualified names (`typeShapesByName`'s keys are qualified), against
        /// which a parameter's nested spelling is qualified for a file-scope test.
        let typeUniverse: Set<String>

        /// The scan's access restrictions, keyed by `Discover.coordinate(of:)`.
        let restrictionByCoordinate: [String: AccessRestriction]

        private let hasScan: Bool

        /// The accept path's resolver over the scanned shapes, or `nil` with no scan.
        private(set) lazy var generator: ((String) -> String?)? = hasScan
            ? InteractiveTriage.projectTypeGenerator(types: presentedShapes, aliases: typeAliases)
            : nil

        /// The resolver's own account of a type it could not derive, or `nil` with no scan.
        private(set) lazy var failureReason: ((String) -> String?)? = hasScan
            ? InteractiveTriage.generatorFailureReason(types: presentedShapes, aliases: typeAliases)
            : nil

        private var presentedShapes: [TypeShape] {
            InteractiveTriage.presentedShapes(typeShapesByName: typeShapesByName, visible: testVisibleTypeNames)
        }

        /// No scan: empty tables and no resolver, so a project type draws the `.todo` marker and
        /// the scaffold declines it.
        init() {
            typeShapesByName = [:]
            inheritedTypesByName = [:]
            equalityOutsideInheritance = []
            genericParametersByName = [:]
            testVisibleTypeNames = []
            typeAliases = [:]
            actorTypeNames = []
            typeUniverse = []
            restrictionByCoordinate = [:]
            hasScan = false
        }

        init(pipeline: PipelineResult) {
            typeShapesByName = pipeline.typeShapesByName
            inheritedTypesByName = pipeline.inheritedTypesByName
            equalityOutsideInheritance = pipeline.equalityOutsideInheritance
            genericParametersByName = pipeline.genericParametersByName
            testVisibleTypeNames = pipeline.testVisibleTypeNames
            typeAliases = pipeline.typeAliases
            actorTypeNames = ActorReceiver.actorTypeNames(in: pipeline.typeShapesByName)
            typeUniverse = Set(pipeline.typeShapesByName.keys)
            restrictionByCoordinate = Dictionary(
                pipeline.restrictedFunctions.map { (coordinate(of: $0.summary.location), $0.restriction) }
            ) { first, _ in first }
            hasScan = true
        }

        static var unscanned: ReferenceOracleContext { ReferenceOracleContext() }
    }

    /// A scaffold to print, or the reason none can compile.
    enum ReferenceOracleOutcome: Equatable {
        case scaffold(String)
        case declined(String)

        var scaffold: String? {
            guard case let .scaffold(text) = self else { return nil }
            return text
        }

        var decline: String? {
            guard case let .declined(reason) = self else { return nil }
            return reason
        }
    }

    /// Templates whose reference-definition advisory carries a runnable
    /// oracle stub: a `predicate` (the docstring IS the boolean law) and a
    /// `comparator` (the docstring is the ordering KEY the strict-weak-ordering
    /// law can't capture). Both are Bool-returning functions the emitter handles
    /// uniformly — a comparator is just a two-argument predicate on ordering.
    private static let oracleStubTemplates: Set<String> = ["predicate", "comparator"]

    /// The reference oracle for a documented function: a scaffold that compiles, the reason it
    /// cannot, or `nil` where the advisory never offered one.
    ///
    /// The checks run in a fixed order, and the first that fires is the one printed: access,
    /// initializer, generic subject, the call plan, a type the test cannot name, the result's
    /// `==`, then each argument's generator.
    static func referenceOracleOutcome(
        for summary: FunctionSummary,
        advisory: DocstringAdvisory,
        suggestions: [Suggestion],
        context: ReferenceOracleContext
    ) -> ReferenceOracleOutcome? {
        guard let docComment = summary.docComment,
              let suggestion = oracleSourceSuggestion(for: summary, advisory: advisory, suggestions: suggestions)
        else { return nil }
        if let reason = subjectDeclineReason(for: summary, context: context) {
            return .declined(reason)
        }
        let evidence = ActorReceiver.marking(summary.inferenceEvidence, actorTypeNames: context.actorTypeNames)
        let plan: SubjectCallPlan
        switch SubjectCallPlan.outcome(for: evidence, typeUniverse: context.typeUniverse) {
        case let .declined(reason): return .declined(reason)
        case let .plan(planned): plan = planned
        }
        if let reason = unnameableTypeReason(plan: plan, summary: summary, context: context)
            ?? UnequatableResultGate.declineReason(
                display: evidence.displayName,
                returnTypeText: plan.returnTypeText,
                owner: evidence.qualifiedTypeName,
                typeShapesByName: context.typeShapesByName,
                inheritedTypesByName: context.inheritedTypesByName,
                typeUniverse: context.typeUniverse,
                equalityOutsideInheritance: context.equalityOutsideInheritance
            ) {
            return .declined(reason)
        }
        let draws: LiftedTestEmitter.ReferenceOracleDraws
        switch oracleDraws(plan: plan, summary: summary, suggestion: suggestion, context: context) {
        case let .failure(decline): return .declined(decline.reason)
        case let .success(drawn): draws = drawn
        }
        let subject = LiftedTestEmitter.ReferenceOracleSubject(
            callee: plan.callee,
            owner: evidence.qualifiedTypeName,
            parameters: summary.parameters,
            returnTypeText: plan.returnTypeText,
            isAsync: plan.isAsync,
            isThrows: plan.isThrows,
            declaresNonisolated: summary.declaresNonisolated
        )
        return .scaffold(LiftedTestEmitter.referenceOracle(
            subject: subject,
            draws: draws,
            equalityKind: plan.equalityKind,
            docComment: docComment,
            seed: SamplingSeed.derive(from: suggestion.identity)
        ))
    }

    /// The suggestion a scaffold takes its seed and generators from, or `nil` for the shapes that
    /// have never printed one: no parameters, a lifted-test reference, another template's
    /// reference, a `Void` result, or no suggestion to draw from.
    private static func oracleSourceSuggestion(
        for summary: FunctionSummary,
        advisory: DocstringAdvisory,
        suggestions: [Suggestion]
    ) -> Suggestion? {
        guard !summary.parameters.isEmpty else { return nil }
        switch advisory {
        case let .referenceDefinition(reference):
            guard oracleStubTemplates.contains(reference.template), !reference.fromLiftedTest else {
                return nil
            }
            return suggestions.first { $0.templateName == reference.template }

        case .fallbackContract, .complementaryContract:
            // The docstring is the contract the templates could not name — either because
            // nothing role-entailed fired at all, or because what fired is unreachable by
            // realistic input and so checks something else. Both want the same scaffold: make
            // the sentence runnable as a from-the-spec reference implementation, which needs a
            // concrete, non-Void return to compare against. Any surviving pick (determinism /
            // red herring) gives a stable seed and generator source.
            guard let returned = summary.returnTypeText, returned != "Void", returned != "()" else {
                return nil
            }
            return suggestions.first
        }
    }

    /// Steps 1 to 3, which need the function but not its call: no test can call it, it is an
    /// initializer, or it names a type parameter no test can bind.
    private static func subjectDeclineReason(
        for summary: FunctionSummary,
        context: ReferenceOracleContext
    ) -> String? {
        let owner = summary.qualifiedContainingTypeName ?? summary.containingTypeName
        let display = "`\(owner.map { "\($0)." } ?? "")\(displayName(for: summary))`"
        // `internalOrSPI` is the one restriction `@testable import` lifts (SPI aside).
        if let restriction = context.restrictionByCoordinate[coordinate(of: summary.location)],
           restriction != .internalOrSPI {
            return "\(display) cannot be called from a test: \(restriction.remedy)"
        }
        if summary.isInitializer {
            return "\(display) is an initializer; the reference oracle calls functions and methods only"
        }
        return GenericSubjectGate.declineReason(
            for: summary.inferenceEvidence,
            owner: owner,
            genericParametersByName: context.genericParametersByName
        )
    }
}
