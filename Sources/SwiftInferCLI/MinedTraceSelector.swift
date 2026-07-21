import SwiftInferCore
import SwiftInferTestLifter

/// TestStore Trace Mining (Slice 2) — turns raw mined `MinedActionTrace`s
/// into the payload-free case-name sequences the verifier can replay for a
/// given reducer candidate. The filtering here is what keeps the emitted
/// `let minedTraces: [[Action]] = …` literals **compilable**, so it is
/// deliberately strict:
///
///   1. **Carrier gate — `.tca` only (for now).** Selection needs the
///      candidate's Action alphabet to validate case names, and that alphabet
///      (`actionCases`) is captured at discovery for `.tca` carriers only.
///      Generic / Elm carriers don't carry it yet, so they get no mined traces
///      (a stale name would otherwise fail the verifier *build*). Widening to
///      generic carriers is a follow-up (capture the CaseIterable alphabet at
///      discovery) — see `docs/teststore-trace-mining-build-plan.md` Slice 3.
///   2. **Reducer join.** Keep only traces whose `reducerTypeName` matches the
///      candidate's `enclosingTypeName` (a nil-reducer bare-`store` fallback
///      trace never joins — it can't be attributed to a specific reducer).
///   3. **Payload-free only.** A payload-bearing action's args reference
///      test-body-local bindings the standalone verifier can't reconstruct
///      (build-plan §3); those traces are dropped whole.
///   4. **Stale-case guard.** Every case name must be in the candidate's
///      current Action alphabet; a renamed/removed case drops the trace (the
///      host suite is self-validating, but discovery and the tests can drift).
///   5. **Non-empty.** An empty `sent` list yields nothing to replay.
enum MinedTraceSelector {

    static func payloadFreeSeedTraces(
        from traces: [MinedActionTrace],
        candidate: ReducerCandidate
    ) -> [[String]] {
        guard candidate.carrierKind == .tca,
              let enclosing = candidate.enclosingTypeName else {
            return []
        }
        let alphabet = Set(candidate.actionCases.map(\.name))
        return traces.compactMap { trace -> [String]? in
            guard trace.reducerTypeName == enclosing else {
                return nil
            }
            let names = trace.sent.map(\.caseName)
            guard !names.isEmpty,
                  trace.sent.allSatisfy(\.isPayloadFree),
                  names.allSatisfy(alphabet.contains) else {
                return nil
            }
            return names
        }
    }
}
