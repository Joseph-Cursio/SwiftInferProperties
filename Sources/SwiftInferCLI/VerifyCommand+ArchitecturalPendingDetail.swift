import Foundation
import SwiftInferCore

/// V1.89 lint pass — extracted from
/// `VerifyCommand+AllFromIndex.swift` so the main file stays under
/// SwiftLint's 400-line cap. Houses the build-output classifier that
/// reclassifies `.measuredError` build failures into specific
/// `.architecturalCoveragePending` categories.
extension SwiftInferCommand.Verify {

    /// V1.56.A — reclassify build failures whose cause is a known
    /// architectural-coverage-pending category, returning a short
    /// detail string suitable for the SurveyRecord. Returns `nil` when
    /// the build failure doesn't match any known category — caller
    /// keeps the v1.52 `.measured-error` classification.
    ///
    /// **Currently recognized**:
    ///   - `is inaccessible due to '<access-level>'` → `"internal-api-not-accessible"`.
    ///     Cycle-52 surfaced 2 `Complex.rescaledDivide(_:_:)` picks
    ///     declared `internal` in swift-numerics. Accessibility is a
    ///     measurement-tooling gap (fix: skip non-public symbols at
    ///     indexer time, or `@testable import` in the workdir), not a
    ///     verifier-architecture gap.
    ///   - `instance member ... cannot be used on type` →
    ///     `"instance-method-shape-not-supported"`. V1.59.A surfaced
    ///     23 OS picks that compile-fail because the resolver builds
    ///     `OrderedSet.sort(value)` (static call) but `sort()` is an
    ///     instance method. **Much of this is now emitted directly**:
    ///     idempotence (nullary mutating-void + self-returning + lifted,
    ///     V1.60.A), commutativity/associativity (binary instance ops,
    ///     via `receiverCallExpression`'s `{ $0.method(with: $1) }`
    ///     shape), and self-inverse round-trips all emit the receiver
    ///     form. The classifier still fires for the shapes not yet
    ///     routed to a receiver emit — non-nullary *direct* (unlifted)
    ///     idempotence instance methods, monotonicity / dual-style
    ///     instance methods, and mixed round-trip pairs (instance
    ///     forward + non-instance inverse) — which remain pending.
    ///
    /// **Why both streams**: `swift build` formats compiler diagnostics
    /// to stdout (parent-process-readable) and emits SwiftPM-level
    /// errors to stderr. Cycle-53 measurement (`docs/calibration-
    /// cycle-53-findings.md`) confirmed the "inaccessible due to"
    /// message lands on stdout; checking both makes the pattern robust
    /// against SwiftPM future-version changes.
    ///
    /// **Extension point**: v1.60+ may add more patterns (e.g. for
    /// `@_spi` symbols, ambiguous overloads, etc.) as cycle-N evidence
    /// motivates.
    static func architecturalPendingDetail(
        buildStdout: String,
        buildStderr: String
    ) -> String? {
        if buildStdout.contains("is inaccessible due to '")
            || buildStderr.contains("is inaccessible due to '") {
            return "internal-api-not-accessible"
        }
        if matchesInstanceMethodShape(stdout: buildStdout, stderr: buildStderr) {
            return "instance-method-shape-not-supported"
        }
        if matchesCarrierConformanceGap(stdout: buildStdout, stderr: buildStderr) {
            return "carrier-missing-required-conformance"
        }
        return nil
    }

    /// V1.59.A — recognize instance-method-on-type errors. Three
    /// related Swift compiler diagnostics for the same root cause
    /// (synthesized stub calls `<Type>.<method>(value)` static shape
    /// but `<method>` is an instance method). The idempotence /
    /// commutativity / associativity / self-inverse-round-trip shapes
    /// now emit the receiver form, so these diagnostics only surface for
    /// the still-static shapes (see `architecturalPendingDetail`); the
    /// classifier stays as their guard.
    ///
    /// **(a)** `instance member ... cannot be used on type` — the
    ///         canonical diagnostic.
    /// **(b)** `no exact matches in call to instance method` — Swift
    ///         emits this when there's an instance method matching
    ///         the name but no static overload.
    /// **(c)** `compile command failed due to signal` (typically
    ///         signal 6 = SIGABRT) — swift-frontend CRASH on the
    ///         static-call-of-instance-mutating-method shape. Empirical
    ///         in cycle-56 on OS picks like `_ensureUnique()`,
    ///         `_isUnique()`, `_regenerateHashTable()`. The compiler
    ///         bails before emitting a structured diagnostic, but
    ///         the underlying cause is the same instance-method-shape
    ///         gap. Match conservatively — only when the
    ///         `emit-module` or `compile command` strings appear
    ///         alongside `signal`, not on arbitrary signal mentions.
    ///
    /// V1.63.A — `generic parameter '<X>' could not be inferred` is
    /// the diagnostic Swift produces when a static-call-shape on a
    /// nested generic type can't resolve type arguments. Same
    /// architectural category as the other instance-method-shape errors.
    /// Protocol-carrier variant — static-calling an instance method whose
    /// carrier is a *protocol* (e.g. `StringProtocol.addingIntercappedPrefix(x)`)
    /// does not produce the concrete-type `"cannot be used on type"` diagnostic.
    /// An instance method is not a static member of the existential metatype, so
    /// Swift reports `type 'any StringProtocol' has no member
    /// 'addingIntercappedPrefix'` — the `"type 'any …'"` + `"has no member"`
    /// pairing is the tell (requiring both keeps it off ordinary
    /// missing-member typos on concrete types). Same root cause as the other
    /// cases (an instance method emitted in the static `Type.method(x)` shape),
    /// fixed by the same v1.60+ instance-method emission. Surfaced dogfooding
    /// swift-argument-parser's internal `StringProtocol` picks
    /// (`addingIntercappedPrefix`, `editDistance(to:)`).
    private static func matchesInstanceMethodShape(stdout: String, stderr: String) -> Bool {
        let instanceMemberOnType = "cannot be used on type"
        let noExactMatchesInstance = "no exact matches in call to instance method"
        let cannotInferGenericParam = "could not be inferred"
        let compileCrashOnSignal =
            (stdout.contains("compile command failed due to signal")
                || stdout.contains("emit-module command failed due to signal"))
        let stderrCrashOnSignal =
            (stderr.contains("compile command failed due to signal")
                || stderr.contains("emit-module command failed due to signal"))
        let stdoutInstanceMember =
            (stdout.contains("instance member") && stdout.contains(instanceMemberOnType))
            || stdout.contains(noExactMatchesInstance)
            || (stdout.contains("generic parameter") && stdout.contains(cannotInferGenericParam))
            || (stdout.contains("type 'any ") && stdout.contains("has no member"))
            || compileCrashOnSignal
        let stderrInstanceMember =
            (stderr.contains("instance member") && stderr.contains(instanceMemberOnType))
            || stderr.contains(noExactMatchesInstance)
            || (stderr.contains("generic parameter") && stderr.contains(cannotInferGenericParam))
            || (stderr.contains("type 'any ") && stderr.contains("has no member"))
            || stderrCrashOnSignal
        return stdoutInstanceMember || stderrInstanceMember
    }

    /// V1.59.A — monotonicity picks on non-Comparable carriers hit
    /// `global function 'min' requires that '<Carrier>' conform to
    /// 'Comparable'` — the monotonicity stub uses `min`/`max` to order
    /// the two trial values. v1.61+ may add a Comparable-aware
    /// monotonicity composer or a different ordering strategy.
    private static func matchesCarrierConformanceGap(stdout: String, stderr: String) -> Bool {
        let requiresConformance = "requires that"
        let conformTo = "conform to"
        let stdoutConformance =
            stdout.contains(requiresConformance) && stdout.contains(conformTo)
        let stderrConformance =
            stderr.contains(requiresConformance) && stderr.contains(conformTo)
        return stdoutConformance || stderrConformance
    }
}
