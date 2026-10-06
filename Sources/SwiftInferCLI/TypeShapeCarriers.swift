import Foundation
import SwiftInferCore

/// The three type-shape carrier scans `discover-reducers` appends, over one directory.
///
/// Built together because all three scan the same `directory` through
/// `FunctionScanner.scanCorpus(directory:)`, and since construction facts were wired in each
/// scan builds its project's purity first — parsing the whole construction universe. One
/// `PackagePurity` for the three is the same answer at a third of the parse.
struct TypeShapeCarriers {
    /// PROTOTYPE — value-semantics carriers: structs holding reference-backed storage (a
    /// closure / mutable container / corpus class), through which a "value" can leak shared
    /// mutable state. Recognition only (slice 2): no invariant is emitted yet — see
    /// docs/archive/valuesemantic-build-plan.md.
    let valueSemantics: [ValueSemanticCandidate]
    /// PROTOTYPE — defensive-copy carriers: classes that vend a copy()/clone() (Ch. 9 §9.3).
    /// Recognition only.
    let defensiveCopies: [DefensiveCopyCandidate]
    /// PROTOTYPE — identity-stability carriers: Hashable classes whose == / hash may read
    /// mutable state (Ch. 9 §9.3.3).
    let stableIdentities: [StableIdentityCandidate]

    init(directory: URL) throws {
        let purity = PackagePurity.forScan(of: directory)
        valueSemantics = try ValueSemanticDiscoverer.discover(directory: directory, purity: purity)
        defensiveCopies = try DefensiveCopyDiscoverer.discover(directory: directory, purity: purity)
        stableIdentities = try StableIdentityDiscoverer.discover(directory: directory, purity: purity)
    }
}
