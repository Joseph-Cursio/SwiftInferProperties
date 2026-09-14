import Foundation
import Testing

@testable import SwiftInferCore

/// `nonisolated` overrides an enclosing global actor, and the scanner now reads it.
///
/// ## What changed, and what did not
///
/// The skip was deliberate and its reasoning still holds: missing `nonisolated` makes an emitted
/// test hop onto an actor it did not need — which compiles, and costs a context switch per trial
/// — while *inferring* nonisolation wrongly would omit a hop the test does need, which does not
/// compile. The asymmetry favours over-hopping.
///
/// **The clause that expired is "no corpus subject spells it on a candidate".**
/// `SearchService.parseQuery(_:)` is `nonisolated static func` inside an `@Observable @MainActor`
/// type, and the emitted totality stub wrapped it in `await MainActor.run { … }`. It compiles, so
/// nothing went red — which is exactly why it needed looking for rather than waiting for.
///
/// And the asymmetry never argued against *reading the keyword*, only against guessing at it.
@Suite("Isolation — nonisolated overrides the enclosing actor")
struct NonisolatedResolutionTests {

    private func actor(of name: String, in source: String) -> String? {
        FunctionScanner.scanCorpus(source: source, file: "F.swift")
            .summaries.first { $0.name == name }?.globalActor
    }

    /// The measured shape, reduced.
    @Test func aNonisolatedMemberOfAnIsolatedTypeIsNotIsolated() {
        let source = """
        @MainActor
        struct SearchService {
            nonisolated static func parseQuery(_ query: String) -> Int { query.count }
        }
        """
        #expect(actor(of: "parseQuery", in: source) == nil)
    }

    /// **The control that keeps this a narrowing rather than a removal.** A plain member of the
    /// same type must still inherit the actor — that is #432, and it is what the emitted hop is
    /// for.
    @Test func aPlainMemberOfAnIsolatedTypeStillInheritsIt() {
        let source = """
        @MainActor
        struct SearchService {
            static func rank(_ query: String) -> Int { query.count }
        }
        """
        #expect(actor(of: "rank", in: source) == "MainActor")
    }

    /// `nonisolated(unsafe)` says the same thing about isolation and differs only in what it
    /// waives, so it must resolve the same way.
    @Test func theUnsafeSpellingIsAlsoNonisolated() {
        let source = """
        @MainActor
        final class Store {
            nonisolated(unsafe) static func read(_ key: String) -> Int { key.count }
        }
        """
        #expect(actor(of: "read", in: source) == nil)
    }

    /// A declaration's own attribute still wins over the enclosing type — unchanged behaviour,
    /// pinned because this edit touches the same resolution path.
    @Test func anOwnAttributeStillBeatsTheEnclosingType() {
        let source = """
        struct Plain {
            @MainActor static func render(_ text: String) -> Int { text.count }
        }
        """
        #expect(actor(of: "render", in: source) == "MainActor")
    }

    /// A free function carrying neither is nonisolated, and was already.
    @Test func aFreeFunctionHasNoActor() {
        #expect(actor(of: "normalize", in: "func normalize(_ text: String) -> Int { text.count }") == nil)
    }

    /// `nonisolated` on a function inside a type that has no actor changes nothing — the answer
    /// was already `nil`, and this pins that the new guard did not invent an answer.
    @Test func nonisolatedInsideAPlainTypeIsStillNil() {
        let source = """
        struct Plain {
            nonisolated static func scan(_ text: String) -> Int { text.count }
        }
        """
        #expect(actor(of: "scan", in: source) == nil)
    }
}
