/// The signature shapes `IdempotenceTemplate` can propose a law for — stated
/// **once**, because two copies of it disagreed and the disagreement was silent.
///
/// ## Why this type exists
///
/// The template accepts two shapes. `T -> T` is the obvious one; `T? -> T` is
/// admitted deliberately by `IdempotenceTemplate.optionalNarrowingSignal`, since
/// `f(f(x))` still typechecks — the non-optional result promotes back to `T?`.
/// Common for coalesce-with-default shapes.
///
/// The scanner had its own copy of the gate, and it accepted only the first:
/// `parameter.type.trimmedDescription == returnType.trimmedDescription`, exact
/// string equality. `idempotenceReturnShape` is computed **only** behind that
/// gate, so for every `T? -> T` candidate the shape was `nil` — and
/// `IdempotenceTemplate.returnShapeVeto` cannot tell *"never computed"* from
/// *"computed, and the result does not extend its input"*. Both are `nil`.
///
/// **The guard checked something narrower than the thing it protects**, which is
/// the `CuratedEntryRole` / `KitCoverageDriftTests` pattern: a veto that looks
/// green while the hole stays open.
///
/// Measured 2026-08-05. `SwiftInferCommand.Scaffold.defaultOutputURL(packageRoot:)`
/// is `(URL?) -> URL` and its body is
/// `(packageRoot ?? …).appendingPathComponent(…)` — and `appendingPathComponent`
/// is the **first entry** in `IdempotenceReturnShapeClassifier.extensionCalls`.
/// The classifier would have returned `.extendsInput` on that body unmodified.
/// It was never asked. The law ran and refuted at trial 0, which is the veto's
/// whole job to prevent.
///
/// Neither gate calls the other now; both call this.
public enum IdempotenceCandidateShape {

    /// Whether `candidate` is the `Optional` of `base` — written `T?` or
    /// `Optional<T>`.
    ///
    /// Textual, like everything else at this layer: the scanner has no type
    /// resolution, so `Optional<Foo>` and `Foo?` are two spellings it must match
    /// by hand. A spelling this misses degrades to *not a candidate*, which is
    /// the safe direction — the law is not proposed rather than proposed without
    /// its veto.
    public static func isOptional(_ candidate: String, of base: String) -> Bool {
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespaces)
        let trimmedBase = base.trimmingCharacters(in: .whitespaces)
        return trimmedCandidate == "\(trimmedBase)?"
            || trimmedCandidate == "Optional<\(trimmedBase)>"
    }

    /// Whether a one-parameter function of this signature is a shape the
    /// idempotence template can propose for: `T -> T`, or the narrowing
    /// `T? -> T`.
    ///
    /// This is the predicate that decides whether `idempotenceReturnShape` gets
    /// computed, so **widening it widens the veto's reach, not the template's**.
    /// Anything added here must be a shape the template already proposes for, or
    /// the classifier starts paying for bodies nothing will ask about.
    public static func admitsIdempotenceLaw(
        parameterType: String,
        returnType: String
    ) -> Bool {
        let trimmedParameter = parameterType.trimmingCharacters(in: .whitespaces)
        let trimmedReturn = returnType.trimmingCharacters(in: .whitespaces)
        return trimmedParameter == trimmedReturn
            || isOptional(trimmedParameter, of: trimmedReturn)
    }
}
