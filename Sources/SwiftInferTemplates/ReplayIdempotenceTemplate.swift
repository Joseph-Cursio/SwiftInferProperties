import SwiftEffectInference
import SwiftInferCore

/// Replay-idempotence template — the discovery side of SwiftIdempotency's subject.
///
/// Where `IdempotenceTemplate` proves the **value** law `f(f(x)) == f(x)` for a
/// pure function — and deliberately *vetoes* the moment it reads
/// `@ExternallyIdempotent`, because a key-routed handler does not satisfy that
/// unconditional law (see `IdempotenceTemplate+DeclaredEffect`) — this template
/// fires on exactly that vetoed population: a side-effecting handler that is safe
/// to run **twice** (its observable effects happen once), a property stated over
/// effects, not return values.
///
/// **M1 scope** (Branches A + B of `docs/archive/replay-idempotence-template-sketch.md`,
/// itself distilled from SwiftIdempotency's replay-idempotency shape catalog):
///
///   - **Branch A — annotation.** `declaredEffect == .externallyIdempotent`, i.e.
///     the author's own `@ExternallyIdempotent(by:)` claim. The annotation names
///     the key parameter to hold fixed. Matches the annotated fixtures
///     `OfflineManager.download` and `AcronymService.notifyCache`.
///   - **Branch B — key parameter.** A parameter typed `IdempotencyKey`: a handler
///     that threads a stable key through its signature even without annotating
///     itself.
///
///   - **Branch C — dedup gate (M2).** A dedup gate detected in the body
///     (`BodySignals.dedupGateShape`): an early-return dedup check
///     (`OrderCreatedHandler.handle`) or a fetch-then-insert
///     (`OfflineManager.download` without its annotation). Structural inference,
///     +40 (M9) — above the bare key parameter, level with the annotation once the
///     ≥70%×3 external calibration gate cleared.
///
/// Band (post-M9, and B′ promoted 2026-08-07): the author-intent and by-construction
/// signals each reach `.likely` alone — Branch A's annotation (+40), Branch C's dedup
/// gate (+40), the idempotent-write guarantee (+40), and Branch B′'s `IdempotencyKey`
/// builder (+40). Only the bare key PARAMETER (+25 — a type *without proof of use*)
/// stays `.possible`, reaching `.likely` only combined with another signal, per the
/// sketch's "start at possible, let evidence bias the score."
///
/// The `unkeyedEffectVeto` was subsumed by M4/M7's effect-dominance requirement.
/// The ungated buggy twin needs no veto: with no gate detected, Branch C simply
/// never fires — no gate, no proposal.
///
/// Not in `TemplateName.verifiable`: the effect boundary can't be synthesized, so
/// there is no runnable value law. Discovery proposes it; the accept flow emits an
/// `assertIdempotentEffects` scaffold (`LiftedTestEmitter.replayIdempotent`).
public enum ReplayIdempotenceTemplate {

    /// Build a suggestion for `summary`, or `nil` when it is not a replay
    /// candidate or the score collapses to `.suppressed` (e.g. an author-declared
    /// `@NonIdempotent`).
    public static func suggest(for summary: FunctionSummary) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: summary)
    }

    /// Constraint factory. Mirrors `IdempotenceTemplate.makeConstraint` shape.
    public static func makeConstraint() -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: TemplateName.replayIdempotence.rawValue,
            appliesTo: { Self.isCandidate($0) },
            signals: { Self.accumulatedSignals(for: $0) },
            evidence: { [$0.inferenceEvidence] },
            identity: Self.makeIdentity(for:),
            carrier: { $0.containingTypeName },
            caveats: { Self.makeCaveats(for: $0) }
        )
    }

    // MARK: - Gate

    /// The candidate gate: an author-declared `@ExternallyIdempotent` claim
    /// (Branch A), a parameter typed `IdempotencyKey` (Branch B), or a dedup gate
    /// detected in the body (Branch C, M2). Computed properties are excluded — a
    /// getter is not a handler. Signals below can still veto a matched candidate
    /// (an author who wrote both a key parameter and `@NonIdempotent`).
    static func isCandidate(_ summary: FunctionSummary) -> Bool {
        guard !summary.isComputedProperty else { return false }
        return hasExternallyIdempotentAnnotation(summary)
            || keyParameter(of: summary) != nil
            || summary.bodySignals.dedupGateShape != nil
            || summary.bodySignals.buildsIdempotencyKey
            || summary.bodySignals.callsIdempotentWrite
    }

    /// The `IdempotencyKey`-typed parameter, if any. Exact type-text match for M1;
    /// an optional key (`IdempotencyKey?`) is not a stable-key shape and is left
    /// for later.
    static func keyParameter(of summary: FunctionSummary) -> Parameter? {
        summary.parameters.first { $0.typeText == "IdempotencyKey" }
    }

    static func hasExternallyIdempotentAnnotation(_ summary: FunctionSummary) -> Bool {
        if case .externallyIdempotent = summary.declaredEffect { return true }
        return false
    }

    // MARK: - Signals

    static func accumulatedSignals(for summary: FunctionSummary) -> [Signal] {
        var signals: [Signal] = []
        if let annotation = annotationSignal(for: summary) {
            signals.append(annotation)
        }
        if let key = keyParameterSignal(for: summary) {
            signals.append(key)
        }
        if let gate = dedupGateSignal(for: summary) {
            signals.append(gate)
        }
        if let builder = keyBuilderSignal(for: summary) {
            signals.append(builder)
        }
        if let idempotentWrite = idempotentWriteSignal(for: summary) {
            signals.append(idempotentWrite)
        }
        if let veto = declaredNonIdempotentVeto(for: summary) {
            signals.append(veto)
        }
        if let nonDeterministic = nonDeterministicKeyCounter(for: summary) {
            signals.append(nonDeterministic)
        }
        return signals
    }

    /// Branch A. The `@ExternallyIdempotent(by:)` claim, worth +40 and naming the
    /// key parameter to hold fixed. Alone this lands in `.likely` (band-promotion,
    /// 2026-08-07): this is the author's *explicit* retry-safety declaration, not
    /// the tool's inference, so the "promote inference only on external evidence"
    /// rule does not gate it — a claim is at least as confident as inferred
    /// structure, and surfacing the property that tests it by default is the point
    /// of the annotate-once-enforced-twice loop.
    static func annotationSignal(for summary: FunctionSummary) -> Signal? {
        guard case let .externallyIdempotent(keyParameter) = summary.declaredEffect else {
            return nil
        }
        let key = keyParameter.map { "`\($0)`" } ?? "a caller-supplied key"
        return Signal(
            kind: .replayExternallyIdempotentAnnotation,
            weight: 40,
            detail: "Author-declared externally idempotent (dedup key: \(key)) — "
                + "the handler claims retry-safety when routed through that key, so "
                + "the effect property `run twice under one key ⇒ effects run once` "
                + "is exactly what should be checked"
        )
    }

    /// Branch B. An `IdempotencyKey` parameter, worth +25. Alone this lands in
    /// `.possible`; with Branch A it reaches `.likely`.
    static func keyParameterSignal(for summary: FunctionSummary) -> Signal? {
        guard let key = keyParameter(of: summary) else { return nil }
        let label = key.label ?? key.internalName
        return Signal(
            kind: .replayIdempotencyKeyParameter,
            weight: 25,
            detail: "Threads a stable `IdempotencyKey` parameter (`\(label)`) through "
                + "its signature — a replay-safe handler holds that key fixed across "
                + "retries; the property quantifies over it"
        )
    }

    /// Branch C (M2). A dedup gate detected in the body — an early-return dedup
    /// check, fetch-then-insert, state-flag, or guard-form. Worth +40, promoted from
    /// +30 (2026-08-07) after clearing the external-evidence gate: 8/8 accepted
    /// (MacCloud 2 + public corpus 6) across three consecutive re-sweeps (M5/M7/M8),
    /// meeting the PRD §3.5 ≥70%×3 rule the reducer-idempotence family used. Alone it
    /// now lands in `.likely`. The firming pass (2026-08-07) expanded the corpus to
    /// 12 repos (~9,700 files): **0 false positives**, so the promotion's risk is
    /// confirmed low — but the accepted-TP count held at 8 (in-handler dedup gates
    /// are rare; typical code dedups at the DB/framework layer). Firm on precision,
    /// TP-sparse by the shape's rarity. Still above the bare key parameter (+25, a
    /// type without proof of use), which stays `.possible`.
    static func dedupGateSignal(for summary: FunctionSummary) -> Signal? {
        guard let shape = summary.bodySignals.dedupGateShape else { return nil }
        let description: String
        switch shape {
        case let .earlyReturnDedup(keyRoot):
            let key = keyRoot.map { " keyed on `\($0)`" } ?? ""
            description = "an early-return dedup check\(key)"

        case .fetchThenInsert:
            description = "a fetch-existing-then-insert branch"

        case let .stateFlagGuard(flag):
            let named = flag.map { " on `\($0)`" } ?? ""
            description = "an early return on an already-handled state flag\(named)"

        case let .guardDedup(verb):
            let named = verb.map { " `\($0)`" } ?? ""
            description = "a guard-form claim-once check\(named)"
        }
        return Signal(
            kind: .replayDedupGate,
            weight: 40,
            detail: "Body has a dedup gate (\(description)) before its effect — the "
                + "effect runs at most once per key, so `run twice ⇒ effects run "
                + "once` is the property to check"
        )
    }

    /// Branch B′ (M6; promoted 2026-08-07). The body builds an `IdempotencyKey(…)`
    /// from its input — the key-from-entity builder (`StripeWebhookHandler.makeChargeRequest`).
    /// Worth +40 → `.likely` alone, like the annotation and unlike the bare key
    /// PARAMETER (+25, which stays `.possible`).
    ///
    /// The M9 rule "promote inference only on external evidence" guards *shape*
    /// inferences that can false-positive on real code; this is not one. Constructing
    /// `IdempotencyKey` is a **by-construction author signal**: the type exists solely
    /// for idempotency and cannot be built by accident, so precision is 1.0 by the type
    /// name. That is a claim of intent — the same class as `@ExternallyIdempotent`
    /// (Branch A, +40) — not a guess to hold at `.possible`. It needs no external
    /// calibration and can acquire none: the type is SwiftIdempotency-specific, so no
    /// public corpus uses it and promotion adds exactly zero external false positives.
    /// The key parameter stays `.possible` because it is a type *without proof of use*
    /// — received, not established here. Being a *pure* value builder, its property is
    /// the value form (the built value is stable across calls), not an effect form.
    static func keyBuilderSignal(for summary: FunctionSummary) -> Signal? {
        guard summary.bodySignals.buildsIdempotencyKey else { return nil }
        return Signal(
            kind: .replayKeyBuilder,
            weight: 40,
            detail: "Constructs an `IdempotencyKey` from its input — the built value "
                + "(and its key) must be stable across invocations, so a downstream "
                + "retry is safe; a key derived from `UUID()`/`Date()` would break it"
        )
    }

    /// M10. The body calls an idempotent-write primitive (`upsert`, `firstOrCreate`,
    /// …). Worth +40 → `.likely` alone — like the annotation, this is a *guarantee*,
    /// not the tool's inference: an upsert applied twice leaves the same state, so
    /// the "gate promotion on external evidence" rule doesn't apply (it gates
    /// guesses, not the semantics of a chosen operation). This branch recovers the
    /// recall the firming pass showed the gate detector can't reach — much real
    /// dedup is an idempotent write, not an in-handler if/guard.
    static func idempotentWriteSignal(for summary: FunctionSummary) -> Signal? {
        guard summary.bodySignals.callsIdempotentWrite else { return nil }
        return Signal(
            kind: .replayIdempotentWrite,
            weight: 40,
            detail: "Uses an idempotent-write primitive (upsert / firstOrCreate / …) — "
                + "the write is idempotent by construction, so `run twice ⇒ same state`. "
                + "Confirm no OTHER effect (email, queue publish) runs unconditionally "
                + "alongside it — the primitive guards the write, not those"
        )
    }

    /// The author denied this exact claim. Same posture as the value template's
    /// declared-non-idempotent veto: restating a rejected claim is noise.
    static func declaredNonIdempotentVeto(for summary: FunctionSummary) -> Signal? {
        guard summary.declaredEffect == .nonIdempotent else { return nil }
        return Signal(
            kind: .declaredNonIdempotentEffect,
            weight: Signal.vetoWeight,
            detail: "Author-declared `@NonIdempotent` — the declaration denies "
                + "retry-safety, so proposing a replay-idempotency property restates "
                + "a claim the author already rejected"
        )
    }

    /// A non-deterministic call in the body is a counter-signal, not (yet) a veto:
    /// a keyed handler may legitimately read the clock for a log line, but it may
    /// also be deriving its key from `UUID()` / `Date()`, which would make the
    /// claim a lie. M1 has no key-flow analysis to tell these apart, so it demotes
    /// rather than suppresses; the hard `nonStableKeyVeto` waits for M2's
    /// `BodySignals.dedupGate` to root the key expression.
    static func nonDeterministicKeyCounter(for summary: FunctionSummary) -> Signal? {
        guard summary.bodySignals.hasNonDeterministicCall else { return nil }
        return Signal(
            kind: .nonDeterministicBody,
            weight: -15,
            detail: "Body calls a non-deterministic API — if the key is derived from "
                + "`UUID()` / `Date()` rather than a stable id, replay-idempotency "
                + "fails; confirm the key is stable across retries"
        )
    }

    // MARK: - Identity & caveats

    private static func makeIdentity(for summary: FunctionSummary) -> SuggestionIdentity {
        SuggestionIdentity(
            canonicalInput: TemplateName.replayIdempotence.rawValue
                + "|" + canonicalSignature(of: summary)
        )
    }

    /// A refactor-stable signature key: owning type + name + parameter types.
    static func canonicalSignature(of summary: FunctionSummary) -> String {
        let owner = summary.qualifiedContainingTypeName ?? summary.containingTypeName ?? ""
        let paramTypes = summary.parameters.map(\.typeText).joined(separator: ",")
        return "\(owner).\(summary.name)(\(paramTypes))"
    }

    static func makeCaveats(for summary: FunctionSummary) -> [String] {
        var caveats = [
            "The property is over EFFECTS, not the return value — a trivial return "
                + "(e.g. `Bool`) can hide a duplicated effect. Observe the effect "
                + "through an injected recorder (`IdempotentEffectRecorder`).",
            "Idempotence holds only if the key is stable across retries; a key "
                + "derived from `UUID()` / `Date()` breaks it.",
            "Gate detection (Branch C) confirms a leading dedup/fetch branch that "
                + "returns early, not that it dominates every effect path — a second "
                + "effect outside the guarded branch is not yet checked."
        ]
        if hasExternallyIdempotentAnnotation(summary), keyParameter(of: summary) == nil {
            caveats.append(
                "The `@ExternallyIdempotent(by:)` key is named in the annotation but "
                    + "no parameter is typed `IdempotencyKey`; check the named "
                    + "parameter actually carries a stable key."
            )
        }
        return caveats
    }
}
