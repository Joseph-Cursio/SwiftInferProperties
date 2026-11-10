import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// V2.0 M3.C — pipeline orchestration tests. The candidate-resolution
// path (pin parsing + filtering) is unit-tested in isolation; the
// full `runPipeline(target:pinRaw:workingDirectory:)` is exercised
// via a fixture directory walk. The build-and-run integration test
// lands at M3.E once the v2.2.0 kit tag is published.

@Suite("VerifyInteractionPipeline — V2.0 M3.C orchestration")
struct VerifyInteractionPipelineTests {

    func candidate(
        functionName: String,
        enclosingTypeName: String? = nil,
        signatureShape: ReducerSignatureShape = .stateActionReturnsState,
        carrierKind: ReducerCarrierKind = .elmStyle
    ) -> ReducerCandidate {
        ReducerCandidate(
            location: "Sources/Test/F.swift:1",
            enclosingTypeName: enclosingTypeName,
            functionName: functionName,
            signatureShape: signatureShape,
            stateTypeName: "S",
            actionTypeName: "A",
            carrierKind: carrierKind
        )
    }

    // MARK: - resolveCandidate — single match

    @Test("single candidate without a pin resolves directly")
    func singleCandidateNoPinResolvesDirectly() throws {
        let resolved = try VerifyInteractionPipeline.resolveCandidate(
            candidates: [candidate(functionName: "reduce")],
            pinRaw: nil
        )
        #expect(resolved.functionName == "reduce")
    }

    @Test("zero candidates without a pin throws noReducersDetected")
    func zeroCandidatesNoPinThrows() {
        #expect(throws: VerifyInteractionError.noReducersDetected) {
            _ = try VerifyInteractionPipeline.resolveCandidate(candidates: [], pinRaw: nil)
        }
    }

    @Test("multiple candidates without a pin throws requiresPin with all qualifiedNames")
    func multipleCandidatesNoPinThrows() {
        let candidates = [
            candidate(functionName: "reduceA"),
            candidate(functionName: "reduceB"),
        ]
        #expect(throws: (any Error).self) {
            _ = try VerifyInteractionPipeline.resolveCandidate(candidates: candidates, pinRaw: nil)
        }
        // Specifically the requiresPin case:
        do {
            _ = try VerifyInteractionPipeline.resolveCandidate(candidates: candidates, pinRaw: nil)
            Issue.record("expected requiresPin error")
        } catch let error as VerifyInteractionError {
            switch error {
            case let .requiresPin(names):
                #expect(names == ["reduceA", "reduceB"])

            default:
                Issue.record("expected .requiresPin, got \(error)")
            }
        } catch {
            Issue.record("expected VerifyInteractionError, got \(error)")
        }
    }

    // MARK: - resolveCandidate — pinned

    @Test("pin filters candidate list to a single match")
    func pinFiltersToSingleMatch() throws {
        let candidates = [
            candidate(functionName: "reduceA"),
            candidate(functionName: "reduceB", enclosingTypeName: "Inbox", carrierKind: .generic),
        ]
        let resolved = try VerifyInteractionPipeline.resolveCandidate(
            candidates: candidates,
            pinRaw: "Inbox.reduceB"
        )
        #expect(resolved.functionName == "reduceB")
        #expect(resolved.enclosingTypeName == "Inbox")
    }

    // MARK: - resolveCandidate — cycle-117 exact qualified-name preference

    @Test("a free-function `reduce` pin resolves to the free function, not the same-named methods")
    func freeFunctionPinDisambiguates() throws {
        // The cycle-116 finding: a free `reduce` (qualifiedName == "reduce")
        // alongside `Foo.reduce` / `Bar.reduce` was unresolvable because the
        // lenient match matched all three. Exact qualifiedName preference
        // now picks the free function.
        let candidates = [
            candidate(functionName: "reduce", enclosingTypeName: "Foo", carrierKind: .generic),
            candidate(functionName: "reduce"),  // free function → qualifiedName "reduce"
            candidate(functionName: "reduce", enclosingTypeName: "Bar", carrierKind: .generic),
        ]
        let resolved = try VerifyInteractionPipeline.resolveCandidate(
            candidates: candidates,
            pinRaw: "reduce"
        )
        #expect(resolved.enclosingTypeName == nil)
        #expect(resolved.qualifiedName == "reduce")
    }

    @Test("a fully-qualified pin resolves via exact match even when a free function shares the name")
    func qualifiedPinResolvesAlongsideFreeFunction() throws {
        let candidates = [
            candidate(functionName: "reduce"),  // free `reduce`
            candidate(functionName: "reduce", enclosingTypeName: "Foo", carrierKind: .generic),
        ]
        let resolved = try VerifyInteractionPipeline.resolveCandidate(
            candidates: candidates,
            pinRaw: "Foo.reduce"
        )
        #expect(resolved.enclosingTypeName == "Foo")
    }

    @Test("bare-name convenience is preserved: `body` still resolves `Inbox.body` via the lenient fallback")
    func bareNameConvenienceStillWorks() throws {
        // No candidate's qualifiedName equals "body" (it's "Inbox.body"), so
        // exact-match misses and the lenient functionName match resolves it —
        // the existing `--reducer body` ergonomic is untouched.
        let candidates = [
            candidate(functionName: "body", enclosingTypeName: "Inbox", carrierKind: .generic)
        ]
        let resolved = try VerifyInteractionPipeline.resolveCandidate(
            candidates: candidates,
            pinRaw: "body"
        )
        #expect(resolved.enclosingTypeName == "Inbox")
    }

    @Test("pin matching zero candidates throws noMatchingReducer")
    func pinNoMatchThrows() {
        let candidates = [candidate(functionName: "reduce")]
        #expect(throws: VerifyInteractionError.noMatchingReducer(pin: "Missing.body")) {
            _ = try VerifyInteractionPipeline.resolveCandidate(candidates: candidates, pinRaw: "Missing.body")
        }
    }

    @Test("pin matching multiple candidates throws ambiguousPin")
    func pinAmbiguousThrows() {
        let candidates = [
            candidate(functionName: "reduce", enclosingTypeName: "InboxA", carrierKind: .generic),
            candidate(functionName: "reduce", enclosingTypeName: "InboxB", carrierKind: .generic),
        ]
        do {
            _ = try VerifyInteractionPipeline.resolveCandidate(
                candidates: candidates,
                pinRaw: "reduce"
            )
            Issue.record("expected ambiguousPin error")
        } catch let error as VerifyInteractionError {
            switch error {
            case let .ambiguousPin(pin, matches):
                #expect(pin == "reduce")
                #expect(matches.count == 2)

            default:
                Issue.record("expected .ambiguousPin, got \(error)")
            }
        } catch {
            Issue.record("expected VerifyInteractionError, got \(error)")
        }
    }

    @Test("module-prefixed pin resolves — module component is a redundant qualifier")
    func modulePrefixedPinResolves() throws {
        // `M.Inbox.reduce` parses to (module: M, type: Inbox, func: reduce);
        // the module is ignored, so it resolves the same as `Inbox.reduce`.
        let candidates = [candidate(functionName: "reduce", enclosingTypeName: "Inbox", carrierKind: .generic)]
        let resolved = try VerifyInteractionPipeline.resolveCandidate(
            candidates: candidates,
            pinRaw: "M.Inbox.reduce"
        )
        #expect(resolved.functionName == "reduce")
        #expect(resolved.enclosingTypeName == "Inbox")
    }
}
