/// Renders the `Gen<T>` body string used when
/// `GeneratorMetadata.Source == .derivedCodableRoundTrip` — the
/// fixture-seeded encode/decode generator that PRD §7.4 rung 5
/// describes for `T: Codable` types whose generator can't be derived
/// any other way.
///
/// **Why a fixture rung at all.** Codable round-trip is unusual among
/// SwiftInfer's generator-derivation rungs: most rungs (`memberwise`,
/// `caseIterable`, `rawRepresentable`) produce a `Gen<T>` that can
/// build values from nothing — the random seed flows through the
/// strategy's machinery into a fresh `T`. Codable can't: `JSONDecoder`
/// needs JSON bytes to decode from, and we have no automatic way to
/// synthesize a representative JSON encoding of an arbitrary
/// `T: Codable` (the kind of "shape" reasoning that would let us is
/// the same shape reasoning the M3 strategist would have used to pick
/// `.derivedMemberwise` first). The Codable rung therefore emits a
/// **scaffold** — a `Gen<T>` whose body wires the encode/decode chain
/// but leaves the input fixture as an explicit placeholder for the
/// user to fill in. The user
/// reviews the writeout, replaces the fixture with a representative
/// JSON encoding of `T`, and the round-trip property exercises their
/// Codable conformance with no further plumbing.
///
/// **Why `try!`.** Same posture PRD §3.5 prescribes elsewhere — false
/// positives (silently passing trials with a wrong-shape value) are
/// more damaging than missed opportunities. With a placeholder `{}`
/// fixture, decoding most non-empty types will trap immediately, and
/// the trap is the visible signal "you must replace this fixture
/// before this property buys you anything."
///
/// **Foundation requirement.** The rendered body uses `Data`,
/// `JSONEncoder`, and `JSONDecoder` — `import Foundation` must be in
/// scope at the writeout site. `InteractiveTriage+Accept`'s
/// `wrappedFileContents` widens the imports list for
/// `.derivedCodableRoundTrip`-source suggestions accordingly.
public enum CodableRoundTripGeneratorRenderer {

    /// Produce the `Gen<\(typeName)> { ... }` body string. Multi-line,
    /// pre-indented at the column the existing
    /// `LiftedTestEmitter+Generators` helpers use so the chooseGenerator
    /// dispatch can interpolate the result in place without
    /// post-processing.
    public static func renderGenerator(for typeName: String) -> String {
        """
        Gen<\(typeName)> { _ in
                // SwiftInfer (TestLifter M5.4): Codable round-trip generator scaffold.
                // Replace `fixtureJSON` with a representative JSON encoding of
                // `\(typeName)` — the encode/decode round-trip exercises the Codable
                // conformance without requiring a custom `\(typeName).gen()` baseline.
                let encoder = JSONEncoder()
                let decoder = JSONDecoder()
                let fixtureJSON = Data("{}".utf8)  // TODO: replace with real fixture
                let value = try! decoder.decode(\(typeName).self, from: fixtureJSON)
                let data = try! encoder.encode(value)
                return try! decoder.decode(\(typeName).self, from: data)
            }
        """
    }
}
