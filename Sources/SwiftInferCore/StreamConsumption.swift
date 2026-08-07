/// Stream-position carriers and the verbs that move them — the
/// non-idempotence family `IteratorProtocol` conformance was always a proxy
/// for, generalized to the types that never conform to it.
///
/// ## The gap this closes
///
/// `IdempotenceTemplate+IteratorVeto` correctly refuses lifted idempotence on
/// `Iterator.next()` / `Iterator.advance()`, but gates on the carrier
/// **conforming to `IteratorProtocol`** (or being named `*Iterator`). A parser
/// is built out of types that do exactly what an iterator does and conform to
/// nothing: `Lexer.Cursor`, `Parser.Lookahead`, `TokenConsumer`.
///
/// Measured on `swiftlang/swift-syntax` @ `9d6e738` (`docs/measurements/parsing-catalog-gap.md`
/// §2): `discover` on `SwiftParser` returned 98 default-tier suggestions, of
/// which **53 were lifted idempotence at `Likely`** — above the default cut —
/// and every one was a consuming method:
///
///     Lexer.Cursor.advance()               Parser.Lookahead.consumeAnyToken()
///     Lexer.Cursor.lexNumber()             Parser.Lookahead.skipSingle()
///     Lexer.Cursor.lexIdentifier()         Parser.Lookahead.canParseType()
///     TokenConsumer.atStartOfExpression()  …
///
/// `advance()` twice is not `advance()` once. That is what a cursor *is*. The
/// claim is false for all 53, and it was the loudest thing the tool said about
/// Apple's Swift parser.
///
/// ## Two tiers, and why the second one is the broad one
///
/// **Tier 1 — the verb, on any carrier.** `advance` / `skip` / `lex` / `eat` /
/// `munch` name the consumption itself. There is no carrier on which "advance"
/// leaves state alone, so no conformance gate is needed — the same argument
/// `MutatorBlockedFromIdempotence` already makes for `removeFirst` /
/// `popNext*`. The membership here is deliberately small; `consume` was
/// measured *out* of it (see `consumingVerbs`).
///
/// **Tier 2 — the carrier, on any verb.** A type named `Cursor` / `Lookahead` /
/// `Scanner` / `Reader` / `Stream` / `Lexer` / `Tokenizer` / `*Consumer` /
/// `Parser` **is a position in a stream**; moving that position is its whole
/// reason to exist. This is the same posture as the iterator veto's *primary*
/// path (any `mutating` method on an `IteratorProtocol` carrier), with a
/// name-shaped carrier test standing in for the conformance.
///
/// Tier 2 has to be the broad one because tier 1 cannot reach the largest
/// sub-family in the measurement: 20 of the 53 are query-*shaped* names on
/// `mutating` methods — `canParseType()`, `atStartOfSwitchCase()`,
/// `isAtModuleSelector()`. A name that reads as a predicate on a method that
/// mutates is *speculative consumption*, and its lifted `(T) -> T` shadow is
/// precisely the state advance.
///
/// ## Why an aggressive veto is the right call here
///
/// It suppresses; it never asserts. PRD §3.5 is explicit that the bias runs
/// toward fewer suggestions, and a false `Likely` above the default cut is the
/// most expensive thing this tool can emit. The cost of over-reach is a
/// *missed* law on a stream type, and the laws that would be missed —
/// `reset()`, `rewind()` — are trivially-true ones. Those get an explicit
/// exemption (`restoringVerbs`) so the interesting ones survive anyway.
///
/// ## Matching is camelCase-token-exact, not prefix
///
/// `"lexicographicallyPrecedes".hasPrefix("lex")` is `true`, and
/// `SwiftLexicalLookup` is a real module in the measured corpus. Tokenizing
/// first and comparing whole tokens means `lexNumber` matches and
/// `lexicalLookup` does not — a prefix test cannot tell those apart.
public enum StreamConsumption {

    /// Verbs that *are* the consumption. Matched as a camelCase token anywhere
    /// in the method name, on any carrier — no conformance or carrier gate.
    ///
    /// Token-anywhere rather than token-first because the real corpus wraps
    /// them: `tryLexEditorPlaceholder`, `tryLexConflictMarker`. Both read as
    /// "attempt to lex X"; the attempt still consumes on success.
    ///
    /// Deliberately **not** here — each is reachable through the tier-2
    /// carrier gate instead, where the carrier settles the ambiguity:
    ///
    /// - `take` — `mutating func take() -> T?` is the `Option::take` idiom,
    ///   which nils the storage and *is* idempotent on the second call.
    /// - `peek` — the defining non-consuming lookahead operation; vetoing it
    ///   would suppress a law that genuinely holds.
    /// - `scan` — reads both ways ("scan forward", but also "rescan and
    ///   refresh a cached result").
    /// - `consume` — **demoted from this tier by measurement.** Shipping it
    ///   ungated cost four true laws on the reference corpora, and the reason
    ///   is exactly the `take` argument one bullet up. `swift-nio`'s
    ///   `TCPConvenienceOptions.consumeAllowLocalEndpointReuse()` is
    ///   `defer { self.allowLocalEndpointReuse = false }` — "consume" there
    ///   means *read the flag and clear it*, so the second call leaves the
    ///   state exactly where the first did and the lifted `(T) -> T` shadow
    ///   **is** idempotent. (Same shape: two more nio siblings, and
    ///   swift-collections' `RangeReplaceableContainer.consumeAll()`.) On a
    ///   *stream* carrier "consume" advances a position instead and is not
    ///   idempotent — which is why tier 2 still catches all seven of
    ///   `SwiftParser`'s `consume*` methods, every one of them on
    ///   `Parser.Lookahead` or `TokenConsumer`. The verb alone does not
    ///   decide; the carrier does.
    public static let consumingVerbs: Set<String> = [
        "advance",
        "skip",
        "lex",
        "eat",
        "munch"
    ]

    /// Nouns that mark a carrier as a **position in a stream**. Matched as a
    /// camelCase token of any dotted component, so `Lexer.Cursor.Position`
    /// matches on `lexer` and on `cursor`.
    ///
    /// `iterator` is included so a carrier the existing `IteratorProtocol`
    /// veto reaches only through its curated-method fallback
    /// (`FooIterator.chomp()`) is covered here on the carrier alone. The two
    /// vetoes are chained, not stacked — see `liftedCarrierVetoes`.
    ///
    /// Deliberately **not** here: `buffer` (a `RingBuffer` / `FrameBuffer` is a
    /// container, not a position) and `builder` (an accumulator — a different
    /// non-idempotence family, and one this veto should not silently claim).
    public static let carrierNouns: Set<String> = [
        "cursor",
        "lookahead",
        "scanner",
        "reader",
        "stream",
        "lexer",
        "tokenizer",
        "consumer",
        "parser",
        "iterator"
    ]

    /// Verbs exempt from the tier-2 carrier gate: they move a stream position
    /// **to a fixed point** rather than forward, so `f(f(s)) == f(s)` really
    /// does hold and the suggestion is worth keeping.
    ///
    /// Matched as the *first* camelCase token only. `rewindTo(_:)` is a reset;
    /// `advanceAndRewind()` is not, and leading-token matching keeps the
    /// exemption from swallowing compound names that also consume.
    public static let restoringVerbs: Set<String> = [
        "reset",
        "rewind",
        "restore",
        "seek",
        "rollback",
        "clear"
    ]

    /// Lowercased camelCase tokens of `name`.
    ///
    /// Splits before an uppercase character that either follows a
    /// non-uppercase, or begins a new word after an acronym run —
    /// `advanceValidatingUTF8Character` → `["advance", "validating", "utf8",
    /// "character"]`, `parseXMLNode` → `["parse", "xml", "node"]`.
    public static func camelCaseTokens(_ name: String) -> [String] {
        let characters = Array(name)
        var tokens: [String] = []
        var current = ""
        for (index, character) in characters.enumerated() {
            let previous = index > 0 ? characters[index - 1] : nil
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            let startsWord = character.isUppercase
                && (previous.map { !$0.isUppercase } ?? false
                    || (next?.isLowercase ?? false))
            if startsWord, !current.isEmpty {
                tokens.append(current.lowercased())
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { tokens.append(current.lowercased()) }
        return tokens
    }

    /// Tier 1 — `methodName` carries a consuming verb as a whole token.
    public static func isConsumingVerb(_ methodName: String) -> Bool {
        !consumingVerbs.isDisjoint(with: Set(camelCaseTokens(methodName)))
    }

    /// Tier 2 — `carrierName` is a stream-position type. Dotted components are
    /// tokenized independently; generic parameters must be stripped by the
    /// caller (`ProtocolCoverageMap.strippingGenericParameters`).
    public static func isStreamCarrier(_ carrierName: String) -> Bool {
        let tokens = carrierName
            .split(separator: ".")
            .flatMap { camelCaseTokens(String($0)) }
        return !carrierNouns.isDisjoint(with: Set(tokens))
    }

    /// Whether `methodName` restores a stream position to a fixed point, and so
    /// keeps its idempotence claim despite a stream-shaped carrier.
    public static func isRestoring(_ methodName: String) -> Bool {
        guard let leading = camelCaseTokens(methodName).first else { return false }
        return restoringVerbs.contains(leading)
    }

    /// The stream-consumption verdict for one lifted candidate, or `nil` when
    /// neither tier applies. The associated value is the half-sentence the veto
    /// renders as its reason.
    public static func verdict(methodName: String, carrier: String) -> String? {
        if isConsumingVerb(methodName) {
            return "'\(methodName)' carries a consuming verb "
                + "(advance / skip / lex / eat / munch)"
        }
        guard isStreamCarrier(carrier), !isRestoring(methodName) else { return nil }
        return "carrier '\(carrier)' is a position in a stream "
            + "(cursor / lookahead / scanner / reader / stream / lexer / "
            + "tokenizer / consumer / parser / iterator), and '\(methodName)' "
            + "is one of its `mutating` moves"
    }
}
