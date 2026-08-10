import Foundation
@testable import SwiftInferCLI
import Testing

/// A carrier the stub cannot **name** is a third thing, and neither existing bucket says it.
///
/// `unsupported-carrier` means *no generator derives this type* and sends the reader to the
/// kit. `build-failed` means *our tooling broke* and sends them to us. The truth is *the verify
/// stub is not allowed to import this module* — the generator exists, the shape is indexed, and
/// `@testable import <Subject>` does not re-export a dependency.
@Suite("Dependency-declared carriers get their own label")
struct DependencyCarrierLabelTests {

    private let checkout =
        "/repo/.build/checkouts/SwiftEffectInference/Sources/SwiftEffectInference/Effect.swift"

    private func detail(_ stdout: String, _ map: [String: String]) -> String? {
        SwiftInferCommand.Verify.architecturalPendingDetail(
            buildStdout: stdout, buildStderr: "", sourceFileByTypeName: map
        )
    }

    /// The measured case: `Effect`, declared in SwiftEffectInference.
    @Test("a dependency-declared carrier is labelled with its module")
    func dependencyCarrierIsLabelled() {
        let out = "main.swift:102:33: error: cannot find type 'Effect' in scope"
        let result = detail(out, ["Effect": checkout])
        #expect(result?.hasPrefix("carrier-declared-in-dependency:") == true)
        #expect(result?.contains("SwiftEffectInference") == true)
        #expect(
            result?.contains("does not import") == true,
            "the label must name the remedy's shape, not just the fault"
        )
    }

    /// **The arm that must not fire.** A locally declared type failing to resolve is a real
    /// tooling problem — probably nested-carrier qualification — and must keep `build-failed`.
    @Test("a locally declared type keeps build-failed")
    func localTypeIsNotRelabelled() {
        let out = "main.swift:100:9: error: cannot find type 'Coverage' in scope"
        #expect(detail(out, ["Coverage": "/repo/Sources/SwiftInferCore/RefutedExpectation.swift"]) == nil)
    }

    /// No map means no claim — the survey may not have threaded declaration sites.
    @Test("an empty map makes no claim")
    func emptyMapMakesNoClaim() {
        #expect(detail("error: cannot find type 'Effect' in scope", [:]) == nil)
    }

    /// A checkout path that is not under `Sources/` is not a module we could import.
    @Test("a checkout path with no Sources component is not labelled")
    func checkoutWithoutSourcesIsNotLabelled() {
        let odd = "/repo/.build/checkouts/Weird/Docs/Effect.swift"
        #expect(detail("error: cannot find type 'Effect' in scope", ["Effect": odd]) == nil)
    }

    /// An unrelated build failure is untouched.
    @Test("an unrelated failure is not relabelled")
    func unrelatedFailureUntouched() {
        #expect(detail("error: expected declaration", ["Effect": checkout]) == nil)
    }
}
