import Foundation
@testable import SwiftInferCLI
import Testing

/// Self-dogfood road test (`docs/measurements/roadtest-self-dogfood.md` §9) — the drift guard
/// for the bug that closed the loop.
///
/// Every synthesized verifier declares a `SwiftPropertyLaws` requirement. So does
/// this package. They are **not** independent: a `verify --all-from-index
/// --corpus-module <M>` survey adds a `.package(path:)` on the working-dir
/// package, and SwiftPM must reconcile the two requirements in one graph. If they
/// name disjoint major ranges the resolve fails before a single property runs,
/// and every entry in the survey is reported as
/// `measured-error: build-failed: exit=1`.
///
/// That is the failure mode this whole project exists to warn about, arriving
/// from the inside: a verdict-shaped non-verdict. `measured-error` reads as "the
/// property could not be checked," a reader files it under "architectural
/// limitation," and nothing about the property was ever involved — the manifest
/// simply named a version that no longer existed in the graph.
///
/// It had drifted a full major version (verifier `2.1.0` / `2.2.0` against the
/// repo's `3.17.0`) and stayed invisible because no prior survey pointed the
/// verifier at a corpus that was *itself* a SwiftPropertyLaws consumer. The
/// frozen cycle27-surface corpus is a library-carrier survey with no user-package
/// path dependency, so its resolve never had to reconcile anything.
@Suite("Verifier workdir — SwiftPropertyLaws pin must not drift from Package.swift")
struct VerifierWorkdirKitPinTests {

    /// This package's `Package.swift`, located relative to this source file so
    /// the test does not depend on the process working directory.
    private static var packageManifest: String {
        get throws {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // SwiftInferCLITests
                .deletingLastPathComponent()  // Tests
                .deletingLastPathComponent()  // <package root>
            return try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        }
    }

    /// The `from:` requirement this package declares for SwiftPropertyLaws.
    private static func declaredKitRequirement(in manifest: String) -> String? {
        for line in manifest.split(separator: "\n") where line.contains("SwiftPropertyLaws.git") {
            guard let fromRange = line.range(of: "from: \"") else { continue }
            let rest = line[fromRange.upperBound...]
            guard let close = rest.firstIndex(of: "\"") else { continue }
            return String(rest[..<close])
        }
        return nil
    }

    /// **The guard.** The emitter's constant must equal the manifest's
    /// requirement. Failing here is the cheap, legible version of the failure;
    /// the expensive version is a whole survey of `measured-error` records
    /// months later.
    @Test("the emitter's kit requirement matches this package's own")
    func emitterPinMatchesPackageManifest() throws {
        let declared = Self.declaredKitRequirement(in: try Self.packageManifest)
        #expect(declared != nil, "could not find the SwiftPropertyLaws dependency in Package.swift")
        #expect(
            VerifierWorkdir.swiftPropertyLawsRequirement == declared,
            """
            The verifier emits SwiftPropertyLaws \
            `from: "\(VerifierWorkdir.swiftPropertyLawsRequirement)"` but this package declares \
            `from: "\(declared ?? "?")"`. A --corpus-module survey resolves both in one graph; \
            if the major ranges are disjoint, every entry records measured-error/build-failed \
            and no property is ever checked. Update \
            VerifierWorkdir.swiftPropertyLawsRequirement.
            """
        )
    }

    /// The requirement reaches **every** workdir mode. The drift happened because
    /// the version was written out four times — once on the algebraic path and
    /// once per interaction path — so a fix applied to one spelling left three
    /// behind. Asserting per-mode is what makes "one constant" true rather than
    /// merely intended.
    @Test("every workdir mode renders the same kit requirement")
    func everyModeRendersTheSameRequirement() {
        let expected = "from: \"\(VerifierWorkdir.swiftPropertyLawsRequirement)\""
        for mode in WorkdirMode.allCases {
            let rendered = VerifierWorkdir.renderPackageSwift(userPackage: nil, mode: mode)
            #expect(
                rendered.contains("SwiftPropertyLaws.git"),
                "\(mode) does not declare SwiftPropertyLaws at all"
            )
            #expect(rendered.contains(expected), "\(mode) renders a stale kit requirement")
        }
    }

    /// No workdir mode may render a 2.x requirement again. Named explicitly
    /// because those are the two literals that actually drifted, and a
    /// copy-paste of an old mode arm is exactly how a third would arrive.
    @Test("no mode renders the drifted 2.x literals")
    func noModeRendersTheDriftedLiterals() {
        for mode in WorkdirMode.allCases {
            let rendered = VerifierWorkdir.renderPackageSwift(userPackage: nil, mode: mode)
            #expect(!rendered.contains("SwiftPropertyLaws.git\", from: \"2."), "\(mode) regressed")
        }
    }
}
