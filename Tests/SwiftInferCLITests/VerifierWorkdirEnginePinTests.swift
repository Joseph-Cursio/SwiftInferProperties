import Foundation
import Testing

@testable import SwiftInferCLI

/// **The engine pin, which had no guard until the 2.0 upgrade needed one.**
///
/// `swift-property-based` is a transitive dependency of the kit, but every synthesized
/// workdir manifest declares it **directly** — deliberately, so resolution does not lean
/// on the kit's own dep graph. That makes it a *second* pin, independent of
/// `swiftPropertyLawsRequirement`, and independent pins drift.
///
/// `VerifierWorkdirKitPinTests` has guarded the kit requirement since the self-dogfood
/// road test found it drifted, and its own comment records the shape: *"the version was
/// written out four times … so a fix applied to one spelling left three behind."* The
/// engine line was written out four times too, and nothing checked it.
///
/// **Measured 2026-08-19**: on the swift-property-based 2.0 upgrade the kit moved to
/// `from: "2.0.0"` while these lines still said `1.0.0`. The intersection is empty, so
/// SwiftPM cannot resolve and **every** entry reports `measured-error: build-failed` —
/// which reads as an architectural limitation rather than a broken manifest.
@Suite("Verifier workdir — the engine requirement is one constant, and it resolves")
struct VerifierWorkdirEnginePinTests {

    /// The major of `swift-property-based` as this package actually resolved it.
    ///
    /// **`Package.resolved`, not `Package.swift`**, because this package does not declare
    /// the engine at all — it arrives through the kit. The resolved file is the only place
    /// the real version appears, and it is the version a workdir will be asked to agree with.
    static func resolvedEngineVersion() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftInferCLITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // <package root>
            .appendingPathComponent("Package.resolved")
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let pins = object?["pins"] as? [[String: Any]] ?? []
        for pin in pins {
            let identity = pin["identity"] as? String ?? ""
            guard identity.contains("property-based") else { continue }
            let state = pin["state"] as? [String: Any] ?? [:]
            if let version = state["version"] as? String { return version }
        }
        throw EnginePinError.notResolved
    }

    enum EnginePinError: Error { case notResolved }

    /// **The disjoint-range check.** An emitted `from: "2.0.0"` against a graph that
    /// resolved 1.x is unsatisfiable, and the symptom is every entry failing to build.
    @Test("the emitted engine requirement shares a major with what actually resolved")
    func emittedEngineMajorMatchesResolved() throws {
        let resolved = try Self.resolvedEngineVersion()
        let emitted = VerifierWorkdir.swiftPropertyBasedRequirement

        let resolvedMajor = resolved.split(separator: ".").first.map(String.init)
        let emittedMajor = emitted.split(separator: ".").first.map(String.init)

        #expect(resolvedMajor == emittedMajor, """
        The verifier emits swift-property-based `from: "\(emitted)"` but this package's \
        graph resolved \(resolved). Disjoint majors cannot resolve together, so every \
        verify entry records measured-error/build-failed and no property is ever checked. \
        Update `VerifierWorkdir.swiftPropertyBasedRequirement`, and check the kit's own \
        requirement moved too — it is the thing that decides what can resolve.
        """)
    }

    /// The requirement must reach **every** workdir mode. Asserting per-mode is what makes
    /// "one constant" true rather than merely intended — the same reasoning the kit pin's
    /// second test gives, after the kit drifted in exactly this way.
    @Test("every workdir mode renders the same engine requirement")
    func everyModeRendersTheSameEngineRequirement() {
        let expected = "from: \"\(VerifierWorkdir.swiftPropertyBasedRequirement)\""
        for mode in WorkdirMode.allCases {
            let rendered = VerifierWorkdir.renderPackageSwift(userPackage: nil, mode: mode)
            #expect(
                rendered.contains("swift-property-based.git"),
                "\(mode) does not declare swift-property-based at all"
            )
            #expect(rendered.contains(expected), "\(mode) renders a stale engine requirement")
        }
    }
}
