import SwiftInferCore

/// The **erased self-form** arm of `typeSymmetrySignal` — a transform declared
/// on a protocol that returns the protocol's erased wrapper rather than `Self`,
/// configured by parameters the caller may omit.
///
/// ## The shape, and why the existing gate rejected it
///
/// `docs/parsing-catalog-gap.md` §4/§5. swift-syntax's formatter is:
///
/// ```swift
/// extension SyntaxProtocol {
///   public func formatted(using format: BasicFormat = BasicFormat()) -> Syntax
/// }
/// ```
///
/// `format(format(x)) == format(x)` is the one law every source formatter owes,
/// and the catalog could not see this one at any tier. Probing found **two**
/// independent gates, not the one the survey originally recorded:
///
/// 1. **The return is erased.** The self-form arm requires
///    `containingTypeName == returnType` or a literal `Self`. Here the carrier
///    is `SyntaxProtocol` and the return is `Syntax`.
/// 2. **The parameter is configuration.** The self-form arm requires
///    `parameters.isEmpty`, and `using format:` is a defaulted knob, not an
///    operand — `x.formatted()` is a legal call.
///
/// The survey's §4 note blamed only the erasure. That was incomplete, and the
/// correction is recorded there.
///
/// ## Why the law is well-formed anyway
///
/// The thing that makes `f(f(x))` meaningful is being able to feed the result
/// back in. Here you can, and for a checkable reason:
///
/// ```swift
/// public protocol SyntaxProtocol: CustomStringConvertible, …
/// public struct Syntax: SyntaxProtocol, SyntaxHashable   // ← the return conforms
/// ```
///
/// So `tree.formatted().formatted()` type-checks. That is the admissibility
/// test this arm applies, and it is exact rather than a heuristic:
/// **the return type must conform to the carrier.**
///
/// It also rejects the near-miss correctly. `struct B { func normalized() ->
/// AnyNode }` erases to an unrelated type, `b.normalized().normalized()` does
/// not compile, and `AnyNode` does not conform to `B` — so no signal.
///
/// ## Lower confidence, deliberately
///
/// Weight **25** rather than the 30 the concrete forms earn, per the survey's
/// "admit … as a lower-confidence variant". With a curated verb (`formatted`,
/// +40) that lands at 70 — `Likely`, visible on a default run, without
/// claiming `Strong`. The erasure is a real reason for doubt: the law is
/// stated over the *erased* type, so it says nothing about whether the
/// concrete node type round-trips through the transform unchanged.
///
/// ## Scope limit, stated rather than discovered
///
/// The conformance lookup reads `inheritedTypesByName`, which is built from the
/// **scanned corpus**. `Syntax` is declared in `SwiftSyntax` while `formatted`
/// lives in `SwiftBasicFormat`, so a single-module scan of `SwiftBasicFormat`
/// cannot resolve the conformance and this arm stays silent. Scanning both
/// modules together resolves it. That is the same cross-module scoping limit
/// `ProxyConstruction` and `EquatableResolver` already carry, and the
/// conservative direction: an unresolvable conformance yields no suggestion
/// rather than a guessed one.
extension IdempotenceTemplate {

    /// Type-symmetry signal for the erased self-form, or `nil` when the shape
    /// or the conformance does not hold.
    static func erasedSelfFormSignal(
        for summary: FunctionSummary,
        inheritedTypesByName: [String: Set<String>]
    ) -> Signal? {
        guard !summary.isMutating,
              !summary.isStatic,
              let carrier = summary.containingTypeName,
              let returnType = summary.returnTypeText,
              returnType != "Void", returnType != "()",
              returnType != "Self",
              returnType != carrier else {
            return nil
        }
        // Every parameter must be omittable — the call has to read as a unary
        // transform of `self`. A required parameter is part of the arity and
        // this is not a `T -> T` in any sense.
        guard summary.parameters.allSatisfy({ $0.hasDefault && !$0.isInout }) else {
            return nil
        }
        // **The return must be a FIXED POINT, not merely a conformer.** This
        // is the tightening measurement forced, and the distinction is the
        // whole idea: an *erasure* absorbs itself, a *decorator* nests.
        //
        //   Syntax.formatted() -> Syntax                      erasure  ✓
        //   AsyncSequence.adjacentPairs() -> AsyncAdjacentPairsSequence<Self>
        //                                                     decorator ✗
        //
        // Both conform to their carrier, so the conformance test alone admits
        // both. But applying the decorator twice yields
        // `AsyncAdjacentPairsSequence<AsyncAdjacentPairsSequence<S>>` — a
        // DIFFERENT type from one application — so `f(f(x)) == f(x)` does not
        // type-check and there is no law to state. The first cut admitted six
        // of these across swift-async-algorithms and swift-nio
        // (`adjacentPairs`, `compacted`, `joined`, `removeDuplicates`,
        // `splitLines`, `splitUTF8Lines`), every one false.
        //
        // A generic return parameterised by the receiver is the signature of
        // that whole family, so requiring a non-generic return separates them
        // exactly.
        guard !returnType.contains("<") else { return nil }
        // The admissibility test: can the result be fed back in?
        let strippedReturn = ProtocolCoverageMap.strippingGenericParameters(returnType)
        let strippedCarrier = ProtocolCoverageMap.strippingGenericParameters(carrier)
        guard let conformances = inheritedTypesByName[strippedReturn],
              conformances.contains(strippedCarrier) else {
            return nil
        }
        // **Conformance alone is not erasure.** The second tightening
        // measurement forced. `String` conforms to swift-argument-parser's
        // `ExpressibleByArgument`, so `ExpressibleByArgument
        // .defaultValueDescription() -> String` passed every test above — but
        // `String` is not the erased form of that protocol, it merely happens
        // to satisfy it, and a description of a description is not a fixed
        // point. Two false firings out of four, which is poor precision for an
        // arm that ASSERTS rather than suppresses.
        //
        // So the return must also be *named* as the carrier's erasure. That is
        // not an arbitrary filter — it is what a type-erased wrapper IS in
        // Swift, and the convention is unambiguous: `Syntax` / `SyntaxProtocol`,
        // `AnyShape` / `Shape`.
        guard isNamedErasure(of: strippedCarrier, returnType: strippedReturn) else {
            return nil
        }
        return Signal(
            kind: .typeSymmetrySignature,
            weight: 25,
            detail: "Type-symmetry signature: self -> \(returnType) on \(carrier) "
                + "(erased self-form — `\(returnType)` conforms to `\(carrier)`, "
                + "so the result can be fed back in; lower confidence than a "
                + "concrete `T -> T` because the law is stated over the erased type)"
        )
    }

    /// Whether `returnType` is named as `carrier`'s type-erased wrapper, by the
    /// two Swift conventions for it:
    ///
    /// - `Syntax` ⟷ `SyntaxProtocol` — the protocol is the type plus
    ///   `Protocol`. swift-syntax's own spelling, and the motivating case.
    /// - `AnyShape` ⟷ `Shape` — the wrapper is `Any` plus the protocol.
    ///   The stdlib/SwiftUI spelling (`AnyView`, `AnyHashable`,
    ///   `AnyCollection`).
    ///
    /// Deliberately exact rather than fuzzy. A looser rule (shared stem, say)
    /// re-admits the accidental conformances this exists to exclude — the same
    /// lesson `CodecCarrierPairing` records for the cross-type counter, where a
    /// shared-stem test would have re-admitted 1,380 noise pairs.
    static func isNamedErasure(of carrier: String, returnType: String) -> Bool {
        carrier == returnType + "Protocol"
            || returnType == "Any" + carrier
    }

    /// The caveat the erased form owes, appended when this arm fired.
    static func erasedSelfFormCaveat(carrier: String, returnType: String) -> String {
        "THE LAW IS STATED OVER THE ERASED TYPE `\(returnType)`, not over the concrete "
            + "type you called it on. `\(returnType)` conforms to `\(carrier)`, so "
            + "applying the transform twice compiles and the claim is well-formed — but "
            + "equality is being checked on the erasure, so a difference the erased type "
            + "does not represent is invisible to this property. Two concrete nodes that "
            + "erase to equal values will pass it. If the concrete type carries "
            + "distinctions the erasure drops, state the law on the concrete type instead."
    }
}
