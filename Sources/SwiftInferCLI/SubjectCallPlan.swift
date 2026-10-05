import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// How a test calls the subject of an agreement law — `f(args) == oracle(args)` — or the named
/// reason it cannot.
///
/// ## Why this is one type
///
/// Two places asked these questions and had to agree: `InteractiveTriage.deterministicStub`, which
/// writes the stub, and `StubApplicationArity.declineReason`, which tells the reader why it did
/// not. They were *kept in step* by prose and by tests that pinned both sides of each row — and
/// one row had already drifted: the `inout` decline read `inout ` off the rendered signature,
/// which the scanner never renders (`FunctionScannerVisitor.strippingParameterSpecifiers`), so a
/// scanned `inout` subject got a stub that passed a drawn `let` to it and could not compile.
/// Both now read one `Outcome`, so a plan exists exactly when no reason does. The docstring
/// advisory's reference oracle states the same law against `<name>_reference` and needs the
/// same answer.
///
/// ## The order
///
/// The first check that fires wins, and each later check may assume the earlier ones passed:
///
/// 1. the result's tuple shape (`determinismResultDeclineReason`);
/// 2. a `mutating` method, which no drawn (immutable) receiver can call;
/// 3. no arguments at all, so nothing to range over;
/// 4. an instance method with no recorded type, so no receiver to draw;
/// 5. a function-typed parameter, which no generator draws — asked before 7, because
///    `parameterTypes(from:)` cuts the signature at its first `->` and mis-splits it: a lone
///    closure parameter used to be drawn from a generator for `(Int`, and one beside others was
///    reported as a label-count mismatch;
/// 6. an `inout` parameter, read from `Evidence.inoutParameterIndices`;
/// 7. labels and parameter types that disagree in number;
/// 8. no value to compare;
/// 9. a function-typed result, which `==` cannot compare.
///
/// ⚠ **Step 6 is the determinism and reference-oracle plan's alone.** The shared arity-free
/// checks (`arityFreeArgumentTypes`, `StubApplicationArity.arityFreeDeclineReason`) are left
/// reading the signature, because totality shares them and writes an `inout` subject correctly
/// through a `var` copy (`totalityStub`).
///
/// Whether the RESULT type has `==` at all is not asked here: that needs the scanned types, and
/// is `UnequatableResultGate`'s question.
struct SubjectCallPlan: Equatable {

    /// The subject, spelled as accept spells it.
    let callee: CalleeReference

    /// One type per drawn argument — the declaring type first for an instance method's receiver,
    /// then each parameter, with `Self` spelled as the declaring type and nested names qualified
    /// against the plan's type universe.
    let argumentTypes: [String]

    /// The result type as declared, effects stripped.
    let returnTypeText: String

    let isAsync: Bool
    let isThrows: Bool

    /// How two results are compared: approximately for a floating-point result.
    var equalityKind: LiftedTestEmitter.EqualityKind {
        InteractiveTriage.equalityKind(forTypeText: returnTypeText)
    }

    enum Outcome: Equatable {
        case plan(SubjectCallPlan)
        case declined(String)
    }

    /// The plan for `evidence`, or the first reason it cannot be called.
    ///
    /// - Parameter typeUniverse: the qualified names against which a parameter's nested spelling
    ///   is qualified (`Inner` inside `Outer` is `Outer.Inner` in a test file) — the scanned
    ///   types, and for the reference oracle the aliases nested in them too (`Account.ID`).
    ///   Empty leaves every spelling as written, which is what accept passes today.
    static func outcome(for evidence: Evidence, typeUniverse: Set<String> = []) -> Outcome {
        if let reason = InteractiveTriage.determinismResultDeclineReason(for: evidence) {
            return .declined(reason)
        }
        guard let callee = CalleeReference(evidence: evidence) else {
            return .declined(evidence.isMutatingMethod
                ? "\(evidence.displayName) is a `mutating` method, so it cannot be called on a drawn "
                    + "receiver, which is immutable"
                : "\(evidence.displayName) names no function a call can spell")
        }
        if let reason = callShapeDeclineReason(callee: callee, evidence: evidence) {
            return .declined(reason)
        }
        guard let argumentTypes = InteractiveTriage.arityFreeArgumentTypes(callee: callee, evidence: evidence) else {
            let parameters = InteractiveTriage.parameterTypes(from: evidence.signature)
            return .declined("\(callee.displaySignature) records \(callee.argumentLabels.count) argument "
                + "label(s) and \(parameters.count) parameter type(s), so the call cannot be spelled "
                + "reliably")
        }
        let effects = InteractiveTriage.determinismEffects(in: evidence.signature)
        let returned = InteractiveTriage.returnType(from: strippingEffects(evidence.signature))
        guard let returnTypeText = returned, returnTypeText != "Void", returnTypeText != "()" else {
            return .declined("\(evidence.displayName) returns no value to compare")
        }
        if returnTypeText.contains("->") {
            return .declined("\(evidence.displayName) returns a function (`\(returnTypeText)`), which `==` "
                + "cannot compare")
        }
        let owner = evidence.qualifiedTypeName
        return .plan(Self(
            callee: callee,
            argumentTypes: spelled(argumentTypes, callee: callee, owner: owner, universe: typeUniverse),
            returnTypeText: returnTypeText,
            isAsync: effects.isAsync,
            isThrows: effects.isThrows
        ))
    }

    /// The reason `outcome(for:)` declines, or `nil` when it plans a call.
    static func declineReason(for evidence: Evidence) -> String? {
        guard case let .declined(reason) = outcome(for: evidence) else { return nil }
        return reason
    }

    /// Steps 3 to 6: the questions about the call's shape that need the callee but not the split
    /// parameter list.
    private static func callShapeDeclineReason(callee: CalleeReference, evidence: Evidence) -> String? {
        // A static computed property or a static nullary function is called with nothing, so
        // there is no input for "every input" to range over.
        if callee.applicationArity == 0 {
            return "\(callee.displaySignature) takes no arguments, so there is no input for the law "
                + "to range over"
        }
        if callee.isInstanceMethod, evidence.qualifiedTypeName == nil {
            return "\(callee.displaySignature) is an instance method with no recorded enclosing type, "
                + "so there is no receiver to draw"
        }
        // Read from the scanner's own list: the rendered signature is what mis-splits.
        if let closure = evidence.parameterTypeNames.first(where: { $0.contains("->") }) {
            return "\(callee.displaySignature) takes a function-typed parameter (`\(closure)`), and no "
                + "generator draws a function"
        }
        // The specifier is stripped from the rendered type, so the scanner's index list is the
        // evidence; a hand-built row may still spell it, and is read the old way too.
        let rendered = InteractiveTriage.parameterTypes(from: evidence.signature)
        if !evidence.inoutParameterIndices.isEmpty || rendered.contains(where: { $0.hasPrefix("inout ") }) {
            return "\(callee.displaySignature) takes an `inout` parameter, and a drawn value is "
                + "immutable, so the call cannot be spelled"
        }
        return nil
    }

    /// `signature` with the subject's own effects removed, so the result reads as the type after
    /// `->`. The emitter re-applies them as `await` / `try?` on each call.
    static func strippingEffects(_ signature: String) -> String {
        signature
            .replacingOccurrences(of: " async throws ->", with: " ->")
            .replacingOccurrences(of: " async ->", with: " ->")
            .replacingOccurrences(of: " throws ->", with: " ->")
    }

    /// Each argument type as a test file must write it. The receiver is the declaring type and
    /// is already spelled that way; a parameter's `Self` becomes the declaring type — a test file
    /// has no `Self` — and its nested names are qualified against `universe`.
    private static func spelled(
        _ types: [String],
        callee: CalleeReference,
        owner: String?,
        universe: Set<String>
    ) -> [String] {
        guard let owner else { return types }
        let receiverCount = callee.isInstanceMethod ? 1 : 0
        return types.enumerated().map { index, type in
            guard index >= receiverCount else { return type }
            let selfless = replacingSelf(in: type, with: owner)
            return TypeShapeBuilder.resolvedSpelling(selfless, enclosing: owner, universe: universe)
        }
    }

    /// `spelling` with every whole-word `Self` replaced by `owner`: `[Self]` → `[Owner]`,
    /// `Self.Element` → `Owner.Element`, and `SelfType` or `x.Self` untouched.
    static func replacingSelf(in spelling: String, with owner: String) -> String {
        spelling.replacingOccurrences(
            of: #"(?<![A-Za-z0-9_.])Self(?![A-Za-z0-9_])"#,
            with: NSRegularExpression.escapedTemplate(for: owner),
            options: .regularExpression
        )
    }
}
