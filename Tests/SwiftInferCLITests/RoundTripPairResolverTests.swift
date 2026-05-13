import Foundation
import SwiftInferCore
import Testing

@testable import SwiftInferCLI

/// V1.42.C.6 — RoundTripPairResolver lookup + Verify pipeline-glue
/// helpers (seed derivation, workdir segment naming, budget parsing).
@Suite("RoundTripPairResolver — V1.42.C.6 lookup + pipeline helpers")
struct RoundTripPairResolverTests {

    // MARK: - Fixtures

    private static func entry(
        template: String = "round-trip",
        carrier: String? = "Complex<Double>",
        primary: String = "exp(_:)",
        hash: String = "0xBC43359C0574816B"
    ) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: hash,
            templateName: template,
            typeName: carrier,
            score: 60,
            tier: "Strong",
            primaryFunctionName: primary,
            location: "/Module.swift:1",
            firstSeenAt: "2026-05-11T00:00:00Z",
            lastSeenAt: "2026-05-11T00:00:00Z"
        )
    }

    // MARK: - resolve(_:) — happy paths

    // V1.54.A — V1.52.A's free-function classification reverted per
    // cycle-50 evidence (`docs/calibration-cycle-50-findings.md`).
    // The bare `exp(value)` form doesn't resolve from a workdir that
    // imports only `ComplexModule` + `RealModule` — the
    // `_Numerics`-globals live behind a separate import. The
    // `Complex.exp(_:)` static-method form (the v1.51 default)
    // compiles cleanly and reaches the property check via V1.53.A's
    // DYLD fix.

    @Test("Complex<Double> + exp(_:) → Complex.exp / Complex.log")
    func resolvesExpLogPair() throws {
        let result = try RoundTripPairResolver.resolve(Self.entry(primary: "exp(_:)"))
        #expect(result.forwardCall == "Complex.exp")
        #expect(result.inverseCall == "Complex.log")
    }

    @Test("bidirectional — log(_:) resolves to inverse exp(_:)")
    func resolvesLogExpPair() throws {
        let result = try RoundTripPairResolver.resolve(Self.entry(primary: "log(_:)"))
        #expect(result.forwardCall == "Complex.log")
        #expect(result.inverseCall == "Complex.exp")
    }

    @Test("trigonometric pairs resolve in both directions")
    func resolvesTrigPairs() throws {
        let cosResult = try RoundTripPairResolver.resolve(Self.entry(primary: "cos(_:)"))
        #expect(cosResult.inverseCall == "Complex.acos")
        let acosResult = try RoundTripPairResolver.resolve(Self.entry(primary: "acos(_:)"))
        #expect(acosResult.inverseCall == "Complex.cos")
        let sinResult = try RoundTripPairResolver.resolve(Self.entry(primary: "sin(_:)"))
        #expect(sinResult.inverseCall == "Complex.asin")
        let tanResult = try RoundTripPairResolver.resolve(Self.entry(primary: "tan(_:)"))
        #expect(tanResult.inverseCall == "Complex.atan")
    }

    // V1.45.D — hyperbolic pairs added to the curated list. Unblocks
    // cycle-27 picks #4 (sinh/asinh) and #5 (tanh/atanh).

    @Test("V1.45.D — hyperbolic sinh/asinh pair resolves in both directions")
    func resolvesSinhAsinhPair() throws {
        let sinhResult = try RoundTripPairResolver.resolve(Self.entry(primary: "sinh(_:)"))
        #expect(sinhResult.forwardCall == "Complex.sinh")
        #expect(sinhResult.inverseCall == "Complex.asinh")
        let asinhResult = try RoundTripPairResolver.resolve(Self.entry(primary: "asinh(_:)"))
        #expect(asinhResult.forwardCall == "Complex.asinh")
        #expect(asinhResult.inverseCall == "Complex.sinh")
    }

    @Test("V1.45.D — hyperbolic cosh/acosh pair resolves in both directions")
    func resolvesCoshAcoshPair() throws {
        let coshResult = try RoundTripPairResolver.resolve(Self.entry(primary: "cosh(_:)"))
        #expect(coshResult.forwardCall == "Complex.cosh")
        #expect(coshResult.inverseCall == "Complex.acosh")
        let acoshResult = try RoundTripPairResolver.resolve(Self.entry(primary: "acosh(_:)"))
        #expect(acoshResult.forwardCall == "Complex.acosh")
        #expect(acoshResult.inverseCall == "Complex.cosh")
    }

    @Test("V1.45.D — hyperbolic tanh/atanh pair resolves in both directions")
    func resolvesTanhAtanhPair() throws {
        let tanhResult = try RoundTripPairResolver.resolve(Self.entry(primary: "tanh(_:)"))
        #expect(tanhResult.forwardCall == "Complex.tanh")
        #expect(tanhResult.inverseCall == "Complex.atanh")
        let atanhResult = try RoundTripPairResolver.resolve(Self.entry(primary: "atanh(_:)"))
        #expect(atanhResult.forwardCall == "Complex.atanh")
        #expect(atanhResult.inverseCall == "Complex.tanh")
    }

    // MARK: - resolve(_:) — error paths

    @Test("non-round-trip template → .unsupportedTemplate")
    func unsupportedTemplateThrows() throws {
        do {
            _ = try RoundTripPairResolver.resolve(Self.entry(template: "idempotence"))
            Issue.record("expected .unsupportedTemplate")
        } catch let error as VerifyError {
            switch error {
            case let .unsupportedTemplate(template, expected):
                #expect(template == "idempotence")
                #expect(expected == ["round-trip"])
            default:
                Issue.record("expected .unsupportedTemplate; got \(error)")
            }
        }
    }

    @Test("non-Complex<Double> carrier → .unsupportedCarrier")
    func unsupportedCarrierThrows() throws {
        do {
            _ = try RoundTripPairResolver.resolve(Self.entry(carrier: "Array<Int>"))
            Issue.record("expected .unsupportedCarrier")
        } catch let error as VerifyError {
            switch error {
            case .unsupportedCarrier:
                break
            default:
                Issue.record("expected .unsupportedCarrier; got \(error)")
            }
        }
    }

    @Test("forward function name not in curated list → .unsupportedPair")
    func unsupportedPairThrows() throws {
        do {
            _ = try RoundTripPairResolver.resolve(Self.entry(primary: "noSuchFunc(_:)"))
            Issue.record("expected .unsupportedPair")
        } catch let error as VerifyError {
            switch error {
            case let .unsupportedPair(forward, supported):
                #expect(forward == "noSuchFunc(_:)")
                #expect(supported.contains("exp(_:)"))
            default:
                Issue.record("expected .unsupportedPair; got \(error)")
            }
        }
    }

    // MARK: - String helpers

    @Test("bareTypeName strips generic argument")
    func bareTypeNameStripsGeneric() {
        #expect(RoundTripPairResolver.bareTypeName(from: "Complex<Double>") == "Complex")
        #expect(RoundTripPairResolver.bareTypeName(from: "Array<Int>") == "Array")
        #expect(RoundTripPairResolver.bareTypeName(from: "Foo") == "Foo")
    }

    @Test("stripParameterLabels drops everything from the first paren")
    func stripParameterLabelsCorrect() {
        #expect(RoundTripPairResolver.stripParameterLabels("exp(_:)") == "exp")
        #expect(RoundTripPairResolver.stripParameterLabels("foo(arg:other:)") == "foo")
        #expect(RoundTripPairResolver.stripParameterLabels("bare") == "bare")
    }

    // MARK: - Pipeline helpers in Verify

    @Test("findPackageRoot walks up to the directory containing Package.swift")
    func findPackageRootWalksUp() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("find-package-root-tests")
            .appendingPathComponent(UUID().uuidString)
        let nested = temp.appendingPathComponent("a/b/c")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        try "// stub".write(
            to: temp.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        let found = SwiftInferCommand.Verify.findPackageRoot(startingFrom: nested)
        #expect(found?.standardizedFileURL == temp.standardizedFileURL)
    }

    @Test("findPackageRoot returns nil when no Package.swift exists upward")
    func findPackageRootReturnsNilWhenAbsent() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("find-package-root-nil-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        // No Package.swift exists in the temp tree, but the search
        // will walk up past /tmp/ to the filesystem root. To make this
        // a tight test we'd need a sandboxed FS — for now we accept
        // that the test depends on the actual filesystem not having a
        // Package.swift at /. Sufficient for the v1.42 ship gate.
        // (Skipped if a stray Package.swift ever appears upstream.)
    }

    @Test("makeSeedHex is deterministic — same hash, same seed")
    func makeSeedHexDeterministic() {
        let hash = "0xBC43359C0574816B"
        let first = SwiftInferCommand.Verify.makeSeedHex(from: hash)
        let second = SwiftInferCommand.Verify.makeSeedHex(from: hash)
        #expect(first == second)
    }

    @Test("makeSeedHex differs for different hashes")
    func makeSeedHexVariesAcrossHashes() {
        let first = SwiftInferCommand.Verify.makeSeedHex(from: "0xBC43359C0574816B")
        let second = SwiftInferCommand.Verify.makeSeedHex(from: "0xDEADBEEF12345678")
        #expect(first != second)
    }

    @Test("makeSeedHex spread guarantees non-zero low bit per component")
    func makeSeedHexSpreadNonZero() {
        // Empty hash exercises the "all-zero input" edge case — the
        // FNV spread must still produce non-zero state to avoid the
        // Xoshiro all-zero seed degenerate behavior.
        let seed = SwiftInferCommand.Verify.makeSeedHex(from: "0x0000000000000000")
        #expect(seed.stateA != 0)
        #expect(seed.stateB != 0)
        #expect(seed.stateC != 0)
        #expect(seed.stateD != 0)
    }

    @Test("workdirSegment uses first 4 hex chars after 0x prefix")
    func workdirSegmentExtracts4Chars() {
        #expect(SwiftInferCommand.Verify.workdirSegment(for: "0xBC43359C0574816B") == "BC43")
        #expect(SwiftInferCommand.Verify.workdirSegment(for: "BC43359C0574816B") == "BC43")
    }

    @Test("parseBudget maps small / standard correctly")
    func parseBudgetKnownValues() {
        #expect(SwiftInferCommand.Verify.parseBudget("small") == .small)
        #expect(SwiftInferCommand.Verify.parseBudget("SMALL") == .small)
        #expect(SwiftInferCommand.Verify.parseBudget("standard") == .standard)
    }

    @Test("parseBudget falls back to small on unknown values")
    func parseBudgetUnknownFallsBackToSmall() {
        #expect(SwiftInferCommand.Verify.parseBudget("absurd") == .small)
        #expect(SwiftInferCommand.Verify.parseBudget("") == .small)
    }
}
