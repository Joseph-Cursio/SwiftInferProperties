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

    static let corpora = PartialPurityConsumerMeasuredTests.corpora

    struct Arm {
        let corpus: String
        let summaries: Int
        let computedProperties: Int
        /// Summaries for a property whose accessor block declares `_modify`.
        let modifyProperties: [String]
        let suggestionsOnModify: Int
        let vetoedOnModify: Int
        /// Admitted properties whose accessor block declares more than one accessor —
        /// the population for the second half of open item 50.
        let multiAccessorAdmitted: [String]
    }

    static let measured: [Arm] = corpora.compactMap { corpus in
        guard let scanned = try? FunctionScanner.scanCorpus(directory: corpus.root) else {
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
        let multi = scanned.summaries
            .filter { $0.isComputedProperty && accessorSpecifiers(of: $0).count > 1 }
            .map { "\($0.name) @ \($0.location.line) — \(accessorSpecifiers(of: $0).sorted().joined(separator: "+"))" }

        return Arm(
            corpus: corpus.name,
            summaries: scanned.summaries.count,
            computedProperties: scanned.summaries.filter(\.isComputedProperty).count,
            modifyProperties: modify.map { "\($0.name) @ \($0.location.line)" }.sorted(),
            suggestionsOnModify: touching.count,
            vetoedOnModify: touching.filter { suggestion in
                suggestion.score.signals.contains { $0.kind == .impureSubject && $0.isVeto }
            }.count,
            multiAccessorAdmitted: multi.sorted()
        )
    }

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

    @Test("control — the corpora are reachable and have computed properties")
    func theCorpusIsReachable() {
        #expect(Self.measured.count >= 2, "only \(Self.measured.count) corpora scanned")
        #expect(Self.measured.contains { $0.computedProperties > 0 }, """
        No corpus produced a computed property at all, so every zero below is the \
        instrument's rather than the corpus's.
        """)
    }

    /// **No admitted property declares a second accessor**, which closes the other half of
    /// open item 50 by removing its population: `SoundPurity.verdict(forGetter:)` is handed
    /// the whole `AccessorBlockSyntax`, and reading a `_modify` body it should not was the
    /// complaint. With mutating accessors rejected upstream, every block it now sees holds
    /// exactly one accessor, so there is nothing else in it to misread.
    ///
    /// **Reopens the moment this fires** — a `get` + `_read` pair is legal, admitted, and
    /// would put the whole-block read back in play.
    @Test("no admitted property has a second accessor to misread")
    func theOracleSeesOneAccessor() {
        for arm in Self.measured {
            #expect(arm.multiAccessorAdmitted.isEmpty, """
            \(arm.corpus): \(arm.multiAccessorAdmitted.count) admitted propert(ies) declare \
            more than one accessor, so `verdict(forGetter:)` is reading a block it was not \
            asked about: \(arm.multiAccessorAdmitted.joined(separator: ", "))
            """)
        }
    }

    @Test("census — mutable properties admitted as read-only")
    func census() {
        for arm in Self.measured {
            print("""
            \(arm.corpus): \(arm.summaries) summaries · \(arm.computedProperties) computed properties
              declaring `_modify` yet summarised: \(arm.modifyProperties.count) \
            \(arm.modifyProperties.joined(separator: ", "))
              suggestions resting on one: \(arm.suggestionsOnModify) (vetoed \(arm.vetoedOnModify))
              admitted with more than one accessor: \(arm.multiAccessorAdmitted.count) \
            \(arm.multiAccessorAdmitted.joined(separator: ", "))
            """)
        }
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
