import SwiftEffectInference

/// Phase 0 adapters: lift the two existing candidate types onto the unified
/// `StatefulRole`. These prove the isomorphism the `StatefulRoleDiscoverer`
/// design rests on, and let Phase 1 reimplement the discoverers behind the
/// `RolePolicy` seam while keeping the existing `Codable` candidate types (and
/// their persisted wire shapes) untouched.

public extension ViewModelCandidate {

    /// This MVVM view model as a `StatefulRole`. The mapping is direct — the
    /// view model is already modelled as a "reducer-in-disguise" (State ↔
    /// stored fields, Action ↔ mutating methods).
    func asStatefulRole() -> StatefulRole {
        StatefulRole(
            location: location,
            typeName: typeName,
            paradigm: .mvvm,
            recognizedBy: observability == .observableMacro ? .macro : .conformance,
            state: .storedFields(stateFields.map {
                RoleStateField(name: $0.name, typeText: $0.typeText, isMutable: $0.isMutable)
            }),
            actions: actions.map {
                RoleAction(
                    name: $0.name,
                    parameterTypes: $0.parameterTypes,
                    firstParameterLabel: $0.firstParameterLabel,
                    isAsync: $0.isAsync,
                    isThrows: $0.isThrows,
                    mutatesStateDirectly: $0.mutatesStateDirectly
                )
            },
            // A view model is always an instance you build (injecting fakes for
            // protocol dependencies); the recording-output-fake distinction
            // (`Collaborator`) is a Phase 2 capability, so none are surfaced here.
            construction: .instance(
                initParameters: initParameters.map {
                    RoleInitParameter(label: $0.label, typeText: $0.typeText)
                },
                fakedCollaborators: []
            ),
            collaborators: [],
            // The existing candidate carries no purity classification; a future
            // MVVMPolicy would run SoundPurity here.
            effect: nil
        )
    }
}

public extension ReducerCandidate {

    /// This reducer as a `StatefulRole`. `carrierKind` already distinguishes the
    /// reducer families, so the paradigm maps faithfully: TCA stays `.tca`;
    /// Elm / ReSwift / Mobius / Workflow fold into the `.redux` family at this
    /// granularity (the finer `carrierKind` is retained on the candidate).
    func asStatefulRole() -> StatefulRole {
        StatefulRole(
            location: location,
            typeName: enclosingTypeName ?? functionName,
            paradigm: Self.paradigm(for: carrierKind),
            // The candidate doesn't record its exact recognition path; TCA is
            // conformance/macro-driven, the rest are signature-shape matches.
            recognizedBy: carrierKind == .tca ? .conformance : .signatureShape,
            state: .namedType(stateTypeName),
            // A reducer's Action enum cases are its action alphabet — each case
            // is, by definition, a direct state mutation.
            actions: actionCases.map {
                RoleAction(name: $0.name, parameterTypes: $0.payloadTypes, mutatesStateDirectly: true)
            },
            // A reducer is fundamentally a function `(S, A) -> S` the harness
            // calls directly. (TCA-conformance reducers are still driven through
            // their reduce function; refining that to an instance carrier is a
            // Phase 1 concern.)
            construction: .freeFunction(name: functionName),
            collaborators: [],
            effect: Self.effect(for: purity)
        )
    }

    private static func paradigm(for carrier: ReducerCarrierKind) -> Paradigm {
        switch carrier {
        case .tca: return .tca
        case .elmStyle, .reSwift, .mobius, .workflow, .generic: return .redux
        }
    }

    /// Sound projection of `ReducerPurity` onto the SEI `Effect` lattice. The
    /// negative cases are sound over-approximations; `.pure` maps to `nil`
    /// (unknown), NOT `Effect.pure` — `ReducerPurity.pure` only rules out TCA
    /// effects and hidden mutation, not I/O / nondeterminism / partiality, so
    /// claiming `Effect.pure` from it alone would be unsound. Establishing
    /// `.pure` requires `SoundPurity` (the meet with `PurityInferrer`).
    private static func effect(for purity: ReducerPurity) -> Effect? {
        switch purity {
        case .effectBearing, .hiddenMutability: return .nonIdempotent
        case .pure: return nil
        }
    }
}
