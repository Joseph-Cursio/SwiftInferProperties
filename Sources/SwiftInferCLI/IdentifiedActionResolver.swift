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
/// needs an Action→reducer back-map. A child resolves only when (i) its
/// `State.ID` is one of the cheaply-defaultable types (`UUID` via a canned
/// literal, `Int`/`String` folded in for free) **and** (ii) it has a
/// payload-free action case (depth 0 — no recursion into further composition
/// wrappers, so a self-recursive `IdentifiedActionOf<Self>` terminates).
/// Everything else is left unresolved → stays excluded + disclosed.
enum IdentifiedActionResolver {

    /// `State.ID` types the verifier can construct a canonical id literal for.
    /// `UUID` is the dominant real TCA id (recount: 6/8); `Int`/`String` are
    /// cheap and folded in even though the recount found no real use.
    static let defaultableIDTypes: Set<String> = ["UUID", "Int", "String"]

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
                  defaultableIDTypes.contains(idType),
                  let freeCase = child.actionCases.first(where: \.payloadTypes.isEmpty)
            else { return caseInfo }
            changed = true
            return ActionCaseInfo(
                name: caseInfo.name,
                payloadTypes: caseInfo.payloadTypes,
                resolvedElement: ResolvedIdentifiedElement(
                    idType: idType,
                    childActionType: child.actionTypeName,
                    childActionCase: freeCase.name
                )
            )
        }
        guard changed else { return candidate }
        return candidate.replacingActionCases(newCases)
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
