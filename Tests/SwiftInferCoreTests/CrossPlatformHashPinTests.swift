import Foundation
@testable import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// Every SHA-256 the package computes, pinned to values computed OUTSIDE it — so a platform
/// whose hash differs fails here rather than silently re-keying every store.
///
/// **Why this exists.** CryptoKit is Apple-only; on Linux the same `SHA256` comes from
/// apple/swift-crypto's `Crypto` (`#if canImport(CryptoKit)` at each of the four sites). Both
/// implement the standard digest, so the bytes should agree — but suggestion identities are KEYS:
/// `decisions.json`, `verify-evidence.json`, `index.json`, skip markers and generated test file
/// names all join on them. A hash that differed by platform would orphan every recorded decision
/// on the other platform with no error at all. Run on macOS and in `swift:6.4-noble`.
///
/// **The oracle is independent.** The primitive vectors were computed with Python's `hashlib`
/// (`hashlib.sha256(s.encode("utf-8")).hexdigest().upper()`, truncated as each site truncates),
/// never by running this package, so a test cannot pass by agreeing with itself. The end-to-end
/// pair is the identity and fingerprint a macOS build recorded for a real round trip, through
/// the scanner and the template, which is where a platform difference in canonicalisation (as
/// opposed to hashing) would show.
@Suite("Cross-platform hash pins — identities and fingerprints are byte-identical everywhere")
struct CrossPlatformHashPinTests {

    // MARK: - The four hashing sites, against hashlib

    @Test("SuggestionIdentity: first 8 bytes of SHA-256, ASCII and non-ASCII input")
    func suggestionIdentity() {
        #expect(SuggestionIdentity(canonicalInput: "hello").display == "0x2CF24DBA5FB0A30E")
        #expect(
            SuggestionIdentity(canonicalInput: "idempotence|MyType.f(_:)|(Int)->Int").display
                == "0x132E7F88AD35AD82"
        )
        // UTF-8 encoding of the canonical input is part of the key: an accented type name and an
        // emoji in a signature must hash the same on every platform.
        let unicode = SuggestionIdentity(canonicalInput: "round-trip|Café.encode(_:)|(String) -> String|é∑🙂")
        #expect(unicode.display == "0x8C49FA27C795FA94")
        #expect(unicode.normalized == "8C49FA27C795FA94")
    }

    @Test("SubjectFingerprint.digest: first 8 bytes of SHA-256")
    func subjectFingerprintDigest() {
        #expect(SubjectFingerprint.digest("func normalize(_ s: String) -> String { s }") == "9E8C8A3E83C6F9BE")
    }

    /// All 32 bytes, packed as four big-endian `UInt64`s — the seed a lifted test replays from.
    @Test("SamplingSeed: the full 32-byte SHA-256 of `<hash>|sampling`")
    func samplingSeed() {
        #expect(
            SamplingSeed.renderHex(SamplingSeed.derive(fromIdentityHash: "3184A52016D53F64"))
                == "0x7814A969B9D511A6E1C68A9161E2F3DE0E05FEED5CD7E09A9E497482B257B8A2"
        )
        #expect(
            SamplingSeed.renderHex(SamplingSeed.derive(from: SuggestionIdentity(canonicalInput: "hello")))
                == "0xCE637E391303551A0A18FCACB0265FC624A1F16649BA40477F4E4D650EBC89A1"
        )
    }

    /// The regression file name suffix — `<callee>_regression_<hash>.swift` must name the same
    /// file on every machine (PRD §16 #6).
    @Test("LiftedTestEmitter.regressionFileHash: first 8 hex characters of SHA-256")
    func regressionFileHash() {
        #expect(LiftedTestEmitter.regressionFileHash(for: "\"a b\"") == "5E229E24")
        #expect(LiftedTestEmitter.regressionFileHash(for: "[1, 2, 3]") == "A36B1F2C")
    }

    // MARK: - End to end: a real round trip, scanned and suggested

    /// A toy namespace codec. Its round trip was indexed and verified by a macOS build of
    /// `swift-infer` 1.160.0 on 2026-11-24, which recorded identity `0x3184A52016D53F64` and
    /// subject fingerprint `635A253E0AB94C26` in its `index.json` and `verify-evidence.json`.
    /// The bodies are reproduced verbatim — the fingerprint covers them.
    private static let slugSource = """
        import Foundation

        /// A tiny percent-style codec for path segments.
        public enum Slug {
            /// Encode a string for a URL path segment.
            public static func encode(_ input: String) -> String {
                var out = ""
                for ch in input {
                    switch ch {
                    case "%": out += "%25"
                    case " ": out += "%20"
                    case "/": out += "%2F"
                    default: out.append(ch)
                    }
                }
                return out
            }

            /// Decode a path segment produced by `encode`.
            public static func decode(_ encoded: String) -> String {
                // Planted bug: decodes %2F but forgets %25 ordering subtleties are fine here;
                // the real bug is that "%2F" is decoded but "%20" is left alone.
                encoded
                    .replacingOccurrences(of: "%2F", with: "/")
                    .replacingOccurrences(of: "%25", with: "%")
            }
        }
        """

    @Test("a scanned round trip keeps the identity and fingerprint a macOS build recorded")
    func scannedRoundTripMatchesRecordedKeys() throws {
        let corpus = FunctionScanner.scanCorpus(source: Self.slugSource, file: "Codec.swift")
        let suggestion = try #require(
            FunctionPairing.candidates(in: corpus.summaries).lazy
                .compactMap { RoundTripTemplate.suggest(for: $0) }
                .first { $0.evidence.first?.displayName == "encode(_:)" }
        )
        #expect(suggestion.identity.display == "0x3184A52016D53F64")
        let fingerprint = SubjectFingerprint.forSuggestion(
            evidenceLocations: suggestion.evidence.map(\.location),
            byLocation: SubjectFingerprint.byLocation(corpus.summaries)
        )
        #expect(fingerprint == "635A253E0AB94C26")
    }
}
