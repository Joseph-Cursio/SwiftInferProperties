import SwiftInferCore

/// TestLifter — PRD §7 Contribution 2. Analyzes existing XCTest +
/// Swift Testing suites and emits property-test suggestions derived
/// from the test-body slice (PRD §7.2).
///
/// **M1.0 scaffolding shell.** This file declares the public namespace
/// and the M1 milestone surface. The actual `discover(in:)` entry point
/// lands in M1.5, after the parser (M1.1), slicer (M1.2), detector
/// (M1.3), and identity hashing (M1.4) sub-milestones build out the
/// implementation. M1's user-visible deliverable is the +20 PRD §4.1
/// cross-validation signal lighting up — TestLifter feeds the identity
/// set into TemplateEngine's existing `crossValidationFromTestLifter`
/// parameter (the M3.5 dormant seam).
///
/// See `docs/TestLifter M1 Plan.md` for the full sub-milestone breakdown.
public enum TestLifter {
}
