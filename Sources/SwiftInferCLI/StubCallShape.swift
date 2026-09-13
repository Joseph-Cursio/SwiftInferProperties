import Foundation
import SwiftInferCore

/// How an accepted suggestion's subject is CALLED in the stub it emits.
///
/// ## The defect this closes
///
/// Every accept-path stub spliced the bare function name into the property expression:
/// `funcName(funcName(value))`. That is right for a free function and wrong for everything
/// else, and a type member is nearly everything else. Measured on this repo's own
/// `SwiftInferCore` — 27 emitted stubs, 25 distinct subjects — **0 were free functions**, 20
/// were static members and 5 were instance methods. Compiler-confirmed on a four-shape
/// control: the free-function arm builds clean, and both member arms fail with
/// `cannot find 'staticTrim' in scope`.
///
/// ## The information was already there
///
/// `Evidence` carries `qualifiedTypeName`, `isInstanceMethod`, `isMutatingMethod`,
/// `isComputedProperty` and a labelled `displayName` — and their own doc comments say they
/// exist so *the verify emitter* can choose a call shape. The accept path read none of them
/// and cut the labels off with `functionName(from:)`. **A render defect, not a derivation
/// one**, which is the third time that distinction has decided a fix in this codebase
/// (`docs/measurements/kit-scaffold-conversion.md`).
///
/// The rules here are `VerifyCommand+TemplateDispatch+Bundles`' `labeledCallExpression` and
/// `receiverCallExpression`, applied on the accept side. They are deliberately NOT shared
/// code: that pair is keyed on `SemanticIndexEntry` and this one on `Evidence`, and unifying
/// them means threading one of those types through the other subsystem. The duplication is
/// recorded rather than hidden — see `TargetIsolation`'s note for the same call made about
/// three `dump-package` parsers.
///
/// ## Why an arity, and why declining is the right failure
///
/// An instance method must be called on a receiver: `lhs.merge(rhs)`, never
/// `Doc.merge(lhs, rhs)` — `Doc.merge` is the curried `(Doc) -> (Doc) -> Doc` and does not
/// type-check. The receiver closure `{ $0.merge($1) }` therefore costs one more argument than
/// the method has parameters, and it only fits a template that applies the call with that
/// many. `commutativity` applies two (`f(a, b)`) and fits a one-parameter instance method;
/// `idempotence` applies one (`f(f(x))`) and does not.
///
/// Where they do not fit, **this declines rather than emitting something that cannot
/// compile**. The measured alternative is the 89%-fails-to-compile result in
/// `criterion-a-unmet-subject.md`; a stub that does not build costs the reader more than a
/// suggestion they never saw.
enum StubCallShape {

    /// The expression the stub applies positionally, or `nil` when this subject cannot be
    /// called from a stub that applies `applicationArity` arguments.
    ///
    /// - Parameter applicationArity: how many arguments the template's property expression
    ///   passes — 1 for `idempotence` / `round-trip` / `monotonicity`, 2 for `commutativity` /
    ///   `associativity`.
    static func callExpression(for evidence: Evidence, applicationArity: Int) -> String? {
        guard let bare = InteractiveTriage.functionName(from: evidence.displayName) else {
            return nil
        }
        // Operators never take argument labels and are not members you can qualify: `Money.+`
        // is not a spelling. Left exactly as it was rather than improved — the operator arms
        // have their own emitter path, and changing two things at once makes the A/B
        // unreadable.
        guard !CallExpressionShape.isOperatorName(bare) else { return bare }

        let labels = InteractiveTriage.parameterLabels(from: evidence.displayName)
        guard evidence.isInstanceMethod else {
            return staticOrFreeCall(bare: bare, labels: labels, evidence: evidence)
        }
        return receiverCall(
            bare: bare,
            labels: labels,
            evidence: evidence,
            applicationArity: applicationArity
        )
    }

    // MARK: - Free and static

    /// `Formatter.stripping(from:)` → `{ Formatter.stripping(from: $0) }`;
    /// `Formatter.staticTrim(_:)` → `Formatter.staticTrim`; `freeTrim(_:)` → `freeTrim`.
    ///
    /// A bare function reference is returned wherever it works, so the emitted text stays as
    /// close to the pre-fix output as correctness allows and the diff on a free function is
    /// empty.
    private static func staticOrFreeCall(
        bare: String,
        labels: [String?],
        evidence: Evidence
    ) -> String {
        let qualified = evidence.qualifiedTypeName.map { "\($0).\(bare)" } ?? bare
        guard labels.contains(where: { $0 != nil }) else { return qualified }
        let arguments = labels.enumerated()
            .map { index, label in label.map { "\($0): $\(index)" } ?? "$\(index)" }
            .joined(separator: ", ")
        return "{ \(qualified)(\(arguments)) }"
    }

    // MARK: - Instance

    /// `Doc.merge(_:)` → `{ $0.merge($1) }`, receiver first. Declines a mutating method (it
    /// returns `Void`, so it is not this value-returning shape) and any arity the template
    /// cannot apply.
    private static func receiverCall(
        bare: String,
        labels: [String?],
        evidence: Evidence,
        applicationArity: Int
    ) -> String? {
        guard !evidence.isMutatingMethod else { return nil }
        // A computed property is ACCESSED, not called — the same fact that cost swift-system 5
        // of 6 build failures on the verify side (`criterion-a-swift-system.md` §3). Gated on
        // having no labels as well, because a property with parameters is a disagreement to
        // decline on rather than to resolve silently.
        if evidence.isComputedProperty, labels.isEmpty {
            return applicationArity == 1 ? "{ $0.\(bare) }" : nil
        }
        guard labels.count + 1 == applicationArity else { return nil }
        let arguments = labels.enumerated()
            .map { index, label in
                label.map { "\($0): $\(index + 1)" } ?? "$\(index + 1)"
            }
            .joined(separator: ", ")
        return "{ $0.\(bare)(\(arguments)) }"
    }
}
