import Foundation
import SwiftParser
import SwiftSyntax

/// PROTOTYPE — SwiftSyntax pass that recognises lint-rule visitor carriers:
/// `SyntaxVisitor` subclasses that accumulate findings while walking an AST.
/// This is the carrier `ReducerDiscoverer` and `ViewModelDiscoverer` both
/// miss — a lint rule is neither a `(State, Action) -> State` signature nor
/// an `@Observable` view model, but a stateful walker (`visit(node)`
/// callbacks accumulating issues), the dominant shape in SwiftSyntax-based
/// lint engines (motivating dogfood: `swiftprojectlint`, 124/149 visitors).
///
/// **Recognition is structural, not name-based.** A type is a candidate iff
/// it is a `class` declaring at least one `visit(_:) -> SyntaxVisitorContinueKind`
/// override. That return type is unique to SwiftSyntax visitors, so the
/// recogniser generalises across direct `SyntaxVisitor` subclasses and
/// project base classes alike (`BasePatternVisitor`, etc.) without hard-coding
/// any base name. Base classes that declare no node-specific `visit(_:)`
/// override (e.g. an abstract `BasePatternVisitor`) are correctly excluded.
///
/// **Cross-file / extension-aware**, mirroring `ViewModelDiscoverer`: a
/// visitor's `visit(_:)` overrides may live in `extension` blocks across
/// several files, so the directory scan accumulates per-type info into one
/// table keyed by type name before assembling candidates.
///
/// **Slice 1 is recognition only** — see `RuleVisitorCandidate` and
/// `docs/rule-visitor-carrier-scoping.md`. No invariant is emitted: the
/// carrier's generic law (determinism) is near-always true and would flood
/// `.possible`; its high-value law (no false positive on clean input) is
/// per-rule (TestLifter territory), not a generic property.
public enum RuleVisitorDiscoverer {

    public static func discover(source: String, file: String) -> [RuleVisitorCandidate] {
        var table: [String: RawVisitorInfo] = [:]
        accumulate(source: source, file: file, into: &table)
        return assemble(table)
    }

    public static func discover(file: URL) throws -> [RuleVisitorCandidate] {
        let source = try String(contentsOf: file, encoding: .utf8)
        return discover(source: source, file: file.path)
    }

    /// Recursively scan every `.swift` file under `directory`, merging
    /// per-type info across files (sorted-path order for determinism)
    /// before assembling candidates.
    public static func discover(directory: URL) throws -> [RuleVisitorCandidate] {
        let swiftFiles = SwiftSourceFiles.sorted(in: directory)
        var table: [String: RawVisitorInfo] = [:]
        for fileURL in swiftFiles {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            accumulate(source: source, file: fileURL.path, into: &table)
        }
        return assemble(table)
    }

    // MARK: - Phase 1 — accumulate

    private static func accumulate(
        source: String,
        file: String,
        into table: inout [String: RawVisitorInfo]
    ) {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: file, tree: tree)
        let visitor = RuleVisitorDiscoveryVisitor(file: file, converter: converter)
        visitor.walk(tree)
        for (typeName, partial) in visitor.collected {
            table[typeName, default: RawVisitorInfo()].merge(partial)
        }
    }

    // MARK: - Phase 2 — assemble

    /// Emit a `RuleVisitorCandidate` for each class that declares ≥1
    /// `visit(_:) -> SyntaxVisitorContinueKind` override. Types collected
    /// only because they nested a stray `visit`/`ruleName:` (a struct/enum,
    /// or a class with no node-specific override) have no such override and
    /// are dropped.
    static func assemble(_ table: [String: RawVisitorInfo]) -> [RuleVisitorCandidate] {
        var candidates: [RuleVisitorCandidate] = []
        for (typeName, info) in table {
            guard let location = info.declLocation,
                  !info.visitedNodeTypes.isEmpty else {
                continue
            }
            candidates.append(
                RuleVisitorCandidate(
                    location: location,
                    typeName: typeName,
                    inheritedTypes: info.inheritedTypes,
                    visitedNodeTypes: info.visitedNodeTypes.sorted(),
                    emittedRuleNames: info.emittedRuleNames.sorted()
                )
            )
        }
        return candidates.sorted { lhs, rhs in
            if lhs.location != rhs.location { return lhs.location < rhs.location }
            return lhs.typeName < rhs.typeName
        }
    }
}
