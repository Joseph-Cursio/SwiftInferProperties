import SwiftInferCore

/// Prompt rendering + input parsing for the `[A/B/B'/s/n/?]` triage
/// loop. Extracted from the main `InteractiveTriage` body to keep the
/// orchestrator under SwiftLint's 250-line type-body cap after
/// M8.4.b.1's `B'` arm landed.
extension InteractiveTriage {

    /// Compose the prompt line. M6.4 ships `[A/s/n/?]`; M7.5b extends
    /// to `[A/B/s/n/?]` when a primary proposal is attached; M8.4.b.1
    /// further extends to `[A/B/B'/s/n/?]` when a secondary proposal
    /// is also attached (incomparable arms or the SetAlgebra
    /// secondary). `B` and `B'` arms are ordered per the proposals
    /// list — position 0 is primary, position 1 is secondary.
    static func promptLine(
        position: Int,
        total: Int,
        primaryAvailable: Bool,
        secondaryAvailable: Bool = false
    ) -> String {
        let arms: String
        if primaryAvailable && secondaryAvailable {
            arms = "Accept (A) / Conformance (B) / Conformance' (B') "
                + "/ Skip (s) / Reject (n) / Help (?)"
        } else if primaryAvailable {
            arms = "Accept (A) / Conformance (B) / Skip (s) / Reject (n) / Help (?)"
        } else {
            arms = "Accept (A) / Skip (s) / Reject (n) / Help (?)"
        }
        return "[\(position)/\(total)] \(arms)"
    }

    enum Choice {
        case accept, conformance, conformancePrime, skip, reject
    }

    /// Read one valid choice from `prompt`, looping on `?` (help) and
    /// invalid input. Returns `.skip` on EOF as a safe default —
    /// piped input running out shouldn't auto-accept anything. `b` is
    /// only recognized when `primaryAvailable` is `true`; `b'` and `c`
    /// (typing-friendly alias) are only recognized when
    /// `secondaryAvailable` is `true`. Unrecognized input falls
    /// through (so users don't accidentally trigger a non-existent
    /// conformance write).
    static func readChoice(
        prompt: any PromptInput,
        output: any DiscoverOutput,
        primaryAvailable: Bool = false,
        secondaryAvailable: Bool = false
    ) -> Choice {
        while true {
            output.write("> ")
            guard let line = prompt.readLine() else { return .skip }
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            switch trimmed {
            case "a": return .accept
            case "b" where primaryAvailable: return .conformance
            // M8.4.b.1 — `b'` matches the rendered prompt notation
            // verbatim; `c` is a typing-friendly alias since some
            // terminals/keyboards make the apostrophe awkward.
            case "b'" where secondaryAvailable: return .conformancePrime
            case "c" where secondaryAvailable: return .conformancePrime
            case "s", "": return .skip // empty line = skip-for-now (default-on-Enter)
            case "n": return .reject
            case "?", "h", "help":
                output.write(helpText(
                    primaryAvailable: primaryAvailable,
                    secondaryAvailable: secondaryAvailable
                ))
            default:
                output.write("Unrecognized input '\(trimmed)'. Type ? for help.")
            }
        }
    }

    static func helpText(
        primaryAvailable: Bool,
        secondaryAvailable: Bool = false
    ) -> String {
        var text = """
            A — accept this suggestion. For idempotence / round-trip /
                monotonicity / invariant-preservation / commutativity /
                associativity / identity-element / inverse-pair, a
                property-test stub is written to
                Tests/Generated/SwiftInfer/<TemplateName>/<FunctionName>.swift.
            """
        if primaryAvailable {
            text += "\n"
            text += """
                B — accept Option B (RefactorBridge conformance). A
                    conformance extension is written to
                    Tests/Generated/SwiftInferRefactors/<TypeName>/<ProtocolName>.swift.
                    Once chosen for a type, subsequent suggestions on
                    that type collapse to [A/s/n/?].
                """
        }
        if secondaryAvailable {
            text += "\n"
            text += """
                B' — accept the secondary RefactorBridge conformance
                    (incomparable arms or stdlib secondary like
                    SetAlgebra). Type `b'` or `c` (alias). Same
                    writeout shape as B; once chosen for a type,
                    subsequent suggestions on that type collapse to
                    [A/s/n/?].
                """
        }
        text += "\n"
        text += """
            s — skip for now. Re-surfaces in future --interactive runs.
                (Also the default if you press Enter.)
            n — reject. Hides this suggestion from future runs.
            ? — show this help.
            """
        return text
    }
}
