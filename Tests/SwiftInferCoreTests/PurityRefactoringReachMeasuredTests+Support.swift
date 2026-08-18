import Foundation
import SwiftParser
import SwiftSyntax

@testable import SwiftInferCore
@testable import SwiftInferTemplates

/// The arms for `PurityRefactoringReachMeasuredTests`. Split out only for the 400-line
/// file cap; the reasoning that governs both lives in that suite's header.
///
/// **`SwiftInferCore.SourceLocation` is spelled out everywhere below**, because
/// `SwiftSyntax` ships a `SourceLocation` too and this file imports both. Unqualified,
/// it does not compile — which is the good failure. The bad one would be a file that
/// imported only one and silently keyed the join on the wrong type.
extension PurityRefactoringReachMeasuredTests {

    /// **Item 34's three corpora, reused rather than re-chosen.** Sharing them is what
    /// lets this census be read beside `partial-purity-consumer-declined.md` — a
    /// different corpus would make the `isThrows` control incomparable to the +2 it is
    /// being checked against.
    static let corpora = PartialPurityConsumerMeasuredTests.corpora

    /// The same summary with the purity verdict forced to `.pure`.
    ///
    /// **`isInferredPure` moves with it, and that is not tidiness.** The field's own doc
    /// says `isInferredPure` *is* `purityVerdict == .pure`, and item 40 was filed
    /// precisely because those two facts were once allowed to disagree. An arm forcing
    /// one and not the other would measure a state the pipeline never produces.
    static func withPurityForced(_ summary: FunctionSummary) -> FunctionSummary {
        FunctionSummary(
            name: summary.name,
            parameters: summary.parameters,
            returnTypeText: summary.returnTypeText,
            isThrows: summary.isThrows,
            isAsync: summary.isAsync,
            isMutating: summary.isMutating,
            isStatic: summary.isStatic,
            location: summary.location,
            containingTypeName: summary.containingTypeName,
            bodySignals: summary.bodySignals,
            qualifiedContainingTypeName: summary.qualifiedContainingTypeName,
            discoverableGroup: summary.discoverableGroup,
            invariantKeypath: summary.invariantKeypath,
            isInferredPure: true,
            isClockDeterministic: summary.isClockDeterministic,
            declaresUnknownEffect: summary.declaresUnknownEffect,
            isComputedProperty: summary.isComputedProperty,
            isInitializer: summary.isInitializer,
            docComment: summary.docComment,
            declaredEffect: summary.declaredEffect,
            inferredEffect: summary.inferredEffect,
            purityVerdict: .pure,
            bodyFingerprint: summary.bodyFingerprint
        )
    }

    // MARK: - The join

    /// One suggestion's evidence rows, resolved against the summaries they came from.
    struct Join {
        var evidenceRows = 0
        var resolvedRows = 0
        var descriptions: [String] = []
        var subjects: [Subject] = []
    }

    struct Subject {
        let name: String
        let location: SwiftInferCore.SourceLocation
    }

    /// **Keyed by the full `SourceLocation` — file, line AND column.** Name-keying is the
    /// hazard that has been the dominant defect at this seam in three measurements
    /// (`resolve` and `load` each match several declarations here); a location is unique
    /// by construction and needs no tie-break. Measured: it resolves 100% of rows.
    static func join(
        _ suggestions: [Suggestion],
        against summaries: [FunctionSummary]
    ) -> Join {
        let verdictAt = Dictionary(summaries.map { ($0.location, $0.purityVerdict) }) { first, _ in
            first
        }

        var join = Join()
        for suggestion in suggestions {
            var refuted: [Subject] = []
            for row in suggestion.evidence {
                join.evidenceRows += 1
                guard let verdict = verdictAt[row.location] else { continue }
                join.resolvedRows += 1
                if verdict == .refuted {
                    refuted.append(Subject(name: row.displayName, location: row.location))
                }
            }
            guard !refuted.isEmpty else { continue }
            join.subjects.append(contentsOf: refuted)
            let named = refuted.map { "\($0.name):\($0.location.line)" }.joined(separator: " + ")
            join.descriptions.append("\(suggestion.templateName) :: \(named)")
        }
        return join
    }

    // MARK: - The witness split

    struct WitnessSplit {
        let witness: [String]
        let ignorance: [String]
        /// Read-only computed properties. **A category, not a miss.** They take
        /// `SoundPurity.verdict(forGetter:)`, a different oracle from the one the
        /// attributor replicates, so classifying them with the function causes would be
        /// attributing a verdict to refuters that never ran. Item 40 is the precedent.
        let computedProperty: [String]
        /// Refuted by `PackagePurityJoin` rather than by anything in their own body —
        /// **a witness one hop away, not ignorance.** The attributor reads syntax, and a
        /// joined retraction leaves none: `SoundPurity.verdict(for:)` would answer
        /// `.pure` for these. Before open item 43 shipped, a `.refuted` subject always
        /// carried at least one local cause, so an empty cause set is unambiguous.
        ///
        /// **Bucketing these as ignorance-only would invert their meaning**, which is
        /// what this census did for one run after the join landed.
        let joined: [String]
        /// Subjects the re-parse could not locate at all. Reported, never folded into
        /// any other side — a split that quietly absorbs its own misses is not a split.
        let unclassified: [String]
    }

    /// Re-parse each refuted subject's own file and ask
    /// `PurityRefutationCensusMeasuredTests.Attributor` which causes hold.
    ///
    /// **The split is what separates a soundness finding from a tally.** A
    /// `propagatedTry` refutation is the analyzer saying it could not see past a `try` —
    /// `encode(to:)` is refuted that way and is not impure. Counting those beside a
    /// `FileManager` marker repeats item 32's arithmetic: a bucket tallied whole
    /// over-reports the part anything can act on.
    ///
    /// Keyed by the `func` keyword's line, matching
    /// `FunctionScannerVisitor.funcKeywordLocation` exactly, and the file comes from the
    /// location itself rather than from a second corpus walk — so the classifier cannot
    /// drift from the summaries it is classifying.
    static func witnessSplit(for subjects: [Subject]) -> WitnessSplit {
        var cache: [String: [Int: FunctionDeclSyntax]] = [:]
        let attributor = PurityRefutationCensusMeasuredTests.Attributor()

        var propertyCache: [String: Set<Int>] = [:]
        var witness: [String] = []
        var ignorance: [String] = []
        var computedProperty: [String] = []
        var joined: [String] = []
        var unclassified: [String] = []

        for subject in subjects {
            let file = URL(fileURLWithPath: subject.location.file).lastPathComponent
            let label = "\(subject.name) @ \(file):\(subject.location.line)"
            let functions = parsedFunctions(inFile: subject.location.file, cache: &cache)
            guard let function = functions[subject.location.line] else {
                let properties = parsedPropertyLines(inFile: subject.location.file, cache: &propertyCache)
                if properties.contains(subject.location.line) {
                    computedProperty.append(label)
                } else {
                    unclassified.append(label)
                }
                continue
            }
            let causes = attributor.causes(of: function)
            let named = causes.filter(\.isWitness).map(\.rawValue).sorted().joined(separator: "+")
            if causes.isEmpty {
                joined.append(label)
            } else if named.isEmpty {
                ignorance.append(label)
            } else {
                witness.append("\(label) — \(named)")
            }
        }
        return WitnessSplit(
            witness: witness.sorted(),
            ignorance: ignorance.sorted(),
            computedProperty: computedProperty.sorted(),
            joined: joined.sorted(),
            unclassified: unclassified.sorted()
        )
    }

    /// Lines carrying a computed property's `var` keyword — the position
    /// `makeSummary(fromComputedProperty:)` records, so the key matches by construction.
    private static func parsedPropertyLines(
        inFile path: String,
        cache: inout [String: Set<Int>]
    ) -> Set<Int> {
        if let hit = cache[path] { return hit }
        var found: Set<Int> = []
        if let source = try? String(contentsOfFile: path, encoding: .utf8) {
            let tree = Parser.parse(source: source)
            let converter = SwiftSyntax.SourceLocationConverter(fileName: path, tree: tree)
            let collector = ComputedPropertyCollector(viewMode: .sourceAccurate)
            collector.walk(tree)
            for property in collector.properties {
                let position = property.bindingSpecifier.positionAfterSkippingLeadingTrivia
                found.insert(converter.location(for: position).line)
            }
        }
        cache[path] = found
        return found
    }

    private static func parsedFunctions(
        inFile path: String,
        cache: inout [String: [Int: FunctionDeclSyntax]]
    ) -> [Int: FunctionDeclSyntax] {
        if let hit = cache[path] { return hit }
        var found: [Int: FunctionDeclSyntax] = [:]
        if let source = try? String(contentsOfFile: path, encoding: .utf8) {
            let tree = Parser.parse(source: source)
            let converter = SwiftSyntax.SourceLocationConverter(fileName: path, tree: tree)
            let collector = CensusFunctionCollector(viewMode: .sourceAccurate)
            collector.walk(tree)
            for function in collector.functions {
                let position = function.funcKeyword.positionAfterSkippingLeadingTrivia
                found[converter.location(for: position).line] = function
            }
        }
        cache[path] = found
        return found
    }

    // MARK: - The arms

    struct Arms {
        let corpus: String
        let summaries: Int
        let baseline: Int
        let throwsMasked: Int
        let purityForced: Int
        let subjectsPure: Int
        let subjectsPartial: Int
        let subjectsRefuted: Int
        let join: Join
        let split: WitnessSplit
    }

    static func arms(for corpus: PartialPurityConsumerMeasuredTests.Corpus) throws -> Arms {
        let scanned = try FunctionScanner.scanCorpus(directory: corpus.root)
        let summaries = scanned.summaries

        func suggestions(_ input: [FunctionSummary]) -> [Suggestion] {
            TemplateRegistry.discover(
                in: input, identities: scanned.identities, typeDecls: scanned.typeDecls
            )
        }

        let base = suggestions(summaries)
        let joined = join(base, against: summaries)

        return Arms(
            corpus: corpus.name,
            summaries: summaries.count,
            baseline: base.count,
            throwsMasked: suggestions(summaries.map {
                $0.isThrows ? PartialPurityConsumerMeasuredTests.withThrowsMasked($0) : $0
            }).count,
            purityForced: suggestions(summaries.map {
                $0.purityVerdict == .pure ? $0 : withPurityForced($0)
            }).count,
            subjectsPure: summaries.filter { $0.purityVerdict == .pure }.count,
            subjectsPartial: summaries.filter { $0.purityVerdict == .pureButPartial }.count,
            subjectsRefuted: summaries.filter { $0.purityVerdict == .refuted }.count,
            join: joined,
            split: witnessSplit(for: joined.subjects)
        )
    }

    static let measured: [Arms] = corpora.compactMap { try? arms(for: $0) }
}

/// Every `var` with an accessor block, for the computed-property arm of the witness
/// split. Deliberately does not replicate `isReadOnlyGetter` — the question here is
/// *"is this declaration a computed property"*, not *"would the scanner summarise it"*,
/// and answering the second would make the classifier agree with the scanner by
/// construction rather than by measurement.
final class ComputedPropertyCollector: SyntaxVisitor {
    var properties: [VariableDeclSyntax] = []

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.bindings.first?.accessorBlock != nil { properties.append(node) }
        return .skipChildren
    }
}
