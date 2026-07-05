import Foundation
import SwiftInferCore

/// Item 2 slice 3 — resolve a parent `.tca` reducer's
/// `IdentifiedActionOf<Child>` Action cases against the discovered child
/// reducers, so Phase B's relaxed exploration can construct a canonical
/// `IdentifiedAction.element(id:action:)` value without deriving the child.
///
/// **Why a resolution pass (not a threaded map).** The emitter only ever sees
/// one `ReducerCandidate` and an `ActionCaseInfo`'s *type-name string*
/// (`"IdentifiedActionOf<Child>"`) — nothing about `Child`. Rather than thread
/// a `[typeName: ReducerCandidate]` map through `compositionGenerator` /
/// `constructibleCases` / `excludedCaseNames` / `tcaActionGenLines` *and* the
/// evidence coverage fold (which would have to stay perfectly in sync), this
/// resolver runs once in `VerifyInteractionPipeline.resolveAndEmit`, enriches
/// the matched candidate's cases with `resolvedElement` facts, and returns the
/// enriched candidate. Everything downstream reads the same enriched candidate,
/// so emit + coverage counting can't diverge.
///
/// **Scope (per the slice-3 recount).** Only the `IdentifiedActionOf<Child>`
/// spelling is resolved — the recount over Point-Free's real Examples tree found
/// zero spelled-out `IdentifiedAction<_, _>` cases, and resolving that form
/// needs an Action→reducer back-map. A child resolves when (i) its `State.ID`
/// is cheaply-defaultable **and** (ii) a constructible child action exists —
/// see `childActionValue`.
///
/// **Slice 3c — depth-bounded child recursion.** The child action is chosen by
/// `childActionValue`: a payload-free case first (3b base case — always
/// terminates), else a constructible payload-bearing case (raw scalar/Optional/
/// collection / `PresentationAction` / `Result` / `BindingAction` / a *nested*
/// `IdentifiedActionOf<GrandChild>`). The nested case recurses with a **depth
/// bound** (`maxChildDepth`), so a self-recursive `IdentifiedActionOf<Self>`
/// with no payload-free case terminates (falls back to excluded) instead of
/// looping. Per the recount this adds ~0 real reach (every real child already
/// has a payload-free case) but completes the construction for payload-only
/// children (e.g. a `binding`-only child, now reachable via slice 4).
enum IdentifiedActionResolver {

    /// Slice 3c — recursion depth cap for nested `IdentifiedActionOf`. `0` = the
    /// parent's own element (3b); each nested level adds one. Bounded so a
    /// self-recursive child terminates.
    static let maxChildDepth = 2

    /// True when the `State.ID` type is one the verifier can construct a
    /// canonical literal for — the single source of truth is
    /// `ActionSequenceStubEmitter.defaultValueLiteral` (UUID + the shared
    /// defaultable-type table: sized ints / Bool / String / Double / Optionals
    /// / collections). In practice real ids are `UUID` (recount: 6/8) or
    /// `Int`/`String`; the wider set is harmless (a constructed `.element`
    /// no-ops against the empty initial State regardless).
    static func isDefaultableIDType(_ type: String) -> Bool {
        ActionSequenceStubEmitter.defaultValueLiteral(for: type) != nil
    }

    /// Enrich `candidate`'s `IdentifiedActionOf<Child>` cases against `all`
    /// (the full discovered/deduped candidate set). Returns the candidate
    /// unchanged when it's non-`.tca` or nothing resolves.
    static func resolve(
        _ candidate: ReducerCandidate,
        among all: [ReducerCandidate]
    ) -> ReducerCandidate {
        guard candidate.carrierKind == .tca else { return candidate }
        var changed = false
        let newCases = candidate.actionCases.map { caseInfo -> ActionCaseInfo in
            guard caseInfo.resolvedElement == nil,
                  caseInfo.payloadTypes.count == 1,
                  let childName = identifiedActionChild(caseInfo.payloadTypes[0]),
                  let child = lookupChild(childName, among: all),
                  let idType = child.stateIDTypeName,
                  isDefaultableIDType(idType),
                  let childValue = childActionValue(for: child, among: all, depth: 0)
            else { return caseInfo }
            changed = true
            return ActionCaseInfo(
                name: caseInfo.name,
                payloadTypes: caseInfo.payloadTypes,
                resolvedElement: ResolvedIdentifiedElement(
                    idType: idType,
                    childActionValue: childValue
                )
            )
        }
        guard changed else { return candidate }
        return candidate.replacingActionCases(newCases)
    }

    /// Slice 3b/3c — a concrete `Child.Action` value expression for
    /// `.element(id:, action:)`, or `nil` if nothing is constructible within
    /// `maxChildDepth`. Tries a **payload-free** case first (3b — always
    /// terminates), then the first constructible **payload-bearing** case:
    /// raw scalar/Optional/collection (via the shared `defaultValueLiteral`),
    /// `PresentationAction` → `.dismiss`, type-erased `Result` →
    /// `.failure(CancellationError())`, `BindingAction` → `.set(\.field, value)`
    /// over a defaultable State field, or a *nested* `IdentifiedActionOf` —
    /// which recurses with `depth + 1` and is skipped once `depth` reaches
    /// `maxChildDepth`, guaranteeing termination on self-recursion.
    static func childActionValue(
        for child: ReducerCandidate,
        among all: [ReducerCandidate],
        depth: Int
    ) -> String? {
        let action = child.actionTypeName
        // 3b base case — payload-free (always terminates).
        if let free = child.actionCases.first(where: \.payloadTypes.isEmpty) {
            return "\(action).\(free.name)"
        }
        // 3c — the first constructible payload-bearing case, in source order.
        for caseInfo in child.actionCases where caseInfo.payloadTypes.count == 1 {
            let payload = caseInfo.payloadTypes[0].trimmingCharacters(in: .whitespaces)
            if let literal = ActionSequenceStubEmitter.defaultValueLiteral(for: payload) {
                return "\(action).\(caseInfo.name)(\(literal))"
            }
            if payload.hasPrefix("PresentationAction<") {
                return "\(action).\(caseInfo.name)(.dismiss)"
            }
            if payload.hasPrefix("Result<"),
               payload.hasSuffix(", any Error>") || payload.hasSuffix(", Error>") {
                return "\(action).\(caseInfo.name)(.failure(CancellationError()))"
            }
            if payload.hasPrefix("BindingAction<"),
               let field = child.stateFields.first(where: {
                   ActionSequenceStubEmitter.defaultValueLiteral(for: $0.typeName) != nil
               }),
               let literal = ActionSequenceStubEmitter.defaultValueLiteral(for: field.typeName) {
                return "\(action).\(caseInfo.name)(.set(\\.\(field.name), \(literal)))"
            }
            if depth < maxChildDepth,
               let grandName = identifiedActionChild(payload),
               let grand = lookupChild(grandName, among: all),
               let gid = grand.stateIDTypeName,
               let idLiteral = ActionSequenceStubEmitter.defaultValueLiteral(for: gid),
               let grandValue = childActionValue(for: grand, among: all, depth: depth + 1) {
                return "\(action).\(caseInfo.name)(.element(id: \(idLiteral), action: \(grandValue)))"
            }
        }
        return nil
    }

    /// `"IdentifiedActionOf<Child>"` → `"Child"`; `nil` for any other payload
    /// (including the spelled-out `IdentifiedAction<ID, Action>` form, which
    /// slice 3 deliberately does not resolve).
    static func identifiedActionChild(_ payload: String) -> String? {
        let trimmed = payload.trimmingCharacters(in: .whitespaces)
        let prefix = "IdentifiedActionOf<"
        guard trimmed.hasPrefix(prefix), trimmed.hasSuffix(">") else { return nil }
        let inner = trimmed.dropFirst(prefix.count).dropLast()
        let child = inner.trimmingCharacters(in: .whitespaces)
        return child.isEmpty ? nil : child
    }

    /// Find the child reducer candidate by type name. Matches on the child's
    /// *last* path component against the candidate's `enclosingTypeName`, so
    /// both a top-level `Row` and a nested `Feature` spelled
    /// `ObservableBasicsView.Feature` resolve (discovery records the immediate
    /// enclosing type name, not the qualified path).
    static func lookupChild(
        _ childName: String,
        among all: [ReducerCandidate]
    ) -> ReducerCandidate? {
        let last = childName.split(separator: ".").last.map(String.init) ?? childName
        return all.first { $0.enclosingTypeName == last }
    }
}
