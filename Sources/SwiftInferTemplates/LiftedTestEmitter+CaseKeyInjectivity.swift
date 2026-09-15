import SwiftInferCore

/// The `caseiterable-key-injectivity` arm: distinct cases map to distinct keys (#474).
///
/// ## Not a property test, and that is the point
///
/// Every other arm draws inputs and checks a law over a sample. This one has no input to draw:
/// the member takes none, and its domain is the enum's **entire, finite case list**. The template
/// says so in its own caveat — *"CHECK IT EXHAUSTIVELY, NOT BY SAMPLING"* — because over a
/// 197-case enum a sampled check has to be lucky to draw the one colliding pair and reports
/// success when it is not. So the stub is a plain loop over `allCases`: no generator, no backend,
/// no seed, and a pass that means the law **holds** for every case rather than for the ones drawn.
///
/// ## Grouped by `String(describing:)`, not by the key itself
///
/// The template admits keys of `String`, `Int`, `UInt`, `Int32`, `Int64`, `Character` and
/// `StaticString`. Grouping needs `Hashable`, and **`StaticString` is not** — a stub keyed on the
/// raw value would not compile for it. Every admitted type's description is injective (two
/// distinct `Int`s never describe alike), so describing first decides distinctness exactly and
/// compiles for all seven.
extension LiftedTestEmitter {

    /// Emit a `@Test` asserting that `member` takes a distinct value on every case of `enumType`.
    ///
    /// - Parameters:
    ///   - enumType: the `CaseIterable` enum, qualified as a test must spell it.
    ///   - member: the zero-argument instance member — a computed property or a method; its
    ///     `isolation` becomes the test's global actor, since the loop reads it synchronously.
    public static func caseKeyInjectivity(enumType: String, member: CalleeReference) -> String {
        let key = member.call("$0")
        let actor = member.isolation.map { "@\($0) " } ?? ""
        let subject = "\(enumType).\(member.bareName)"
        return """
        @Test \(actor)func \(member.bareName)_isInjectiveOverCases() {
            let casesByKey = Dictionary(grouping: \(enumType).allCases, by: { String(describing: \(key)) })
            let collisions = casesByKey.filter { $0.value.count > 1 }.sorted { $0.key < $1.key }
            let report = collisions.map { "\\($0.key) ← \\($0.value)" }
            #expect(collisions.isEmpty, "\(subject) is not injective over allCases — cases sharing a key: \\(report)")
        }
        """
    }
}
