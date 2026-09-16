import Foundation
import SwiftInferCore

/// **Do not write a stub whose call names a type parameter.**
///
/// For a generic subject the emitter writes the type parameter where a type belongs:
///
/// ```swift
/// // struct KeyedDecoding<Key: CodingKey> { func contains(_ key: Key) -> Bool }
/// let arg0 = (KeyedDecoding.gen() /* … no generator derived … */).run(using: &rng)
/// let arg1 = (Key.gen()           /* … no generator derived … */).run(using: &rng)
/// ```
///
/// `Key` is not a name outside its declaration, so the file fails with `cannot find 'Key' in
/// scope`. **No budget, generator or import makes it compile** — the name does not exist at the
/// call site. The receiver is wrong the same way: `KeyedDecoding` needs its argument.
///
/// ## The posture is the availability gate's
///
/// That gate withdrew **24 of 4,161 rows (0.58%)** and shipped because it *costs no laws* —
/// every row it removed named a subject a test could never call. This is the same class.
/// Measured over the 19 corpus-funnel repositories plus the 20 manifest corpora: **50 rows name
/// a generic parameter of an enclosing declaration, and 5 write a generic receiver without its
/// arguments** (#493). Withdrawing them removes nothing that could ever have run, and replaces a
/// compiler error in code the reader did not write with a sentence naming the unbound name.
///
/// ## Why it declines rather than substitutes, for now
///
/// `ConcreteInstantiation` already chooses `Int` for a generic carrier and already declines with
/// a reason when a constraint `Int` cannot satisfy — it is what `scaffold-kit-suites` uses, and
/// `Discover+PipelineAssembly` already computes the `genericParametersByName` it needs and drops
/// it before the stub writer. **Substituting is the better fix and it is a bigger one**: the
/// emitter would have to rewrite the receiver AND every parameter whose type is a bound
/// parameter, through four dispatch layers each already at SwiftLint's argument cap. That is
/// worth 5 rows; this is worth 50, at one call site. Split deliberately, not overlooked.
enum GenericSubjectGate {

    /// Why no stub can be written for this suggestion, or `nil` when it is not generic-blocked.
    ///
    /// Named parameters rather than a `Context` so the rule is testable without building one,
    /// which is how `StubApplicationArity.declineReason` next to it is shaped.
    static func declineReason(
        for suggestion: Suggestion,
        genericParametersByName: [String: [TypeDecl.GenericParameter]]
    ) -> String? {
        guard !genericParametersByName.isEmpty,
              let evidence = suggestion.evidence.first,
              let owner = evidence.qualifiedTypeName ?? suggestion.carrier
        else { return nil }

        let bound = boundParameters(of: owner, in: genericParametersByName)
        guard !bound.isEmpty else { return nil }

        let display = suggestion.evidence.first?.displayName ?? suggestion.templateName
        // A parameter whose TYPE is one of the bound names: the `Key.gen()` case.
        let named = evidence.parameterTypeNames
            .map(bareName)
            .filter { bound.contains($0) }
        if let first = named.first {
            return "\(display) takes \(first), which is a generic parameter of "
                + "\(bareName(owner)) and names no type at the call site"
        }
        // The receiver itself: the `KeyedDecoding.gen()` case.
        return "\(display) is declared on the generic type \(bareName(owner)), and a stub cannot "
            + "name it without its type arguments"
    }

    /// Every generic parameter name the declaration (or an enclosing one) binds.
    ///
    /// Both keys are tried for the same reason `ConcreteInstantiation.rendered` tries both: the
    /// scanner keys a nested type by its qualified name where it saw one and by the bare name
    /// otherwise.
    private static func boundParameters(
        of qualifiedTypeName: String,
        in genericParametersByName: [String: [TypeDecl.GenericParameter]]
    ) -> Set<String> {
        var names: Set<String> = []
        var prefix: [String] = []
        for component in qualifiedTypeName.split(separator: ".").map(String.init) {
            prefix.append(component)
            let generics = genericParametersByName[prefix.joined(separator: ".")]
                ?? genericParametersByName[component]
                ?? []
            names.formUnion(generics.map(\.name))
        }
        return names
    }

    /// `Box<Int>` → `Box`, `[Foo]` → `Foo`. Matches how shapes are keyed.
    private static func bareName(_ typeName: String) -> String {
        let trimmed = typeName.trimmingCharacters(in: CharacterSet(charactersIn: "[]?! "))
        let head = trimmed.split { "<>,. ".contains($0) }.first
        return head.map(String.init) ?? trimmed
    }
}
