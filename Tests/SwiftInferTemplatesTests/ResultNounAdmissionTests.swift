import Foundation
@testable import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// Guards the result-noun admission route added 2026-08-13.
///
/// `SwiftCodeTokenizer.tokens(inLine: String) -> [Token]` got no totality law while a
/// byte-identical function named `tokenize` did — same shape, same docstring, same body, only
/// the leading name token differing
/// (`docs/measurements/exploratory-swiftformatrulestudio.md` §5.4).
///
/// **The rejection arms are the point.** Admitting the noun on the verb route's terms scores
/// 50% on the measured population, so this route is deliberately stricter. Every arm below
/// that asserts a NON-admission is protecting that decision; delete them and the route
/// silently widens back to the version measurement rejected.
@Suite("Result-noun admission — input totality")
struct ResultNounAdmissionTests {

    private func summary(
        _ name: String,
        label: String?,
        type: String = "String",
        returns: String = "[Token]"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [
                Parameter(
                    label: label, internalName: label ?? "value",
                    typeText: type, isInout: false
                )
            ],
            returnTypeText: returns,
            isThrows: false, isAsync: false, isMutating: false, isStatic: true,
            location: SourceLocation(file: "T.swift", line: 1, column: 1),
            containingTypeName: "Tokenizer",
            bodySignals: .empty
        )
    }

    // MARK: - The witness

    @Test("the witness admits: a result noun with a content label")
    func witnessAdmits() {
        #expect(InputTotalityTemplate.admission(for: summary("tokens", label: "inLine")) != nil)
    }

    @Test("the equivalent verb form still admits — the route it was measured against")
    func verbFormUnchanged() {
        #expect(InputTotalityTemplate.admission(for: summary("tokenize", label: "line")) != nil)
    }

    // MARK: - The rejections that keep precision

    @Test("the measured false positive is rejected: a result noun with a FILTER label")
    func filterLabelRejected() {
        // Harmonize's `tokens(startingWith: String) -> [Token]`. The `String` is a prefix to
        // match, not text to interpret. Admitting the noun without requiring a content label
        // takes this one too, which is the 50% precision the route was tightened against.
        #expect(InputTotalityTemplate.admission(for: summary("tokens", label: "startingWith")) == nil)
    }

    @Test("an AGENT noun is rejected however good its label")
    func agentNounRejected() {
        // `parser`/`decoder`/`lexer` name a thing that does the work — a factory returning one
        // interprets nothing, so totality over its argument is not the claim.
        for agent in ["parser", "decoder", "lexer", "tokenizer"] {
            #expect(
                InputTotalityTemplate.admission(for: summary(agent, label: "source")) == nil,
                "agent noun `\(agent)` must not admit"
            )
        }
    }

    @Test("a location label still vetoes the result-noun route")
    func locationLabelStillVetoes() {
        #expect(InputTotalityTemplate.admission(for: summary("tokens", label: "inFile")) == nil)
        #expect(InputTotalityTemplate.admission(for: summary("tokens", label: "path")) == nil)
    }

    @Test("a result noun with NO label is rejected — the content label is required")
    func unlabelledResultNounRejected() {
        #expect(InputTotalityTemplate.admission(for: summary("tokens", label: nil)) == nil)
    }

    // MARK: - Label normalisation

    @Test("a leading preposition is stripped so `inLine` and `line` classify alike")
    func prepositionStripped() {
        #expect(HostileInputEntryPoints.normalizedLabel("inLine") == "line")
        #expect(HostileInputEntryPoints.normalizedLabel("fromSource") == "source")
        #expect(HostileInputEntryPoints.normalizedLabel("line") == "line")
    }

    @Test("normalisation never splits inside a word")
    func normalisationDoesNotSplitWords() {
        // `into`, `information`, `format`, `input` all start with a stripped preposition and
        // are single words. Requiring an uppercase next character is what stops the strip —
        // without it `input` normalises to `put`, which is an egress verb, and `information`
        // to `formation`. The label sets are the precision mechanism for BOTH routes, so a
        // loose match here would weaken the veto that keeps `load(projectRoot:)` out.
        for word in ["into", "information", "format", "input", "index", "offset", "atom"] {
            #expect(
                HostileInputEntryPoints.normalizedLabel(word) == word,
                "`\(word)` must survive normalisation unchanged"
            )
        }
    }

    @Test("normalisation cannot weaken the location veto — every location label survives it")
    func normalisationPreservesTheLocationVeto() {
        // The direction that would be a REGRESSION rather than a miss. Asserted over the whole
        // set rather than on examples: normalisation is a rewrite applied before every lookup,
        // so the property that matters is that no member of the set rewrites to a non-member.
        // (`at` is the near miss — it IS a preposition, and survives only because the strip
        // requires something after it.)
        for label in HostileInputEntryPoints.locationLabels {
            #expect(
                HostileInputEntryPoints.isLocationLabel(label),
                "`\(label)` stopped being a location label under normalisation"
            )
        }
        for label in HostileInputEntryPoints.contentLabels {
            #expect(
                HostileInputEntryPoints.isContentLabel(label),
                "`\(label)` stopped being a content label under normalisation"
            )
        }
        // And the gain the rewrite exists for.
        #expect(HostileInputEntryPoints.isLocationLabel("fromPath"))
    }

    @Test("an ALL-CAPS acronym after a preposition is a known miss, not a regression")
    func acronymLabelIsAKnownMiss() {
        // `atURL` normalises to `uRL`, not `url`, because only the first character is
        // lowercased. Recorded rather than fixed: it did not match before this change either,
        // so it is a pre-existing miss and not something the rewrite broke — and there is no
        // measured witness for the acronym form. Fixing it on speculation is how a rule gets
        // fitted to an imagined case.
        #expect(!HostileInputEntryPoints.isLocationLabel("atURL"))
    }

    // MARK: - The explanation

    @Test("the reason says RESULT for a noun and VERB for a verb, never verb for both")
    func explanationMatchesTheRoute() {
        // The row first shipped reading "`tokens` leads with the interpretation verb `tokens`",
        // which a reader checking the reasoning against the name would find flatly untrue.
        let nounSignals = InputTotalityTemplate.signals(for: summary("tokens", label: "inLine"))
        let nounReason = nounSignals.map(\.detail).joined(separator: " ")
        #expect(nounReason.contains("names its RESULT"))
        #expect(!nounReason.contains("interpretation verb"))

        let verbSignals = InputTotalityTemplate.signals(for: summary("tokenize", label: "line"))
        let verbReason = verbSignals.map(\.detail).joined(separator: " ")
        #expect(verbReason.contains("interpretation verb"))
    }
}
