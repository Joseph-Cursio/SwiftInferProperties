import Foundation

/// V1.89 lint pass — utility helpers extracted from
/// `VerifyCommand.swift`'s `Verify` struct body so the main file
/// stays under SwiftLint's 400-line and the `Verify` struct stays
/// under the 250-line type-body cap. These functions are pure
/// utilities (package-root walk-up, seed derivation, workdir-segment
/// naming, --budget parsing) — none of them touch the command's
/// state, so the relocation is a no-op semantically.
extension SwiftInferCommand.Verify {

    /// Walk up parent directories looking for `Package.swift`.
    /// Mirrors `BaselineLoader.findPackageRoot` / `DecisionsLoader.
    /// findPackageRoot` / `VocabularyLoader.findPackageRoot` —
    /// inlined here rather than extracted because each loader's
    /// posture is to stay independent.
    static func findPackageRoot(startingFrom directory: URL) -> URL? {
        var current = directory.standardizedFileURL
        while true {
            let manifest = current.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: manifest.path) {
                return current
            }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent == current {
                return nil
            }
            current = parent
        }
    }

    /// Map the user-facing `--budget` string to the emitter's
    /// `TrialBudget` enum. Unknown values fall back to `.small`
    /// with a diagnostic on stderr (the v1.42 default; matches
    /// the plan's "Unknown values emit a diagnostic and fall back
    /// to `small`" sketch).
    static func parseBudget(_ raw: String) -> RoundTripStubEmitter.TrialBudget {
        switch raw.lowercased() {
        case "small":
            return .small
        case "standard":
            return .standard
        default:
            FileHandle.standardError.write(
                Data("warning: unknown --budget '\(raw)'; defaulting to 'small'\n".utf8)
            )
            return .small
        }
    }

    /// Derive a deterministic Xoshiro seed quadruple from the
    /// suggestion's identity hash. The identity hash is
    /// 16 hex chars (after the `0x` prefix); we partition it into
    /// 4 chunks of 4 hex chars each, each chunk extended via
    /// FNV-like spreading to a full UInt64. Pure function — same
    /// hash always yields the same seed, so verify runs are
    /// reproducible.
    static func makeSeedHex(from identityHash: String) -> RoundTripStubEmitter.SeedHex {
        let stripped = identityHash.hasPrefix("0x")
            ? String(identityHash.dropFirst(2))
            : identityHash
        let padded = (stripped + String(repeating: "0", count: 16)).prefix(16)
        let stateA = UInt64(padded.prefix(4), radix: 16) ?? 0
        let restAfterA = padded.dropFirst(4)
        let stateB = UInt64(restAfterA.prefix(4), radix: 16) ?? 0
        let restAfterB = restAfterA.dropFirst(4)
        let stateC = UInt64(restAfterB.prefix(4), radix: 16) ?? 0
        let stateD = UInt64(restAfterB.dropFirst(4), radix: 16) ?? 0
        return RoundTripStubEmitter.SeedHex(
            stateA: spread(stateA),
            stateB: spread(stateB),
            stateC: spread(stateC),
            stateD: spread(stateD)
        )
    }

    /// FNV-like spread of a small UInt64 nibble to a full 64-bit
    /// state. Prevents the first 16 bits of Xoshiro state from
    /// being all-zero (which would produce a poor RNG sequence)
    /// while preserving determinism. Mixing constants borrowed
    /// from xxhash's avalanche step.
    private static func spread(_ word: UInt64) -> UInt64 {
        var hash = word ^ 0xCBF2_9CE4_8422_2325
        hash = hash &* 0x100_0000_01B3
        hash ^= hash >> 32
        return hash | 1
    }

    /// `0xBC43359C0574816B` → `"BC43"`. The first 4 hex chars
    /// after the `0x` prefix make a stable, filename-safe
    /// segment. Collisions are theoretically possible but
    /// `lookupSuggestion`'s prefix-match already failed with
    /// `.ambiguousPrefix` if two entries share a 4-hex prefix at
    /// the lookup stage, so we won't reach here for ambiguous
    /// cases.
    static func workdirSegment(for identityHash: String) -> String {
        let stripped = identityHash.hasPrefix("0x")
            ? String(identityHash.dropFirst(2))
            : identityHash
        return String(stripped.prefix(4))
    }
}
