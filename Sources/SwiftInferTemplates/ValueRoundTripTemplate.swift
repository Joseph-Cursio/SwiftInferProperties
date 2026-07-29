import Foundation
import SwiftInferCore

/// The **value-reader** role — a `(Representation) -> Value?` that decodes a value out of the thing
/// that denotes it, and the law it owes: **round-trip**, `read(write(v)) == v`.
///
/// This template exists because a hand-written property found a real bug that the catalog was
/// silent on. Three security visitors in SwiftProjectLint each had an `extractStringValue`, and two
/// read the *source text* of a string literal rather than its value:
///
/// ```swift
/// return String(literal.description.dropFirst().dropLast())   // "a\"b" -> `a\"b`, not `a"b`
/// ```
///
/// Nothing reports that wrong. A URL-scheme check simply stops recognising the value and a
/// sensitive-key check stops matching — silent under-detection inside a security rule. The
/// round-trip property produced the counterexample immediately, and then found the same class of
/// bug in the *fix*, which joined `StringSegmentSyntax.content.text` — also source text.
///
/// ## Why it is not `round-trip`
///
/// `RoundTripTemplate` needs a **declared pair**: two functions in the corpus whose names and
/// signatures oppose (`encode`/`decode`). This shape has only one half. The other direction is the
/// *construction* of the representation — writing the literal, building the URL, rendering the
/// path — which may live in another module, in the language itself, or in a test. A pair-matcher
/// cannot see it, which is exactly why these functions fell through to `determinism`.
///
/// So the law is stated with its generator obligation made explicit: the reader supplies the
/// write direction, because only they know it.
///
/// ## Name-conjectured, and deliberately not role-entailed
///
/// `(R) -> V?` alone owes nothing — `firstIndex(of:)` has that shape and owes no round-trip. The
/// name is what asserts the function *reads a value out of* its argument rather than computing
/// something new. A correct implementation of a differently-intended function would fail this, so
/// it stays a conjecture and sits below the confidence cut, like `filter-subset` before the
/// role-entailment work and like `idempotence` still.
///
/// ## Reach, measured after registering — and it does NOT include the motivating bug
///
/// Stated here because it is the opposite of what the story above implies. On
/// `SwiftProjectLintRules` the template fires **once**, and not on `extractStringValue`:
///
/// | function | access | fires |
/// |---|---|---|
/// | `extractPropertyWrapper(from: VariableDeclSyntax) -> PropertyWrapper?` | internal | **yes** |
/// | `extractStringValue(from: StringLiteralExprSyntax) -> String?` ×2 | `private` | no |
/// | `extractStringValue(_: StringLiteralExprSyntax) -> String` | `private`, non-optional | no |
///
/// Isolated on a two-file fixture differing only in one keyword: the same declaration scores
/// 1 suggestion as `func` and **0** as `private func`. A plain `discover` run produces no summary
/// for a `private` declaration, so no template sees it — and seeding does not recover *this* law
/// either: `--seeds` focuses suggestions that already exist and synthesizes only the generic
/// determinism law, so a seeded private reader reports `kept 0 of 26`.
///
/// So the shape this template was built from is, today, out of its own reach. That is a statement
/// about the access-level boundary rather than about this template — every name-gated shape template
/// has it — and it is deliberately *not* patched around here: `SeedKind.restrictedFunction` argues
/// "access level belongs in the advice, never in the gate", which if applied to analysis is a
/// pipeline change affecting every template, not a per-template fix. Recorded, not attempted.
public enum ValueRoundTripTemplate {

    /// Verbs that assert "recover the value this thing denotes".
    ///
    /// Deliberately narrow. `get`/`make`/`build` are absent: they say a value is *produced*, not
    /// that it is *recovered from a representation*, and only recovery owes a round-trip.
    public static let curatedReaderVerbs: [String] = [
        "value", "represented", "decode", "decoded", "parse", "parsed",
        "read", "extract", "extracted", "literal", "unquote"
    ]

    /// Representation types — the "written form" side of the round-trip.
    ///
    /// A syntax node, a string, or raw bytes. The point of the list is that a representation is a
    /// *carrier of notation*: it can be written down and read back, which is what makes the law
    /// checkable at all.
    static let representationSuffixes: [String] = [
        "Syntax", "String", "Substring", "Data", "URL", "Token", "Literal", "Node"
    ]

    public static func suggest(for summary: FunctionSummary) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: summary)
    }

    public static func makeConstraint() -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "value-round-trip",
            appliesTo: Self.isValueReader,
            signals: Self.signals(for:),
            evidence: { [$0.inferenceEvidence] },
            identity: { summary in
                SuggestionIdentity(
                    canonicalInput: "value-round-trip|"
                        + IdempotenceTemplate.canonicalSignature(of: summary)
                )
            },
            carrier: { $0.containingTypeName },
            caveats: Self.caveats(for:)
        )
    }

    // MARK: - Shape gate

    /// One representation-typed parameter, an optional non-`Bool` return, and a reader verb.
    ///
    /// The optional return is load-bearing rather than incidental: it is how a reader says *this
    /// representation denotes no value*. A non-optional reader has nowhere to put that answer and
    /// usually invents one, which is a different finding.
    static func isValueReader(_ summary: FunctionSummary) -> Bool {
        guard summary.parameters.count == 1,
              !summary.isMutating, !summary.isAsync, !summary.isInitializer,
              let returnType = summary.returnTypeText?.trimmingCharacters(in: .whitespaces),
              returnType.hasSuffix("?"), returnType != "Bool?" else {
            return false
        }
        let valueType = String(returnType.dropLast())
        let parameterType = summary.parameters[0].typeText.trimmingCharacters(in: .whitespaces)
        // Reading a T out of a T is a normaliser, not a reader — `LayerStrippingTemplate` owns it.
        guard parameterType != valueType else { return false }
        return isRepresentation(parameterType) && hasReaderVerb(summary.name)
    }

    static func isRepresentation(_ type: String) -> Bool {
        representationSuffixes.contains { type.hasSuffix($0) }
    }

    /// The type the generator must produce — the **value**, not the representation.
    ///
    /// The law is `read(write(v)) == v`, quantified over values, so `v` is what gets
    /// generated and the representation is derived from it by the `write` the reader
    /// supplies. Generating the representation instead would be a different (and
    /// weaker) property: most arbitrary representations denote nothing, so the
    /// reader returns `nil` and the comparison never happens.
    ///
    /// `nil` when the summary is not a value reader, so the registry's
    /// `generatorType` is never a guess about an unmatched shape.
    public static func valueType(of summary: FunctionSummary) -> String? {
        guard isValueReader(summary),
              let returnType = summary.returnTypeText?.trimmingCharacters(in: .whitespaces)
        else { return nil }
        return String(returnType.dropLast())
    }

    static func hasReaderVerb(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return curatedReaderVerbs.contains { lowered.contains($0) }
    }

    // MARK: - Scoring

    static func signals(for summary: FunctionSummary) -> [Signal] {
        guard isValueReader(summary),
              let returnType = summary.returnTypeText?.trimmingCharacters(in: .whitespaces) else {
            return []
        }
        let parameterType = summary.parameters[0].typeText.trimmingCharacters(in: .whitespaces)
        // Possible tier (20 + 15 = 35), the same posture and arithmetic as `filter-subset`: a
        // name-conjecture a differently-intended function would fail.
        return [
            Signal(
                kind: .typeSymmetrySignature,
                weight: 20,
                detail: "Value reader: \(parameterType) -> \(returnType) — a representation in, "
                    + "the value it denotes out, with `nil` for \"denotes nothing\""
            ),
            Signal(
                kind: .exactNameMatch,
                weight: 15,
                detail: "'\(summary.name)' says it RECOVERS a value rather than computing one, so "
                    + "writing a value down and reading it back owes you the value"
            )
        ]
    }

    static func caveats(for summary: FunctionSummary) -> [String] {
        let parameterType = summary.parameters.first?.typeText.trimmingCharacters(in: .whitespaces)
            ?? "the representation"
        return [
            "THE LAW IS `read(write(v)) == v` for every value `v` that can be written down. You "
                + "must supply `write` — building a \(parameterType) from a value — because only "
                + "you know it; it may live in the language, another module, or a test helper. "
                + "That is the whole cost of this property, and it is the reason no pair-matching "
                + "template could propose it.",
            "GENERATE THE NOTATION, NOT JUST THE VALUE. The bug this law exists to catch is a "
                + "reader that returns the WRITTEN FORM instead of the value — slicing delimiters "
                + "off the source text rather than decoding it. Values whose written form differs "
                + "from the value are the only ones that catch it: an embedded quote, a backslash, "
                + "an escape sequence, a multi-line or alternately-delimited form. A generator "
                + "drawing plain alphanumerics will pass against a completely broken reader.",
            "ASK WHAT A SILENT MISREAD COSTS. A reader that returns notation rather than value is "
                + "not reported wrong by anything — the value simply stops matching whatever it is "
                + "compared against downstream. In a security or routing rule that is silent "
                + "under-detection, which looks exactly like a clean result.",
            "CHECK WHAT `nil` MEANS. A representation that denotes no compile-time value must "
                + "return `nil` rather than a plausible-looking partial answer assembled from the "
                + "parts around the hole. State that as its own law; it is a different claim from "
                + "the round-trip and is refuted by different inputs.",
            "THE ROUND-TRIP IS NAME-CONJECTURED. `(\(parameterType)) -> …?` owes nothing on its "
                + "own — a lookup or a search has that shape and no round-trip. It is owed here "
                + "because the NAME says the function recovers a value. Confirm that before "
                + "encoding it."
        ]
    }
}
