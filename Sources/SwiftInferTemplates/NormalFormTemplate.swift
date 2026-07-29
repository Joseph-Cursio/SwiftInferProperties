import SwiftInferCore

/// The **normal-form / retract** law: for a parse-print pair, printing what you
/// parsed lands in a canonical form, and re-normalising changes nothing.
///
///     normalize(s) = print(parse(s))
///     ⟹  normalize(normalize(s)) == normalize(s)
///
/// Equivalently `parse ∘ print ∘ parse == parse` — parse is a *retraction*.
///
/// ## Why this needs its own template
///
/// `docs/parsing-catalog-gap.md` §3d. A parse-print pair admits three laws, and
/// they do **not** have the same truth conditions:
///
/// | law | domain | holds when |
/// |---|---|---|
/// | `parse(print(t)) == t` | values | essentially always; the cheap direction |
/// | `print(parse(s)) == s` | source text | **only if the printer is full-fidelity** |
/// | `print(parse(print(parse(s)))) == print(parse(s))` | source text | **always** |
///
/// The middle one is the interesting claim and it is *false for every lossy
/// parser* — false for correct code. Until now the distinction lived in
/// `RoundTripTemplate`'s caveat prose, which is caveat text doing a template's
/// job: the reader was told three laws exist and left to work out which one
/// their code owes.
///
/// So `round-trip` keeps the **conjecture** and this template states the
/// **entailment**. They coexist deliberately — the reader sees the strong claim
/// to check if their printer is full-fidelity, and the one that holds either
/// way.
///
/// ## Role-entailed, with one real precondition
///
/// For a deterministic pair this is not a guess: printing produces text in the
/// printer's own canonical style, and parsing that text yields the tree it came
/// from, so the second pass has nothing left to change. What it *does* require
/// is that `parse ∘ print == id` on trees the parser actually produces — the
/// cheap direction above. A printer that emits text its own parser rejects, or
/// re-parses differently, breaks this, and that is a genuine and serious bug.
///
/// ## Scope, and the gate that measurement forced
///
/// The first cut gated on **type shape alone** — `text -> structure` paired
/// with `structure -> text`. That fired **47 times** across the corpora and the
/// great majority were false, because plenty of functions have those types and
/// parse nothing: `ByteBufferAllocator.buffer(string:)` is a constructor,
/// `LintConfigurationLoader.load(projectRoot:)` takes a **path**,
/// `CleanExit.message(_:)` is a wrapper, and
/// `generateHelp(screenWidth: Int) -> String` against
/// `editDistance(to: String) -> Int` is pure type coincidence.
///
/// Adding the name evidence the catalog already had — an interpretation verb on
/// the parse half, no location-shaped label, `debugDescription` excluded as a
/// developer dump rather than a printer — took it to **1**:
/// `Parser.parse(source:) × SyntaxProtocol.description()`, the swift-syntax
/// pair, which now carries this law alongside the fidelity claim §3c reached.
/// Zero on swift-nio, swift-collections, SwiftProjectLint and
/// swift-argument-parser.
///
/// One firing is thin, and it is the honest number: this law only *arises*
/// where a real parse-print pair exists, and there is exactly one of those in
/// the corpora.
public enum NormalFormTemplate {

    /// Parameter/return types that count as source text.
    ///
    /// Reuses `HostileInputEntryPoints`' carriers so "what counts as text"
    /// has one definition in the catalog rather than two that drift.
    static var textTypes: Set<String> {
        HostileInputEntryPoints.textCarriers.union(HostileInputEntryPoints.byteCarriers)
    }

    /// The pair split into its parse and print halves, or `nil` when it is not
    /// a text↔structure pair.
    static func parsePrintHalves(
        of pair: FunctionPair
    ) -> (parse: FunctionSummary, print: FunctionSummary)? {
        guard let forwardDomain = FunctionPairing.transformationDomain(pair.forward),
              let reverseDomain = FunctionPairing.transformationDomain(pair.reverse),
              let forwardReturn = pair.forward.returnTypeText,
              let reverseReturn = pair.reverse.returnTypeText else {
            return nil
        }
        let forwardParses = textTypes.contains(forwardDomain) && !textTypes.contains(forwardReturn)
        let reverseParses = textTypes.contains(reverseDomain) && !textTypes.contains(reverseReturn)
        let forwardPrints = textTypes.contains(forwardReturn) && !textTypes.contains(forwardDomain)
        let reversePrints = textTypes.contains(reverseReturn) && !textTypes.contains(reverseDomain)
        if forwardParses, reversePrints, isParse(pair.forward), isPrint(pair.reverse) {
            return (pair.forward, pair.reverse)
        }
        if reverseParses, forwardPrints, isParse(pair.reverse), isPrint(pair.forward) {
            return (pair.reverse, pair.forward)
        }
        return nil
    }

    /// Whether this half genuinely **interprets** its text.
    ///
    /// The type shape alone is not evidence, which measurement established the
    /// hard way: gating on `text -> structure` fired 47 times across the
    /// corpora and the great majority were false —
    /// `ByteBufferAllocator.buffer(string:)` (a constructor, not a parser),
    /// `LintConfigurationLoader.load(projectRoot:)` (a **path**, not content),
    /// `CleanExit.message(_:)` (a wrapper). Every one has the right types and
    /// none of them parses anything.
    ///
    /// So the parse half must carry an interpretation verb, and must not be
    /// handed a location — both tests already exist for `InputTotalityTemplate`
    /// and are reused here rather than re-derived.
    static func isParse(_ summary: FunctionSummary) -> Bool {
        guard HostileInputEntryPoints.hasInterpretationVerb(summary.name) else { return false }
        return !summary.parameters.contains { HostileInputEntryPoints.isLocationLabel($0.label) }
    }

    /// Whether this half genuinely **renders** the structure back to text.
    ///
    /// `debugDescription` is excluded on purpose. It is documented as a
    /// developer-facing dump and is not required to round-trip — swift-nio's
    /// `ByteBuffer.debugDescription` prints `ByteBuffer { readerIndex: 0, … }`,
    /// which no parser reads back. `description` survives because for a
    /// full-fidelity printer it IS the canonical rendering (swift-syntax), and
    /// the parse-half gate above is what keeps the debug-dump cases out.
    static func isPrint(_ summary: FunctionSummary) -> Bool {
        summary.name != "debugDescription"
    }

    public static func suggest(for pair: FunctionPair) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: pair)
    }

    public static func makeConstraint() -> Constraint<FunctionPair> {
        Constraint<FunctionPair>(
            templateName: "normal-form",
            appliesTo: { parsePrintHalves(of: $0) != nil },
            signals: Self.signals(for:),
            evidence: { [$0.forward.inferenceEvidence, $0.reverse.inferenceEvidence] },
            identity: { pair in
                let names = [
                    "\(pair.forward.containingTypeName ?? "").\(pair.forward.name)",
                    "\(pair.reverse.containingTypeName ?? "").\(pair.reverse.name)"
                ].sorted()
                return SuggestionIdentity(
                    canonicalInput: "normal-form|" + names.joined(separator: "|")
                )
            },
            carrier: { $0.forward.containingTypeName },
            carrierType: { pair in
                parsePrintHalves(of: pair).flatMap {
                    FunctionPairing.transformationDomain($0.parse)
                }
            },
            caveats: Self.caveats(for:)
        )
    }

    static func signals(for pair: FunctionPair) -> [Signal] {
        guard let halves = parsePrintHalves(of: pair) else { return [] }
        let parseName = halves.parse.name
        let printName = halves.print.name
        var signals: [Signal] = [
            Signal(
                kind: .typeSymmetrySignature,
                weight: 35,
                detail: "Parse/print pair over source text: `\(parseName)` reads text into a "
                    + "structure and `\(printName)` writes it back, so "
                    + "`\(printName)(\(parseName)(s))` is a NORMAL FORM — normalising a second "
                    + "time must change nothing"
            )
        ]
        if halves.parse.containingTypeName == halves.print.containingTypeName {
            signals.append(
                Signal(
                    kind: .exactNameMatch,
                    weight: 5,
                    detail: "Both halves are declared on the same type, so they are meant to be "
                        + "used together"
                )
            )
        }
        return signals
    }

    static func caveats(for pair: FunctionPair) -> [String] {
        guard let halves = parsePrintHalves(of: pair) else { return [] }
        let parseName = halves.parse.name
        let printName = halves.print.name
        return [
            "IF YOUR PRINTER IS FULL-FIDELITY, STATE THE STRONGER LAW INSTEAD: "
                + "`\(printName)(\(parseName)(s)) == s`. That catches everything this one does "
                + "and more. This law is the fallback for a printer that normalises — one that "
                + "drops comments, rewrites whitespace, reorders keys, or canonicalises literal "
                + "spellings. Reach for it only when the stronger claim is genuinely false.",
            "THE LAW IS OVER THE TEXT `\(parseName)` ACCEPTS. If `\(parseName)` throws or "
                + "returns nil for input it cannot read, the composition is undefined there and "
                + "the property has nothing to say — restrict the generator to parseable text, "
                + "or handle the rejection explicitly rather than letting it read as a failure.",
            "IT RESTS ON `\(parseName)(\(printName)(t)) == t` holding for trees `\(parseName)` "
                + "actually produces. A printer that emits text its own parser rejects, or that "
                + "re-parses to a DIFFERENT tree, breaks this — and that is exactly the bug "
                + "worth finding, so a counterexample here is a real defect rather than a "
                + "mis-stated property.",
            "BOTH HALVES MUST BE DETERMINISTIC. A printed form carrying a timestamp, a UUID, a "
                + "hash seed, or dictionary iteration order will differ between the two passes "
                + "and fail this law for reasons that have nothing to do with parsing.",
            "GENERATING PARSEABLE TEXT IS THE HARD PART. A `Gen<String>` of arbitrary characters "
                + "is rejected by any real parser, so the property runs on nothing. Generate a "
                + "corpus of valid fragments — or better, generate the STRUCTURE and print it to "
                + "get text, which is parseable by construction."
        ]
    }
}
