import Foundation
import SwiftInferCore
import SwiftInferTemplates
import SwiftParser
import SwiftSyntax

/// One subject from `scripts/count_threshold_census.py controls`.
struct Subject: Codable {
    let group: String
    let name: String
    let repository: String
    let repositoryRoot: String
    let roots: [String]
    let sourcesComponentOnly: Bool
    let revision: String?
    let dirty: Bool
}

/// Today's reading of a count row (§2.3).
struct TodayRow: Codable {
    let condition: String
    let returned: String
    let firesWhenConditionHolds: Bool
    let n: Int
    let op: String
    let lo: Int
    let hi: Int
    /// `≤lo` or `≥hi`: the counted lengths over which today's law fires.
    let lawSide: String
    let reach: Int
    let notApplied: Bool
    let oneSideOnly: Bool
    let beyondReach: Bool
}

struct Row: Codable {
    let key: String
    let repository: String
    let file: String
    let line: Int
    let name: String
    let enclosingKind: String
    let typeName: String?
    let isStatic: Bool
    let restriction: String?
    let inScan: Bool
    var today: TodayRow?
    var extended: ExtendedRow?
    var refusal: String?
    var walkEligible = false
    var reach = 0
    var emittableCandidate = false
}

struct GateChange: Codable {
    let key: String
    let condition: String
    let returned: String
}

struct GateAB: Codable {
    var today = 0
    var labelAware = 0
    var gained: [GateChange] = []
    var lost: [GateChange] = []
}

struct SubjectCount: Codable {
    let name: String
    let repository: String
    let revision: String?
    let dirty: Bool
    var files = 0
    var functions = 0
}

struct CensusRecord: Codable {
    var functions = 0
    var files = 0
    var subjects: [SubjectCount] = []
    var replicaDisagreements: [String] = []
    var gateAB = GateAB()
    var rows: [Row] = []
    var refusals: [String: Int] = [:]
}

/// Every `func` with a body, nested ones included.
final class FunctionCollector: SyntaxVisitor {
    var functions: [FunctionDeclSyntax] = []

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.body != nil { functions.append(node) }
        return .visitChildren
    }
}

enum Census {
    static let skippedNames: Set<String> = [".build", "build", "DerivedData", "checkouts", "Pods", "Carthage", ".swiftinfer"]

    static func isSkipped(_ component: String) -> Bool {
        component.hasPrefix(".") || skippedNames.contains(component) || component == "Tests" || component == "tests"
            || component.hasSuffix("Tests") || component.lowercased() == "fixtures"
    }

    /// `.swift` files under `root`, skipping §3's directories below the root (never the root's own path).
    static func swiftFiles(under root: URL, sourcesComponentOnly: Bool) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        var found: [URL] = []
        for case let url as URL in walker {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if isSkipped(url.lastPathComponent) { walker.skipDescendants() }
            } else if url.pathExtension == "swift" {
                let relative = url.path.dropFirst(root.path.count).split(separator: "/")
                if !sourcesComponentOnly || relative.dropLast().contains("Sources") { found.append(url) }
            }
        }
        return found.sorted { $0.path < $1.path }
    }

    /// The longest `String` the stub's edge-biased generator can draw (§2.3).
    static func reach(line: Int, source: String) -> Int {
        let longest = SubjectLiterals.harvest(declarationAt: line, in: source).map(\.count).max()
        return max(10, (longest ?? 0) + 8)
    }

    /// Reads one file into `record`. `repository` and `repositoryRoot` key the rows.
    static func read(
        source: String,
        path: String,
        repository: String,
        repositoryRoot: String,
        into record: inout CensusRecord
    ) -> Int {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: path, tree: tree)
        let statics = StaticConstants(tree)
        let scanned = FunctionScanner.scanCorpus(source: source, file: path)
        let summaries = Dictionary(scanned.summaries.map { ($0.location.line, $0) }) { first, _ in first }
        let restrictions = Dictionary(scanned.restricted.map { ($0.summary.location.line, $0.restriction) }) { a, _ in a }
        let collector = FunctionCollector(viewMode: .sourceAccurate)
        collector.walk(tree)
        let relative = path.hasPrefix(repositoryRoot + "/") ? String(path.dropFirst(repositoryRoot.count + 1)) : path
        for function in collector.functions {
            let line = converter.location(for: function.funcKeyword.positionAfterSkippingLeadingTrivia).line
            let key = "\(repository):\(relative):\(line) \(function.name.text)"
            read(function, line: line, key: key, source: source, statics: statics,
                 summary: summaries[line], restriction: restrictions[line], repository: repository,
                 relative: relative, into: &record)
        }
        return collector.functions.count
    }

    // swiftlint:disable:next function_parameter_count
    private static func read(
        _ function: FunctionDeclSyntax,
        line: Int,
        key: String,
        source: String,
        statics table: StaticConstants,
        summary: FunctionSummary?,
        restriction: AccessRestriction?,
        repository: String,
        relative: String,
        into record: inout CensusRecord
    ) {
        let shipped = GuardDomainReader.read(function)
        let replica = ReplicaReader.read(function, gate: .text)
        let shippedTuple = shipped.map { [$0.condition, $0.returnedExpression, $0.parameterName, "\($0.firesWhenConditionHolds)"] }
        let replicaTuple = replica.map { [$0.condition, $0.returnedExpression, $0.parameterName, "\($0.firesWhenConditionHolds)"] }
        if shippedTuple != replicaTuple { record.replicaDisagreements.append(key) }
        let labelAware = ReplicaReader.read(function, gate: .labelAware)
        if shipped != nil { record.gateAB.today += 1 }
        if labelAware != nil { record.gateAB.labelAware += 1 }
        if let labelAware, replica == nil {
            record.gateAB.gained.append(GateChange(key: key, condition: labelAware.condition, returned: labelAware.returnedExpression))
        }
        if let replica, labelAware == nil {
            record.gateAB.lost.append(GateChange(key: key, condition: replica.condition, returned: replica.returnedExpression))
        }

        let enclosing = Enclosing.of(Syntax(function))
        let scope = table.scope(for: enclosing.typeName)
        var row = Row(
            key: key, repository: repository, file: relative, line: line, name: function.name.text,
            enclosingKind: enclosing.kind, typeName: enclosing.typeName,
            isStatic: function.modifiers.contains { [.keyword(.static), .keyword(.class)].contains($0.name.tokenKind) },
            restriction: restriction?.rawValue, inScan: summary != nil
        )
        var interesting = false
        let reach = { Census.reach(line: line, source: source) }

        // (a): today's template row whose condition compares a count.
        if let summary, GuardDomainTemplate.suggest(for: summary) != nil, let replica, replica.conditionNodes.count >= 1,
           let comparison = comparison(of: replica, statics: scope) {
            let (lo, hi) = comparison.boundary
            let lawAbove = comparison.holds(at: hi) == replica.firesWhenConditionHolds
            let drawn = reach()
            row.reach = drawn
            row.today = TodayRow(
                condition: replica.condition, returned: replica.returnedExpression,
                firesWhenConditionHolds: replica.firesWhenConditionHolds, n: comparison.n, op: comparison.op,
                lo: lo, hi: hi, lawSide: lawAbove ? "≥\(hi)" : "≤\(lo)", reach: drawn,
                notApplied: lawAbove && hi > drawn, oneSideOnly: drawn < hi, beyondReach: hi > drawn
            )
            var context = ExtendedReader.Context(
                parameter: replica.parameterName,
                parameterType: function.signature.parameterClause.parameters.first?.type.trimmedDescription ?? "",
                statics: scope
            )
            context.cReasons = []
            row.walkEligible = ["String", "Substring"].contains(context.parameterType)
                && WalkEligibility.isEligible(comparison.counted, context: context)
            interesting = true
        }

        // (b) and (c): the extended reader.
        switch ExtendedReader.read(function, statics: scope) {
        case .admitted(var extended):
            let sameAsToday = shipped.map {
                $0.returnedExpression == extended.counted && $0.firesWhenConditionHolds == extended.lawWhenConditionHolds
            } ?? false
            extended.isNew = !sameAsToday
            row.extended = extended
            row.walkEligible = row.walkEligible || extended.walkEligible
            if row.reach == 0 { row.reach = reach() }
            interesting = true
        case .refused(let reason):
            row.refusal = reason
            let bucket = reason.split(separator: ":").first.map(String.init) ?? reason
            record.refusals[bucket.hasPrefix("let ") ? "let initialiser" : bucket, default: 0] += 1
            interesting = true
        case .notApplicable:
            break
        }
        guard interesting else { return }

        let changes = (row.today?.beyondReach == true) || (row.extended?.isNew == true)
        let blocked = restriction.map { $0 != .internalOrSPI } ?? false
        row.emittableCandidate = changes && row.walkEligible && row.inScan && !blocked
            && enclosing.kind != "actor" && enclosing.kind != "nested" && enclosing.kind != "protocol"
        record.rows.append(row)
    }

    private static func comparison(of replica: ReplicaDomain, statics: StaticConstants.Scope) -> CountComparison? {
        if replica.fromTernary {
            return CountComparison.read(elements: replica.conditionNodes, statics: statics)
        }
        guard replica.conditionNodes.count == 1 else { return nil }
        return CountComparison.read(replica.conditionNodes[0], statics: statics)
    }
}
