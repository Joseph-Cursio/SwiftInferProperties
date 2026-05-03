import Foundation
import SwiftInferCore

/// Suggestion-field extraction helpers + `DecisionRecord` construction.
/// All `static`; called by both accept paths.
extension InteractiveTriage {

    /// Pull the function identifier out of a display name like
    /// `"normalize(_:)"` → `"normalize"`. Returns `nil` if the format
    /// doesn't match.
    static func functionName(from displayName: String) -> String? {
        guard let parenIndex = displayName.firstIndex(of: "(") else { return nil }
        let name = String(displayName[..<parenIndex])
        guard !name.isEmpty else { return nil }
        return name
    }

    /// Pull the first parameter type out of a signature like
    /// `"(String) -> String"` or `"(Money, Money) -> Money"`.
    /// Whitespace tolerant; returns `nil` if the parens are missing.
    static func paramType(from signature: String) -> String? {
        guard let openIndex = signature.firstIndex(of: "("),
              let closeIndex = signature.firstIndex(of: ")") else {
            return nil
        }
        let inside = signature[signature.index(after: openIndex)..<closeIndex]
        let trimmed = inside.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        let firstComponent = trimmed.split(separator: ",").first.map(String.init) ?? trimmed
        let stripped = firstComponent.trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? nil : stripped
    }

    /// Pull the return type out of a signature like
    /// `"(String) -> Int"` — returns `"Int"`. Strips any trailing
    /// `preserving X` clause (`InvariantPreservationTemplate`) or
    /// ` seed X` clause (M5.5 lifted reduce-equivalence promotion) that
    /// the templates encode after the return-type position. Returns
    /// `nil` if no `->` separator exists.
    static func returnType(from signature: String) -> String? {
        guard let arrowRange = signature.range(of: "->") else { return nil }
        var tail = signature[arrowRange.upperBound...].trimmingCharacters(in: .whitespaces)
        if let preservingRange = tail.range(of: " preserving ") {
            tail = String(tail[..<preservingRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        if let seedRange = tail.range(of: " seed ") {
            tail = String(tail[..<seedRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return tail.isEmpty ? nil : tail
    }

    /// Pull the keypath text out of an invariant-preservation signature
    /// like `"(Widget) -> Widget preserving \\.isValid"` — returns
    /// `"\\.isValid"`. Returns `nil` if the `preserving` marker is absent
    /// (the signature isn't from `InvariantPreservationTemplate`).
    static func invariantKeypath(from signature: String) -> String? {
        guard let preservingRange = signature.range(of: " preserving ") else { return nil }
        let tail = signature[preservingRange.upperBound...].trimmingCharacters(in: .whitespaces)
        return tail.isEmpty ? nil : tail
    }

    /// Pull the seed expression out of a lifted reduce-equivalence
    /// signature like `"(Int, Int) -> Int seed 0"` — returns `"0"`.
    /// `LiftedSuggestionPromotion.reduceEquivalenceEvidence` encodes
    /// the seed here so the M5.5 lifted reduce-equivalence stub can
    /// thread it into the rendered `xs.reduce(<seed>, <op>)` test
    /// without losing the seed the test body actually used (PRD §3.5
    /// — emit the property the body claimed, not a stronger one).
    /// Returns `nil` if the ` seed ` marker is absent (signature not
    /// from a lifted reduce-equivalence promotion).
    static func seedSource(from signature: String) -> String? {
        guard let seedRange = signature.range(of: " seed ") else { return nil }
        let tail = signature[seedRange.upperBound...].trimmingCharacters(in: .whitespaces)
        return tail.isEmpty ? nil : tail
    }

    static func makeRecord(
        for suggestion: Suggestion,
        decision: Decision,
        timestamp: Date
    ) -> DecisionRecord {
        DecisionRecord(
            identityHash: suggestion.identity.normalized,
            template: suggestion.templateName,
            scoreAtDecision: suggestion.score.total,
            tier: suggestion.score.tier,
            decision: decision,
            timestamp: timestamp,
            signalWeights: suggestion.score.signals.map { signal in
                SignalSnapshot(kind: signal.kind.rawValue, weight: signal.weight)
            }
        )
    }
}
