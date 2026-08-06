import Foundation
import SwiftInferCore

/// Reporting for seeds that name work a human must do before any tool can help — extractable
/// kernels, and seeds whose `kind` this build cannot read.
///
/// Split out of `Discover+Seeds.swift` to keep that file inside the `file_length` cap; no
/// behaviour change from the move.
extension SwiftInferCommand.Discover {

    /// Whether a seed's file was part of this scan.
    ///
    /// Seed paths are written relative to the linter's working directory while scanned paths are
    /// absolute, so the test is a path-component-aligned suffix match. Matching on the bare
    /// basename would collide across targets — this project has three files named
    /// `SuppressionVisitorBase.swift`-alike and several `Support/` twins — and matching on
    /// equality would never fire at all.
    static func inScope(_ seed: SeedManifest.Seed, scannedFiles: Set<String>) -> Bool {
        scannedFiles.contains { scanned in
            scanned == seed.file || scanned.hasSuffix("/" + seed.file)
        }
    }

    /// Announce the seeds that name pure logic with **no name yet**.
    ///
    /// This is the whole reason `kind` exists. A kernel cannot be focused on — its symbol is the
    /// impure method the logic is trapped inside, so narrowing to it would make this tool refuse the
    /// function and report `kept 0` for code that demonstrably has property-testable logic in it.
    /// Silently skipping them would be no better: the reader would see a smaller number and no
    /// reason for it.
    ///
    /// So they are neither focused on nor dropped. They are *named*, with the one instruction that
    /// unblocks them.
    ///
    /// **Scoped to what was actually scanned.** A manifest is written for a whole project while a
    /// `discover` run covers one target, so an unscoped listing names kernels the reader cannot act
    /// on from here — measured on SwiftProjectLint as a byte-identical 204-line block emitted for
    /// four different `--sources` values, naming all seven packages every time. The rest of the
    /// focus reporting already scopes correctly; this block did not.
    ///
    /// When the manifest holds kernels but none are in scope, that is *said* rather than shown as
    /// silence — a listing that vanishes reads as "no kernels here", which is a different claim
    /// and usually a false one.
    static func reportRefactorPending(
        in seedManifest: SeedManifest,
        scannedFiles: Set<String>,
        diagnostics: any DiagnosticOutput
    ) {
        let pending = seedManifest.refactorPendingSeeds
        guard !pending.isEmpty else { return }

        // Only the kernel listing scopes. It names a LOCATION — work to do in a specific file —
        // and a location in a target you are not scanning is not work you can do from here.
        let allKernels = pending.filter { $0.kind == .extractableKernel }
        let kernels = allKernels.filter { inScope($0, scannedFiles: scannedFiles) }

        // The unrecognised-kind warning does NOT scope, and the distinction is the point: it says
        // *this build cannot read the manifest*, which is a statement about tool versions rather
        // than about a place in the code. A manifest carrying a kind this binary does not know is
        // equally wrong whichever target the seed points at, and silencing it because the file
        // happens to sit elsewhere would hide a version skew behind a scoping rule.
        let unknown = pending.filter { seed in
            if case .unrecognised = seed.kind { return true }
            return false
        }

        if kernels.isEmpty, !allKernels.isEmpty {
            diagnostics.writeDiagnostic(
                "note: the manifest names \(allKernels.count) extractable kernel(s), none of them "
                    + "under the scanned sources. They belong to other targets; re-run `discover` "
                    + "there to see them."
            )
        }

        if !kernels.isEmpty {
            diagnostics.writeDiagnostic(
                "\(kernels.count) extractable kernel(s) — pure logic with no name yet, so there is "
                    + "nothing here to index, call, or generate inputs for. No law can be proposed "
                    + "until a human draws the boundary:"
            )
            for seed in prioritised(kernels) {
                diagnostics.writeDiagnostic(listing(seed))
            }
        }

        // The rule is named because this warning is about a **version skew**, and the rule is the
        // only field that says where the skew is. "kind 'x' is unrecognised" tells a reader to
        // upgrade; "rule `Pure Closure Property-Test Candidate` emitted kind 'x'" tells them which
        // half of the producer moved, which is the difference between an upgrade and a bug report.
        //
        // This is the first thing in this repo ever to read `rule`. It was decoded and stored from
        // the day the field existed and consulted by nothing — optional on this side, non-optional
        // on the producer's, and documented as "attribution in warnings" while no warning attributed
        // anything.
        for seed in unknown {
            diagnostics.writeDiagnostic(
                "warning: seed `\(seed.symbol)` (\(seed.file):\(seed.line)), from rule "
                    + "`\(seed.rule)`, has kind '\(seed.kind.rawValue)', which this build does not "
                    + "recognise. It was NOT focused on: narrowing to a symbol whose meaning is "
                    + "unknown is how a tool ends up reporting a confident zero. Upgrade "
                    + "swift-infer, or re-run without --seeds."
            )
        }
    }

    /// Kernels whose role **entails** a law come first.
    ///
    /// Extraction is work, and this listing is the only place the tool can say which of it pays. A
    /// `comparator` or a `predicate` owes a law that a correct implementation cannot fail, so
    /// extracting one has a guaranteed payoff. A `transform` might yield nothing but a shape.
    /// Ordering by that turns a flat list of chores into a ranked one.
    ///
    /// Stable within each group — the two filters preserve input order — so the block stays
    /// byte-comparable between runs, which the scoping tests rely on.
    static func prioritised(_ kernels: [SeedManifest.Seed]) -> [SeedManifest.Seed] {
        kernels.filter { $0.role?.entailedTemplateName != nil }
            + kernels.filter { $0.role?.entailedTemplateName == nil }
    }

    /// One kernel line: where it is, what it is, and what extracting it buys.
    ///
    /// The role is the whole product of carrying it. A kernel can never be analysed — there is no
    /// name to call — so "a comparator, which owes a strict weak ordering" is the only thing
    /// separating this line from a bare location.
    ///
    /// For an entailed role the line goes further and names the template, because that is a promise
    /// the tool can keep: `ComparatorTemplate`, `PredicateTemplate` and `PartitionTemplate` all
    /// exist, and "entailed" is precisely the claim that a correct implementation cannot fail the
    /// law they propose. Saying it for a conjectured role would be selling a maybe as a guarantee.
    static func listing(_ seed: SeedManifest.Seed) -> String {
        var line = "  \(seed.file):\(seed.line): inside `\(seed.symbol)` — extract it into a "
            + "named value type, then re-run the linter to seed it properly."
        if let law = seed.role?.lawSentence {
            line += " It is \(law)."
        }
        if let template = seed.role?.entailedTemplateName {
            line += " Extracting it PAYS: `discover` will then propose the `\(template)` law, "
                + "which a correct implementation cannot fail."
        }
        return line
    }
}
