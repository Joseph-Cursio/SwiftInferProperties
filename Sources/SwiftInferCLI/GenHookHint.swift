import Foundation

/// V1.150 — the one-line, user-facing pointer at the `static func gen()`
/// escape hatch, surfaced wherever Unverifiable picks appear (`prove-then-show`,
/// `report`). An "Unverifiable" carrier isn't a fundamental limit — it's just a
/// type the strategist has no auto-generator recipe for. Supplying a generator
/// unblocks it; this makes that otherwise-invisible mechanism discoverable.
enum GenHookHint {
    static let text =
        "Tip: an Unverifiable pick means the strategist has no generator for its carrier. "
            + "Add `static func gen() -> Gen<T>` for that type in your target — a same-file "
            + "extension works even for external types (e.g. `extension BigUInt { static func gen() … }`) "
            + "— and its picks become testable."
}
