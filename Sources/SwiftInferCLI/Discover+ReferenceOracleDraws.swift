import Foundation
import PropertyLawCore
import SwiftInferCore
import SwiftInferTemplates

/// What the reference oracle draws, and the two declines that depend on the drawn types: a type a
/// test file cannot name, and an argument no generator derives. Split from
/// `Discover+ReferenceOracle.swift` for SwiftLint's file-length cap.
extension SwiftInferCommand.Discover {

    /// Why the oracle cannot be built, carried through a `Result`.
    struct ReferenceOracleDecline: Error, Equatable {
        let reason: String
    }

    /// One generator per call argument, receiver first, plus the `Sendable` shims the drawn types
    /// need — or the first argument nothing derives for.
    ///
    /// A placeholder is never printed: the scaffold's promise is that it compiles once the
    /// `fatalError` line is replaced, and the `.gen()` marker `defaultGenerator` writes for an
    /// underived type does not. The decline names the type the draw stops at and the resolver's
    /// reason, which is what the reader has to act on.
    static func oracleDraws(
        plan: SubjectCallPlan,
        summary: FunctionSummary,
        suggestion: Suggestion,
        context: ReferenceOracleContext
    ) -> Result<LiftedTestEmitter.ReferenceOracleDraws, ReferenceOracleDecline> {
        var generators: [String] = []
        for (index, typeName) in plan.argumentTypes.enumerated() {
            let generator = oracleGenerator(for: suggestion, typeName: typeName, context: context)
            if LiftedTestEmitter.isUnresolvedGenerator(generator) {
                let role = argumentRole(at: index, plan: plan, summary: summary)
                return .failure(
                    generatorDecline(typeName: typeName, role: role, suggestion: suggestion, context: context)
                )
            }
            generators.append(generator)
        }
        let shims = plan.argumentTypes.reduce(into: Set<String>()) { result, spelling in
            result.formUnion(SendableShim.types(
                in: spelling,
                visible: context.testVisibleTypeNames,
                shapes: context.typeShapesByName,
                inheritedTypes: context.inheritedTypesByName
            ))
        }
        return .success(.init(generators: generators, argumentTypes: plan.argumentTypes, sendableShims: shims.sorted()))
    }

    /// `chooseGenerator` with the accept path's resolver — and its mock arm only for the type the
    /// mock was inferred for. `chooseGenerator` returns a suggestion's mock for EVERY type it is
    /// asked about, which a one-carrier law never noticed and a receiver-plus-arguments draw would.
    static func oracleGenerator(
        for suggestion: Suggestion,
        typeName: String,
        context: ReferenceOracleContext
    ) -> String {
        var source = suggestion
        if source.mockGenerator?.typeName != typeName {
            source.mockGenerator = nil
        }
        return InteractiveTriage.chooseGenerator(
            for: source,
            typeName: typeName,
            customGenerator: context.generator,
            failureReason: context.failureReason
        )
    }

    /// Why a scanned type the call or the reference names cannot be written in a test file, or
    /// `nil`.
    ///
    /// The scan sets aside a function that is itself `private`, or inside a `private` type
    /// (`AccessRestriction`), and `subjectDeclineReason` answers for those. It cannot see a member
    /// of an unmarked `extension PrivateType`, nor a visible function that takes or returns a
    /// `private` type — and a test file can name neither, nor extend the first.
    static func unnameableTypeReason(
        plan: SubjectCallPlan,
        summary: FunctionSummary,
        context: ReferenceOracleContext
    ) -> String? {
        let owner = summary.qualifiedContainingTypeName
        let result = TypeShapeBuilder.resolvedSpelling(
            owner.map { SubjectCallPlan.replacingSelf(in: plan.returnTypeText, with: $0) } ?? plan.returnTypeText,
            enclosing: owner ?? "",
            universe: context.typeUniverse
        )
        let spellings = [owner].compactMap(\.self) + plan.argumentTypes + [result]
        let hidden = spellings.lazy.flatMap(typeNames(in:)).first { name in
            context.typeShapesByName[name]?.hasPrimaryDeclaration == true
                && context.testVisibleTypeNames.contains(name) == false
        }
        guard let hidden else { return nil }
        return "`\(owner.map { "\($0)." } ?? "")\(displayName(for: summary))` cannot be called from a test: it "
            + "names `\(hidden)`, which is `private` or `fileprivate` (or nested in a type that is), so no "
            + "test file can name it. Widen it to `internal`."
    }

    /// `the receiver`, or the parameter at `index` as its label reads in the call.
    private static func argumentRole(at index: Int, plan: SubjectCallPlan, summary: FunctionSummary) -> String {
        let parameterIndex = index - (plan.callee.isInstanceMethod ? 1 : 0)
        guard parameterIndex >= 0 else { return "its receiver" }
        guard parameterIndex < summary.parameters.count else { return "argument \(index + 1)" }
        let parameter = summary.parameters[parameterIndex]
        return "its `\(parameter.label ?? "_ \(parameter.internalName)"):` argument"
    }

    /// The decline for an argument nothing derives for, naming the type the draw stops at: a
    /// scanned type inside the spelling that does not derive on its own (`Item` in `[Item]`), or
    /// the spelling itself.
    ///
    /// The remedy is `static func gen()` only where there is a declaration to put it on: a type
    /// the scan shaped (or any type, with no scan to say otherwise). A foreign type
    /// (`Range<Int>`), a structural one (`[(version: String, remediation: String?)]`), an
    /// existential or a bare generic owner (`Array`) has none in the scanned sources, so the
    /// reader is told to write that check by hand instead.
    private static func generatorDecline(
        typeName: String,
        role: String,
        suggestion: Suggestion,
        context: ReferenceOracleContext
    ) -> ReferenceOracleDecline {
        let inner = typeNames(in: typeName).first { name in
            guard name != typeName, context.typeUniverse.contains(name) else { return false }
            let generator = oracleGenerator(for: suggestion, typeName: name, context: context)
            return LiftedTestEmitter.isUnresolvedGenerator(generator)
        }
        let blocked = inner ?? typeName
        let because = context.failureReason?(blocked).map { " (\($0))" } ?? ""
        let remedy = context.typeUniverse.contains(blocked) || context.hasScan == false
            ? "supply `static func gen()` on `\(blocked)`, then re-run discover"
            : "`\(blocked)` is not a concrete type the scanned sources declare, so there is no declaration to "
                + "give a `static func gen()`; write this check by hand"
        return ReferenceOracleDecline(
            reason: "no generator derives for `\(blocked)`\(because), so the oracle cannot draw \(role) — \(remedy)"
        )
    }

    /// The dotted type names a spelling mentions — `[Outer.Inner: Int]` → `Outer.Inner`, `Int`.
    private static func typeNames(in spelling: String) -> [String] {
        let identifier = /[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*/
        return spelling.matches(of: identifier).map { String($0.output) }
    }
}
