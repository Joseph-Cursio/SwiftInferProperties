import Foundation
import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftInferCore
@testable import SwiftInferTemplates

/// **`isReadOnlyGetter` accepts a `_modify` coroutine, so a MUTABLE property is summarised
/// as a read-only one and carries laws.**
///
/// Open item 50, found by `docs/measurements/purity-refactoring-reach.md` §3 while that
/// census was measuring something else.
///
/// ```swift
/// public var unordered: UnorderedView {
///   get { UnorderedView(_base: self) }
///   _modify { … self = OrderedSet(); defer { self = view._base }; yield &view }
/// }
/// ```
///
/// The guard accepts any accessor list containing `get` and not containing the literal
/// `"set"`. A `_modify` coroutine **is** a mutating accessor — `set.unordered.insert(x)`
/// writes through it — so the property is admitted as the pure `self -> T` map the
/// templates assume, which it is not.
///
/// ## Two defects, and they currently cancel
///
/// `SoundPurity.verdict(forGetter:)` is handed the **whole** `AccessorBlockSyntax`, so it
/// reads the `_modify` body, sees `self = OrderedSet()`, and answers `.refuted` — correct
/// about the property, wrong about the getter, which is pure. Since open item 54's veto
/// ships, that refutation is what withholds the laws.
///
/// **So fixing the oracle alone would re-admit them.** Narrow `verdict(forGetter:)` to the
/// getter and `unordered` becomes `.pure`, the veto stops firing, and eight laws over a
/// genuinely mutable property come back. The source of the rows has to close first, which
/// is what this suite measures and what the fix in this change does.
@Suite("Census — a `_modify` property is summarised as read-only", .serialized)
struct ModifyAccessorCensusMeasuredTests {

    static let corpus = PartialPurityConsumerMeasuredTests.corpora
        .first { $0.name.contains("OrderedCollections") }

    struct Arm {
        let summaries: Int
        let computedProperties: Int
        /// Summaries for a property whose accessor block declares `_modify`.
        let modifyProperties: [String]
        let suggestionsOnModify: Int
        let vetoedOnModify: Int
    }

    static let measured: Arm? = {
        guard let corpus, let scanned = try? FunctionScanner.scanCorpus(directory: corpus.root) else {
            return nil
        }
        let suggestions = TemplateRegistry.discover(
            in: scanned.summaries, identities: scanned.identities, typeDecls: scanned.typeDecls
        )
        let modify = scanned.summaries.filter { $0.isComputedProperty && declaresModify($0) }
        let modifyLocations = Set(modify.map(\.location))

        let touching = suggestions.filter { suggestion in
            suggestion.evidence.contains { modifyLocations.contains($0.location) }
        }
        return Arm(
            summaries: scanned.summaries.count,
            computedProperties: scanned.summaries.filter(\.isComputedProperty).count,
            modifyProperties: modify.map { "\($0.name) @ \($0.location.line)" }.sorted(),
            suggestionsOnModify: touching.count,
            vetoedOnModify: touching.filter { suggestion in
                suggestion.score.signals.contains { $0.kind == .impureSubject && $0.isVeto }
            }.count
        )
    }()

    /// Re-parses the declaration and reads its accessor specifiers. The summary carries no
    /// accessor vocabulary, and inferring "has a `_modify`" from the verdict would assume
    /// exactly what this census is testing.
    ///
    /// **The first version of this detector was a 20-line text window over the source, and
    /// it over-matched.** It reported two survivors after the fix — `keys` in
    /// `OrderedDictionary+Elements.SubSequence.swift`, whose body is the implicit getter
    /// `{ _base._keys[_bounds] }` and which is genuinely read-only — because a *neighbouring*
    /// declaration's `_modify` fell inside the window. A census whose detector over-matches
    /// is the blind-detector problem inverted: `module-state-base-rate.md` published a zero
    /// from an instrument that could not see, and this would have published a residue from
    /// one that saw too much.
    static func declaresModify(_ summary: FunctionSummary) -> Bool {
        accessorSpecifiers(of: summary).contains("_modify")
    }

    /// Accessor specifiers on the property declared at this summary's location, keyed by
    /// the `var` keyword's line — the position `makeSummary(fromComputedProperty:)`
    /// records, so the key matches by construction.
    static func accessorSpecifiers(of summary: FunctionSummary) -> Set<String> {
        guard let text = try? String(contentsOfFile: summary.location.file, encoding: .utf8) else {
            return []
        }
        let tree = Parser.parse(source: text)
        let converter = SwiftSyntax.SourceLocationConverter(fileName: summary.location.file, tree: tree)
        let collector = ModifyPropertyCollector(viewMode: .sourceAccurate)
        collector.walk(tree)

        for property in collector.properties {
            let position = property.bindingSpecifier.positionAfterSkippingLeadingTrivia
            guard converter.location(for: position).line == summary.location.line,
                  let block = property.bindings.first?.accessorBlock else { continue }
            switch block.accessors {
            case .getter:
                return ["get"]

            case let .accessors(list):
                return Set(list.map(\.accessorSpecifier.text))
            }
        }
        return []
    }

    @Test("control — the corpus is reachable and has computed properties")
    func theCorpusIsReachable() throws {
        let arm = try #require(Self.measured, "OrderedCollections did not resolve")
        #expect(arm.summaries > 300, "only \(arm.summaries) summaries — the corpus did not scan")
        #expect(arm.computedProperties > 0, "no computed properties at all; the census cannot fire")
    }

    @Test("census — mutable properties admitted as read-only")
    func census() throws {
        let arm = try #require(Self.measured)
        print("""
        OrderedCollections: \(arm.summaries) summaries · \(arm.computedProperties) computed properties
          summarised despite declaring `_modify`: \(arm.modifyProperties.count)
            \(arm.modifyProperties.joined(separator: "\n    "))
          suggestions resting on one: \(arm.suggestionsOnModify)
          …of those, vetoed: \(arm.vetoedOnModify)
        """)
    }
}

/// Every `var` carrying an accessor block, for the census's accessor lookup.
final class ModifyPropertyCollector: SyntaxVisitor {
    var properties: [VariableDeclSyntax] = []

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.bindings.first?.accessorBlock != nil { properties.append(node) }
        return .skipChildren
    }
}
