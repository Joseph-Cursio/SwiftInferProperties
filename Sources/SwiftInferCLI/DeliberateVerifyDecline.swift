/// Templates `verify` does not measure **on purpose**, with the reason — the verify-side twin of
/// `DeliberateStubDecline`.
///
/// Before #701 these fell through to `unsupportedTemplate`, whose remedy says *"a gap in
/// swift-infer… Nothing you write unblocks these"*. For the two characterisation laws that reads
/// as a composer someone has yet to write, and it is not: a composer was weighed and refused,
/// because a verify pass of a law read out of the code under test is a pass by construction. For
/// `input-order-independence` it hides what the gap actually is, which is two index columns and
/// the rows a composer would still not reach. Both are decisions with a measured reason, and the
/// reason belongs on the channels a reader sees — the verify error, the survey row's detail and
/// `report`'s cause breakdown — not in a doc comment.
///
/// **A decline and a deferral travel on different channels** (`Disposition`). The two
/// characterisation laws are refused: `VerifyError.declinedByDesign`, cause
/// `UnverifiableCause.declinedByDesign`, whose wording says no composer is coming. The deferral
/// waits on a composer that is planned: `VerifyError.deferredComposer`, cause
/// `UnverifiableCause.deferredComposer`. They shared the decline channel at first, and verify then
/// printed a reason saying *deferred, not declined* inside a wrapper saying *by design … not a
/// missing composer* — and `report`, `accept-check` and the cause breakdown filed a deferral as a
/// permanent refusal.
///
/// **A decline can never shadow a verifiable template.** `buildStubBundle` consults this only
/// after `TemplateName.verifiable` has refused the template, and `DeliberateVerifyDeclineTests`
/// asserts every verifiable member answers nil, so a template that gains a composer later must
/// leave this switch in the same change.
///
/// **None of these is a `TemplateName` case, deliberately.** A case is what a verifiable template
/// needs; a declined one is a string the template registry writes (`SortedOutputTemplate`,
/// `MarkerDispatchTemplate`, `InputOrderIndependenceTemplate`), matched here as the accept path
/// matches it.
enum DeliberateVerifyDecline {

    /// Whether verify refuses a template for good, or waits on a composer that is planned.
    enum Disposition: Equatable {
        /// A composer was weighed and refused (`VerifyError.declinedByDesign`).
        case declined
        /// A composer is planned and the reason names what ends the wait
        /// (`VerifyError.deferredComposer`).
        case deferred
    }

    /// Which kind of recorded decision `templateName` is, or nil when it is none.
    static func disposition(forTemplate templateName: String) -> Disposition? {
        switch templateName {
        case "sorted-output", "marker-dispatch": .declined
        case "input-order-independence": .deferred
        default: nil
        }
    }

    /// The user-facing reason verify does not measure `templateName`, or nil when it is not a
    /// recorded decision (a verifiable template, or an ordinary composer gap). Answers for a
    /// deferral too; `disposition(forTemplate:)` says which wrapper the reason goes in.
    static func reason(forTemplate templateName: String) -> String? {
        switch templateName {
        // #701. A CHARACTERISATION law (`Refutability.characterisationTemplates`,
        // Refutability.swift:160-171): the oracle is the tie-break chain read out of the subject's
        // own body (SortedOutputTemplate.swift:23-30). Verify rebuilds a stale index from current
        // source before it runs (`reindexIfNeeded`, Verify+Reindex.swift:24-62), so the comparator
        // a composer would check is the one the code under test compiled. It can fail only when
        // that comparator is not a strict weak ordering; every other run passes by construction,
        // and a `measured-bothPass` promotes to Verified and reaches docc's verified-only surface
        // (`DoccPageBuilder`, DoccPageBuilder.swift:33-50), which has no characterisation
        // exclusion. The accepted stub is checked in and keeps the comparator it was read from,
        // which is what lets it catch a LATER edit: on `ImpactReport.from` it killed 4 of 5
        // comparator edits (commit 9a04eba7).
        case "sorted-output":
            return "a characterisation law — verify re-reads the comparator from the code it runs "
                + "against, so it could fail only on a comparator that is not a strict weak "
                + "ordering, and any other pass is by construction and would read as Verified. "
                + "The accepted, checked-in stub is the instrument: it keeps the comparator it was "
                + "read from and catches a later edit"

        // #701. The same law class (Refutability.swift:169-170; MarkerDispatchTemplate.swift:
        // 127-129): the keyword table is restated from the body, and a verify run re-reads it from
        // the code under test, so only the stub's own `checked > 0` guard or a reader defect could
        // fail it. Two secondary reasons, either enough alone: the domain is an exhaustive table
        // with no generator, which does not fit verify's trial and edge-pass protocol
        // (StrategistDispatchEmitter+Templates.swift:45-56) — reporting the table size as a trial
        // count would misstate what `bothPass` covers; and the population is 1 row over the 43
        // local repositories that completed a census (commit 7b7b1bf3).
        case "marker-dispatch":
            return "a characterisation law — verify re-reads the keyword table from the code it "
                + "runs against, so a pass is by construction and would read as Verified; and the "
                + "table is checked exhaustively, with no generator, which verify's trial protocol "
                + "cannot state. The accepted, checked-in stub is the instrument: it catches a "
                + "later edit"

        // #701. DEFERRED, not declined (`Disposition.deferred`, so it travels as
        // `VerifyError.deferredComposer`, whose wrapper already says a composer is planned and
        // the accepted stub runs the law meanwhile) — this one is a conjecture and can fail today
        // (input-order-independence.md §5). The oracle needs `SortedOutput.member` and
        // `dictionaryKeyMember` (LiftedTestEmitter+InputOrder.swift:22-39), and `buildEntry`
        // persists only `documented-range`'s match payload (#701); this one is not indexed
        // (Index+Projection.swift), so no composer can name the key member without guessing.
        // `SemanticIndexEntry.documentedRange` is the precedent for the column it would need.
        // And it would move 0 of the 4
        // measured rows (input-order-independence.md §3) to a verdict today: two are `private`
        // (`buildChurnScores`, `TuneModel.aggregate`), which `@testable` does not reach; one
        // (`ImpactReport.from`) sits in a `.defaultIsolation(MainActor.self)` target and verify
        // composers do not hop onto an actor; one (`ruleHotspots`) traps on the strategist's
        // full-range `Int` counts before the law is checked (§4). Ends when a composer exists
        // (falsifier: `composeInputOrderIndependencePass`, registered in that doc's §5).
        case "input-order-independence":
            return "the law needs the sorted result's member and its dictionary-key member, "
                + "which the index does not carry yet, and of the 4 measured rows none would "
                + "reach a verdict today (2 are private, 1 needs a MainActor hop verify does not "
                + "make, 1 traps on full-range counts). The wait ends when "
                + "`composeInputOrderIndependencePass` exists"

        default:
            return nil
        }
    }

    /// Throw `VerifyError.declinedByDesign` when `templateName` is a recorded decline, and
    /// `VerifyError.deferredComposer` when it is a recorded deferral.
    ///
    /// Called from `buildStubBundle`'s first gate, ahead of `unsupportedTemplate`, so the reason
    /// replaces the composer-gap message rather than sitting beside it.
    static func requireMeasured(templateName: String) throws {
        guard let disposition = disposition(forTemplate: templateName),
              let reason = reason(forTemplate: templateName)
        else { return }
        switch disposition {
        case .declined:
            throw VerifyError.declinedByDesign(template: templateName, reason: reason)

        case .deferred:
            throw VerifyError.deferredComposer(template: templateName, reason: reason)
        }
    }
}
