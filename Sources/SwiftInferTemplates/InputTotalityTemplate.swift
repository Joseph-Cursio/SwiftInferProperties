import SwiftInferCore

/// The **input-totality** law: a function handed arbitrary bytes must return or
/// throw for every one of them — it must never trap.
///
///     Parser.parse(source: String) -> SourceFileSyntax
///     ⟹  for every String whatsoever, parse returns. No force-unwrap crash,
///        no unchecked index, no overflow, no precondition failure.
///
/// This is the law a fuzz harness asserts, reached without needing one to
/// exist — see `HostileInputEntryPoints` for why detecting
/// `LLVMFuzzerTestOneInput` was measured and rejected (two Swift definitions in
/// reach, both compiler test fixtures; the real fuzzers are C++).
///
/// ## Role-entailed, not conjectured
///
/// Most of this catalog proposes laws read off a *name* — conjectures a correct
/// implementation may fail. This one is different, and it is scored
/// differently. A parser that traps on some input is broken **by virtue of
/// being a parser**: nothing about "interpret these bytes" admits "unless the
/// bytes are strange". So the caveat block does not say "confirm this is meant
/// to hold" — it says *how to look for the violation*.
///
/// The same argument `ProxyConstruction` already makes for syntax predicates:
/// *"a predicate over syntax owes totality, and half-written code is what an
/// analyser is handed on every keystroke."*
///
/// ## What makes it refutable, and what makes it hard
///
/// Refutable: any input that trips a trap. Hard: a generator drawing
/// *realistic* text will essentially never produce one. The counterexamples
/// live in malformed input — empty, invalid UTF-8, lone surrogates, unbalanced
/// delimiters, pathological nesting — and they have to be generated on purpose.
/// That is the same lesson CLAUDE.md records for collision-dependent laws, in a
/// different costume: a generator tuned for coverage of the *type* is silently
/// mistuned for coverage of the *law*.
///
/// And a violation **crashes the test process** rather than shrinking to a
/// tidy counterexample. That is not a defect of the property; it is what a trap
/// is, and it is why fuzzers exist. The caveat says so plainly so nobody reads
/// a crashed run as a broken harness.
public enum InputTotalityTemplate {

    public static func suggest(for summary: FunctionSummary) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: summary)
    }

    public static func makeConstraint() -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "input-totality",
            appliesTo: { admission(for: $0) != nil },
            signals: Self.signals(for:),
            evidence: { [$0.inferenceEvidence] },
            identity: { summary in
                SuggestionIdentity(
                    canonicalInput: "input-totality|"
                        + "\(summary.containingTypeName ?? "")|\(summary.name)"
                )
            },
            carrier: { $0.containingTypeName },
            carrierType: { hostileParameter(of: $0)?.typeText },
            caveats: { _ in Self.makeCaveats() }
        )
    }

    /// The parameter that carries untrusted input, if any.
    ///
    /// A **location-shaped label vetoes the whole function**, not just that
    /// parameter: `load(projectRoot: String)` is being told where to look, and
    /// no other argument makes it a parser.
    static func hostileParameter(of summary: FunctionSummary) -> Parameter? {
        // Egress: the bytes are going out, not coming in. A type filter cannot
        // tell the two apart — see `HostileInputEntryPoints.egressVerbs`.
        guard !HostileInputEntryPoints.hasEgressVerb(summary.name) else { return nil }
        guard !summary.parameters.contains(where: {
            HostileInputEntryPoints.isLocationLabel($0.label)
        }) else {
            return nil
        }
        return summary.parameters.first { parameter in
            HostileInputEntryPoints.byteCarriers.contains(parameter.typeText)
                || (HostileInputEntryPoints.textCarriers.contains(parameter.typeText)
                    && admitsText(summary, parameter: parameter))
        }
    }

    /// Whether a text-carrying parameter admits this function.
    ///
    /// **Two routes on deliberately different terms.** A leading interpretation VERB asserts
    /// that the argument is being read as a structure, so it needs only the absence of a
    /// location label. A leading result-NOUN (`tokens(inLine:)`) describes the return value and
    /// asserts nothing about the argument, so it additionally requires a positive content
    /// label — measured, because the noun on the verb's terms admits
    /// `tokens(startingWith: String)`, whose `String` is a filter prefix. See
    /// `HostileInputEntryPoints.resultNouns`.
    private static func admitsText(_ summary: FunctionSummary, parameter: Parameter) -> Bool {
        if HostileInputEntryPoints.hasInterpretationVerb(summary.name) { return true }
        return HostileInputEntryPoints.hasResultNoun(summary.name)
            && HostileInputEntryPoints.isContentLabel(parameter.label)
    }

    /// How the function was admitted, or `nil`.
    static func admission(for summary: FunctionSummary) -> HostileInputEntryPoints.Admission? {
        guard let returnType = summary.returnTypeText,
              returnType != "Void", returnType != "()",
              !summary.isMutating,
              let parameter = hostileParameter(of: summary) else {
            return nil
        }
        if HostileInputEntryPoints.byteCarriers.contains(parameter.typeText) {
            return .byteCarrier(typeName: parameter.typeText)
        }
        guard let verb = StreamConsumption.camelCaseTokens(summary.name).first else { return nil }
        return .interpretedText(typeName: parameter.typeText, verb: verb)
    }

    /// The "why suggested" line for a text-admitted function.
    ///
    /// **Two routes admit a text carrier and they are not the same claim**, so this must not
    /// say "verb" for both: a reader checking the reasoning against the name would find it
    /// flatly untrue for `tokens(inLine:)`, which leads with a noun. That row shipped for one
    /// afternoon reading *"leads with the interpretation verb `tokens`"*.
    static func textAdmissionReason(
        _ summary: FunctionSummary,
        typeName: String,
        verb: String
    ) -> String {
        if HostileInputEntryPoints.hasInterpretationVerb(summary.name) {
            return "`\(summary.name)` leads with the interpretation verb `\(verb)` and takes a "
                + "`\(typeName)` — it reads the argument as a structure, so it owes TOTALITY "
                + "over every string that type admits"
        }
        return "`\(summary.name)` names its RESULT (`\(verb)`) rather than its action, and "
            + "takes a `\(typeName)` under a content label — the argument is the text it "
            + "interprets, so it owes TOTALITY over every string that type admits"
    }

    static func signals(for summary: FunctionSummary) -> [Signal] {
        guard let admission = admission(for: summary) else { return [] }
        var signals: [Signal] = []
        switch admission {
        case .byteCarrier(let typeName):
            signals.append(
                Signal(
                    kind: .exactNameMatch,
                    weight: 35,
                    detail: "`\(summary.name)` interprets a raw `\(typeName)` — content by "
                        + "construction, so it owes TOTALITY: a value or a thrown error for "
                        + "every byte sequence, never a trap"
                )
            )

        case let .interpretedText(typeName, verb):
            signals.append(
                Signal(
                    kind: .exactNameMatch,
                    weight: 30,
                    detail: textAdmissionReason(summary, typeName: typeName, verb: verb)
                )
            )
        }
        if let parameter = hostileParameter(of: summary),
           HostileInputEntryPoints.isContentLabel(parameter.label) {
            signals.append(
                Signal(
                    kind: .exactNameMatch,
                    weight: 10,
                    detail: "Argument label `\(parameter.label ?? "")` names a payload rather "
                        + "than a location"
                )
            )
        }
        if summary.isThrows {
            signals.append(
                Signal(
                    kind: .exactNameMatch,
                    weight: 5,
                    detail: "`throws` — the function already has a way to REJECT bad input, so "
                        + "a trap on bad input is unambiguously a defect rather than a "
                        + "design choice"
                )
            )
        }
        return signals
    }

    static func makeCaveats() -> [String] {
        [
            "THROWING IS NOT A VIOLATION. `throws` is the function saying \"this input is "
                + "invalid\", which is the correct answer to invalid input. Returning `nil` is "
                + "the same. The law is only about TRAPS — force-unwrap, unchecked index, "
                + "unchecked overflow, `precondition` on attacker-controlled data.",
            "A VIOLATION CRASHES THE TEST PROCESS instead of shrinking to a tidy "
                + "counterexample. That is what a trap is, and it is why fuzzers exist — do not "
                + "read a crashed run as a broken harness. Note the seed, then narrow by hand.",
            "A GENERATOR OF REALISTIC INPUT WILL NEVER FIND THIS. The counterexamples live in "
                + "malformed input: the empty value, invalid UTF-8, lone surrogates, unbalanced "
                + "delimiters, unterminated literals, pathological nesting depth, and lengths at "
                + "the boundaries. Generate those deliberately — a generator tuned for coverage "
                + "of the TYPE is silently mistuned for coverage of THIS LAW.",
            "This law is ROLE-ENTAILED, not a naming conjecture: nothing about \"interpret "
                + "these bytes\" admits \"unless the bytes are strange\". If it does not hold, "
                + "that is a finding about the function rather than a reason to skip the "
                + "property."
        ]
    }
}
