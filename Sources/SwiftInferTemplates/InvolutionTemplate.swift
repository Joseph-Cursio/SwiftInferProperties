import SwiftInferCore

/// The **involution** law: `f(f(x)) == x` — applying a self-inverse function
/// twice returns the original.
///
/// This template exists because the engine already *knows* these functions and
/// says nothing useful about them. `reverse`, `negate`, `toggle`, `invert`,
/// `complement`, `twosComplement` are curated in `MutatorBlockedFromIdempotence`
/// — but only *negatively*, to veto them from idempotence, because
/// `reverse(reverse(x)) == x`, not `reverse(x)`. That veto is a fact stated and
/// then discarded: the engine recognizes an involution precisely so it can
/// refuse to call it idempotent, and then proposes no law at all. This template
/// is the positive half — it turns that recognition into the law the function
/// actually owes.
///
/// **The name is required to fire.** Every `(T) -> T` is a candidate *shape*,
/// but almost none is an involution — so unlike idempotence (which surfaces the
/// shape alone at `Possible`), this template stays silent without a curated
/// involution verb. A law that fired on every endomorphism would be the Daikon
/// flood the catalogue exists to avoid; a law that fires only on `transposed` /
/// `inverted` / `negated` is refutable and specific.
///
/// **Refutable:** a `reverse` that trims one element too many, a `negate` with a
/// sign bug, a `transpose` that mishandles a non-square shape — each fails
/// `f(f(x)) == x`, and none is caught by an example test that only checks one
/// direction.
public enum InvolutionTemplate {

    /// Canonical involution verbs — functions that are their own inverse. Both
    /// the base form (a free/static `negate(_ x:) -> T`) and the past-participle
    /// form (an instance `x.negated() -> T`) appear, since Swift's naming
    /// convention splits mutating (`negate`) from non-mutating (`negated`).
    ///
    /// The mathematically-canonical involutions (`reversed`, `negated`,
    /// `inverted`, `complemented`, `transposed`, `conjugated`, `twosComplement`)
    /// are self-inverse by definition. `flipped` / `mirrored` / `swapped` /
    /// `toggled` are involutions in the common case but carry a caveat: confirm
    /// the operation is genuinely self-inverse for the type in question.
    public static let curatedVerbs: Set<String> = [
        "reverse", "reversed",
        "negate", "negated",
        "invert", "inverted",
        "complement", "complemented",
        "transpose", "transposed",
        "conjugate", "conjugated",
        "twosComplement",
        "flipped",
        "mirrored",
        "swapped",
        "toggled"
    ]

    public static func suggest(for summary: FunctionSummary) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: summary)
    }

    public static func makeConstraint() -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "involution",
            appliesTo: Self.isInvolution,
            signals: Self.signals(for:),
            evidence: { [$0.inferenceEvidence] },
            identity: { summary in
                SuggestionIdentity(canonicalInput: "involution|" + Self.canonicalSignature(of: summary))
            },
            carrier: { $0.containingTypeName },
            // The generator carrier is `T` — the return type, which the two
            // accepted shapes both make equal to the operand: the parameter type
            // (free form) or the containing type (instance form).
            carrierType: { $0.returnTypeText },
            caveats: { _ in Self.makeCaveats() }
        )
    }

    /// A unary endomorphism named like an involution. Two accepted shapes:
    ///   - **free / static:** exactly one non-`inout` parameter whose type is the
    ///     return type — `func negate(_ x: Int) -> Int`;
    ///   - **instance:** zero parameters, returning the containing type —
    ///     `func inverted() -> Matrix` (`self -> Self`).
    /// Mutating, async, throwing, and operator declarations are excluded.
    static func isInvolution(_ summary: FunctionSummary) -> Bool {
        guard curatedVerbs.contains(summary.name),
              !summary.isAsync,
              !summary.isThrows,
              !summary.isMutating,
              !isOperator(summary.name),
              let returnType = summary.returnTypeText,
              returnType != "Void",
              returnType != "()" else {
            return false
        }
        // Free / static: `(T) -> T`.
        if summary.parameters.count == 1,
           let param = summary.parameters.first,
           !param.isInout,
           param.typeText == returnType {
            return true
        }
        // Instance: `self -> Self`. The return may be written as the literal `Self`
        // (`func inverted() -> Self`) — canonicalize it to the container. Involution is
        // name-gated (a curated verb is required above), so this stays low-volume; and
        // it is the nullary self-form only, so the binary-param hazard is untouched.
        if summary.parameters.isEmpty,
           let container = summary.containingTypeName,
           container == returnType || returnType == "Self" {
            return true
        }
        return false
    }

    static func signals(for summary: FunctionSummary) -> [Signal] {
        guard isInvolution(summary), let returnType = summary.returnTypeText else {
            return []
        }
        var signals = [
            Signal(
                kind: .typeSymmetrySignature,
                weight: 30,
                detail: "Type-symmetry signature: T -> T (T = \(returnType))"
            ),
            Signal(
                kind: .involutionSignature,
                weight: 40,
                detail: "Involution verb match: '\(summary.name)' — applying it twice "
                    + "returns the original, so it owes `f(f(x)) == x`"
            )
        ]
        // Corroborate-only docstring signal (+15): a documented `self-inverse` /
        // `own inverse` / `twice returns the original` raises the tier of the
        // already name+shape-matched involution. Negation-gated at the source.
        if let corroboration = DocstringPropertyCorroborator.corroboration(
            for: .involution,
            in: summary.docComment
        ) {
            signals.append(
                Signal(
                    kind: .docstringCorroboration,
                    weight: 15,
                    detail: "Docstring corroborates involution: '\(corroboration.matchedPhrase)'"
                )
            )
        }
        return signals
    }

    private static func isOperator(_ name: String) -> Bool {
        name.allSatisfy { !$0.isLetter && !$0.isNumber && $0 != "_" }
    }

    /// Stable identity string, mirroring `IdempotenceTemplate`'s form so the two
    /// closely-related templates hash consistently.
    static func canonicalSignature(of summary: FunctionSummary) -> String {
        let typePrefix = summary.containingTypeName.map { "\($0)." } ?? ""
        let labels = summary.parameters.map { ($0.label ?? "_") + ":" }.joined()
        let paramTypes = summary.parameters.map(\.typeText).joined(separator: ",")
        let returnType = summary.returnTypeText ?? "Void"
        return "\(typePrefix)\(summary.name)(\(labels))|(\(paramTypes))->\(returnType)"
    }

    static func makeCaveats() -> [String] {
        [
            "THE LAW IS `f(f(x)) == x` — self-inverse, NOT idempotent. An involution applied twice "
                + "returns the ORIGINAL, so `f(x) != x` for almost every x. If applying it once "
                + "already equals x, it is the identity, not an involution — and if `f(f(x)) == f(x)` "
                + "instead, it is idempotent. These three are distinct; only one law is right.",
            "CONFIRM the name names a genuine self-inverse. `reversed` / `negated` / `transposed` / "
                + "`conjugated` / `inverted` are involutions by definition; `flipped` / `mirrored` / "
                + "`swapped` usually are, but a flip that also translates, or a mirror across a moving "
                + "axis, is not self-inverse.",
            "T must conform to Equatable for the emitted property to compile."
        ]
    }
}
