import SwiftInferCore

// Identity-stability render section for `discover-reducers`, in an extension so
// the primary `DiscoverReducers` body stays under the length caps (cycle-145
// precedent).
extension SwiftInferCommand.DiscoverReducers {

    /// PROTOTYPE — renders identity-stability carriers: `Hashable` classes whose
    /// `==` / `hash` may read mutable state (Ch. 9 §9.3.3). One block per class:
    /// location + mutation surface. Recognition only — the verifier confirms
    /// whether a mutation actually disturbs the identity.
    static func renderStableIdentitySummary(_ candidates: [StableIdentityCandidate]) -> String {
        if candidates.isEmpty {
            return "swift-infer discover-reducers: no identity-stability carriers detected.\n"
        }
        let suffix = candidates.count == 1 ? "" : "s"
        var lines: [String] = [
            "swift-infer discover-reducers — detected \(candidates.count) "
                + "identity-stability carrier\(suffix) (mutable Hashable classes):",
            ""
        ]
        for candidate in candidates {
            lines.append(contentsOf: renderStableIdentity(candidate))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func renderStableIdentity(_ candidate: StableIdentityCandidate) -> [String] {
        let origin = "\(candidate.location.file):\(candidate.location.line)"
        let surface = candidate.mutationSurface.map(\.name).joined(separator: ", ")
        return [
            "  \(origin)  \(candidate.typeName)",
            "    mutation surface (\(candidate.mutationSurface.count)): \(surface)"
        ]
    }
}
