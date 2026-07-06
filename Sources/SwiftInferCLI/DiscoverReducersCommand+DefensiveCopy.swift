import SwiftInferCore

// Defensive-copy render section for `discover-reducers`, in an extension so the
// primary `DiscoverReducers` body stays under the type_body_length / file_length
// caps (cycle-145 precedent). Same-file/extension statics reach the pipeline.
extension SwiftInferCommand.DiscoverReducers {

    /// PROTOTYPE — renders defensive-copy carriers: classes that vend a
    /// `copy()`/`clone()` (Ch. 9 §9.3). One block per class: location + an
    /// Equatability note when not verify-ready, the copy method, and the
    /// mutation surface. Recognition only — no invariant emitted.
    static func renderDefensiveCopySummary(_ candidates: [DefensiveCopyCandidate]) -> String {
        if candidates.isEmpty {
            return "swift-infer discover-reducers: no defensive-copy carriers detected.\n"
        }
        let suffix = candidates.count == 1 ? "" : "s"
        var lines: [String] = [
            "swift-infer discover-reducers — detected \(candidates.count) "
                + "defensive-copy carrier\(suffix) (classes with a copy()/clone()):",
            ""
        ]
        for candidate in candidates {
            lines.append(contentsOf: renderDefensiveCopy(candidate))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func renderDefensiveCopy(_ candidate: DefensiveCopyCandidate) -> [String] {
        let note = candidate.equatability == .equatable
            ? "" : "  [not verify-ready: \(candidate.equatability)]"
        let origin = "\(candidate.location.file):\(candidate.location.line)"
        let surface = candidate.mutationSurface.map(\.name).joined(separator: ", ")
        return [
            "  \(origin)  \(candidate.typeName)\(note)",
            "    copy method: \(candidate.copyMethodName)()",
            "    mutation surface (\(candidate.mutationSurface.count)): \(surface)"
        ]
    }
}
