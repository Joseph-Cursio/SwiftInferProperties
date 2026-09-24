import PropertyLawCore
import SwiftInferCore

/// Marks each instance-method row whose declaring type is an actor, so every writer reaches the
/// subject with `await` (`CalleeReference.actorReceiverIsolation`).
///
/// Applied in the accept path, ahead of holding a receiver, because the scan records a global
/// actor but not that the enclosing type is one: an actor's methods are isolated to the instance
/// they are called on. A `nonisolated` member and a static one are not, and are left alone.
enum ActorReceiver {

    static func marking(_ suggestion: Suggestion, actorTypeNames: Set<String>) -> Suggestion {
        guard !actorTypeNames.isEmpty else { return suggestion }
        var copy = suggestion
        copy.evidence = suggestion.evidence.map { row in
            guard row.isInstanceMethod, row.globalActor == nil, !row.declaresNonisolated,
                  let owner = row.qualifiedTypeName, actorTypeNames.contains(owner)
            else { return row }
            return row.withGlobalActor(CalleeReference.actorReceiverIsolation)
        }
        return copy
    }

    /// The names the accept path's scanned shapes declare as actors, under both the key and the
    /// shape's own name, since either is how an evidence row may spell its owner.
    static func actorTypeNames(in shapes: [String: TypeShape]) -> Set<String> {
        shapes.reduce(into: Set<String>()) { names, entry in
            guard entry.value.kind == .actor else { return }
            names.insert(entry.key)
            names.insert(entry.value.name)
        }
    }
}
