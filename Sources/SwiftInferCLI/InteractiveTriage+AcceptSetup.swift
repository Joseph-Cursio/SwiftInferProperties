import Foundation
import PropertyLawCore
import SwiftInferCore
import SwiftInferTemplates

/// The three things `acceptDecision` assembles before it emits anything.
///
/// Split out because that function crossed SwiftLint's body-length cap three times in two days
/// — #493's generic gate, #498's argument types and #492's carrier imports each added to it —
/// and its length was never the interesting part.
extension InteractiveTriage {

    /// A generator for any project type, derived from its parsed shape.
    ///
    /// `GeneratorResolver` is memoized and cycle-guarded, and is built per accept so the stub
    /// emitter can render a custom-typed parameter without the subject having hand-written a
    /// `gen()`. Lifted out of `acceptDecision`, which crossed SwiftLint's body-length cap once
    /// #493's gate and #498's argument types both landed in it.
    static func customGenerator(for context: Context) -> (String) -> String? {
        let resolver = GeneratorResolver(types: Array(context.typeShapesByName.values))
        let explain = generatorFailureReason(for: context)
        return { typeName in
            if let derived = resolver.customTypeGenerator(forTypeName: typeName)?.expression {
                return derived
            }
            // **The reason is attached HERE because this closure is already threaded
            // everywhere a generator is chosen**, so naming the cause needs no signature to
            // move. Delegating to `defaultGenerator` keeps the `RawType` and
            // `DerivationStrategist.composedGenerator` arms exactly as they were — this only
            // reaches the `.todo` arm, and only when the resolver has something to say.
            guard let reason = explain(typeName) else { return nil }
            return LiftedTestEmitter.defaultGenerator(for: typeName, reason: reason)
        }
    }

    /// Why the resolver produced no generator for `typeName`, in one sentence.
    ///
    /// **Built from the SAME resolver that just returned `nil`**, so the explanation cannot
    /// describe a different derivation from the one that failed. `resolutionFailure` is the
    /// kit's own account of its `nil` paths (v4.7.0), and `.noStrategy` carries the strategist's
    /// sentence verbatim rather than a paraphrase.
    static func generatorFailureReason(for context: Context) -> (String) -> String? {
        let resolver = GeneratorResolver(types: Array(context.typeShapesByName.values))
        return { typeName in
            guard let failure = resolver.resolutionFailure(forTypeName: typeName) else {
                return nil
            }
            switch failure {
            case .notInUniverse:
                return "`\(typeName)` is not among the scanned types"

            case .ambiguous:
                return "`\(typeName)` is ambiguous — more than one scanned type has that name"

            case .aliasUnresolved(let underlying):
                return "`\(typeName)` is an alias for `\(underlying)`, which did not resolve"

            case .noStrategy(let reason):
                return reason

            case .unterminatedRecursion:
                return "`\(typeName)` derives through itself without a base case"

            @unknown default:
                // A case the kit adds later must not silently read as "no reason": the marker
                // falls back to its unexplained form, which is what it said before this existed.
                return nil
            }
        }
    }

    /// Say why no stub was written, naming the cause rather than the template where it can.
    ///
    /// **Two unlike causes used to share one sentence**, and the shared one named the template —
    /// so a subject that simply could not be called was reported as a gap in the tool.
    /// `StubApplicationArity` answers first when it has something to say.
    static func reportNoStub(for suggestion: Suggestion, context: Context) {
        context.diagnostics.writeDiagnostic(noStubNote(for: suggestion))
    }

    /// The note `reportNoStub` writes, pure so the choice of sentence can be tested.
    ///
    /// **A deliberate decline answers first** (#478). A template declined by design has no
    /// writer at ANY arity, so its reason is the truer one even where the subject's arity would
    /// also have declined it — and saying *by design* stops a reader waiting for a writer.
    static func noStubNote(for suggestion: Suggestion) -> String {
        let reason = DeliberateStubDecline.reason(forTemplate: suggestion.templateName)
            ?? StubApplicationArity.declineReason(for: suggestion)
        if let reason {
            return "note: no stub written — \(reason); decision recorded without writing a file"
        }
        return "note: no stub writeout available for template '\(suggestion.templateName)' in v1; "
            + "decision recorded without writing a file"
    }

    /// The two maps `VerifyImportSet` needs, or `nil` for a caller with no package on disk.
    ///
    /// Lifted out of `acceptDecision` for its body-length cap, which three separate additions
    /// have now pushed it past (#493's gate, #498's argument types, and this).
    static func carrierImports(for context: Context) -> CarrierImports? {
        context.packageRoot.map {
            CarrierImports(
                typeShapesByName: context.typeShapesByName,
                sourceFileByTypeName: context.sourceFileByTypeName,
                packageRoot: $0
            )
        }
    }
}
