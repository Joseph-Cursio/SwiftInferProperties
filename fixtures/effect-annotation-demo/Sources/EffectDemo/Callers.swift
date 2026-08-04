/// The layer under test — `T -> T` shapes the template proposes a law for, in a
/// DIFFERENT FILE from the effects they call.
///
/// The cross-file split is the whole point. Nothing on these declarations says
/// anything about their retry behaviour; the only evidence lives on their
/// callees, one file over. `discover` alone cannot see it; `discover
/// --resolve-effects` can.
///
/// **The doc comments here are deliberately bland.** A first draft of this
/// fixture used the word "idempotence" in a comment and named its control
/// `trim`, and both leaked into the scores — the word triggers
/// `DocstringPropertyCorroborator` (+15) and `trim` is a curated verb (+40), so
/// the control was not a control and one row read 90 instead of 75. A fixture
/// whose prose moves its own numbers measures the prose.
public enum Callers {

    /// Calls a retry-hostile effect; scores on shape alone (35).
    ///
    /// The law `normalise(normalise(x)) == normalise(x)` may still hold on the
    /// RETURN VALUE — which is why the resolver demotes rather than vetoes.
    /// Evidence about a callee is not a refutation of the law.
    public static func normalise(_ address: String) -> String {
        _ = Effects.sendReceipt(address)
        return address.lowercased()
    }

    /// Second caller, second effect, so the tier is seen propagating from more
    /// than one source. Also shape-only (35).
    public static func canonicalise(_ payload: String) -> String {
        _ = Effects.insertAuditRow(payload)
        return payload.lowercased()
    }

    /// The other half of "demote, not veto", and the reason −45 was chosen over
    /// a veto weight.
    ///
    /// Identical to `normalise` except the name is a curated verb, so it starts
    /// at 75 rather than 35. The same −45 lands it at 30: still visible, with
    /// the callee named in the explainability block. A shape-only guess is
    /// silenced; a corroborated law is demoted and left for a human to judge.
    ///
    /// Nothing is annotated on THIS declaration on purpose — the evidence has to
    /// arrive from the callee, one file over, or the fixture proves nothing.
    public static func normalize(_ address: String) -> String {
        _ = Effects.sendReceipt(address)
        return address.lowercased()
    }

    /// The CONTROL, and the fixture is worthless without it. Same shape, same
    /// file, same score (35) — but it calls nothing retry-hostile, so it must
    /// come through `--resolve-effects` completely unchanged. Without this row,
    /// a resolver that demoted every function would look correct.
    ///
    /// Named `shorten` rather than `trim` precisely because `trim` is a curated
    /// verb: a control that scores differently from its subjects is not one.
    public static func shorten(_ text: String) -> String {
        text.lowercased()
    }
}
