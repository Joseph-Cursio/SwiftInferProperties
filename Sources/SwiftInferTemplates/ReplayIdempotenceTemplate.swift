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
/// **M1 scope** (Branches A + B of `docs/ideas/replay-idempotence-template-sketch.md`,
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
///     +30 — above the bare key parameter, below the author's own annotation.
///
/// A handler that combines signals (annotated + key-typed, or gate + key) earns
/// them together and reaches the `.likely` band; any one alone stays in
/// `.possible`, per the sketch's "start at possible, let evidence bias the score."
///
/// **Still deferred** (M2+): the key-from-entity builder that constructs its key in
/// the body (`StripeWebhookHandler`, no gate and no key parameter — needs a
/// key-construction body signal), and the effect-dominance `unkeyedEffectVeto`.
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
        if let veto = declaredNonIdempotentVeto(for: summary) {
            signals.append(veto)
        }
        if let nonDeterministic = nonDeterministicKeyCounter(for: summary) {
            signals.append(nonDeterministic)
        }
        return signals
    }

    /// Branch A. The `@ExternallyIdempotent(by:)` claim, worth +35 and naming the
    /// key parameter to hold fixed. Alone this lands in `.possible`.
    static func annotationSignal(for summary: FunctionSummary) -> Signal? {
        guard case let .externallyIdempotent(keyParameter) = summary.declaredEffect else {
            return nil
        }
        let key = keyParameter.map { "`\($0)`" } ?? "a caller-supplied key"
        return Signal(
            kind: .replayExternallyIdempotentAnnotation,
            weight: 35,
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

    /// Branch C (M2). A dedup gate detected in the body — an early-return
    /// dedup check or a fetch-then-insert. Worth +30: it is inferred *structure*,
    /// so it sits above the bare key parameter (+25, a type without proof the
    /// handler uses it) and just below the author's own annotation (+35). Alone it
    /// lands in `.possible`.
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
        }
        return Signal(
            kind: .replayDedupGate,
            weight: 30,
            detail: "Body has a dedup gate (\(description)) before its effect — the "
                + "effect runs at most once per key, so `run twice ⇒ effects run "
                + "once` is the property to check"
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
