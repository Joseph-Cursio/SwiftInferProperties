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
/// A generic **function** (`func f<C: MutableCollection>(for sample: C)`) is the same defect with
/// a different source of names: its parameters come from `Evidence.genericParameters`, not the
/// map, and it may have no declaring type at all. #493 read only the map, so it withdrew 8 of the
/// 50 (#497).
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
        guard let evidence = suggestion.evidence.first else { return nil }
        let display = evidence.displayName
        // The function's own `<C>` first: it needs no owner and no map, which is why a top-level
        // generic function slipped both guards below (#497).
        if let reason = ownParameterReason(for: evidence, display: display) {
            return reason
        }
        if let reason = opaqueParameterReason(for: evidence, display: display) {
            return reason
        }
        guard !genericParametersByName.isEmpty,
              let owner = evidence.qualifiedTypeName ?? suggestion.carrier
        else { return nil }

        let bound = boundParameters(of: owner, in: genericParametersByName)
        guard !bound.isEmpty else { return nil }

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

    /// Why a generic FUNCTION cannot be stubbed, or `nil` when it declares no parameters of its own.
    ///
    /// **Every** generic function is withdrawn, not only one whose parameters mention the name. A
    /// parameter spelled `C` gives `C.gen()`; a parameter spelled `Set<T>` gives `Set<T>.gen()`; a
    /// `T` used only in the return type leaves nothing to infer it from. None compiles, so the
    /// name is reported where one is visible and the rule is not narrowed to it.
    ///
    /// Tokenised on identifier boundaries rather than `bareName`, because the head of `Set<T>` is
    /// `Set` and the parameter is the argument.
    private static func ownParameterReason(for evidence: Evidence, display: String) -> String? {
        let own = Set(evidence.genericParameters.map(\.name))
        guard !own.isEmpty else { return nil }
        let named = evidence.parameterTypeNames.lazy
            .compactMap { typeText in identifiers(in: typeText).first { own.contains($0) } }
            .first
        if let named {
            return "\(display) takes \(named), which is a generic parameter of the function itself "
                + "and names no type at the call site"
        }
        let names = evidence.genericParameters.map(\.name).joined(separator: ", ")
        return "\(display) is a generic function over \(names), and a stub cannot name its type "
            + "parameters at the call site"
    }

    /// Why a subject taking an OPAQUE parameter cannot be stubbed, or `nil`.
    ///
    /// `func f(_ node: some SyntaxProtocol)` is `func f<T: SyntaxProtocol>(_ node: T)` written in
    /// sugar, and the scanner records the sugar: `parameterTypeNames` reads `some SyntaxProtocol`
    /// while `genericParameters` is empty, so neither check above sees it. The emitter then writes
    /// `some SyntaxProtocol.gen()`, which is not an expression at all — **10 stubs on
    /// SwiftProjectLint failed with `expected ',' separator`, a SYNTAX error in code the reader
    /// did not write**, and a parse failure hides the derivation-reason marker beside it.
    ///
    /// ⚠ **`any P` is deliberately not included.** An existential names a real type a stub can
    /// spell, so `any P` that fails is an ordinary missing generator, not an unbindable name — the
    /// same cut this gate already makes between *no generator* and *no name*.
    private static func opaqueParameterReason(for evidence: Evidence, display: String) -> String? {
        guard let opaque = evidence.parameterTypeNames.first(where: { identifiers(in: $0).contains("some") })
        else { return nil }
        return "\(display) takes \(opaque), an opaque type — a generic parameter in sugar, which "
            + "names no type at the call site"
    }

    /// `[Set<T>: (C) -> Bool]` → `Set`, `T`, `C`, `Bool`.
    private static func identifiers(in typeText: String) -> [String] {
        typeText
            .split { !($0.isLetter || $0.isNumber || $0 == "_") }
            .map(String.init)
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
