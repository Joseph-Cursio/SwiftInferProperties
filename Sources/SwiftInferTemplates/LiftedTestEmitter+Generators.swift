import PropertyLawCore
import SwiftInferCore

/// `LiftedTestEmitter` generator-expression helpers — split out of
/// `LiftedTestEmitter.swift` to keep the main file under SwiftLint's
/// file-length limit (M4.4 split). The `defaultGenerator(for:)` and
/// `mockInferredGenerator(_:)` functions are the two paths
/// `InteractiveTriage+Accept`'s `chooseGenerator(for:typeName:)`
/// dispatches between based on `Suggestion.generator.source` +
/// `mockGenerator` presence.
public extension LiftedTestEmitter {

    /// Pick the canonical generator expression for the **top-level carrier** `typeName`.
    ///
    /// ## The String arm is edge-biased, and the plain one false-passes
    ///
    /// `RawType.generatorExpression`'s String arm is
    /// `Gen<Character>.letterOrNumber.string(of: 0...8)` — alphanumerics and nothing else. No
    /// `#`, no space, no tab, no quote or bracket. Point that at a function whose job is
    /// recognising markup and the law it checks is vacuous rather than false:
    ///
    /// **Measured on SwiftMarkdownWiki (#416): 11 of 19 emitted stubs drew from it, and every
    /// one of the eleven subjects parses delimiters** — `strippingHeadingMarkers`,
    /// `replaceWikilinks`, `sanitizeFTSQuery`, `highlightCode`, `mimeType`. Replicating the
    /// generated domain exactly for `strippingHeadingMarkers` — every alphanumeric string of
    /// length 0–2, 3 907 of them — the function is a **no-op on all 3 907**. So its idempotence
    /// law passes at every budget forever, while being false of the correct implementation: the
    /// strip is `^`-anchored, so `"# ## Title"` loses one marker run per application.
    ///
    /// ## The fix already existed, in the other consumer
    ///
    /// `StrategistDispatchEmitter` — the `verify` path — reaches for
    /// `RawType.edgeBiasedGeneratorExpression` for exactly this reason, and says so in a comment
    /// that is this issue stated in advance. The stub emitter is a different path and had never
    /// been told. One vocabulary, two consumers, and the fix landed in one of them.
    ///
    /// Scoped to the top-level carrier, which is the kit's own stated intent for the biased
    /// expression: struct **members** keep the plain form, so memberwise derivation and its
    /// goldens are unaffected (see `generatorExpression(forSwiftTypeName:)` below, which is the
    /// member path and deliberately unchanged).
    ///
    /// Non-`RawType` names fall through to `\(typeName).gen()`, the same convention the
    /// `DerivationStrategist` uses — the user supplies `static func gen() -> Gen<T>` or takes the
    /// missing-symbol error. That arm now carries the marker `todoGeneratorMarker` so a reader
    /// and a `grep` can tell a working generator from a deliberate compile error; four of the
    /// nineteen were this arm (`CGFloat`, `URL`, `Date?`, `[PluginLogEntry]`) and nothing said so.
    ///
    /// `subjectLiterals` are the subject's own string literals (`SubjectLiterals`), mixed into a
    /// `String` generator's baseline by the kit — empty for every caller that has no subject, which
    /// renders exactly the expression it always did.
    static func defaultGenerator(
        for typeName: String,
        reason: String? = nil,
        subjectLiterals: [String] = []
    ) -> String {
        if let rawType = RawType(typeName: typeName) {
            return rawType.edgeBiasedGeneratorExpression(subjectTokens: subjectLiterals) ?? rawType.generatorExpression
        }
        // **Ask the kit before giving up.** `DerivationStrategist.composedGenerator` already resolves
        // Foundation value types outside the raw-type set — `Data`, `URL`, `UUID`, `Decimal`,
        // `Date`, `Character` — along with optionals, arrays, sets and dictionaries over them,
        // and the typealiases (`TimeInterval`, `CGFloat`, `unichar`). It has been `public` since
        // v3.3.0 and this emitter never called it.
        //
        // **Measured on SwiftMarkdownWiki: 10 of 21 emitted stubs carried a `.todo` generator,
        // and the kit already had a generator for the parameter type of most of them.** The gap
        // was never a missing generator; it was a consumer that asked `RawType` and then stopped.
        // `Gen<Data>.data()` has existed since v3.11.0.
        //
        // `resolve` is left at its default, so this arm answers only for types the kit knows
        // outright. Project types keep the `.todo`, which is the `GeneratorResolver`'s job and
        // reaches this emitter by a different route.
        if let composed = DerivationStrategist.composedGenerator(forTypeName: typeName) {
            return composed.expression
        }
        return "\(typeName).gen()\(todoGeneratorMarker(reason: reason))"
    }

    /// The generator a **totality** law needs, which is not the one every other law gets.
    ///
    /// `defaultGenerator` reaches for `edgeBiasedGeneratorExpression`, tuned for *structural*
    /// string laws — its tokens are YAML and Markdown markers, because it exists so an
    /// idempotence law could reach a repetition witness. Totality is a different law and wants a
    /// different draw: the counterexamples live in delimiters, non-ASCII and length.
    ///
    /// **Measured, six real trap classes planted in `WikilinkParser.parse` at 100 trials each:
    /// 3 of 6 caught under the edge-biased generator, 6 of 6 under the hostile one, with the
    /// correct implementation passing under both.** The worst miss was the delimiter — that
    /// parser exists to read `[[…]]` and the edge-biased generator cannot produce a bracket.
    /// `docs/measurements/totality-generator-reach.md`.
    ///
    /// Falls back to `defaultGenerator` for every non-`String` type, so this widens nothing it
    /// was not measured against — the sweep covered one parameter type and the claim is scoped
    /// to it.
    ///
    /// **The subject's literals matter most here.** A parser traps on its own delimiters, which are
    /// literals in its body the curated hostile list cannot know: `RuleDocView.parseBlocks` looped
    /// forever on its own `"#"` — freezing the app on 29 bundled documents — and its totality law
    /// passed until its generator drew that literal (`subject-literal-generation-scope.md` §4a).
    static func hostileGenerator(for typeName: String, subjectLiterals: [String] = []) -> String {
        if let rawType = RawType(typeName: typeName),
           let hostile = rawType.hostileGeneratorExpression(subjectTokens: subjectLiterals) {
            return hostile
        }
        return defaultGenerator(for: typeName, subjectLiterals: subjectLiterals)
    }

    /// Appended to the "you supply it" generator arm so an emitted file that cannot compile says
    /// so on the line that cannot compile.
    ///
    /// Borrowed from SwiftPropertyLaws, which added the same marker in August for the same
    /// reason: `.userGen` and `.todo` rendered identically as `Foo.gen()`, so neither a reader
    /// nor a survey could tell a resolved generator from an unresolved one — a survey in that
    /// repo had already miscounted because of it.
    ///
    /// **A block comment, not a line comment, and that is not cosmetic.** SwiftPropertyLaws
    /// could use `//` because its `.todo` reaches the emitter from two callers that both put the
    /// expression last on its line, and its own header says so. Here the generator is spliced
    /// *into* an expression — `{ rng in (\(generator)).run(using: &rng) }` — so a line comment
    /// would swallow `.run(using: &rng) }` and break the file in a way that has nothing to do
    /// with the missing generator. The first draft of this marker did exactly that.
    static var todoGeneratorMarker: String { todoGeneratorMarker(reason: nil) }

    /// The same marker, naming WHY when the caller knows.
    ///
    /// **The kit answers this and we were throwing the answer away.**
    /// `GeneratorResolver.resolutionFailure(forTypeName:)` has returned a `ResolutionFailure`
    /// since v4.7.0 — `.notInUniverse`, `.ambiguous`, `.aliasUnresolved`, `.noStrategy(reason:)`
    /// carrying the strategist's own sentence verbatim, `.unterminatedRecursion` — one case per
    /// `nil` path. Every stub rendered the same fixed string regardless, so **656 markers in one
    /// corpus run said the identical thing** and a reader could not tell five different problems
    /// apart.
    ///
    /// The kit's own commit measured the cost of the discard downstream, in this repository:
    /// the missing-generator census *"had to reconstruct two of the `nil` paths and guess the
    /// third, and left 370 of 2,016 unresolved types (18.4%) unexplained for that reason alone"*.
    ///
    /// Fourth time in this sequence that the fix is a RENDER, not a derivation — `__genMesh`,
    /// `willSet`/`didSet` and the private carrier were the first three
    /// (`docs/measurements/kit-scaffold-conversion.md`).
    ///
    /// Still a block comment, for the reason the property above gives: the generator is spliced
    /// INTO an expression, so a line comment would swallow the rest of the line.
    static func todoGeneratorMarker(reason: String?) -> String {
        guard let reason, !reason.isEmpty else {
            return " /* TODO: no generator derived — supply `static func gen()`; this will not compile */"
        }
        // Newlines would break the splice; the kit writes sentences, not paragraphs, but a
        // defensive fold costs nothing and a broken stub costs a reader the real error.
        let folded = reason.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "*/", with: "* /")
        return " /* TODO: no generator derived — \(folded); supply `static func gen()`; "
            + "this will not compile */"
    }

    /// TestLifter M4.4 — emit a `Gen<T>` expression for a mock-inferred
    /// generator synthesized from observed test construction sites.
    /// Mirrors `MemberwiseEmitter`'s `zip(...).map { Type(...) }` shape
    /// for parameterized constructors and falls back to
    /// `Gen<Type> { _ in Type() }` for the empty-constructor case
    /// (where `MemberwiseEmitter`'s ≥1-member precondition would trip).
    /// Each argument's `swiftTypeName` is resolved against the kit's
    /// `RawType.generatorExpression` table — through M4 the four
    /// supported types (`Int` / `String` / `Bool` / `Double`) all
    /// resolve, so non-`RawType` arguments don't reach this path.
    /// (`MockGeneratorSynthesizer.swiftTypeName(for:)` produces only
    /// these four names; if the M5+ literal classifier widens the
    /// shape, this path needs the corresponding update.)
    static func mockInferredGenerator(_ mock: MockGenerator) -> String {
        // M10.3 — when `mock.domainHint` carries an unvetoed hint, the
        // entire mock-inferred generator is overridden with
        // `Gen<T>.map(forward)` per PRD §7.8 second example. The
        // override surfaces a `// Inferred domain:` provenance comment
        // line above the generator. When vetoed, the mock-inferred
        // generator continues unchanged but the comment surfaces inside
        // the rendered stub via `domainHintCommentLine(for:)` (called
        // by `LiftedTestEmitter` at the test-stub assembly layer).
        if let hint = mock.domainHint, hint.producerVeto == nil {
            let comment = domainCommentLine(for: hint)
            return "// \(comment)\n            \(hint.suggestedGenerator)"
        }
        let typeName = mock.typeName
        guard !mock.argumentSpec.isEmpty else {
            // Empty-constructor mock — the test corpus consistently
            // built `\(typeName)()` with no args. Emit a Gen that
            // always produces the default value.
            return "Gen<\(typeName)> { _ in \(typeName)() }"
        }
        let generators = mock.argumentSpec.map { argument in
            generatorExpression(forSwiftTypeName: argument.swiftTypeName)
        }
        if mock.argumentSpec.count == 1 {
            let argument = mock.argumentSpec[0]
            let labelPrefix = argument.label.map { "\($0): " } ?? ""
            // M9.2 — prepend an `// Inferred precondition:` comment line
            // above the generator expression when the synthesizer
            // surfaced a hint for position 0. Two-space indent matches
            // the surrounding stub indentation pattern.
            let hintComment = preconditionCommentLine(for: 0, in: mock).map { "  \($0)\n            " } ?? ""
            return "\(hintComment)\(generators[0])\n            .map { \(typeName)(\(labelPrefix)$0) }"
        }
        // Multi-arg case — switch from single-line `zip(g1, g2)` to a
        // multi-line shape so per-position `// Inferred precondition:`
        // comments can sit above each generator expression. Without
        // hints the multi-line shape still renders correctly; the
        // hint-line emission is the only conditional bit.
        let argumentLines = generators.enumerated()
            .map { index, generatorExpr -> String in
                let hintLine = preconditionCommentLine(for: index, in: mock)
                    .map { "                \($0)\n" } ?? ""
                return "\(hintLine)                \(generatorExpr)"
            }
            .joined(separator: ",\n")
        let constructionArgs = mock.argumentSpec.enumerated()
            .map { index, argument -> String in
                let labelPrefix = argument.label.map { "\($0): " } ?? ""
                return "\(labelPrefix)$0.\(index)"
            }
            .joined(separator: ", ")
        return "zip(\n\(argumentLines)\n            )\n            "
            + ".map { \(typeName)(\(constructionArgs)) }"
    }

    /// M10.3 — render the `// Inferred domain:` provenance comment line
    /// (without the leading `// ` prefix) for a `DomainHint`. Two
    /// shapes: when not vetoed, narrates the override; when vetoed,
    /// names the veto reason so the user knows why the generator
    /// substitution was skipped.
    static func domainCommentLine(for hint: DomainHint) -> String {
        let sitesPlural = hint.siteCount == 1 ? "site" : "sites"
        if let veto = hint.producerVeto {
            return "Inferred domain: \(hint.reverseName)'s argument was always "
                + "\(hint.forwardName)'s output across \(hint.siteCount) \(sitesPlural) — "
                + "narrowing skipped: \(describeVeto(veto)) — consider \(hint.suggestedGenerator)"
        }
        return "Inferred domain: \(hint.reverseName)'s argument was always "
            + "\(hint.forwardName)'s output across \(hint.siteCount) \(sitesPlural) — "
            + "narrowing to \(hint.suggestedGenerator)"
    }

    private static func describeVeto(_ veto: ProducerVetoReason) -> String {
        switch veto {
        case .producerThrows: return "\(veto) (the runner can't shrink through `try!`)"
        case .producerAsync: return "\(veto) (`Gen<_>.map(_:)` is synchronous)"
        case .producerMultiArg: return "\(veto) (`Gen<_>.map(_:)` is unary)"
        case .producerArgNotGeneratable: return "\(veto) (no Gen<T> source for the producer's argument)"
        }
    }

    /// Render a single `// Inferred precondition:` comment line for the
    /// hint at `position` in `mock.preconditionHints`, or `nil` if no
    /// hint was synthesized for that position. The line text is
    /// self-explanatory: identifies the argument by label (or
    /// `positional[N]` for nil-label), summarizes the detected pattern,
    /// cites the site count, and surfaces the inferrer's pre-computed
    /// `suggestedGenerator` expression. PRD §3.5 conservative posture:
    /// the user-visible default generator is unchanged; the hint is
    /// advisory.
    private static func preconditionCommentLine(
        for position: Int,
        in mock: MockGenerator
    ) -> String? {
        guard let hint = mock.preconditionHints.first(where: { $0.position == position }) else {
            return nil
        }
        let label = hint.argumentLabel ?? "positional[\(hint.position)]"
        let description = describePattern(hint.pattern)
        let sitesPlural = hint.siteCount == 1 ? "site" : "sites"
        return "// Inferred precondition: \(label) — \(description) across "
            + "\(hint.siteCount) \(sitesPlural) — consider \(hint.suggestedGenerator)"
    }

    private static func describePattern(_ pattern: PreconditionPattern) -> String {
        switch pattern {
        case .positiveInt, .nonNegativeInt, .negativeInt, .intRange:
            return describeIntPattern(pattern)

        case .nonEmptyString, .stringLength:
            return describeStringPattern(pattern)

        case .constantBool(let value):
            return "all observed values are \(value)"

        case .positiveDouble, .nonNegativeDouble, .negativeDouble, .doubleRange:
            return describeDoublePattern(pattern)
        }
    }

    private static func describeIntPattern(_ pattern: PreconditionPattern) -> String {
        switch pattern {
        case .positiveInt: return "all observed values are positive Int"
        case .nonNegativeInt: return "all observed values are non-negative Int"
        case .negativeInt: return "all observed values are negative Int"
        case let .intRange(low, high): return "all observed values are in [\(low), \(high)]"
        default: return ""
        }
    }

    private static func describeStringPattern(_ pattern: PreconditionPattern) -> String {
        switch pattern {
        case .nonEmptyString: return "all observed strings are non-empty"
        case let .stringLength(low, high): return "all observed strings have length in [\(low), \(high)]"
        default: return ""
        }
    }

    private static func describeDoublePattern(_ pattern: PreconditionPattern) -> String {
        switch pattern {
        case .positiveDouble: return "all observed values are positive Double"
        case .nonNegativeDouble: return "all observed values are non-negative Double"
        case .negativeDouble: return "all observed values are negative Double"
        case let .doubleRange(low, high): return "all observed values are in [\(low), \(high)]"
        default: return ""
        }
    }

    /// Resolve `swiftTypeName` ("Int" / "String" / "Bool" / "Double")
    /// to the kit's RawType generator expression. Non-RawType names
    /// shouldn't reach this path through M4 (synthesizer guarantees
    /// the four supported types); guard with a `\(typeName).gen()`
    /// fallback so a future widening doesn't crash the renderer.
    private static func generatorExpression(forSwiftTypeName typeName: String) -> String {
        if let rawType = RawType(typeName: typeName) {
            return rawType.generatorExpression
        }
        return "\(typeName).gen()"
    }

    /// TestLifter M5.4 — emit the Codable round-trip generator scaffold
    /// for `typeName`. Dispatched from `chooseGenerator(for:typeName:)`
    /// when `Suggestion.generator.source == .derivedCodableRoundTrip`
    /// (set by `GeneratorSelection.applyCodableRoundTripFallback(...)`).
    /// The body uses `Foundation.JSONEncoder` / `JSONDecoder`; the
    /// writeout wrapper widens its imports list to include
    /// `Foundation` for this source so the rendered stub compiles.
    static func codableRoundTripGenerator(for typeName: String) -> String {
        CodableRoundTripGeneratorRenderer.renderGenerator(for: typeName)
    }
}
