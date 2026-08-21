import Foundation
import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftInferCore

/// **How many normalisers carry their own postcondition as a guard in the body?**
///
/// `fixtures/branch-reaching-generator/` measured that on a legalise-shaped subject the
/// postcondition `isValid(f(x))` refutes **4 of 4** real bugs while idempotence refutes
/// **1 of 4** — and the tool emits the idempotence law. The obvious way to find the
/// predicate, matching it to the normaliser **by name across the type**, was measured and
/// **declined**: 349 shape pairs, ~1–5 genuine.
///
/// This is the route that census pointed at instead. `HTTPField.legalizeValue` opens with
///
/// ```swift
/// if self._isValidValue(value._storage.utf8) { return value }
/// ```
///
/// **The guard IS the postcondition**, inside the function the law is about. No name
/// matching, no cross-member pairing, no `isDisjoint` false pairs.
///
/// ## The shape, and how loose it has to be
///
/// A function `(T) -> T` whose body opens with an `if` or `guard` that calls something
/// and mentions the parameter, with a branch that returns immediately.
///
/// **The argument is NOT required to be the parameter itself.** The motivating call
/// passes `value._storage.utf8`, not `value` — so requiring an exact match would miss the
/// one case this census exists to find, which is the mistake the name-matching version
/// made in the other direction.
///
/// **That looseness is a cost, and it is why the sample rows are printed.** A summary
/// count from a loose rule is exactly what produced 449 spurious pairs last time; the
/// hand-check is the instrument, not the total.
@Suite("Census — normalisers whose body guards on their own postcondition", .serialized)
struct GuardPostconditionCensusMeasuredTests {

    struct Hit {
        let corpus: String
        let file: String
        let function: String
        let guardText: String
    }

    static let hits: [Hit] = {
        var found: [Hit] = []
        for corpus in CorpusManifest.available {
            for file in SwiftSourceFiles.sorted(in: corpus.primaryRoot) {
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                let collector = GuardedNormaliserCollector(viewMode: .sourceAccurate)
                collector.walk(Parser.parse(source: text))
                found.append(contentsOf: collector.found.map {
                    Hit(
                        corpus: corpus.id,
                        file: file.lastPathComponent,
                        function: $0.name,
                        guardText: $0.guardText
                    )
                })
            }
        }
        return found
    }()

    /// **The detector fires on the motivating shape**, asserted on a synthetic witness.
    /// A census whose collector never matches reports the same zero as an empty corpus —
    /// the failure `module-state-base-rate.md` shipped once already.
    @Test("the detector fires on the HTTPField.legalizeValue shape")
    func detectorFires() {
        let tree = Parser.parse(source: """
        struct S {
            static func legalizeValue(_ value: ISOLatin1String) -> ISOLatin1String {
                if self._isValidValue(value._storage.utf8) { return value }
                return ISOLatin1String(unchecked: "")
            }
            static func unguarded(_ value: ISOLatin1String) -> ISOLatin1String {
                return value
            }
            static func notANormaliser(_ value: ISOLatin1String) -> Bool {
                if self._isValidValue(value) { return true }
                return false
            }
        }
        """)
        let collector = GuardedNormaliserCollector(viewMode: .sourceAccurate)
        collector.walk(tree)
        let names = collector.found.map(\.name).sorted()
        #expect(names == ["legalizeValue"], "found \(names)")
    }

    /// The corpora are the manifest's, not a subset.
    @Test("the census scans the corpora the manifest resolves")
    func universeIsTheManifest() {
        #expect(CorpusManifest.available.count >= 8)
    }

    @Test("census — guarded normalisers across the manifest")
    func census() {
        var lines: [String] = ["", "GUARDED NORMALISERS — ALL MANIFEST CORPORA", ""]
        lines.append("corpora: \(CorpusManifest.available.count)")
        lines.append("normalisers `(T) -> T` guarding on a call that mentions the parameter: \(Self.hits.count)")
        lines.append("")
        var byCorpus: [String: Int] = [:]
        for hit in Self.hits { byCorpus[hit.corpus, default: 0] += 1 }
        for (corpus, count) in byCorpus.sorted(by: { $0.value > $1.value }) {
            lines.append("  \(count)  \(corpus)")
        }
        lines.append("")
        lines.append("sample — the hand-check is the instrument, not the total:")
        for hit in Self.hits.prefix(25) {
            lines.append("  [\(hit.corpus)] \(hit.file):\(hit.function)  ⟵  \(hit.guardText.prefix(70))")
        }
        print(lines.joined(separator: "\n"))
    }
}

/// Functions `(T) -> T` whose body opens with a call-bearing `if` / `guard` mentioning the
/// parameter, with an immediately-returning branch.
final class GuardedNormaliserCollector: SyntaxVisitor {

    struct Found {
        let name: String
        let guardText: String
    }

    private(set) var found: [Found] = []

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let body = node.body,
              node.signature.parameterClause.parameters.count == 1,
              let parameter = node.signature.parameterClause.parameters.first,
              let returnType = node.signature.returnClause?.type.trimmedDescription
        else { return .visitChildren }

        // `(T) -> T`. `Self` counts: a normaliser on the containing type returns it.
        let parameterType = parameter.type.trimmedDescription
        guard returnType == parameterType || returnType == "Self" else { return .visitChildren }
        // A `Bool` return is a predicate, not a normaliser, even when `T` is `Bool`.
        guard returnType != "Bool" else { return .visitChildren }

        let binding = parameter.secondName?.text ?? parameter.firstName.text
        guard let first = body.statements.first else { return .visitChildren }

        // **Three hops, not one.** Swift's `if` is an EXPRESSION, and used as a statement
        // it arrives as `StmtSyntax` → `ExpressionStmtSyntax` → `IfExprSyntax`. `guard` is
        // a statement outright. Reaching for `IfExprSyntax` directly matches nothing, and
        // so does stopping at `ExprSyntax`. **`detectorFires` caught both attempts before
        // this census produced a number** — which is the entire reason a synthetic witness
        // is asserted before the corpora are scanned.
        let statement = first.item.as(StmtSyntax.self)
        let ifExpression = statement?.as(ExpressionStmtSyntax.self)?.expression.as(IfExprSyntax.self)
            ?? first.item.as(ExprSyntax.self)?.as(IfExprSyntax.self)
        let guardStatement = statement?.as(GuardStmtSyntax.self)

        let condition: String?
        let returnsEarly: Bool
        if let ifExpr = ifExpression {
            condition = ifExpr.conditions.trimmedDescription
            returnsEarly = ifExpr.body.statements.contains { $0.item.is(ReturnStmtSyntax.self) }
        } else if let guardStmt = guardStatement {
            condition = guardStmt.conditions.trimmedDescription
            returnsEarly = guardStmt.body.statements.contains { $0.item.is(ReturnStmtSyntax.self) }
        } else {
            condition = nil
            returnsEarly = false
        }

        guard let condition, returnsEarly,
              condition.contains("("),          // a call, not a bare comparison
              condition.contains(binding),      // ... mentioning the parameter
              // **An optional binding is not a postcondition.** `guard let initializer =
              // node.initializer` satisfies "contains a call" and is not a predicate at
              // all — it was the dominant false class in this census's first run, where
              // 44 hits included `let type = isRewritable(...)`, `let interval =
              // dateInterval(...)` and `let openAngle = name.firstIndex(of: "<")`.
              //
              // The test that matters is **re-applicability**: a postcondition must be
              // assertable of the OUTPUT, `P(f(x))`. A binding that names a local cannot
              // be, so it cannot serve as the oracle the law needs.
              !condition.contains("let "), !condition.contains("case ")
        else { return .visitChildren }

        found.append(Found(name: node.name.text, guardText: condition))
        return .visitChildren
    }
}
