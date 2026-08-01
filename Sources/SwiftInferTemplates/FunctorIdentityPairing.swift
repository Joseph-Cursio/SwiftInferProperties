import Foundation
import SwiftInferCore

/// Recognises a **carrier-preserving map** — the shape behind the catalog's functor laws.
///
///     container.map { $0 } == container
///
/// ## Provenance
///
/// Six `[reference]` rows in `known-properties`: `Optional`'s map identity, map
/// composition and flatMap right identity, and `mapValues` functor identity on
/// `Dictionary`, `OrderedDictionary` and `TreeDictionary`. Known true, `--verify`-
/// executable, and never transferable to a carrier of the user's own.
///
/// ## The return type is the whole discriminator, and it does two jobs
///
/// **A map is only a functor when it preserves the container.** `Set.map` returns `[T]`,
/// not `Set<T>` — so `s.map { $0 } == s` does not even typecheck, let alone hold.
/// `Dictionary.map` returns `[T]` too, which is exactly why the catalog states the law
/// over `mapValues` and not `map`. Requiring the return type to be the carrier admits
/// `Result`, `Optional`, `EventLoopFuture` and every `mapValues`, and excludes the
/// `Sequence.map` family that changes shape.
///
/// **And it is the kit-overlap gate.** `checkTransformationPropertyLaws` ships
/// `Transformation.mapFusion` — `sample.map(f).map(g) == sample.map { g(f($0)) }` — over
/// **any `Sequence`**. So a bare `map` on a `Sequence` carrier is a double-report and is
/// declined. `mapValues` is not `Sequence.map`, so a dictionary carrier is new surface
/// even though `Dictionary` conforms to `Sequence`. Measured: that distinction is the
/// difference between 8 rows and 11.
///
/// **Unknown conformances decline, and a name fallback backs that up.**
/// `LazyMapSequence.map` IS `Sequence.map` and a double-report — but its `Sequence`
/// conformance is declared in a conditional extension the scanner does not record, so a
/// conformance-only rule **admitted it**, measured. The fallback is the
/// `IdempotenceTemplate+IteratorVeto` pattern: textual conformance primary, name
/// secondary, because a type called `…Sequence` or `…Collection` is one. That single
/// rule is the difference between 9 rows and 8.
public enum FunctorIdentityPairing {

    /// Map-family method names.
    ///
    /// `compactMap` is deliberately absent: `o.compactMap { $0 }` is not the identity —
    /// it removes `nil`s, so on a carrier of Optionals it changes the value. A name that
    /// is a functor for some element types and not others cannot carry this law.
    public static let mapNames: Set<String> = ["map", "mapValues", "mapKeys", "mapError"]

    /// Names whose meaning is `Sequence.map`, and so are covered by the kit when the
    /// carrier is a sequence. `mapValues` and friends are not among them.
    public static let sequenceMapNames: Set<String> = ["map"]

    /// One statable functor-identity law.
    public struct FunctorShape: Sendable, Equatable {

        /// The carrier, generic parameters stripped — `Result`.
        public let typeName: String

        /// The map-family method.
        public let mapper: FunctionSummary

        /// Its return type as written — `Result<NewSuccess, Failure>`.
        public let returnTypeText: String

        public init(typeName: String, mapper: FunctionSummary, returnTypeText: String) {
            self.typeName = typeName
            self.mapper = mapper
            self.returnTypeText = returnTypeText
        }

        /// The law, as Swift.
        public var lawText: String {
            "c.\(mapper.name) { $0 } == c"
        }
    }

    /// Every functor-identity law statable from `summaries`.
    public static func candidates(
        in summaries: [FunctionSummary],
        inheritedTypesByName: [String: Set<String>]
    ) -> [FunctorShape] {
        var result: [FunctorShape] = []
        var seen: Set<String> = []
        for summary in summaries.sorted(by: { $0.location.line < $1.location.line })
        where mapNames.contains(summary.name) {
            guard isMapShaped(summary),
                  let carrier = summary.containingTypeName,
                  let returnType = summary.returnTypeText else { continue }
            let bare = normalisedTypeName(carrier)
            guard normalisedTypeName(returnType) == bare || returnType == "Self" else { continue }
            guard !isKitCoveredSequenceMap(summary, carrier: bare, inheritedTypesByName) else {
                continue
            }
            guard seen.insert("\(bare)|\(summary.name)").inserted else { continue }
            result.append(FunctorShape(
                typeName: bare, mapper: summary, returnTypeText: returnType
            ))
        }
        return result.sorted { ($0.typeName, $0.mapper.name) < ($1.typeName, $1.mapper.name) }
    }

    /// A non-mutating, single-closure-argument method.
    static func isMapShaped(_ summary: FunctionSummary) -> Bool {
        guard !summary.isMutating, !summary.isStatic,
              summary.parameters.count == 1,
              let parameter = summary.parameters.first, !parameter.isInout else {
            return false
        }
        // The argument has to be a function, or this is not a map.
        return parameter.typeText.contains("->") || parameter.typeText.hasPrefix("(")
    }

    /// Whether this is `Sequence.map` on a sequence carrier, which the kit's
    /// `Transformation.mapFusion` already covers.
    ///
    /// Conservative on unknowns: a carrier with no recorded conformances is treated as a
    /// possible sequence and declined, because the sweep showed the scanner misses
    /// conformances for types like `LazyMapSequence` whose `map` IS the kit's law.
    static func isKitCoveredSequenceMap(
        _ summary: FunctionSummary,
        carrier: String,
        _ inheritedTypesByName: [String: Set<String>]
    ) -> Bool {
        guard sequenceMapNames.contains(summary.name) else { return false }
        let conformances = inheritedTypesByName[carrier] ?? []
        if conformances.contains("Sequence") || conformances.contains("Collection") {
            return true
        }
        // Name fallback — the conformance index misses conditional extensions, and
        // `LazyMapSequence` was admitted by a conformance-only rule in the sweep.
        if sequenceShapedSuffixes.contains(where: { carrier.hasSuffix($0) }) { return true }
        // No evidence either way: decline. Silence beats a double-report.
        return conformances.isEmpty
    }

    /// Type-name suffixes that mean "this is a sequence", used only when the conformance
    /// index has no answer.
    static let sequenceShapedSuffixes: [String] = [
        "Sequence", "Collection", "Slice", "View", "Iterator", "Array", "Set"
    ]

    /// Strips generics and Optional sugar, and resolves `[U]` / `[K: V]` to the type they
    /// sugar for — without which `Array.map -> [T]` never matches its carrier.
    static func normalisedTypeName(_ typeText: String) -> String {
        var text = typeText.trimmingCharacters(in: .whitespaces)
        if text.hasSuffix("?") { text = String(text.dropLast()) }
        if text.hasPrefix("["), text.hasSuffix("]") {
            return text.contains(":") ? "Dictionary" : "Array"
        }
        guard let angle = text.firstIndex(of: "<") else { return text }
        return String(text[text.startIndex..<angle])
    }
}
