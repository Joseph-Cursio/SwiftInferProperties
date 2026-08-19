/// Chooses a concrete instantiation for a generic carrier, so emitted code can name a type
/// the compiler will accept.
///
/// **Why this exists.** `scaffold-kit-suites` wrote `Deque.self` and `PersistentSet.self`
/// into generated suites. Neither typechecks — `generic parameter 'Element' could not be
/// inferred` — so *no* generic carrier could produce a compiling suite, with or without a
/// generator. Measured on swift-collections `899809d3` and on the 2022 `876177db^` tree
/// (`plans/kit-suite-backtest-plan.md` §3b and §Arm 1).
///
/// **`Int` is the substitution, and it is the toolchain's existing convention rather than a
/// new invention.** PropertyLawKit's own hand-written recipes bind element types to `Int` —
/// `Gen<Deque<Int>>`, `Gen<OrderedSet<Int>>`, `Gen<TreeSet<Int>>` — with the note *"Phase 1
/// M1 binds element types to `Int`; widening to generic elements is deferred until a consumer
/// needs it."* Matching that keeps a derived instantiation and a curated recipe nameable by
/// the same expression.
///
/// **It declines rather than guesses.** A constraint `Int` does not satisfy produces `nil`,
/// and the caller reports the carrier as blocked with the reason. Emitting `Foo<Int>` for
/// `Foo<T: Collection>` would trade one compile error for another while looking like
/// progress — the conservative-inference posture (PRD §3.5) applied to codegen.
public enum ConcreteInstantiation {

    /// Protocols `Int` conforms to, so a parameter constrained to one can take `Int`.
    ///
    /// Deliberately a closed allowlist rather than "anything we do not recognise is fine":
    /// the failure mode of guessing is emitted code that does not compile, which is exactly
    /// the defect this type exists to remove. Unconstrained parameters are always fine.
    ///
    /// **`CustomDebugStringConvertible` is deliberately absent.** It was in the first draft
    /// and `allowlistIsTrue` rejected it on the first run: `Int` does not conform. That is
    /// the whole reason the allowlist is pinned by a test — a wrong entry here emits code
    /// that does not compile, silently, on somebody else's corpus.
    ///
    /// `Sendable` is included because the kit's suites require it and `Int` satisfies it —
    /// the constraint that surfaced on the 2022 `PersistentSet`, where the *carrier* was
    /// missing the conformance rather than its parameter.
    public static let intSatisfiedConstraints: Set<String> = [
        "Equatable", "Hashable", "Comparable", "Codable", "Encodable", "Decodable",
        "Sendable", "AdditiveArithmetic", "Numeric", "SignedNumeric", "BinaryInteger",
        "FixedWidthInteger", "SignedInteger", "Strideable", "CustomStringConvertible",
        "LosslessStringConvertible", "ExpressibleByIntegerLiteral", "Any", "AnyObject"
    ]

    /// The name to write in emitted source, or `nil` when no concrete instantiation can be
    /// chosen. Returns `typeName` unchanged for a non-generic carrier.
    ///
    /// Composed constraints (`T: Hashable & Codable`) are split and each side checked, since
    /// `Int` satisfying both is the same question asked twice.
    /// A nested type's spelling, where the generic arguments belong to the ENCLOSING type.
    ///
    /// `OrderedDictionary.Elements` must be written `OrderedDictionary<Int, Int>.Elements` —
    /// `Elements` declares no generics of its own and inherits `Key`/`Value` from its parent.
    /// Rendering only the declaration's own parameters left it bare and the emitted suite
    /// failed with *"generic parameter 'Key' could not be inferred"*, eight times in
    /// `OrderedCollections` alone.
    ///
    /// Each dotted component is instantiated from its own entry in `genericParametersByName`,
    /// so `A<Int>.B<Int>` works as well as `A<Int>.B`. A component with no entry is rendered
    /// bare, which is correct for a non-generic nesting level.
    public static func rendered(
        qualifiedTypeName: String,
        genericParametersByName: [String: [TypeDecl.GenericParameter]]
    ) -> String? {
        var pieces: [String] = []
        var prefix: [String] = []
        for component in qualifiedTypeName.split(separator: ".").map(String.init) {
            prefix.append(component)
            // Nested types are keyed by their qualified name where the scanner saw one, and
            // by the bare name otherwise; try both so either indexing works.
            let generics = genericParametersByName[prefix.joined(separator: ".")]
                ?? genericParametersByName[component]
                ?? []
            guard let piece = rendered(typeName: component, genericParameters: generics) else {
                return nil
            }
            pieces.append(piece)
        }
        return pieces.isEmpty ? nil : pieces.joined(separator: ".")
    }

    public static func rendered(
        typeName: String,
        genericParameters: [TypeDecl.GenericParameter]
    ) -> String? {
        guard !genericParameters.isEmpty else { return typeName }
        for parameter in genericParameters {
            guard let constraint = parameter.constraint else { continue }
            let parts = constraint
                .split(separator: "&")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            for part in parts where !intSatisfiedConstraints.contains(part) {
                return nil
            }
        }
        let arguments = Array(repeating: "Int", count: genericParameters.count)
        return "\(typeName)<\(arguments.joined(separator: ", "))>"
    }

    /// The reason a carrier could not be instantiated, phrased for the emitted comment so a
    /// reader can act on it — it names the parameter and the constraint that blocked it,
    /// not just the fact of failure.
    /// The decline reason for a qualified name, or `nil` when it renders.
    public static func declineReason(
        qualifiedTypeName: String,
        genericParametersByName: [String: [TypeDecl.GenericParameter]]
    ) -> String? {
        guard rendered(
            qualifiedTypeName: qualifiedTypeName,
            genericParametersByName: genericParametersByName
        ) == nil else { return nil }
        for component in qualifiedTypeName.split(separator: ".").map(String.init) {
            let generics = genericParametersByName[component] ?? []
            if let reason = declineReason(typeName: component, genericParameters: generics) {
                return reason
            }
        }
        return nil
    }

    public static func declineReason(
        typeName: String,
        genericParameters: [TypeDecl.GenericParameter]
    ) -> String? {
        guard rendered(typeName: typeName, genericParameters: genericParameters) == nil else {
            return nil
        }
        let blocking = genericParameters.compactMap { parameter -> String? in
            guard let constraint = parameter.constraint else { return nil }
            let unsatisfied = constraint
                .split(separator: "&")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !intSatisfiedConstraints.contains($0) }
            guard !unsatisfied.isEmpty else { return nil }
            return "\(parameter.name): \(unsatisfied.joined(separator: " & "))"
        }
        return "Cannot choose a concrete instantiation for `\(typeName)`: `Int` does not "
            + "satisfy \(blocking.joined(separator: ", ")). The kit's suites need a concrete "
            + "type; instantiate it yourself and write the call by hand."
    }
}
