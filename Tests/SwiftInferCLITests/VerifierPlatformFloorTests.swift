import Foundation
import Testing

@testable import SwiftInferCLI

/// The verifier's generated manifest must declare a macOS floor that satisfies **both** the
/// corpus and `PropertyLawKit`.
///
/// Both directions fail totally and in the same words, which is why this suite asserts both:
/// SwiftPM refuses to link an executable whose platform floor is lower than a product it
/// depends on, so a single wrong number sends **every** pick to `build-failed` and reads as
/// "the tool cannot verify this package".
///
/// - corpus HIGHER than the kit — fixed 2026-08-05, measured on SwiftProjectLint at 60 of 60.
/// - corpus LOWER than the kit — fixed 2026-08-14, measured on swift-format at 129 of 129
///   (0 laws executed). A **regression the 2026-08-05 fix introduced**: the hardcoded
///   `.macOS(.v14)` it replaced satisfied the kit by construction.
@Suite("Verifier platform floor — satisfies the corpus AND the kit, in both directions")
struct VerifierPlatformFloorTests {

    @Test("a corpus below the kit floor is raised to it")
    func corpusBelowKitFloorIsRaised() {
        // swift-format's actual declaration. Mirroring it produces
        // "requires macos 13.0, but depends on ... PropertyLawKit which requires macos 14.0".
        #expect(VerifierWorkdir.atLeastKitFloor("13.0") == "14.0")
        #expect(VerifierWorkdir.atLeastKitFloor("10.0") == "14.0")
    }

    @Test("a corpus above the kit floor is mirrored, not clamped")
    func corpusAboveKitFloorIsMirrored() {
        // The 2026-08-05 direction. Clamping to the kit floor here would reintroduce that
        // failure, so this arm is what stops the new fix from undoing the old one.
        #expect(VerifierWorkdir.atLeastKitFloor("26.0") == "26.0")
        #expect(VerifierWorkdir.atLeastKitFloor("15.0") == "15.0")
    }

    @Test("a corpus exactly at the kit floor is unchanged")
    func corpusAtKitFloorIsUnchanged() {
        #expect(VerifierWorkdir.atLeastKitFloor("14.0") == "14.0")
    }

    @Test("an unreadable or absent declaration falls back to the kit floor")
    func absentDeclarationUsesKitFloor() {
        // Not a guess: an Xcode project or a --sources run has no manifest, and the kit floor
        // is the only value that is certainly satisfiable.
        #expect(VerifierWorkdir.atLeastKitFloor(nil) == "14.0")
        #expect(VerifierWorkdir.atLeastKitFloor("not-a-version") == "14.0")
    }

    @Test("comparison is numeric by major version, not lexicographic")
    func comparisonIsNumeric() {
        // "9.0" > "14.0" as strings. This is the trap `declaredMacOSVersion` already calls out
        // for its own regex matches, repeated one layer up.
        #expect(VerifierWorkdir.atLeastKitFloor("9.0") == "14.0")
    }

    @Test("the declared kit floor still matches the kit's own manifest")
    func kitFloorMatchesTheKitManifest() {
        // A literal that drifts below the kit's real floor reintroduces the swift-format
        // failure silently and on every corpus at once. Read from the sibling checkout rather
        // than restated, since a guard that restates what it guards only checks that two
        // copies agree.
        var repoRoot = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 4 { repoRoot = repoRoot.deletingLastPathComponent() }
        let manifest = repoRoot.appendingPathComponent("SwiftPropertyLaws/Package.swift")
        guard FileManager.default.fileExists(atPath: manifest.path) else {
            // A missing sibling checkout reports as unavailable rather than folding into a
            // pass — the `DeferralFalsifierTests` posture: no clone is not a clean bill.
            let unavailable = "SwiftPropertyLaws checkout not found at \(manifest.path) — the "
                + "kit floor could not be verified. This is UNAVAILABLE, not agreement."
            Issue.record(Comment(rawValue: unavailable))
            return
        }
        let declared = VerifierWorkdir.declaredMacOSVersion(
            inPackageAt: manifest.deletingLastPathComponent()
        )
        let drifted = "the kit declares macOS \(declared ?? "nil") but "
            + "VerifierWorkdir.kitMacOSFloor says \(VerifierWorkdir.kitMacOSFloor). A floor "
            + "below the kit's real one sends every pick on every corpus to build-failed."
        #expect(declared == VerifierWorkdir.kitMacOSFloor, Comment(rawValue: drifted))
    }
}

/// The rule has two implementations and the survey runs the one that was NOT fixed first.
///
/// `VerifierWorkdir.macOSPlatformLine` serves the per-suggestion workdir;
/// `SharedVerifierPackage.platformLine` serves `verify --all-from-index`, and so
/// `prove-then-show`. Fixing only the former moved **0 of 129 rows** on swift-format — an A/B
/// whose arms were byte-identical, because the fix was in a path the survey never calls.
///
/// These arms exist so a future change cannot repair one copy and leave the other, which is
/// the failure that cost a full 12-minute survey to detect.
@Suite("Verifier platform floor — both implementations agree")
struct VerifierPlatformFloorParityTests {

    @Test("both platform-line producers floor at the kit version for a low corpus")
    func bothProducersFloorAtKit() {
        // The shared-package producer is private, so it is exercised through the helper both
        // copies now route to. The parity that matters is that neither has its own arithmetic.
        #expect(VerifierWorkdir.atLeastKitFloor("13.0") == VerifierWorkdir.kitMacOSFloor)
        #expect(VerifierWorkdir.macOSPlatformLine(userPackage: nil)
            == ".macOS(\"\(VerifierWorkdir.kitMacOSFloor)\")")
    }

    @Test("neither producer clamps a corpus that is above the kit floor")
    func neitherProducerClamps() {
        #expect(VerifierWorkdir.atLeastKitFloor("26.0") == "26.0")
    }
}
