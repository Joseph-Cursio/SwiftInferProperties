import ArgumentParser
import Foundation
@testable import SwiftInferCLI
import Testing

/// A refusal may not name a flag the CLI does not accept.
///
/// **Built because the existing guard could not see this class.**
/// `refusalsNameTheGateRatherThanAVersion` asserts no refusal dates itself or promises a
/// release, and a flag name is neither — so `.unsupportedCarrier` shipped telling users
/// `PropertyLawSyntax` was "opt-in via `--extra-import`" when no such option is declared
/// anywhere, and stayed green. That message was itself written to *fix* a fiction (a
/// promised version); it replaced one unfalsifiable claim with another, five days later.
///
/// A refusal is the one message a user is guaranteed to read closely, and a flag name in it
/// is the one part they will type verbatim. It is also the one part that is mechanically
/// checkable, which is the whole reason this guard can exist where the prose guards could
/// not: ArgumentParser already knows the answer.
///
/// **The vocabulary is read from ArgumentParser, not restated.** A hand-maintained list of
/// flag names would be a second copy of the CLI surface, and a guard that restates what it
/// guards only checks that two copies agree.
@Suite("Refusal wording — a named flag must be one the CLI accepts")
struct RefusalFlagVocabularyTests {

    // MARK: - The CLI's actual flag vocabulary

    /// Every long-form flag reachable from `swift-infer`, taken from ArgumentParser's own
    /// rendered help for the root command and every subcommand it declares, transitively.
    ///
    /// Rendering help rather than parsing `@Option` declarations is deliberate: it survives
    /// `name: .customLong(…)`, picks up the `--no-` halves that `inversion: .prefixedNo`
    /// synthesises (which no source scan of variable names would produce), and cannot drift
    /// from what the binary really accepts, because it *is* what the binary prints.
    static func declaredFlags() -> Set<String> {
        var found: Set<String> = []
        var queue: [any ParsableCommand.Type] = [SwiftInferCommand.self]
        var seen: Set<String> = []
        while let next = queue.popLast() {
            guard seen.insert(String(reflecting: next)).inserted else { continue }
            found.formUnion(flagTokens(in: next.helpMessage(columns: 400)))
            queue.append(contentsOf: next.configuration.subcommands)
        }
        return found
    }

    /// Long-form flag tokens in a blob of text (`--foo`, `--foo-bar`).
    ///
    /// Trailing punctuation is excluded by the character class, so a flag ending a sentence
    /// (`… pass --sources.`) yields `--sources` rather than `--sources.`; without that the
    /// guard would report a real flag as unknown and be disabled as noisy.
    static func flagTokens(in text: String) -> Set<String> {
        guard let pattern = try? NSRegularExpression(pattern: "--[a-z][a-z0-9]*(-[a-z0-9]+)*") else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var found: Set<String> = []
        for match in pattern.matches(in: text, range: range) {
            if let matched = Range(match.range, in: text) {
                found.insert(String(text[matched]))
            }
        }
        return found
    }

    // MARK: - The refusals under test

    /// Every `VerifyError`, with representative payloads. Mirrors the corpus
    /// `refusalsNameTheGateRatherThanAVersion` uses; kept as its own list so neither guard
    /// silently narrows the other's population.
    static let verifyRefusals: [VerifyError] = [
        .suggestionNotFound(prefix: "AB", closest: ["CD"]),
        .ambiguousPrefix(prefix: "AB", matches: ["CD", "EF"]),
        .indexMissing(expectedPath: URL(fileURLWithPath: "/tmp/index.json")),
        .indexEmpty(path: nil),
        .unsupportedCarrier(carrier: "Widget", expected: ["Int"]),
        .buildFailed(exitCode: 1, stderr: "boom"),
        .runnerCrashed(reason: "signal 9"),
        .unsupportedTemplate(template: "comparator", expected: ["idempotence"]),
        .unsupportedPair(forward: "encode", supported: ["serialize"]),
        .missingPairedFunction(template: "differential-equivalence", primary: "render"),
        .monotonicityDomainNotComparable(domain: "Widget"),
        .invalidArguments(reason: "pick one")
    ]

    static let interactionRefusals: [VerifyInteractionError] = [
        .noReducersDetected,
        .noMatchingReducer(pin: "Feature"),
        .ambiguousPin(pin: "Feature", matches: ["A", "B"]),
        .requiresPin(candidates: ["A", "B"]),
        .unsupported(reason: "no action alphabet"),
        .hiddenMutability(reducer: "Feature"),
        .asyncReducer(reducer: "Feature")
    ]

    // MARK: - The guard

    @Test("no refusal names a flag the CLI does not accept")
    func refusalsNameOnlyRealFlags() {
        let declared = Self.declaredFlags()
        let refusals = Self.verifyRefusals.map { String(describing: $0) }
            + Self.interactionRefusals.map { String(describing: $0) }

        for description in refusals {
            for flag in Self.flagTokens(in: description) {
                #expect(
                    declared.contains(flag),
                    """
                    A refusal tells the user to pass `\(flag)`, which `swift-infer` does not \
                    accept: "\(description)". A user who follows this gets an unknown-option \
                    error on top of the refusal they already hit. Name a real flag, or name \
                    the gate without one.
                    """
                )
            }
        }
    }

    // MARK: - Guards on the guard

    /// Three ways this suite could pass while checking nothing, each closed by an arm:
    /// an empty vocabulary would accept nothing and fail loudly, but an **over-broad** one
    /// accepts anything; an extractor that finds no flags makes the loop vacuous; and an
    /// empty refusal corpus makes it vacuous too.

    @Test("the flag vocabulary is populated and includes a flag known to exist")
    func vocabularyIsReal() {
        let declared = Self.declaredFlags()
        #expect(!declared.isEmpty, "no flags parsed out of the help — the guard would be vacuous")
        #expect(declared.contains("--target"))
        #expect(declared.contains("--suggestion"))
        #expect(
            declared.contains("--no-emit-regression"),
            """
            The `--no-` half of an inverted flag is missing. A source scan of variable names \
            would have this hole, which is why the vocabulary comes from rendered help.
            """
        )
    }

    /// **The arm that proves the guard can fail.** A vocabulary that accepted everything
    /// would pass the suite while catching nothing, and this names the exact fiction that
    /// motivated the guard.
    @Test("the vocabulary rejects a flag that does not exist")
    func vocabularyRejectsAFiction() {
        let declared = Self.declaredFlags()
        #expect(!declared.contains("--extra-import"))
        #expect(!declared.contains("--definitely-not-a-flag"))
    }

    @Test("the extractor finds flags, and stops at sentence punctuation")
    func extractorWorks() {
        #expect(Self.flagTokens(in: "pass --sources.") == ["--sources"])
        #expect(Self.flagTokens(in: "use --all-from-index with --index-path") == ["--all-from-index", "--index-path"])
        #expect(Self.flagTokens(in: "no flags here").isEmpty)
    }

    @Test("the refusal corpus is not empty")
    func corpusIsPopulated() {
        #expect(Self.verifyRefusals.count >= 12)
        #expect(!Self.interactionRefusals.isEmpty)
    }

    /// The regression witness: the message as it shipped, checked against the real
    /// vocabulary. If someone reintroduces `--extra-import` this is what fails first.
    @Test("the shipped --extra-import wording would have been caught")
    func theOriginalDefectIsCaught() {
        let shipped = "for SwiftSyntax nodes, `PropertyLawSyntax` vends generators for the "
            + "erased base types and is opt-in via --extra-import."
        let declared = Self.declaredFlags()
        let named = Self.flagTokens(in: shipped)
        // Hoisted out of `#expect` deliberately: inside the macro, the trailing closure
        // binds to `contains` and the failure message is parsed as its argument.
        let anyUnknown = named.contains { !declared.contains($0) }
        #expect(named == ["--extra-import"])
        #expect(anyUnknown, "the guard must reject the wording it was built for")
    }
}
