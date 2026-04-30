import Testing
@testable import SwiftInferCore

@Suite("SuggestionIdentity — SHA256-derived stable hash per §7.5")
struct SuggestionIdentityTests {

    @Test("Identical inputs produce identical hashes")
    func deterministic() {
        let identityA = SuggestionIdentity(canonicalInput: "idempotence|MyType.f(_:)|(Int)->Int")
        let identityB = SuggestionIdentity(canonicalInput: "idempotence|MyType.f(_:)|(Int)->Int")
        #expect(identityA == identityB)
        #expect(identityA.display == identityB.display)
        #expect(identityA.normalized == identityB.normalized)
    }

    @Test("Different inputs produce different hashes")
    func collisionResistant() {
        let identityA = SuggestionIdentity(canonicalInput: "idempotence|A.f(_:)|(Int)->Int")
        let identityB = SuggestionIdentity(canonicalInput: "idempotence|B.f(_:)|(Int)->Int")
        #expect(identityA != identityB)
        #expect(identityA.normalized != identityB.normalized)
    }

    @Test("Display form is `0x` prefix + 16 uppercase hex characters")
    func displayShape() {
        let identity = SuggestionIdentity(canonicalInput: "any input")
        #expect(identity.display.hasPrefix("0x"))
        #expect(identity.display.count == 18)
        let hex = identity.display.dropFirst(2)
        #expect(hex.allSatisfy { $0.isHexDigit && ($0.isNumber || $0.isUppercase) })
    }

    @Test("Normalized form is the display minus the 0x prefix")
    func normalizedMatchesDisplaySuffix() {
        let identity = SuggestionIdentity(canonicalInput: "any input")
        #expect("0x" + identity.normalized == identity.display)
    }

    @Test("Canonical input is preserved on the identity for diagnostics")
    func canonicalInputRetained() {
        let input = "idempotence|MyType.f(_:)|(Int)->Int"
        let identity = SuggestionIdentity(canonicalInput: input)
        #expect(identity.canonicalInput == input)
    }

    @Test("Known SHA256 prefix matches the displayed hash (regression vector)")
    func knownVector() {
        // First 8 bytes of SHA256("hello"), uppercased.
        let identity = SuggestionIdentity(canonicalInput: "hello")
        #expect(identity.display == "0x2CF24DBA5FB0A30E")
    }
}
