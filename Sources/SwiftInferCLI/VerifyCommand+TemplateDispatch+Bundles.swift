import Foundation
import SwiftInferCore

/// V1.89 lint pass — commutativity + associativity stub-bundle
/// builders extracted from `VerifyCommand+TemplateDispatch.swift`
/// so the main dispatch file stays under SwiftLint's 400-line cap.
/// Same internal-static access as the round-trip / idempotence
/// builders that remain in the dispatch file.
extension SwiftInferCommand.Verify {

    static func commutativityStubBundle(
        entry: SemanticIndexEntry,
        budget: CommutativityStubEmitter.TrialBudget
    ) throws -> VerifyStubBundle {
        let resolved = try CommutativityPairResolver.resolve(entry)
        let source = try CommutativityStubEmitter.emit(
            CommutativityStubEmitter.Inputs(
                functionCall: resolved.functionCall,
                extraImports: [],
                carrierType: entry.typeName ?? "(none)",
                seedHex: makeSeedHex(from: entry.identityHash),
                trialBudget: budget
            )
        )
        // For commutativity, both `forwardName` and `inverseName` slots
        // hold the same single function call. The renderer's
        // `RenderShape.commutativity` reads it once and produces
        // `f(lhs, rhs)` and `f(rhs, lhs)` for the two value lines.
        let context = VerifyResultRenderer.Context(
            templateName: "commutativity",
            forwardName: resolved.functionCall,
            inverseName: resolved.functionCall,
            carrierType: entry.typeName ?? "(none)"
        )
        return VerifyStubBundle(source: source, rendererContext: context)
    }

    static func associativityStubBundle(
        entry: SemanticIndexEntry,
        budget: AssociativityStubEmitter.TrialBudget
    ) throws -> VerifyStubBundle {
        let resolved = try AssociativityPairResolver.resolve(entry)
        let source = try AssociativityStubEmitter.emit(
            AssociativityStubEmitter.Inputs(
                functionCall: resolved.functionCall,
                extraImports: [],
                carrierType: entry.typeName ?? "(none)",
                seedHex: makeSeedHex(from: entry.identityHash),
                trialBudget: budget
            )
        )
        // For associativity, both `forwardName` and `inverseName` slots
        // hold the same single function call. The renderer's
        // `RenderShape.associativity` reads it once and produces
        // `f(f(a, b), c)` and `f(a, f(b, c))` for the two value lines.
        let context = VerifyResultRenderer.Context(
            templateName: "associativity",
            forwardName: resolved.functionCall,
            inverseName: resolved.functionCall,
            carrierType: entry.typeName ?? "(none)"
        )
        return VerifyStubBundle(source: source, rendererContext: context)
    }

    /// Helper — produce a copy of `entry` with `typeName` set to
    /// `carrier`. Used to thread the `GenericBindingResolver`-bound
    /// carrier into the per-template builders without leaking the
    /// bound form back to the SemanticIndex. (V1.149 — relocated here
    /// from `+TemplateDispatch` for the file-length cap; `carrierTypeName`
    /// is preserved so the generator carrier survives owner rebinding.)
    static func rebound(
        _ entry: SemanticIndexEntry,
        toCarrier carrier: String
    ) -> SemanticIndexEntry {
        guard entry.typeName != carrier else { return entry }
        // Mutate a copy. The rebuild this replaces already carried a note that `carrierTypeName`
        // "is preserved so the generator carrier survives owner rebinding" — the fix for this very
        // bug, applied by adding the missing field back, which leaves the trap armed for the next.
        var copy = entry
        copy.typeName = carrier
        return copy
    }

    /// V1.149 — the argument labels of `primaryFunctionName` (e.g.
    /// `"indent(in:)"` → `["in"]`, `"pick(a:b:)"` → `["a", "b"]`,
    /// `"clamp(_:)"` → `["_"]`, `"f()"` → `[]`). Unlabeled parameters
    /// surface as `"_"`.
    static func argumentLabels(from primaryFunctionName: String) -> [String] {
        guard let open = primaryFunctionName.firstIndex(of: "("),
            let close = primaryFunctionName.lastIndex(of: ")"),
            open < close else { return [] }
        let inner = primaryFunctionName[primaryFunctionName.index(after: open)..<close]
        guard !inner.isEmpty else { return [] }
        return inner.split(separator: ":", omittingEmptySubsequences: true).map(String.init)
    }

    /// V1.149 — the call expression the stub applies positionally. A function
    /// with external argument labels can't be called `reference(value)`, so it
    /// gets a label-carrying trampoline closure (`{ reference(in: $0) }`) that
    /// the stub's `\(call)(args)` applies immediately. A label-free function
    /// (all labels `"_"`, or none) returns `reference` unchanged so existing
    /// stdlib-carrier stubs stay byte-identical.
    static func labeledCallExpression(
        primaryFunctionName: String,
        reference: String
    ) -> String {
        let labels = argumentLabels(from: primaryFunctionName)
        guard labels.contains(where: { $0 != "_" }) else { return reference }
        // Operators (`+`, `*`, `<<`, …) never take argument labels — the
        // `a`/`b` in `+(a:b:)` are parameter NAMES, not call labels, so a
        // labeled call `(+)(a: $0, b: $1)` doesn't compile. Apply positionally:
        // `reference` is already the callable operator form `(+)`, so the stub
        // invokes `(+)(lhs, rhs)`. (Only the `.userGen`/strategist dispatch
        // path reaches operators here; `CommutativityPairResolver` never did.)
        let bareName = RoundTripPairResolver.stripParameterLabels(primaryFunctionName)
        if CallExpressionShape.isOperatorName(bareName) { return reference }
        let placeholders = labels.enumerated().map { index, label in
            label == "_" ? "$\(index)" : "\(label): $\(index)"
        }
        let args = placeholders.joined(separator: ", ")
        return "{ \(reference)(\(args)) }"
    }

    /// The call expression for a *non-mutating instance method*, as a receiver
    /// closure the stub applies positionally: `{ $0.method(with: $1) }` —
    /// `$0` is the receiver, the method's own arguments follow as `$1…`
    /// carrying their labels. Applied by the stub's `\(call)(lhs, rhs)`, this
    /// yields `lhs.method(with: rhs)` — the receiver shape a binary instance
    /// operator needs, vs the static `Type.method(lhs, rhs)` (which doesn't
    /// type-check: `Type.method` is the *curried* `(Type) -> (Arg) -> R`).
    /// A nullary instance method (e.g. `reversed()`) yields `{ $0.method() }`,
    /// applied as `\(call)(value)` → `value.method()`.
    ///
    /// Falls back to the positional `labeledCallExpression` (free/static shape)
    /// for free/static functions and for mutating methods — a mutating method
    /// returns `Void`, so it isn't this value-returning receiver shape (it's
    /// idempotence's `var copy; copy.method()` shape instead).
    static func receiverCallExpression(
        entry: SemanticIndexEntry,
        reference: String,
        bareFunctionName: String
    ) -> String {
        guard entry.isInstanceMethod, !entry.isMutatingMethod else {
            return labeledCallExpression(
                primaryFunctionName: entry.primaryFunctionName,
                reference: reference
            )
        }
        let qualifierStripped = bareFunctionName.split(separator: ".").last.map(String.init)
        let methodName = qualifierStripped ?? bareFunctionName
        let labels = argumentLabels(from: entry.primaryFunctionName)
        // Receiver is `$0`; the method's own args are `$1…`. The composers apply
        // this closure immediately (`closure(lhs, rhs)` → `lhs.method(rhs)`) with
        // CONCRETELY-typed generator values, so the `$0`/`$1` shorthand infers
        // cleanly — the verify-emitter matrix test confirms every instance-op
        // cell compiles with this form.
        let placeholders = labels.enumerated().map { index, label in
            label == "_" ? "$\(index + 1)" : "\(label): $\(index + 1)"
        }
        let args = placeholders.joined(separator: ", ")
        return "{ $0.\(methodName)(\(args)) }"
    }

    /// `[Int]` → `Int` — the element type the homomorphism composer generates
    /// (then wraps in `.array(of:)`). Returns the input unchanged when it isn't a
    /// bracketed array, so a non-array carrier degrades to a truthful strategist
    /// error rather than a silent mis-strip.
    static func arrayElementType(of carrier: String) -> String {
        let trimmed = carrier.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]"), !trimmed.contains(":") else {
            return trimmed
        }
        return String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
    }

    /// Single-call resolution shared by idempotence / commutativity /
    /// associativity. `receiverShape` selects the instance-method receiver
    /// closure (`{ $0.method(with: $1) }`) over the static label-trampoline
    /// form (`receiverCallExpression` falls back to the trampoline for
    /// free/static/mutating functions).
    static func singleCallResolved(
        entry: SemanticIndexEntry,
        typeQualifier: String,
        funcName: String,
        receiverShape: Bool
    ) -> ResolvedCalls {
        let reference = CallExpressionShape.render(
            typeQualifier: typeQualifier,
            bareFunctionName: funcName
        )
        let call = receiverShape
            ? receiverCallExpression(entry: entry, reference: reference, bareFunctionName: funcName)
            : labeledCallExpression(primaryFunctionName: entry.primaryFunctionName, reference: reference)
        return ResolvedCalls(
            expressions: [call],
            rendererForwardName: reference,
            rendererInverseName: reference
        )
    }

    /// Render one half (forward or inverse) of a round-trip call. Emits the
    /// instance-method receiver shape (`{ $0.method() }`) only when this half
    /// IS the entry's signalled non-mutating instance method — i.e. when its
    /// bare name matches `primaryFunctionName`. This covers the self-inverse
    /// instance method (forward == inverse == the method, applied twice ==
    /// identity, e.g. `negated()`); a half we have no instance signal for
    /// keeps the static/free shape. Mutating and free/static halves fall back
    /// via `receiverCallExpression`.
    static func roundTripHalfCall(
        entry: SemanticIndexEntry,
        typeQualifier: String,
        bareName: String
    ) -> String {
        let stripped = RoundTripPairResolver.stripParameterLabels(bareName)
        let reference = CallExpressionShape.render(
            typeQualifier: typeQualifier,
            bareFunctionName: stripped
        )
        let primaryStripped = RoundTripPairResolver.stripParameterLabels(entry.primaryFunctionName)
        guard entry.isInstanceMethod, stripped == primaryStripped else { return reference }
        return receiverCallExpression(entry: entry, reference: reference, bareFunctionName: stripped)
    }
}
