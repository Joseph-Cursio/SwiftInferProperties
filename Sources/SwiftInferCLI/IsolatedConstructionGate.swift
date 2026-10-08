import Foundation
import SwiftInferCore

/// Withdraws a stub whose **generator** calls an initializer the generator cannot reach — one
/// isolated to a global actor — and names the declaration to change.
///
/// ## The defect this closes
///
/// A generator runs in the `sample:` closure, which is `@Sendable` and nonisolated, and the
/// backend calls it off any actor. Every derived generator ends in a construction —
/// `zip(…).map { MigrationPlan(fromVersion: $0.0, …) }` — and in a target compiled under
/// `.defaultIsolation(MainActor.self)` that initializer is MainActor-isolated. Measured on
/// SwiftLintRuleStudioCore, after the property side was given its hop: the `applyMigration`
/// mutator stubs failed with *call to main actor-isolated initializer
/// 'init(fromVersion:toVersion:steps:)' in a synchronous nonisolated context*, and nothing in the
/// written file said why. `MainActor.assumeIsolated` is no answer: the closure is checked where it
/// is written, and at run time it is not on the main actor.
///
/// So the stub is withdrawn with the reason, as the other accept-time gates withdraw one that
/// could never compile — and the reason names the remedy, which is the subject's: declare the type
/// `nonisolated` (its stored properties must then be `Sendable`), or give it a `nonisolated init`.
///
/// ## Erring toward writing
///
/// It declines only what it is sure of: a construction of a scanned type, in a target whose
/// default isolation is a global actor or written on the type, that opts out **nowhere** — neither
/// the type nor any of its own initializers is `nonisolated`. A type with one `nonisolated init`
/// passes even if the generator calls another, because a missed decline leaves the stub as it was
/// before this gate, while a wrong one withholds a stub that compiles.
enum IsolatedConstructionGate {

    /// What the gate needs to know about one scanned type.
    struct Fact: Equatable {
        /// Where the type is declared, so its target's default isolation can be read.
        let file: String
        /// A global actor written on the declaration itself (`@MainActor struct …`), if any.
        let declaredGlobalActor: String?
        let isNonisolated: Bool
        let declaresNonisolatedInitializer: Bool

        var optsOut: Bool { isNonisolated || declaresNonisolatedInitializer }
    }

    /// Facts by qualified name and, where it is unambiguous, by simple name — a stub spells a
    /// nested type either way. Extensions are folded into their type's record: one that adds a
    /// `nonisolated init` opts the type out as surely as one in its primary body.
    static func facts(from typeDecls: [TypeDecl]) -> [String: Fact] {
        let primaries = typeDecls.filter { $0.kind != .extension && $0.kind != .protocol }
        var byQualified: [String: Fact] = [:]
        for decl in primaries {
            let extensionsOptOut = typeDecls.contains {
                $0.kind == .extension && $0.name == decl.qualifiedName && $0.declaresNonisolatedInitializer
            }
            byQualified[decl.qualifiedName] = Fact(
                file: decl.location.file,
                declaredGlobalActor: decl.attributeNames.first { $0 == "MainActor" || $0.hasSuffix("Actor") },
                isNonisolated: decl.isNonisolated,
                declaresNonisolatedInitializer: decl.declaresNonisolatedInitializer || extensionsOptOut
            )
        }
        var facts = byQualified
        let bySimple = Dictionary(grouping: primaries, by: \.name)
        for (name, decls) in bySimple where decls.count == 1 && facts[name] == nil {
            facts[name] = byQualified[decls[0].qualifiedName]
        }
        return facts
    }

    /// Why `stub` cannot compile because of an isolated construction in its sample closure, or
    /// `nil`.
    ///
    /// - Parameter isolation: the default isolation of the target declaring a file — injected so
    ///   the gate can be tested without a manifest; the accept path passes `TargetIsolation`.
    static func declineReason(
        stub: String,
        facts: [String: Fact],
        isolation: (String) -> String? = TargetIsolation.defaultIsolation(forFile:)
    ) -> String? {
        guard !facts.isEmpty, let sample = sampleClosure(in: stub) else { return nil }
        for name in constructedTypeNames(in: sample) {
            guard let fact = facts[name], !fact.optsOut,
                  let actor = fact.declaredGlobalActor ?? isolation(fact.file).flatMap(globalActor) else {
                continue
            }
            let source = fact.declaredGlobalActor == nil
                ? "by its target's `.defaultIsolation(\(actor).self)`"
                : "by its `@\(actor)` attribute"
            return "its generator builds a `\(name)`, whose initializer is isolated to \(actor) \(source), "
                + "and a generator runs off \(actor), so the stub cannot compile — declare `\(name)` "
                + "`nonisolated` (its stored properties must then be `Sendable`) or give it a "
                + "`nonisolated init`, and accept again"
        }
        return nil
    }

    /// `nil` for a target that is not isolated to an actor at all.
    private static func globalActor(_ isolation: String) -> String? {
        isolation == "nonisolated" ? nil : isolation
    }

    /// The text of the stub's `sample:` closure — the only place a generator runs. The property
    /// closure is hopped onto the subject's actor, so a construction there is reachable.
    static func sampleClosure(in stub: String) -> String? {
        guard let start = stub.range(of: "sample:") else { return nil }
        let end = stub.range(of: "property:", range: start.upperBound ..< stub.endIndex)?.lowerBound ?? stub.endIndex
        return String(stub[start.upperBound ..< end])
    }

    /// The type names called as initializers in `text`: `Plan(` and `Outer.Inner(`, not
    /// `Step.rename(` (a case or a static member) and not `.gen(`.
    static func constructedTypeNames(in text: String) -> [String] {
        let pattern = #"(?<![\w.])((?:[A-Z]\w*\.)*[A-Z]\w*)\("#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var seen: Set<String> = []
        return regex.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range(at: 1), in: text) else { return nil }
            let name = String(text[swiftRange])
            return seen.insert(name).inserted ? name : nil
        }
    }
}
