import SwiftInferCore

/// Replay-idempotency accept-flow emission for `ReplayIdempotenceTemplate`.
///
/// Split from `LiftedTestEmitter.swift` (which is at the file-length cap) and,
/// more to the point, structurally different from every other arm there: those
/// emit a runnable value law over a generator (`SwiftPropertyBasedBackend.check`).
/// Replay-idempotency has no such law — the property is over *effects*, and the
/// effect boundary (a recorder observing the real side effect) can only be
/// supplied by the author. So this emits a **scaffold**: a `@Test func` that names
/// the handler, shows the `assertIdempotentEffects` shape, and *fails* (via
/// `Issue.record`) until completed — never a silent green.
extension LiftedTestEmitter {

    /// Emit a replay-idempotency scaffold for a side-effecting handler.
    ///
    /// - Parameters:
    ///   - funcName: the handler's simple name.
    ///   - keyLabel: the `IdempotencyKey` parameter's label, when one is present;
    ///     `nil` for an annotation-only match, which gets a generic key comment.
    ///   - ownerType: the enclosing type, used to qualify the call in the comment.
    ///   - isAsync / isThrows: reassembled onto the commented call as `await` / `try`.
    ///
    /// The emitted decl requires `import Testing`, `import SwiftIdempotency`, and
    /// `import SwiftIdempotencyTestSupport` at file scope — noted in the header
    /// comment so the reader wires them up when completing the scaffold.
    public static func replayIdempotent(
        funcName: String,
        keyLabel: String?,
        ownerType: String?,
        isAsync: Bool,
        isThrows: Bool
    ) -> String {
        let testFunctionName = "\(funcName)_isReplayIdempotent"
        let effectPrefix = replayEffectPrefix(isAsync: isAsync, isThrows: isThrows)
        let ownerCall = ownerType.map { "\($0)." } ?? ""
        let keyComment = keyLabel.map {
            "    //   let \($0) = IdempotencyKey(fromAuditedString: \"fixture-key\")  "
                + "// held constant across both runs"
        } ?? "    //   let key = IdempotencyKey(fromAuditedString: \"fixture-key\")  "
            + "// a STABLE key, held constant"
        let todo = "TODO: complete the replay-idempotency scaffold for \(funcName) — "
            + "inject an IdempotentEffectRecorder and assert effects are idempotent "
            + "under a fixed IdempotencyKey"

        return """

        // Replay-idempotency scaffold for `\(funcName)` — complete the two TODOs.
        // The property is over EFFECTS: running the handler twice under the same key
        // must leave the observable effects unchanged. swift-infer cannot synthesize
        // the effect boundary, so this is a scaffold, not a runnable test — it fails
        // (via Issue.record) until you complete it. Requires: import Testing,
        // import SwiftIdempotency, import SwiftIdempotencyTestSupport.
        @Test func \(testFunctionName)() async throws {
            // TODO 1: inject a recorder conforming to `IdempotentEffectRecorder`
            //         that observes this handler's real effect (DB write / network / queue):
            //   let recorder = <YourEffectRecorder>()
            // TODO 2: build the fixed inputs (key held constant) and assert:
        \(keyComment)
            //   try await assertIdempotentEffects(recorders: [recorder]) {
            //       _ = \(effectPrefix)\(ownerCall)\(funcName)(…)
            //   }
            Issue.record("\(todo)")
        }
        """
    }

    /// The `try `/`await ` prefix (in Swift order) for the commented call, or `""`.
    static func replayEffectPrefix(isAsync: Bool, isThrows: Bool) -> String {
        var parts: [String] = []
        if isThrows { parts.append("try") }
        if isAsync { parts.append("await") }
        return parts.isEmpty ? "" : parts.joined(separator: " ") + " "
    }

    /// Emit a key-stability scaffold for a key-from-entity builder (M6). Unlike the
    /// gate scaffold this is the **value** form: the handler is a pure builder, so
    /// the property is that the built value (and its `IdempotencyKey`) is identical
    /// across invocations — `#assertIdempotent`, not `assertIdempotentEffects`. Still
    /// a scaffold: swift-infer can't synthesize the input entity, so it fails via
    /// `Issue.record` until completed. Requires `import Testing`, `import SwiftIdempotency`.
    public static func replayKeyBuilder(
        funcName: String,
        ownerType: String?,
        isThrows: Bool
    ) -> String {
        let testFunctionName = "\(funcName)_buildsAStableKey"
        let ownerCall = ownerType.map { "\($0)." } ?? ""
        let tryPrefix = isThrows ? "try " : ""
        let todo = "TODO: complete the key-stability scaffold for \(funcName) — build a "
            + "fixed input entity and assert #assertIdempotent over it"

        return """

        // Key-stability scaffold for `\(funcName)` — completes the one TODO.
        // The handler derives an IdempotencyKey from its input; the property is that
        // the built value is STABLE across invocations. A key derived from
        // UUID()/Date() instead of the entity's stable id would break it. This is a
        // scaffold (the input entity can't be synthesized) — it fails until completed.
        // Requires: import Testing, import SwiftIdempotency.
        @Test func \(testFunctionName)() throws {
            // TODO: build a fixed input entity, held constant, then assert:
            //   let entity = <FixedEntity>()
            //   #assertIdempotent { \(tryPrefix)\(ownerCall)\(funcName)(entity) }
            Issue.record("\(todo)")
        }
        """
    }
}
