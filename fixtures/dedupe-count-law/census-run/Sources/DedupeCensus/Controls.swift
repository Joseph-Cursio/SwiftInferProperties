import Foundation
import SwiftParser
import SwiftSyntax

/// §4's controls, on in-memory sources. Four are read verbatim from their files; the rest are written here.
enum Controls {
    struct Expected {
        var admitted: Bool
        var route: BodyGate.Route?
        var keepFirst: Bool?
        var candidate: Bool?
        var nameRefusal: String?
        var shapeRefusal: String?
        var bodyRefusal: String?
        var candidateRefusal: String?
    }

    static func function(named name: String, in source: String) -> FunctionDeclSyntax? {
        let collector = FunctionCollector(viewMode: .sourceAccurate)
        collector.walk(Parser.parse(source: source))
        return collector.functions.first { $0.name.text == name }
    }

    static let setBody = """
        var seen: Set<Int> = []
        var result: [Int] = []
        for x in xs {
            if seen.insert(x).inserted {
                result.append(x)
            }
        }
        return result
    """

    static let synthetic: [(String, String, String, Expected)] = [
        ("filter form", "uniqued",
         "func uniqued(_ xs: [Int]) -> [Int] { var seen = Set<Int>(); return xs.filter { seen.insert($0).inserted } }",
         Expected(admitted: true, route: .set, keepFirst: true, candidate: true)),
        ("adjacent", "uniquingAdjacentElements", """
         extension Sequence where Element: Equatable {
             func uniquingAdjacentElements() -> [Element] { var seen: Set<Int> = []; var result: [Element] = []; for x in self { if seen.insert(1).inserted { result.append(x) } }; return result }
         }
         """, Expected(admitted: false, nameRefusal: "name: revoking tail")),
        ("key closure", "dedupe",
         "func dedupe(_ xs: [Int], by key: (Int) -> Int) -> [Int] {\n\(setBody)\n}",
         Expected(admitted: false, shapeRefusal: "shape: parameters")),
        ("two arrays", "deduplicated",
         "func deduplicated(_ a: [Int], _ b: [Int]) -> [Int] {\n\(setBody.replacingOccurrences(of: "in xs", with: "in a"))\n}",
         Expected(admitted: false, shapeRefusal: "shape: parameters")),
        ("filters too", "dedupe", """
         func dedupe(_ xs: [Int]) -> [Int] {
             var seen: Set<Int> = []
             var result: [Int] = []
             for x in xs {
                 guard x > 0 else { continue }
                 if seen.insert(x).inserted { result.append(x) }
             }
             return result
         }
         """, Expected(admitted: false, bodyRefusal: BodyGate.otherSkip)),
        ("pass-through", "dedupe", """
         func dedupe(_ xs: [Item]) -> [Item] {
             var seen: Set<String> = []
             var result: [Item] = []
             for x in xs {
                 guard let id = x.id else { result.append(x); continue }
                 if seen.insert(id).inserted { result.append(x) }
             }
             return result
         }
         """, Expected(admitted: false, bodyRefusal: BodyGate.appendNotBehindInsert)),
        ("extra append", "dedupe", """
         func dedupe(_ xs: [Int]) -> [Int] {
             var seen: Set<Int> = []
             var result: [Int] = []
             for x in xs {
                 if seen.insert(x).inserted { result.append(x) }
             }
             result.append(0)
             return result
         }
         """, Expected(admitted: false, bodyRefusal: BodyGate.appendNotBehindInsert)),
        ("other tail", "dedupeRelationships",
         "func dedupeRelationships(_ xs: [Int]) -> [Int] {\n\(setBody)\n}",
         Expected(admitted: false, nameRefusal: "name: other tail")),
        ("private", "deduped",
         "enum E { private static func deduped(_ xs: [Int]) -> [Int] {\n\(setBody)\n} }",
         Expected(admitted: true, route: .set, keepFirst: true, candidate: false, candidateRefusal: "private")),
        ("generic", "deduped",
         "func deduped<T: Hashable>(_ xs: [T]) -> [T] {\n\(setBody.replacingOccurrences(of: "Int", with: "T"))\n}",
         Expected(admitted: true, route: .set, keepFirst: true, candidate: false, candidateRefusal: "generic element")),
    ]

    /// `(label, file, function, expected)`, read verbatim. Paths are relative to this repository's root.
    static let verbatim: [(String, String, String, Expected)] = [
        ("SwiftUMLBridge dedupe",
         "../SwiftUMLStudio/SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Parsing/CoreDataModelExtractor.swift",
         "dedupe", Expected(admitted: true, route: .set, keepFirst: true, candidate: true)),
        ("ConstructionUniverse.deduplicated", "Sources/SwiftInferCore/ConstructionUniverse.swift",
         "deduplicated", Expected(admitted: true, route: .dictionary, keepFirst: false, candidate: true)),
        ("dedupedByStateAndAction", "Sources/SwiftInferCLI/SwiftInferCommand.DiscoverInteraction+MultiModule.swift",
         "dedupedByStateAndAction", Expected(admitted: true, route: .set, keepFirst: true, candidate: true)),
        ("dedupedByIdentity", "Sources/SwiftInferCLI/SwiftInferCommand.Discover+IdentityDedup.swift",
         "dedupedByIdentity", Expected(admitted: false, bodyRefusal: BodyGate.earlyReturn)),
    ]

    static func check(_ label: String, _ function: FunctionDeclSyntax?, _ expected: Expected) -> [String] {
        guard let function else { return ["\(label): function not found"] }
        let verdict = Census.judge(function)
        var failures: [String] = []
        func expect<T: Equatable>(_ field: String, _ actual: T, _ wanted: T) {
            if actual != wanted { failures.append("\(label): \(field) is \(actual), expected \(wanted)") }
        }
        expect("admitted", verdict.admitted, expected.admitted)
        if let route = expected.route { expect("route", verdict.body?.route, route) }
        if let keepFirst = expected.keepFirst { expect("keepFirst", verdict.body?.keepFirst, keepFirst) }
        if let candidate = expected.candidate { expect("candidate", verdict.candidate, candidate) }
        if let reason = expected.nameRefusal { expect("name refusal", verdict.nameRefusal, reason) }
        if let reason = expected.shapeRefusal { expect("shape refusal", verdict.shapeRefusal, reason) }
        if let reason = expected.bodyRefusal { expect("body refusal", verdict.bodyRefusal, reason) }
        if let reason = expected.candidateRefusal { expect("candidate refusal", verdict.candidateRefusal, reason) }
        if expected.admitted, !verdict.admitted {
            failures.append("\(label): refused by \(verdict.nameRefusal ?? verdict.shapeRefusal ?? verdict.bodyRefusal ?? "?")")
        }
        return failures
    }

    static func run(repositoryRoot: URL) -> [String] {
        var failures: [String] = []
        for (label, name, source, expected) in synthetic {
            failures += check(label, function(named: name, in: source), expected)
        }
        for (label, path, name, expected) in verbatim {
            let url = repositoryRoot.appendingPathComponent(path)
            guard let source = try? String(contentsOf: url, encoding: .utf8) else {
                failures.append("\(label): cannot read \(url.path)")
                continue
            }
            failures += check(label, function(named: name, in: source), expected)
        }
        return failures
    }
}
