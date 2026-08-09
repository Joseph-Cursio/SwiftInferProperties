import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// A stub must write the carrier's **qualified lexical path**, not its bare name.
///
/// `Finding` declared as `ProtocolCoverageAudit.Finding` compiles to *cannot find type
/// 'Finding' in scope*, and the pick lands in `Inconclusive: build-failed` — which reads as a
/// tooling error rather than as the name-resolution problem it is.
///
/// The call-site owner has been qualified since 2026-08-05 (`Scaffold` →
/// `SwiftInferCommand.Scaffold`); the **generator carrier** never was, and they are different
/// types in general — `lawTotal(for:)` is declared on `ProtocolCoverageAudit` and quantifies
/// over `Finding`.
///
/// **The ambiguity arms are the ones that matter.** A wrong qualification fails to compile
/// just as surely as no qualification, while being harder to read, so anything the module
/// cannot resolve uniquely keeps the bare name — today's behaviour.
@Suite("Verify — a nested carrier is written as its qualified path")
struct NestedCarrierQualificationTests {

    private static func shapes(_ names: [String]) -> [String: IndexedTypeShape] {
        Dictionary(uniqueKeysWithValues: names.map { name in
            (name, IndexedTypeShape(name: name, kind: .struct, inheritedTypes: [], hasUserGen: false))
        })
    }

    private static func qualify(
        _ carrier: String, _ names: [String]
    ) -> String {
        SwiftInferCommand.Verify.qualifyingNestedCarrier(carrier, in: shapes(names))
    }

    // MARK: - The fix

    /// The measured case: `ProtocolCoverageAudit.Finding`, which the survey reported as
    /// `build-failed: cannot find type 'Finding' in scope`.
    @Test("a uniquely-named nested carrier is rewritten to its qualified path")
    func nestedCarrierIsQualified() {
        #expect(
            Self.qualify("Finding", ["ProtocolCoverageAudit.Finding", "Suggestion"])
                == "ProtocolCoverageAudit.Finding"
        )
    }

    /// Depth is not special-cased — the map's keys are whole lexical paths.
    @Test("a doubly-nested carrier keeps its full path")
    func doublyNestedCarrierIsQualified() {
        #expect(
            Self.qualify("Row", ["Report.Table.Row"]) == "Report.Table.Row"
        )
    }

    // MARK: - Leave alone

    /// A name that is already a key is top-level, or the caller already qualified it.
    @Test("a top-level carrier is returned untouched")
    func topLevelCarrierIsUntouched() {
        #expect(Self.qualify("Suggestion", ["Suggestion", "A.Finding"]) == "Suggestion")
    }

    /// An already-qualified carrier must not be qualified twice.
    @Test("an already-qualified carrier is not re-qualified")
    func alreadyQualifiedIsUntouched() {
        #expect(
            Self.qualify("ProtocolCoverageAudit.Finding", ["ProtocolCoverageAudit.Finding"])
                == "ProtocolCoverageAudit.Finding"
        )
    }

    /// **Ambiguity keeps the status quo.** Two `Finding`s in different parents give no way to
    /// choose, and picking one would fail to compile while looking deliberate.
    @Test("an ambiguous name is left bare rather than guessed")
    func ambiguousNameIsLeftBare() {
        #expect(
            Self.qualify("Finding", ["A.Finding", "B.Finding"]) == "Finding"
        )
    }

    /// An unknown carrier is left alone — the module may not declare it at all (stdlib,
    /// a dependency), and inventing a path would turn a working stub into a broken one.
    @Test("an unknown carrier is left bare")
    func unknownCarrierIsLeftBare() {
        #expect(Self.qualify("Int", ["A.Finding"]) == "Int")
        #expect(Self.qualify("Finding", []) == "Finding")
    }

    // MARK: - Composed spellings are not names
    //
    // The suffix match runs on `.\(carrier)`, so without the identifier guard a carrier of
    // `[Finding]` could match `A.Finding` on its tail and be rewritten into a corrupt
    // spelling. These are shapes the strategist composes, not names to look up.

    @Test("array, optional and generic spellings are never rewritten")
    func composedSpellingsAreUntouched() {
        let universe = ["ProtocolCoverageAudit.Finding"]
        #expect(Self.qualify("[Finding]", universe) == "[Finding]")
        #expect(Self.qualify("Finding?", universe) == "Finding?")
        #expect(Self.qualify("Box<Finding>", universe) == "Box<Finding>")
        #expect(Self.qualify("[String: Finding]", universe) == "[String: Finding]")
    }

    /// A partial-component match must not fire: `OtherFinding` is not `Finding`, and the
    /// leading `.` in the suffix test is what keeps them apart.
    @Test("a name that merely ends in the carrier is not a match")
    func partialComponentIsNotAMatch() {
        #expect(Self.qualify("Finding", ["A.OtherFinding"]) == "Finding")
    }

    @Test("an empty carrier is returned untouched")
    func emptyCarrierIsUntouched() {
        #expect(Self.qualify("", ["A.Finding"]).isEmpty)
    }
}
