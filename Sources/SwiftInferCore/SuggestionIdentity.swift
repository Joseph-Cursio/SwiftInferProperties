import CryptoKit
import Foundation

/// Stable identity hash for a suggestion per PRD v0.3 §7.5.
///
/// Computed from `(template ID, function signature canonical form, AST shape
/// of property region)`. M1.5 uses template ID + canonical signature(s) only —
/// the AST-shape addition is deferred until M6 (per §7.9), which is fine
/// because round-trip and idempotence don't have a non-signature "property
/// region" to encode at the M1 surface.
///
/// The display form is `0x` + 16 uppercase hex characters (the first 8 bytes
/// of `SHA256(canonicalInput)`). 64 bits is comfortable collision territory
/// for the volumes M1 produces and matches the budget in PRD §16 #6 — that
/// row defines the seed as "the low 64 bits of `SHA256(suggestionIdentityHash
/// || 'sampling')`", so 64 bits of identity is enough surface for the
/// downstream sampling-seed derivation.
public struct SuggestionIdentity: Sendable, Equatable, Hashable {

    /// Canonical input that was hashed. Retained for diagnostics — debuggers
    /// can see exactly what was fed into SHA256, which makes hash collisions
    /// or "why did this rename change the hash?" easy to investigate.
    public let canonicalInput: String

    /// `0x`-prefixed 16-character uppercase hex of the first 8 bytes of
    /// `SHA256(canonicalInput.utf8)`. The form rendered in the §4.5
    /// explainability block.
    public let display: String

    /// `display` minus the `0x` prefix, uppercased. The form `SkipMarker`
    /// matchers compare against — a `// swiftinfer: skip <hash>` marker
    /// is normalized to this representation before set-membership testing.
    public let normalized: String

    public init(canonicalInput: String) {
        self.canonicalInput = canonicalInput
        let digest = SHA256.hash(data: Data(canonicalInput.utf8))
        let prefixBytes = Array(digest).prefix(8)
        let hex = prefixBytes.map(Self.hexByte).joined()
        self.display = "0x" + hex
        self.normalized = hex
    }

    private static func hexByte(_ byte: UInt8) -> String {
        let raw = String(byte, radix: 16, uppercase: true)
        return raw.count == 1 ? "0" + raw : raw
    }
}
