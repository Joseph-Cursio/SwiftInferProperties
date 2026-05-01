import CryptoKit
import Foundation
import Testing
@testable import SwiftInferCore

@Suite("SamplingSeed — PRD v0.4 §16 #6 256-bit deterministic seed derivation")
struct SamplingSeedTests {

    // MARK: - Determinism + reproducibility

    @Test
    func sameIdentityProducesSameSeed() {
        let identity = SuggestionIdentity(canonicalInput: "idempotence|Foo.normalize(_:)|(String)->String")
        let first = SamplingSeed.derive(from: identity)
        let second = SamplingSeed.derive(from: identity)
        #expect(first == second)
    }

    @Test
    func reDerivingFromTheNormalizedHashMatchesIdentityDerivation() {
        // §16 #6 reproducibility: callers that have only the
        // normalized hash text (e.g. when re-running sampling against
        // a `// swiftinfer: skip` marker's recorded hash) must get
        // exactly the same seed as callers that have the full
        // SuggestionIdentity value.
        let identity = SuggestionIdentity(canonicalInput: "round-trip|encode|decode")
        let viaIdentity = SamplingSeed.derive(from: identity)
        let viaHash = SamplingSeed.derive(fromIdentityHash: identity.normalized)
        #expect(viaIdentity == viaHash)
    }

    // MARK: - Independence

    @Test
    func differentIdentitiesProduceDifferentSeeds() {
        let alpha = SuggestionIdentity(canonicalInput: "idempotence|alpha")
        let beta = SuggestionIdentity(canonicalInput: "idempotence|beta")
        #expect(SamplingSeed.derive(from: alpha) != SamplingSeed.derive(from: beta))
    }

    @Test
    func samplingSeedFirstWordIsIndependentOfTheIdentityHash() {
        // SuggestionIdentity uses the FIRST 8 bytes of `SHA256(canonicalInput)`;
        // SamplingSeed uses the FIRST 8 bytes of a DIFFERENT SHA256
        // (with `|sampling` appended) for `stateA`, and the next three
        // 8-byte words for `stateB`/`C`/`D`. The two values must not
        // collide accidentally — different SHA256 inputs make collision
        // statistically vanishing, but the test pins it explicitly.
        let identity = SuggestionIdentity(canonicalInput: "idempotence|Sample.run(_:)|(Int)->Int")
        let identityFirstWord = UInt64(identity.normalized, radix: 16) ?? 0
        let seed = SamplingSeed.derive(from: identity)
        #expect(seed.stateA != identityFirstWord)
    }

    // MARK: - 256-bit width

    @Test
    func derivedSeedFillsAllFourStateWordsWithEntropy() {
        // The derivation pulls all 32 bytes of SHA256 — every state
        // word should carry hash entropy. None of the words should be
        // zero for a non-trivial input (probability < 2^-64 each, so
        // this is a tight smoke check on the packing).
        let identity = SuggestionIdentity(canonicalInput: "idempotence|fill-test")
        let seed = SamplingSeed.derive(from: identity)
        #expect(seed.stateA != 0)
        #expect(seed.stateB != 0)
        #expect(seed.stateC != 0)
        #expect(seed.stateD != 0)
        // All four words distinct is also overwhelmingly likely (and
        // pins the packing isn't accidentally writing the same word
        // four times).
        #expect(Set([seed.stateA, seed.stateB, seed.stateC, seed.stateD]).count == 4)
    }

    // MARK: - Hex rendering

    @Test
    func renderHexIsAlwaysSixtyFourUppercaseHexCharsWithPrefix() {
        let identity = SuggestionIdentity(canonicalInput: "idempotence|hex-test")
        let seed = SamplingSeed.derive(from: identity)
        let hex = SamplingSeed.renderHex(seed)
        #expect(hex.hasPrefix("0x"))
        // "0x" + 4 × 16 = 66 chars total (PRD v0.4 §16 #6 widening).
        #expect(hex.count == 66)
        let bare = String(hex.dropFirst(2))
        #expect(bare.allSatisfy { $0.isHexDigit && ($0.isNumber || $0.isUppercase) })
    }

    @Test
    func renderHexZeroPadsEachStateWord() {
        // Each state word must render as exactly 16 hex chars even when
        // the underlying value is small. The M5+ lifted-test stub
        // splits the 64-char hex back into four 16-char chunks; any
        // truncation would produce different UInt64s on round-trip.
        let seed = SamplingSeed.Value(stateA: 0x42, stateB: 0, stateC: 0xDEADBEEF, stateD: .max)
        let hex = SamplingSeed.renderHex(seed)
        #expect(hex == "0x0000000000000042000000000000000000000000DEADBEEFFFFFFFFFFFFFFFFF")
    }

    @Test
    func renderHexAllZerosFormsCanonicalAllZeroSeed() {
        let seed = SamplingSeed.Value(stateA: 0, stateB: 0, stateC: 0, stateD: 0)
        #expect(SamplingSeed.renderHex(seed) == "0x" + String(repeating: "0", count: 64))
    }

    // MARK: - Spec — the literal §16 #6 input shape

    @Test
    func derivationInputIsTheNormalizedHashPlusPipeSampling() {
        // Pin the exact input convention PRD v0.4 §16 #6 specifies so
        // a future contributor doesn't accidentally drop the `|`
        // separator (which would shift every seed in lockstep but
        // still be deterministic — silent breakage). Re-derive
        // manually here; if the SamplingSeed implementation diverges
        // from the spec, this test catches it.
        let identity = SuggestionIdentity(canonicalInput: "idempotence|spec-anchor")
        let manualInput = identity.normalized + "|sampling"
        let manualSeed = referenceFullSHA256(manualInput)
        #expect(SamplingSeed.derive(from: identity) == manualSeed)
    }

    /// Recompute the §16 #6 derivation independently — same SHA256
    /// hash, all 32 bytes packed as four big-endian UInt64s. Used to
    /// pin the spec against accidental drift in `SamplingSeed.derive`.
    private func referenceFullSHA256(_ input: String) -> SamplingSeed.Value {
        // Defer to the same CryptoKit primitive the production code
        // uses; the point of this helper is to exercise the
        // *concatenation* + *packing* convention, not to re-implement
        // SHA256.
        let digest = SHA256.hash(data: Data(input.utf8))
        let bytes = Array(digest)
        return SamplingSeed.Value(
            stateA: pack(bytes, offset: 0),
            stateB: pack(bytes, offset: 8),
            stateC: pack(bytes, offset: 16),
            stateD: pack(bytes, offset: 24)
        )
    }

    private func pack(_ bytes: [UInt8], offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value = (value << 8) | UInt64(bytes[offset + index])
        }
        return value
    }
}
