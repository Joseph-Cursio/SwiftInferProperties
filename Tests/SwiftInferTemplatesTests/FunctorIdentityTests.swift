import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// **Functor identity** — `c.map { $0 } == c`, from the `known-properties` `[reference]`
/// rows.
///
/// The return-type rule does two jobs at once, and both are pinned below: it is the
/// correctness gate (a map that changes the container cannot carry this law) and the
/// kit-overlap gate (`Transformation.mapFusion` covers `Sequence.map`).
@Suite("Functor identity — mapping the identity function changes nothing")
struct FunctorIdentityTests {

    private static let loc = SourceLocation(file: "Result.swift", line: 40, column: 1)

    private func mapper(
        _ name: String,
        on carrier: String,
        returns: String,
        parameter: String = "(Success) -> NewSuccess",
        isMutating: Bool = false
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [
                Parameter(
                    label: nil, internalName: "transform",
                    typeText: parameter, isInout: false
                )
            ],
            returnTypeText: returns,
            isThrows: false,
            isAsync: false,
            isMutating: isMutating,
            isStatic: false,
            location: Self.loc,
            containingTypeName: carrier,
            bodySignals: .empty
        )
    }

    // MARK: - The shape it exists for

    @Test("A carrier-preserving map on a non-sequence fires")
    func carrierPreservingMapFires() {
        let shapes = FunctorIdentityPairing.candidates(
            in: [mapper("map", on: "Result", returns: "Result<NewSuccess, Failure>")],
            inheritedTypesByName: ["Result": ["Equatable", "Sendable"]]
        )
        #expect(shapes.count == 1)
        let suggestion = shapes.first.flatMap(FunctorIdentityTemplate.suggest(for:))
        #expect(suggestion?.templateName == "functor-identity")
        #expect(suggestion?.score.total == 70)
        #expect(suggestion?.score.tier == .likely)
        #expect(shapes.first?.lawText == "c.map { $0 } == c")
    }

    /// `mapValues` is not `Sequence.map`, so a dictionary carrier is new surface even
    /// though `Dictionary` conforms to `Sequence`. This is the distinction that took the
    /// measured population from 5 usable rows to 8.
    @Test("mapValues on a Sequence carrier is NOT the kit's law")
    func mapValuesOnSequenceCarrierFires() {
        let shapes = FunctorIdentityPairing.candidates(
            in: [
                mapper(
                    "mapValues", on: "Dictionary", returns: "Dictionary<Key, T>",
                    parameter: "(Value) throws -> T"
                )
            ],
            inheritedTypesByName: ["Dictionary": ["Sequence", "Collection"]]
        )
        #expect(shapes.count == 1)
        #expect(shapes.first?.typeName == "Dictionary")
    }

    // MARK: - The return-type rule as a CORRECTNESS gate

    /// `Set.map` returns `[T]`, so `s.map { $0 } == s` does not even typecheck.
    /// `Dictionary.map` is the same shape — which is exactly why the catalog states the
    /// law over `mapValues`.
    @Test("A map returning [T] changes the container and is declined")
    func shapeChangingMapDeclined() {
        let setMap = FunctorIdentityPairing.candidates(
            in: [mapper("map", on: "Bag", returns: "[T]", parameter: "(Element) -> T")],
            inheritedTypesByName: ["Bag": ["Equatable"]]
        )
        #expect(setMap.isEmpty)
    }

    /// `[U]` is sugar for `Array<U>`, so the normaliser has to resolve it or an
    /// `Array.map -> [T]` would never match its own carrier.
    @Test("Bracket sugar resolves to the type it sugars for")
    func bracketSugarNormalises() {
        #expect(FunctorIdentityPairing.normalisedTypeName("[U]") == "Array")
        #expect(FunctorIdentityPairing.normalisedTypeName("[K: V]") == "Dictionary")
        #expect(FunctorIdentityPairing.normalisedTypeName("Result<A, B>") == "Result")
        #expect(FunctorIdentityPairing.normalisedTypeName("Foo?") == "Foo")
    }

    // MARK: - The return-type rule as a KIT-OVERLAP gate

    /// `checkTransformationPropertyLaws` ships `Transformation.mapFusion` over any
    /// `Sequence`, so a bare `map` on a sequence carrier is the kit's job.
    @Test("A bare map on a known Sequence carrier is declined as a double-report")
    func sequenceMapDeclined() {
        let shapes = FunctorIdentityPairing.candidates(
            in: [mapper("map", on: "Chunks", returns: "Chunks<T>", parameter: "(E) -> T")],
            inheritedTypesByName: ["Chunks": ["Sequence"]]
        )
        #expect(shapes.isEmpty)
    }

    /// **The witness that added the name fallback.** `LazyMapSequence.map` IS
    /// `Sequence.map`, but its conformance is declared in a conditional extension the
    /// scanner does not record — so a conformance-only rule admitted it on the real
    /// corpus. Textual conformance primary, name secondary, per
    /// `IdempotenceTemplate+IteratorVeto`.
    @Test("A sequence-shaped NAME is declined even when the conformance is missing")
    func sequenceNameFallback() {
        for carrier in ["LazyMapSequence", "SomeCollection", "MySlice", "KeysView"] {
            let shapes = FunctorIdentityPairing.candidates(
                in: [mapper("map", on: carrier, returns: "\(carrier)<T>", parameter: "(E) -> T")],
                inheritedTypesByName: [carrier: ["Sendable"]]
            )
            #expect(shapes.isEmpty, "\(carrier) should be declined by the name fallback")
        }
    }

    @Test("No conformance evidence at all declines rather than admits")
    func unknownCarrierDeclined() {
        let shapes = FunctorIdentityPairing.candidates(
            in: [mapper("map", on: "Mystery", returns: "Mystery<T>", parameter: "(E) -> T")],
            inheritedTypesByName: [:]
        )
        #expect(shapes.isEmpty)
    }

    // MARK: - Shape gates

    /// `o.compactMap { $0 }` is NOT the identity — it removes `nil`s, so on a carrier of
    /// Optionals it changes the value. A name that is a functor for some element types
    /// and not others cannot carry this law.
    @Test("compactMap is not in the map family")
    func compactMapExcluded() {
        #expect(FunctorIdentityPairing.mapNames.contains("compactMap") == false)
    }

    @Test("A non-closure argument is not a map")
    func nonClosureArgumentDeclined() {
        let shapes = FunctorIdentityPairing.candidates(
            in: [mapper("map", on: "Result", returns: "Result<T, E>", parameter: "Int")],
            inheritedTypesByName: ["Result": ["Equatable"]]
        )
        #expect(shapes.isEmpty)
    }

    @Test("A mutating map is not the value-returning functor")
    func mutatingMapDeclined() {
        let shapes = FunctorIdentityPairing.candidates(
            in: [mapper("map", on: "Result", returns: "Result<T, E>", isMutating: true)],
            inheritedTypesByName: ["Result": ["Equatable"]]
        )
        #expect(shapes.isEmpty)
    }

    // MARK: - Explainability (PRD §4.5)

    /// Identity is the weaker half and the caveat has to say so, or a green run reads as
    /// "map is a functor" when it only means "map is a functor at the identity function".
    @Test("The caveats name composition as the stronger law, and the kit boundary")
    func caveatsCarryTheLimits() {
        let shapes = FunctorIdentityPairing.candidates(
            in: [mapper("map", on: "Result", returns: "Result<NewSuccess, Failure>")],
            inheritedTypesByName: ["Result": ["Equatable"]]
        )
        let caveats = shapes.first.map(FunctorIdentityTemplate.makeCaveats(for:)) ?? []
        #expect(caveats.contains { $0.contains("IDENTITY IS THE WEAKER HALF") })
        #expect(caveats.contains { $0.contains("Transformation.mapFusion") })
        #expect(caveats.contains { $0.contains("re-sorting") })
    }

    @Test("The generator recipe asks for the short-circuit states")
    func generatorRationale() {
        let shapes = FunctorIdentityPairing.candidates(
            in: [mapper("map", on: "Result", returns: "Result<NewSuccess, Failure>")],
            inheritedTypesByName: ["Result": ["Equatable"]]
        )
        let recipes = shapes.first.map(FunctorIdentityTemplate.makeGenerators(for:)) ?? []
        #expect(recipes.first?.rationale.contains("short-circuit path") == true)
        #expect(recipes.first?.rationale.contains("failure branch") == true)
    }

    @Test("Identity is distinct per map name and stable across rebuilds")
    func identityIsStableAndScoped() {
        func build() -> [SuggestionIdentity] {
            let shapes = FunctorIdentityPairing.candidates(
                in: [
                    mapper("map", on: "Result", returns: "Result<T, E>"),
                    mapper("mapError", on: "Result", returns: "Result<S, F>")
                ],
                inheritedTypesByName: ["Result": ["Equatable"]]
            )
            return shapes.map(FunctorIdentityTemplate.makeIdentity(for:))
        }
        let first = build()
        #expect(Set(first).count == 2, "one identity per map-family method")
        #expect(first == build())
    }
}
