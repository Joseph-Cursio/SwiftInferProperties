/// Functions that **interpret untrusted input** — the shape a fuzz harness is
/// built around, and the one law it asserts: **totality**.
///
/// ## Where this came from
///
/// `docs/measurements/parsing-catalog-gap.md` §6's follow-on. The starting question was
/// whether to detect libFuzzer harnesses (`LLVMFuzzerTestOneInput`). Measured
/// answer: **no**. Across every repo in reach there are exactly two Swift
/// harness definitions, both compiler test fixtures — one deliberately crashes
/// to prove the fuzzer runtime works, the other is empty and tests driver
/// flags — and neither calls a library function. The real Swift fuzzers
/// (demangler, reflection) are **C++**, which a Swift source analyser cannot
/// read. A detector would have fired twice, on noise, forever.
///
/// But the *law* a fuzz harness asserts does not need a harness to exist. A
/// function handed arbitrary bytes owes totality whether or not anyone wired a
/// fuzzer to it, and those functions are plentiful where harnesses are not.
///
/// ## The law
///
/// For **every** input the parameter type admits, the function returns or
/// throws — it never traps. A force-unwrap, an unchecked index, an
/// unchecked arithmetic overflow, a `precondition` on attacker-controlled
/// data: each is a violation, and each is a real bug in exactly the code most
/// likely to meet hostile input.
///
/// Throwing is **not** a violation. `throws` is the function saying "this input
/// is invalid", which is the correct answer to invalid input.
///
/// ## Two admission routes, and the trap between them
///
/// **Byte-typed parameter** — `Data`, `[UInt8]`, `UnsafeRawBufferPointer`,
/// `ByteBufferView`. Content by construction; nobody passes a filename as
/// `[UInt8]`. No verb needed.
///
/// **Text parameter plus an interpretation verb** — `parse`, `decode`,
/// `deserialize`, `lex`, `tokenize`, `unmarshal`, `unpack`. A bare `String`
/// parameter is far more often a *name* than a payload, so the verb carries
/// the claim.
///
/// **The trap, measured.** `read` and `load` look like interpretation verbs and
/// are not: swift-nio's `readlink(_ path: String) -> String` and
/// SwiftProjectLint's `load(projectRoot: String) -> LintConfiguration` both
/// take a **location**, not content. So those verbs are excluded, and a
/// location-shaped argument **label** vetoes admission outright — which is what
/// separates `load(projectRoot:)` from `InlineSuppressionParser
/// .parse(fileContent:)`, two functions of identical type shape in the same
/// package.
public enum HostileInputEntryPoints {

    /// Parameter types that are raw content by construction.
    public static let byteCarriers: Set<String> = [
        "Data",
        "[UInt8]",
        "UnsafeRawBufferPointer",
        "UnsafeBufferPointer<UInt8>",
        "ByteBufferView",
        "ArraySlice<UInt8>"
    ]

    /// Parameter types that *may* be content but are just as often a name.
    /// Admitted only alongside an interpretation verb.
    public static let textCarriers: Set<String> = [
        "String", "Substring", "SyntaxText"
    ]

    /// Verbs that mean "interpret these bytes as a structure".
    ///
    /// `read` and `load` are deliberately absent — measured as
    /// location-takers more often than content-takers. `from` is absent as
    /// too generic to carry a claim on its own.
    public static let interpretationVerbs: [String] = [
        "parse", "decode", "deserialize", "lex", "tokenize",
        "unmarshal", "unpack", "demangle", "disassemble"
    ]

    /// Nouns naming the **result** of an admitted verb, for a function that states its output
    /// instead of its action — `tokens(inLine:)` beside `tokenize(line:)`.
    ///
    /// ## Why a second route rather than more verbs
    ///
    /// Measured on `SwiftFormatRuleStudioCore`: `SwiftCodeTokenizer.tokens(inLine: String) ->
    /// [Token]` gets no totality law, while a byte-identical function named `tokenize` does
    /// (`docs/measurements/exploratory-swiftformatrulestudio.md` §5.4). Same shape, same
    /// docstring, same body — only the leading name token differs, noun against verb.
    ///
    /// **Result-nouns only. Agent-nouns are excluded and the distinction is the whole rule.**
    /// `tokens` names what comes *out*; `parser`, `decoder`, `lexer` name a thing that *does*
    /// the work, so a function called `parser(...)` is a factory returning a parser and
    /// interprets nothing. Admitting agent-nouns would claim totality over a constructor.
    ///
    /// ## This route is STRICTER than the verb route, because measurement said so
    ///
    /// Across eight corpora there are exactly four `func tokens(` declarations, and admitting
    /// the noun on the verb route's terms — a text carrier and no location label — scores
    /// **2 of 4, and 1 of the 2 text-carrying ones is wrong**:
    ///
    /// | declaration | text carrier | correct to admit |
    /// |---|---|---|
    /// | `tokens(startingWith: String) -> [Token]` (Harmonize) | yes | **no** — a filter prefix |
    /// | `tokens(viewMode:)` (swift-syntax) | no | n/a |
    /// | `tokens(inByteRange:)` (SwiftLint) | no | n/a |
    /// | `tokens(inLine: String) -> [Token]` (the witness) | yes | yes |
    ///
    /// 50% precision, against the ≥50% bar `same-name-differential-pairing.md` froze and then
    /// rejected a rule at 40% under. **A verb asserts interpretation; a noun only describes
    /// the return value**, and `startingWith` is exactly the *"a bare `String` is far more
    /// often a name than a payload"* case this type's header already warns about.
    ///
    /// So the noun route additionally requires a **positive content label**, where the verb
    /// route needs only the absence of a location one. That separates the two witnesses
    /// cleanly: `inLine` is content, `startingWith` is a predicate.
    ///
    /// **Population is 1 and that is stated, not hidden.** This is a correctness fix for a
    /// shape the catalog already intends to cover, not a recall win — see the A/B in the
    /// findings doc, which moves exactly one row across eight corpora.
    public static let resultNouns: [String] = ["tokens", "lexemes"]

    /// Whether `methodName` leads with a result-noun of an admitted verb.
    public static func hasResultNoun(_ methodName: String) -> Bool {
        guard let leading = StreamConsumption.camelCaseTokens(methodName).first else {
            return false
        }
        return resultNouns.contains(leading)
    }

    /// Verbs that mean the bytes are going **out**, not coming in.
    ///
    /// The byte-carrier route needs no verb — raw bytes are content by
    /// construction — but that admits the wrong direction of travel. Measured:
    /// swift-nio's `write(pointer: UnsafeRawBufferPointer)` and
    /// `sendmsg(pointer:destinationPtr:…)` are syscall wrappers whose buffer is
    /// data being TRANSMITTED. Totality over arbitrary outgoing buffers is not
    /// the interesting claim, and they were four of the first eighteen
    /// firings — every false one.
    ///
    /// Ingress and egress look identical to a type filter. Only the verb
    /// distinguishes them.
    public static let egressVerbs: Set<String> = [
        "write", "send", "sendmsg", "sendto", "emit", "output",
        "flush", "transmit", "post", "put", "upload", "publish"
    ]

    /// Whether `methodName` leads with a verb that sends bytes out.
    public static func hasEgressVerb(_ methodName: String) -> Bool {
        guard let leading = StreamConsumption.camelCaseTokens(methodName).first else {
            return false
        }
        return egressVerbs.contains(leading)
    }

    /// Argument labels naming a **location** rather than a payload. Any of
    /// these vetoes admission: the function is being handed somewhere to look,
    /// and totality over arbitrary paths is not the interesting claim.
    public static let locationLabels: Set<String> = [
        "path", "pathname", "filePath", "file", "url", "directory",
        "projectRoot", "root", "at", "name", "named", "key", "identifier"
    ]

    /// Argument labels that positively name a payload. Not required, but they
    /// raise confidence when the type alone is ambiguous.
    /// `line` / `lines` joined on 2026-08-13 with the result-noun route: a line IS the text,
    /// which is why `tokens(inLine:)` is a payload-taker and `tokens(startingWith:)` is not.
    public static let contentLabels: Set<String> = [
        "source", "text", "content", "fileContent", "contents",
        "data", "bytes", "input", "buffer", "payload", "body", "raw",
        "line", "lines"
    ]

    /// Whether `label` names somewhere to look rather than something to read.
    public static func isLocationLabel(_ label: String?) -> Bool {
        guard let label else { return false }
        return locationLabels.contains(normalizedLabel(label))
    }

    /// Whether `label` positively names a payload.
    public static func isContentLabel(_ label: String?) -> Bool {
        guard let label else { return false }
        return contentLabels.contains(normalizedLabel(label))
    }

    /// A label with a leading English preposition removed — `inLine` → `line`.
    ///
    /// Swift's labels read as prose at the call site, so the same noun appears bare in one
    /// declaration and prepositioned in another: `tokenize(line:)` against
    /// `tokens(inLine:)`, `parse(source:)` against `parse(fromSource:)`. Exact set membership
    /// sees those as different words and classifies one of each pair as unknown.
    ///
    /// **Only the preposition is stripped, never a longer prefix.** Anything more aggressive
    /// starts matching inside real words — and the label sets are the precision mechanism for
    /// both admission routes, so a loose match here weakens the veto that keeps
    /// `load(projectRoot:)` out.
    static func normalizedLabel(_ label: String) -> String {
        for preposition in ["in", "from", "of", "for", "with", "at", "to"] {
            guard label.hasPrefix(preposition), label.count > preposition.count else { continue }
            let rest = label.dropFirst(preposition.count)
            // `inLine` splits, `internal` does not: the character after the preposition must
            // begin a new camel-case word, or `into`/`information` normalise to nonsense.
            guard let first = rest.first, first.isUppercase else { continue }
            return first.lowercased() + rest.dropFirst()
        }
        return label
    }

    /// Whether `methodName` leads with an interpretation verb.
    ///
    /// Leading-token match, so `parseSourceFile` and `decodeChunk` qualify
    /// while `reparseIfNeeded` does not — and, critically, `StringLiteralKind`
    /// style compounds cannot be matched by accident, which a naive substring
    /// test does (it reads `String` inside `StringLiteralKind`).
    public static func hasInterpretationVerb(_ methodName: String) -> Bool {
        guard let leading = StreamConsumption.camelCaseTokens(methodName).first else {
            return false
        }
        return interpretationVerbs.contains(leading)
    }

    /// How a parameter admitted this function, or `nil` if it did not.
    public enum Admission: Sendable, Equatable {
        /// A raw-bytes parameter — content by construction.
        case byteCarrier(typeName: String)
        /// Text plus an interpretation verb in the function's name.
        case interpretedText(typeName: String, verb: String)
    }
}
