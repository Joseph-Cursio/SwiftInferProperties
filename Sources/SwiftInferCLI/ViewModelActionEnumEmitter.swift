import Foundation
import SwiftInferCore

/// PROTOTYPE — materializes an `@Observable` view model's action alphabet
/// into a **synthetic `Action` enum + a `drive(_:_:)` dispatcher**.
///
/// This is the "M1′ live-class" materialization (Observable Carrier
/// proposal, thread 1): the view model's mutating methods *are* its action
/// surface, so lifting `func add(_:)` / `func rename(id:to:)` into
///
/// ```swift
/// enum CartModelAction: Sendable {
///     case add(Item)
///     case rename(id: UUID, to: String)
/// }
/// func drive(_ model: CartModel, _ action: CartModelAction) {
///     switch action {
///     case .add(let a0):          model.add(a0)
///     case .rename(let a0, let a1): model.rename(id: a0, to: a1)
///     }
/// }
/// ```
///
/// is a mechanical, total transform. Once the enum exists, `Gen<[Action]>`
/// comes from the kit's `ActionSequenceFactory` (Slice 3), unlocking the
/// multi-step random interleavings the current single-pass verifier can't
/// reach. The dispatcher drives a *live* instance (methods mutate the
/// reference in place) — no synthetic value-`State` projection.
///
/// **Scope (this slice):** the enum + dispatcher text only. Methods that
/// can't sit in a synchronous dispatcher — `async` / `throws` — are dropped
/// from the surface **with a recorded reason** (explainability is
/// first-class), never silently. Payload *generatability* filtering and the
/// sequence loop are Slice 3.
public enum ViewModelActionEnumEmitter {

    /// Why a method was left out of the synthetic action surface.
    public enum SkipReason: String, Equatable, Sendable {
        /// `async` — can't be called from the synchronous dispatcher.
        case asyncMethod = "async"
        /// `throws` — ditto; a throwing call needs a `try`/handler the
        /// dispatcher doesn't model.
        case throwingMethod = "throws"
    }

    /// A method dropped from the action surface, with its reason.
    public struct Skipped: Equatable, Sendable {
        public let action: String
        public let reason: SkipReason

        public init(action: String, reason: SkipReason) {
            self.action = action
            self.reason = reason
        }
    }

    /// One lifted method ↔ its synthesized case name — the map the
    /// dispatcher and (Slice 3) the generator are built from.
    public struct LiftedCase: Equatable, Sendable {
        public let caseName: String
        public let action: ViewModelAction

        public init(caseName: String, action: ViewModelAction) {
            self.caseName = caseName
            self.action = action
        }
    }

    public struct Result: Equatable, Sendable {
        /// `<TypeName>Action`.
        public let enumName: String
        /// The `enum … { … }` + `func drive(…) { … }` source fragment.
        public let source: String
        /// Lifted methods, in declared (sorted) order, with case names.
        public let lifted: [LiftedCase]
        /// Methods excluded from the surface, with reasons.
        public let skipped: [Skipped]
        /// `true` when *every* lifted case is nullary, so the enum can
        /// conform to `CaseIterable` (drives `actionSequence(forCaseIterable:)`
        /// in Slice 3). Mixed/payloaded ⇒ `false` (needs a composed
        /// `Gen<Action>`).
        public let isCaseIterable: Bool

        public init(
            enumName: String,
            source: String,
            lifted: [LiftedCase],
            skipped: [Skipped],
            isCaseIterable: Bool
        ) {
            self.enumName = enumName
            self.source = source
            self.lifted = lifted
            self.skipped = skipped
            self.isCaseIterable = isCaseIterable
        }
    }

    /// Synthesize the enum + dispatcher for `typeName`'s action alphabet.
    public static func emit(typeName: String, actions: [ViewModelAction]) -> Result {
        let enumName = "\(typeName)Action"

        var lifted: [LiftedCase] = []
        var skipped: [Skipped] = []
        var usedCaseNames: Set<String> = []

        for action in actions {
            if action.isAsync {
                skipped.append(Skipped(action: action.name, reason: .asyncMethod))
                continue
            }
            if action.isThrows {
                skipped.append(Skipped(action: action.name, reason: .throwingMethod))
                continue
            }
            let caseName = uniqueCaseName(for: action, taken: &usedCaseNames)
            lifted.append(LiftedCase(caseName: caseName, action: action))
        }

        let isCaseIterable = lifted.allSatisfy(\.action.parameters.isEmpty)
        let source = renderSource(
            typeName: typeName,
            enumName: enumName,
            lifted: lifted,
            isCaseIterable: isCaseIterable
        )
        return Result(
            enumName: enumName,
            source: source,
            lifted: lifted,
            skipped: skipped,
            isCaseIterable: isCaseIterable
        )
    }

    // MARK: - Case naming

    /// A collision-safe, keyword-safe case identifier. Base is the method
    /// name; overloaded methods (same name, different signatures) are
    /// disambiguated by appending capitalized argument labels, then a
    /// numeric suffix as a last resort. Result is inserted into `taken`.
    private static func uniqueCaseName(
        for action: ViewModelAction,
        taken: inout Set<String>
    ) -> String {
        var candidate = action.name
        if taken.contains(candidate) {
            let labelSuffix = action.parameters
                .map { $0.label.map(capitalizedFirst) ?? "Unlabeled" }
                .joined()
            if !labelSuffix.isEmpty { candidate = action.name + labelSuffix }
        }
        var unique = candidate
        var counter = 2
        while taken.contains(unique) {
            unique = "\(candidate)\(counter)"
            counter += 1
        }
        taken.insert(unique)
        return escapeIfKeyword(unique)
    }

    // MARK: - Rendering

    private static func renderSource(
        typeName: String,
        enumName: String,
        lifted: [LiftedCase],
        isCaseIterable: Bool
    ) -> String {
        let conformances = isCaseIterable ? "CaseIterable, Sendable" : "Sendable"

        let cases = lifted.map { "    case \(caseDeclaration($0))" }
            .joined(separator: "\n")
        let enumBlock = lifted.isEmpty
            ? "enum \(enumName): \(conformances) {}"
            : "enum \(enumName): \(conformances) {\n\(cases)\n}"

        let arms = lifted.map { "    case \(dispatchArm($0, modelName: "model"))" }
            .joined(separator: "\n")
        let driveBlock = lifted.isEmpty
            ? "func drive(_ model: \(typeName), _ action: \(enumName)) {}"
            : """
            func drive(_ model: \(typeName), _ action: \(enumName)) {
                switch action {
            \(arms)
                }
            }
            """

        return "\(enumBlock)\n\n\(driveBlock)"
    }

    /// `add(Item)` / `rename(id: UUID, to: String)` / `beginCheckout`.
    private static func caseDeclaration(_ lifted: LiftedCase) -> String {
        let params = lifted.action.parameters
        guard !params.isEmpty else { return lifted.caseName }
        let payload = params.map { param -> String in
            if let label = param.label { return "\(label): \(param.typeText)" }
            return param.typeText
        }
        .joined(separator: ", ")
        return "\(lifted.caseName)(\(payload))"
    }

    /// `.add(let a0): model.add(a0)` /
    /// `.rename(let a0, let a1): model.rename(id: a0, to: a1)` /
    /// `.beginCheckout: model.beginCheckout()`.
    private static func dispatchArm(_ lifted: LiftedCase, modelName: String) -> String {
        let params = lifted.action.parameters
        // Bind positionally (a0, a1, …) so a parameter label that happens to
        // be a Swift keyword never becomes a binding identifier.
        let bindingNames = params.indices.map { "a\($0)" }
        let call = callExpression(lifted.action, modelName: modelName, bindings: bindingNames)
        guard !params.isEmpty else {
            return ".\(lifted.caseName): \(call)"
        }
        let bindings = bindingNames.map { "let \($0)" }.joined(separator: ", ")
        return ".\(lifted.caseName)(\(bindings)): \(call)"
    }

    /// `model.rename(id: a0, to: a1)` — original method name + labels.
    private static func callExpression(
        _ action: ViewModelAction,
        modelName: String,
        bindings: [String]
    ) -> String {
        let arguments = zip(action.parameters, bindings).map { param, binding -> String in
            if let label = param.label { return "\(label): \(binding)" }
            return binding
        }
        .joined(separator: ", ")
        // Escape a keyword method name at the call site too (the recognizer
        // stores `node.name.text`, which has the backticks stripped).
        return "\(modelName).\(escapeIfKeyword(action.name))(\(arguments))"
    }

    // MARK: - Identifier helpers

    private static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// Swift keywords that can appear as a method name and would break an
    /// enum-case identifier if left unescaped.
    private static let reservedWords: Set<String> = [
        "associatedtype", "class", "deinit", "enum", "extension", "func",
        "import", "init", "inout", "let", "operator", "protocol", "struct",
        "subscript", "typealias", "var", "break", "case", "continue",
        "default", "defer", "do", "else", "fallthrough", "for", "guard",
        "if", "in", "repeat", "return", "switch", "where", "while", "as",
        "catch", "false", "is", "nil", "rethrows", "self", "Self", "super",
        "throw", "throws", "true", "try"
    ]

    private static func escapeIfKeyword(_ identifier: String) -> String {
        reservedWords.contains(identifier) ? "`\(identifier)`" : identifier
    }
}
