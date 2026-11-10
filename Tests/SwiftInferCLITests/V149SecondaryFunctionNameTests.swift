import Foundation
import PropertyLawCore
import Testing

@testable import SwiftInferCLI
@testable import SwiftInferCore

// V1.49.E — unit tests for V1.49.C secondaryFunctionName + resolver fallback.

@Suite("V1.49.C — secondaryFunctionName + non-curated pair resolver fallback")
struct V149SecondaryFunctionNameTests {

    private static func entry(
        primary: String,
        secondary: String? = nil,
        carrier: String = "Complex<Double>"
    ) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: "0xABCD1234EFFE5678",
            templateName: "round-trip",
            score: 30,
            tier: "Possible",
            primaryFunctionName: primary,
            location: "/Module.swift:1",
            firstSeenAt: "2026-05-12T00:00:00Z",
            lastSeenAt: "2026-05-12T00:00:00Z",
            typeName: carrier,
            secondaryFunctionName: secondary
        )
    }

    @Test("curated pair lookup still wins when present")
    func curatedTakesPrecedence() throws {
        // exp(_:) is in the curated list. The resolver uses the
        // curated inverse `log(_:)`, ignoring any secondaryFunctionName.
        // V1.54.A — restored to the v1.51 `.staticMethod` shape after
        // cycle-50 showed the v1.52.A free-function form fails to
        // compile from a workdir that imports ComplexModule but not
        // the `_Numerics`-globals module.
        let result = try RoundTripPairResolver.resolve(
            Self.entry(primary: "exp(_:)", secondary: "WRONG(_:)")
        )
        #expect(result.forwardCall == "Complex.exp")
        #expect(result.inverseCall == "Complex.log")
    }

    @Test("non-curated pair falls back to secondaryFunctionName")
    func nonCuratedFallbackUsesSecondary() throws {
        // _minimumCapacity/_scale isn't in the curated list. The
        // resolver should reach for the secondaryFunctionName.
        let result = try RoundTripPairResolver.resolve(
            Self.entry(
                primary: "_minimumCapacity(forScale:)",
                secondary: "_scale(forMinimumCapacity:)",
                carrier: "Int"
            )
        )
        #expect(result.forwardCall == "Int._minimumCapacity")
        #expect(result.inverseCall == "Int._scale")
    }

    @Test("no curated match + no secondary → .unsupportedPair")
    func unsupportedPairWhenBothMiss() throws {
        #expect(throws: VerifyError.self) {
            _ = try RoundTripPairResolver.resolve(
                Self.entry(primary: "unknown(_:)", secondary: nil, carrier: "Int")
            )
        }
    }

    @Test("JSON round-trip preserves secondaryFunctionName")
    func jsonRoundTripsSecondary() throws {
        let original = Self.entry(
            primary: "_minimumCapacity(forScale:)",
            secondary: "_scale(forMinimumCapacity:)"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(SemanticIndexEntry.self, from: data)
        #expect(decoded.secondaryFunctionName == "_scale(forMinimumCapacity:)")
        #expect(decoded == original)
    }

    @Test("pre-v1.49 JSON (no secondaryFunctionName) decodes cleanly as nil")
    func preV49JsonMigrates() throws {
        // Verbatim pre-v1.49 entry JSON — no secondaryFunctionName key.
        let json = """
        {
            "firstSeenAt": "2026-05-10T00:00:00Z",
            "identityHash": "0xBC43359C0574816B",
            "lastSeenAt": "2026-05-11T12:34:56Z",
            "location": "/foo/Bar.swift:1",
            "primaryFunctionName": "exp(_:)",
            "score": 30,
            "templateName": "round-trip",
            "tier": "Possible",
            "typeName": "Complex<Double>"
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(SemanticIndexEntry.self, from: data)
        #expect(decoded.secondaryFunctionName == nil)
        #expect(decoded.primaryFunctionName == "exp(_:)")
    }

    @Test("updated(from:) propagates secondaryFunctionName from other")
    func updatedPropagatesSecondary() {
        let original = Self.entry(primary: "exp(_:)", secondary: nil)
        let newer = Self.entry(primary: "exp(_:)", secondary: "log(_:)")
        let merged = original.updated(from: newer)
        #expect(merged.secondaryFunctionName == "log(_:)")
    }
}
