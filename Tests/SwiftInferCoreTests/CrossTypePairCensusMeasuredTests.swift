import Foundation
import Testing

@testable import SwiftInferCore
@testable import SwiftInferTemplates

/// **How general is the cross-type round-trip pairing, and is any of it salvageable?**
///
/// The 2026-08-19 survey's largest single-cause population: `round-trip` proposes **72**
/// entries and **0** run, **62** of them declining *"Cross-type round-trip pair: forward in
/// X, reverse in Y — property cannot type-check across distinct containing types"*.
///
/// Those 62 are `Advisory`, so the zero is by design rather than a failure —
/// `crossTypeRoundTripPair` is one of `StructuralBlocker.blockingKinds`. **The question is
/// therefore not why they do not run but whether proposing them earns its place**, and the
/// visibility rows are the precedent: kept, and explained better once a remedy existed.
///
/// **A cross-type pair has no equivalent remedy.** A law about a `private` subject can be
/// lifted to its caller; a pairing that cannot type-check cannot be lifted anywhere,
/// because the pairing itself is what fails.
///
/// ## The control this census exists to run
///
/// **Two declines this week were closed by the same control**: the parameter-role class was
/// 5 rows all in this repository, and OrderedCollections had **zero** — the shape was what a
/// *code generator* produces, not what a library does. 39 of these 62 involve stub
/// emitters, which is the same character.
///
/// So the question is measured on corpora this repo does not own, before anything is built
/// or declined. **Counting the denominator before believing a concentration** is the lesson
/// today keeps re-teaching: *3 of 3* was 3 of the 5 rows in existence.
@Suite("Census — is cross-type round-trip pairing general or self-only?", .serialized)
struct CrossTypePairCensusMeasuredTests {

    @Test("control — every corpus produced round-trip suggestions to classify")
    func theCensusReaches() {
        #expect(!Self.readings.isEmpty, "no corpus scanned")
        #expect(Self.readings.contains { $0.roundTrip > 0 }, """
        No corpus produced a round-trip suggestion at all, so every split below is the \
        instrument's rather than the corpus's.
        """)
    }

    @Test("census — cross-type pairs per corpus")
    func census() {
        for reading in Self.readings {
            print("""
            \(reading.corpus): \(reading.roundTrip) round-trip suggestions
              cross-type (evidence rows in different containing types): \(reading.crossType)
              same-type:                                                \(reading.sameType)
              …cross-type rows whose carriers are BOTH emitters:        \(reading.emitterPairs)
            """)
            for row in reading.samples.prefix(6) { print("    \(row)") }
        }
    }
}
