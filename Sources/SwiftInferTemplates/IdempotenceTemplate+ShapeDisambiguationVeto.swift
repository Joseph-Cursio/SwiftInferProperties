import SwiftInferCore

/// V1.24.D — capacity-from-scale + formatter shape-disambiguation veto
/// on `IdempotenceTemplate.suggest(for:)` non-lifted path. Direct cycle-20
/// finding closure (the 5-cycle-flat 0% idempotence non-lifted rate is
/// dominated by shape-coincidence patterns where the function's
/// signature matches `(T) -> T` but the semantic content is NOT
/// idempotent).
///
/// Two shape-coincidence classes vetoed:
///
/// 1. **Capacity-from-scale shape.** Function name matches `*Capacity*`
///    or `*Count*` AND first-parameter label is `forScale:` or
///    `forCapacity:` AND `(Int) -> Int` shape. Examples:
///    `_minimumCapacity(forScale:)`, `_maximumCapacity(forScale:)`,
///    `wordCount(forScale:)`, `_scale(forCapacity:)`. The idempotence
///    claim `f(f(scale)) == f(scale)` is meaningless — capacity-of-
///    capacity (or word-count-of-word-count) is a shape-coincidence,
///    not a fixed-point operation.
///
/// 2. **Formatter shape**, split into two arms because the original
///    single arm bundled two different arguments and applied the union of
///    their triggers with neither of their conditions:
///
///    - `_description*` — **structural wrapping**, no type gate.
///      `_description(type:)` prepends a type wrapper, so applying it twice
///      prepends twice. That is a claim about what the function does to a
///      value and holds at `(String) -> String` as much as anywhere.
///    - `format*` — the **type** argument, gated on `param != return`. The
///      stated rationale was that `format(_:) -> String` over non-`String`
///      input cannot be applied to its own result, and that only obtains when
///      the parameter and return types differ.
///
///    The bundling cost a real law. `format(_ s: String) -> String` is a
///    source formatter, `format(format(x)) == format(x)` is the canonical
///    law it owes, and the veto suppressed it on the name prefix while
///    `curatedVerbs` was simultaneously crediting that same name +40. See
///    `docs/parsing-catalog-gap.md` §4.
///
///    **Where the gate leaves `format*`, stated plainly.** Only two arms of
///    `typeSymmetrySignal` admit a parameter — the exact-equal form and the
///    optional-narrowing form (`func mergedWith(_ x: T?) -> T`) — so once
///    gated, `format*` fires on `(T?) -> T` and nothing else. On that one
///    shape the original *type* rationale is false too: `format(format(x))`
///    type-checks, because `T` promotes back to `T?`, which is precisely why
///    the optional-narrowing arm admits it. The arm therefore states the
///    weaker claim that is actually true — a function collapsing "absent"
///    into a concrete value is defaulting, and the second application asks a
///    different question — and labels it a conjecture rather than a type
///    error. Deleting the arm outright is a defensible follow-on; it is kept
///    because narrowing a veto is a precision change and measurement shows
///    keeping it costs nothing.
///
/// Fires `Signal.vetoWeight` when either pattern matches. Wired into
/// `IdempotenceTemplate.suggest(for:)` (non-lifted path only).
///
/// Mechanism class: extension of class 7 (function-name + type-shape
/// composite, V1.14.1 / V1.16.1 / V1.21.C lineage). Third extension in
/// the lineage (SetAlgebra → math-forward → capacity/formatter).
extension IdempotenceTemplate {

    /// Returns a veto `Signal` when the summary matches one of the two
    /// shape-coincidence patterns. `nil` otherwise.
    ///
    /// Wired into `IdempotenceTemplate.suggest(for:)` alongside the
    /// existing `setAlgebraShapeVeto`, `mathForwardFunctionVeto`,
    /// `assumedKitCoverage`, etc.
    static func shapeDisambiguationVeto(for summary: FunctionSummary) -> Signal? {
        // Common shape gate: single non-inout param, non-mutating,
        // non-Void return (the typeSymmetry shape gate from
        // typeSymmetrySignal). Re-checked here so the veto is robust
        // to call-site re-ordering.
        guard summary.parameters.count == 1,
              let param = summary.parameters.first,
              !param.isInout,
              !summary.isMutating,
              let returnType = summary.returnTypeText,
              returnType != "Void",
              returnType != "()" else {
            return nil
        }

        let name = summary.name

        // Pattern 1: capacity / scale domain conversion — `(Int) -> Int`
        // shape AND name contains a domain-conversion token AND first-
        // param label is a cross-domain marker. Both conditions required
        // to avoid false positives on curated idempotence verbs that
        // happen to use `forScale:` etc. (e.g., `normalize(forScale:)`).
        //
        // Catches both directions:
        //   - `_minimumCapacity(forScale:)` (capacity-FROM-scale)
        //   - `_scale(forCapacity:)` (scale-FROM-capacity; "Scale" / "scale" in name)
        //   - `wordCount(forScale:)` (Count token)
        // Skips: `normalize(forScale:)`, `simplify(forScale:)` (no
        // Capacity/Count/Scale token in name).
        if returnType == "Int", param.typeText == "Int" {
            let domainTokens = ["Capacity", "Count", "Scale", "scale"]
            let nameHit = domainTokens.contains { name.contains($0) }
            let labelHit: Bool = {
                guard let label = param.label else { return false }
                return label == "forScale" || label == "forCapacity"
            }()
            if nameHit, labelHit {
                let labelStr = param.label ?? "_"
                return Signal(
                    kind: .protocolCoveredProperty,
                    weight: Signal.vetoWeight,
                    detail: "Shape-coincidence: '\(name)(\(labelStr):)' is a "
                        + "cross-domain Int conversion (capacity↔scale family) "
                        + "with `(Int) -> Int` shape; `\(name)(\(name)(s))` "
                        + "is a type-shape coincidence, not an idempotent "
                        + "fixed-point operation"
                )
            }
        }

        return formatterVeto(name: name, param: param, returnType: returnType)
    }

    /// The two formatter arms of pattern 2, split from the main veto body to
    /// stay under the function-length cap. They are two different arguments
    /// and are gated differently — see the type's doc comment.
    private static func formatterVeto(
        name: String,
        param: Parameter,
        returnType: String
    ) -> Signal? {
        // Pattern 2a: `_description*` — STRUCTURAL WRAPPING, so no type gate.
        // `_description(type:)` prepends a type wrapper; applying it twice
        // prepends twice. That argument is about what the function does to a
        // value, not about the types, so it holds at `(String) -> String` too.
        if name.hasPrefix("_description") {
            return Signal(
                kind: .protocolCoveredProperty,
                weight: Signal.vetoWeight,
                detail: "Shape-coincidence: '\(name)' prepends a structural "
                    + "wrapper (prefix `_description`), so `\(name)(\(name)(x))` "
                    + "compounds it — the type info is prepended twice, which "
                    + "is not idempotent"
            )
        }

        // Pattern 2b: `format*` — the TYPE argument, so it takes the type gate.
        //
        // §4 of `docs/parsing-catalog-gap.md`. The rationale this veto has
        // always stated is a type mismatch: "`format(_:)` returns String for
        // non-String input", so `format(format(x))` cannot type-check. True —
        // and it only obtains when the parameter type differs from the return
        // type. The veto fired on the *name prefix alone*, so it also fired at
        // `(String) -> String`, where the argument does not apply and where
        // idempotence is the canonical law a source formatter owes.
        //
        // Measured before the fix, on identical `String -> String` shapes:
        // `normalize` scored 75 Strong, `format` and `formatSource` were
        // suppressed. `format` is in `curatedVerbs` and earns +40 there, so
        // the catalog was crediting the verb and then vetoing it on the same
        // name.
        //
        // **The gate is narrow, and worth being honest about.** Only two arms
        // of `typeSymmetrySignal` admit a parameter at all: the exact-equal
        // form (`param == return`, now correctly not vetoed) and the
        // optional-narrowing form (`func mergedWith(_ x: T?) -> T`). So this
        // arm now fires on `format(_ x: T?) -> T` and nothing else.
        //
        // And on that one shape the ORIGINAL wording would have been false as
        // well: `format(format(x))` type-checks fine, because `T` promotes
        // back to `T?` — which is the whole reason the optional-narrowing arm
        // admits the shape. So the message below claims the weaker thing that
        // is actually true: a function that collapses "absent" into a concrete
        // value is a defaulting step, and the second application is answering
        // a different question from the first. That is a conjecture about
        // meaning, not a type error, and it is stated as one.
        //
        // Removing this arm outright is a defensible follow-on. It is left in
        // place because narrowing a veto is a precision change, and the
        // measurement below shows it costs nothing to keep.
        // **A DEFAULTED parameter is not the operand**, so comparing it to the
        // return type is not the type argument at all — it is comparing a
        // configuration knob against a result. `SyntaxProtocol.formatted(using
        // format: BasicFormat = BasicFormat()) -> Syntax` is a transform *of
        // self*, and `BasicFormat != Syntax` says nothing about whether
        // `x.formatted().formatted()` type-checks (it does — see
        // `IdempotenceTemplate+ErasedSelfForm.swift`). Without this clause the
        // §4 gate vetoes precisely the case §5 exists to admit, which is how
        // it was found.
        if name.hasPrefix("format"), !param.hasDefault, param.typeText != returnType {
            return Signal(
                kind: .protocolCoveredProperty,
                weight: Signal.vetoWeight,
                detail: "Shape-coincidence: '\(name)' takes \(param.typeText) "
                    + "and returns \(returnType), so it DEFAULTS an absent "
                    + "value rather than transforming a present one; "
                    + "`\(name)(\(name)(x))` asks a different question the "
                    + "second time, when the input can no longer be absent"
            )
        }

        return nil
    }
}
