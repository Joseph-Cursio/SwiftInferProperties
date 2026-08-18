import Foundation
import SwiftParser
import SwiftSyntax

@testable import SwiftInferCore

// Type classification for `SoundnessArmReachCensusMeasuredTests`. Split out for the
// 400-line cap; the reasoning lives in that suite's header.

extension SoundnessArmReachCensusMeasuredTests {

    /// What a probe harness would have to write to supply a value of a package type.
    ///
    /// **The strict `isDegenerate` rule counts every package type as blocking, and that
    /// understates the arm's reach.** `WorkdirMode` is a `CaseIterable` enum —
    /// `.allCases.first!` is one expression, not a construction problem — and a struct
    /// whose stored properties are all degenerate is a memberwise call away. Reporting
    /// only the strict figure would decline the arm on a cost that is not real.
    ///
    /// A protocol is a genuine third answer: the probe must author a conforming stub.
    /// Cheap in absolute terms, but it is code the harness owns and can get wrong, so it
    /// is counted separately rather than folded into either side.
    enum TypeCost: String {
        case degenerate       // stdlib — nothing to write
        case cheap            // CaseIterable enum, or a struct of degenerate fields
        case stubRequired     // a protocol existential
        case expensive        // anything else, or not found in Sources/
    }

    /// Every type declaration in `Sources/`, with what it would cost to construct.
    ///
    /// Built once over the same file enumeration the other censuses use, so a type this
    /// package does not declare falls to `.expensive` rather than being guessed at — the
    /// same treatment the unrecognised-callee census gives a callee it has no oracle for.
    static let typeCosts: [String: TypeCost] = {
        var table: [String: TypeCost] = [:]
        let root = PurityRefutationCensusMeasuredTests.packageSourcesRoot
        for file in SwiftSourceFiles.sorted(in: root) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let collector = TypeCostCollector(viewMode: .sourceAccurate)
            collector.walk(Parser.parse(source: text))
            for (name, cost) in collector.costs where table[name] == nil {
                table[name] = cost
            }
        }
        return table
    }()

    /// The cost of supplying `type`, unwrapping the spellings that do not change it.
    static func cost(of type: String) -> TypeCost {
        if isDegenerate(type) { return .degenerate }
        // `any Foo` / `some Foo` are the protocol spellings.
        let bare = type
            .replacingOccurrences(of: "any ", with: "")
            .replacingOccurrences(of: "some ", with: "")
            .trimmingCharacters(in: .whitespaces)
        // A nested spelling resolves on its last component: `SpeculativeWidening.Candidate`.
        let leaf = bare.split(separator: ".").last.map(String.init) ?? bare
        return typeCosts[leaf] ?? .expensive
    }
}

/// Type declarations and what they cost to construct.
///
/// Nested types are recorded under their own simple name, which is how a parameter
/// spelling like `SpeculativeWidening.Candidate` resolves — the census strips to the
/// leaf rather than tracking full paths, and a collision between two nested types of
/// the same name would resolve to whichever file sorts first. Recorded because it is a
/// real limit and the same name-keying hazard every census at this seam carries.
final class TypeCostCollector: SyntaxVisitor {

    private(set) var costs: [String: SoundnessArmReachCensusMeasuredTests.TypeCost] = [:]

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        costs[node.name.text] = .stubRequired
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let conformances = node.inheritanceClause?.inheritedTypes
            .map(\.type.trimmedDescription) ?? []
        costs[node.name.text] = conformances.contains("CaseIterable") ? .cheap : .expensive
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        costs[node.name.text] = Self.cost(ofStoredPropertiesIn: node.memberBlock)
        return .visitChildren
    }

    /// A struct is cheap when every stored property is degenerate — then a memberwise
    /// call supplies it. Computed properties are ignored: they take no argument.
    ///
    /// A property with an initial value is also fine even when its type is not
    /// degenerate, because the memberwise initialiser defaults it — so it is skipped
    /// rather than counted as blocking.
    static func cost(
        ofStoredPropertiesIn members: MemberBlockSyntax
    ) -> SoundnessArmReachCensusMeasuredTests.TypeCost {
        for member in members.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
            for binding in variable.bindings {
                // A computed property has an accessor block and no stored value.
                if binding.accessorBlock != nil { continue }
                if binding.initializer != nil { continue }
                guard let type = binding.typeAnnotation?.type.trimmedDescription else { continue }
                if !SoundnessArmReachCensusMeasuredTests.isDegenerate(type) { return .expensive }
            }
        }
        return .cheap
    }
}
