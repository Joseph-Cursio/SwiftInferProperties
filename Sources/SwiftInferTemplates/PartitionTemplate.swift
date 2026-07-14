import Foundation
import SwiftInferCore

/// The **partition / tiling** law: the parts must reconstitute the whole.
///
/// This template exists because of a number: on a real iOS app the pipeline returned **six
/// suggestions and zero refutable claims**. All six were determinism laws — `f(x) == f(x)` — which a
/// pure function satisfies by definition and which therefore cannot fail for any reason having to do
/// with what the function computes. Six suggestions; nothing that could ever go red; none of the
/// app's three known bugs found.
///
/// The diagnosis is that **purity is a licence, not a hypothesis.** Knowing a function is pure says
/// it *may* be property-tested; it says nothing about what should be *true* of it. Ask a tool that
/// knows only "this is pure" for a law and the only law it can honestly give you is the definition of
/// purity. **Falsifiable laws come from a function's role** — and a role is what a template encodes.
/// That is why this catalogue is load-bearing rather than decorative: it is the only mechanism in the
/// pipeline that can produce a law capable of failing.
///
/// So every law below is stated to *reject implementations*. Each one names a plausible, type-correct
/// chunker that it throws out — because a law that rejects nothing is a tautology wearing a template's
/// clothes.
public enum PartitionTemplate {

    public static func suggest(for shape: PartitionShape) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: shape)
    }

    public static func makeConstraint() -> Constraint<PartitionShape> {
        Constraint<PartitionShape>(
            templateName: "partition",
            appliesTo: { _ in true },
            signals: Self.accumulatedSignals(for:),
            evidence: { shape in
                var evidence = [shape.tiler.inferenceEvidence]
                if let progress = shape.progress {
                    evidence.append(progress.inferenceEvidence)
                }
                return evidence
            },
            identity: Self.makeIdentity(for:),
            carrier: { $0.typeName },
            carrierType: { $0.typeName },
            caveats: Self.makeCaveats(for:)
        )
    }

    static func accumulatedSignals(for shape: PartitionShape) -> [Signal] {
        let evidence: String
        switch shape.tilerForm {
        case .range:
            evidence = "`\(shape.tiler.name)` maps a part index to a range of the whole — that is a "
                + "partition, and its parts must tile the whole exactly"

        case .slice:
            evidence = "`\(shape.tiler.name)` takes the whole and a part index and returns a part of "
                + "it — that is a partition, and its parts must reassemble the whole exactly"
        }

        var signals: [Signal] = [
            Signal(kind: .indexToRangeSignature, weight: 40, detail: evidence)
        ]

        if let progress = shape.progress {
            signals.append(
                Signal(
                    kind: .progressFractionSignature,
                    weight: 20,
                    detail: "`\(progress.name)` reports a fraction over the same index domain — it "
                        + "must be monotonic, stay within 0...1, and terminate at 1.0"
                )
            )
        }

        return signals
    }

    /// The laws — each stated as *what it rejects*, because a law that rejects nothing is a
    /// tautology, and a tautology is what this template exists to replace.
    static func makeCaveats(for shape: PartitionShape) -> [String] {
        // The tiling law and the totality law both read differently depending on what the tiler hands
        // back. Stating a *range* law at a function that returns bytes would send the reader looking
        // for upper bounds it does not have — a law the reader cannot encode is worse than silence.
        let tiling: String
        let totality: String
        switch shape.tilerForm {
        case .range:
            tiling = "The tiling law is: consecutive parts abut and never overlap — part `i`'s upper "
                + "bound is part `i+1`'s lower bound — and together they cover the whole exactly. It "
                + "rejects an off-by-one in the last part, a chunker that drops the remainder, and "
                + "one that double-counts a boundary byte."
            totality = "TOTALITY: an index outside the valid range must yield an empty range, not a "
                + "trap. It rejects the `dropFirst(negative)` family, which crashes rather than "
                + "returning nothing — and a negative index is exactly what a corrupt server counter "
                + "supplies."

        case .slice:
            tiling = "The tiling law is: CONCATENATING the parts, in index order, reproduces the "
                + "whole EXACTLY — same bytes, same length, nothing dropped and nothing repeated. "
                + "Assert on the join, not on each part: a chunker that drops the remainder and one "
                + "that double-counts a boundary byte both produce parts that look individually "
                + "plausible, and only the join tells you."
            totality = "TOTALITY: an index outside the valid range must yield an EMPTY part, not a "
                + "trap. Generate negative indices and indices past the end **on purpose** — this is "
                + "the clause that rejects the `dropFirst(negative)` family, which crashes rather "
                + "than returning nothing, and a negative index is exactly what a corrupt server "
                + "counter supplies."
        }

        var caveats: [String] = [
            tiling,
            totality,
            "The part count must be `ceil(whole / partSize)` — not `whole / partSize`, which silently "
                + "drops a trailing partial part, and not `whole / partSize + 1`, which invents an "
                + "empty one when the division is exact."
        ]

        if shape.progress != nil {
            caveats.append(
                "PROGRESS TERMINATES AT 1.0, *including for an empty whole*. Name the empty case "
                    + "explicitly: a general 'monotonic and ends at 1.0' property passes VACUOUSLY on "
                    + "an empty input, because its sample array is empty and there is no last element "
                    + "to check. A boundary case still has to be named, even under PBT — this is the "
                    + "law that catches a progress bar that hangs forever on a zero-byte upload."
            )
            caveats.append(
                "Progress must stay within `0.0...1.0`. It rejects a fraction computed against a "
                    + "declared size the whole then exceeds — an over-sending server drives it above "
                    + "1.0."
            )
        }

        caveats.append(
            "A partition over a resumable index needs its start CLAMPED to `0...count`. An unclamped "
                + "value from outside — a server's resume counter, say — either traps (negative) or "
                + "silently reports the work complete (too large). The law quantifies over the whole "
                + "integer range on purpose, because that value is not yours to trust."
        )

        return caveats
    }

    static func makeIdentity(for shape: PartitionShape) -> SuggestionIdentity {
        SuggestionIdentity(canonicalInput: "partition|\(shape.typeName)|\(shape.tiler.name)")
    }
}
