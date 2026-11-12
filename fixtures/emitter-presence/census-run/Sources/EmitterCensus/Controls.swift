import Foundation
import SwiftParser
import SwiftSyntax

/// §4's controls. Four are read verbatim from SwiftUMLStudio `e36da59` (copied into `control-sources/`); the rest
/// are written here. Each is read as its own repository, so helper hops resolve only within it.
enum Controls {
    struct Expected {
        var admitted: Bool
        var tier: String?
        var statableKinds: [String]?
        var candidate: Bool?
        var refusal: String?
        var widening: String?
        var obligationKind: String?
        var guardText: String?
        var chain: [String]?
        var transform: String?
        var maxDepth: Int?
    }

    static func rows(sources: [(String, String)]) -> [String: Row] {
        var record = CensusRecord()
        let parsed = sources.map { Census.parse(source: $0.1, path: "/controls/\($0.0)", repositoryRoot: "/controls") }
        let index = Census.index(parsed)
        for file in parsed { Census.read(file, repository: "controls", index: index, into: &record) }
        return Dictionary(record.rows.map { ($0.name, $0) }) { first, _ in first }
    }

    static let synthetic: [(String, String, String, Expected)] = [
        ("if let guard", "f", """
         func f(model: M) -> String { var lines: [String] = []; for n in model.nodes { if let line = nodeLine(n) { lines.append(line) } }; return lines.joined(separator: "\\n") }
         """, Expected(admitted: false, refusal: "no statable obligation", obligationKind: "call-guarded")),
        ("where guard", "f", """
         func f(model: M) -> String { var lines: [String] = []; for s in model.states where s.isFinal { lines.append("[*] <- \\(s.name)") }; return lines.joined() }
         """, Expected(admitted: true, tier: "as-written", statableKinds: ["primary"], guardText: "s.isFinal")),
        ("dedupe via Set", "f", """
         func f(model: M) -> String { var lines: [String] = []; let names = Set(model.edges.map(\\.from)); for n in names { lines.append("node \\(n)") }; return lines.joined() }
         """, Expected(admitted: false, refusal: "no obligation")),
        ("trailing removeLast", "f", """
         func f(model: M) -> String { var lines: [String] = []; for n in model.nodes { lines.append("node \\(n.name)") }; lines.removeLast(); return lines.joined() }
         """, Expected(admitted: false)),
        ("break", "f", """
         func f(model: M) -> String { var lines: [String] = []; for n in model.nodes { if lines.count > 9 { break }; lines.append("node \\(n.name)") }; return lines.joined() }
         """, Expected(admitted: false, refusal: "exit in loop")),
        ("scalar loop", "f", """
         func f(text: String) -> String { var out = ""; for scalar in text.unicodeScalars { out += "\\(scalar)" }; return out }
         """, Expected(admitted: false, refusal: "no obligation")),
        ("appendAsNewLine", "f", """
         func f(model: M) -> String { var out = ""; for m in model.members { out.appendAsNewLine("+ \\(m.name)") }; return out }
         """, Expected(admitted: false, widening: "W3", obligationKind: "W3")),
        ("sorted() source", "f", """
         func f(model: M) -> String { var lines: [String] = []; for n in model.nodes.sorted() { lines.append("n \\(n)") }; return lines.joined() }
         """, Expected(admitted: false, widening: "W1")),
        ("bare append", "f", """
         func f(model: M) -> [String] { var lines: [String] = []; for n in model.names { lines.append(n) }; return lines }
         """, Expected(admitted: false, refusal: "no statable obligation", obligationKind: "bare")),
        ("private builder", "b", """
         private extension K { static func b(model: M) -> String { var lines: [String] = []; for n in model.nodes { lines.append("node \\(n.name)") }; return lines.joined() } }
         """, Expected(admitted: true, tier: "as-written", statableKinds: ["primary"], candidate: false)),
    ]

    static func check(_ label: String, _ row: Row?, _ expected: Expected) -> [String] {
        guard let row else { return expected.admitted ? ["\(label): no row"] : [] }
        var failures: [String] = []
        let reading = row.reading
        func fail(_ what: String) { failures.append("\(label): \(what) (reading: refusal=\(reading.refusal ?? "-") tier=\(reading.tier ?? "-") obligations=\(reading.obligations.map { "\($0.kind)@\($0.line)" }) widenings=\(reading.widenings))") }
        if row.admitted != expected.admitted { fail("admitted \(row.admitted), expected \(expected.admitted)") }
        if let tier = expected.tier, reading.tier != tier { fail("tier \(reading.tier ?? "-"), expected \(tier)") }
        if let kinds = expected.statableKinds, reading.obligations.filter(\.statable).map(\.kind) != kinds {
            fail("statable kinds \(reading.obligations.filter(\.statable).map(\.kind)), expected \(kinds)")
        }
        if let candidate = expected.candidate, row.candidate != candidate { fail("candidate \(row.candidate)") }
        if let refusal = expected.refusal, reading.refusal != refusal { fail("refusal \(reading.refusal ?? "-"), expected \(refusal)") }
        if let widening = expected.widening, !reading.widenings.contains(widening) { fail("no \(widening)") }
        if let kind = expected.obligationKind, !reading.obligations.contains(where: { $0.kind == kind }) { fail("no \(kind) obligation") }
        if let guardText = expected.guardText, !reading.obligations.contains(where: { $0.guards.contains(guardText) }) {
            fail("no guard \(guardText)")
        }
        if let chain = expected.chain, !reading.obligations.contains(where: { $0.helper?.resolved == true && $0.helper?.chain == chain }) {
            fail("no resolved helper chain \(chain): \(reading.obligations.compactMap(\.helper).map { "\($0.chain) \($0.resolved) \($0.reason ?? "")" })")
        }
        if let transform = expected.transform, !reading.obligations.contains(where: { $0.helper?.transform == transform }) {
            fail("no transform \(transform)")
        }
        if let depth = expected.maxDepth, reading.obligations.filter(\.statable).map(\.depth).max() != depth {
            fail("max depth \(reading.obligations.filter(\.statable).map(\.depth).max() ?? 0), expected \(depth)")
        }
        return failures
    }

    static func run(controlSources: URL) -> [String] {
        var failures: [String] = []
        let names = ["ComponentScript.swift.txt", "ComponentSVGRenderer+SVG.swift.txt", "ComponentSVGRenderer.swift.txt"]
        let sources = names.compactMap { name in
            (try? String(contentsOf: controlSources.appendingPathComponent(name), encoding: .utf8)).map { (name, $0) }
        }
        guard sources.count == names.count else { return ["control sources missing under \(controlSources.path)"] }
        let verbatim = rows(sources: sources)
        failures += check("buildMermaidText", verbatim["buildMermaidText"], Expected(
            admitted: true, tier: "as-written", statableKinds: ["primary", "primary", "primary"], candidate: false, maxDepth: 2))
        failures += check("buildPlantUMLText", verbatim["buildPlantUMLText"], Expected(
            admitted: true, tier: "as-written", statableKinds: ["primary", "primary", "primary"], candidate: false))
        failures += check("renderSVG", verbatim["renderSVG"], Expected(
            admitted: true, tier: "helper", candidate: true, obligationKind: "call-guarded",
            chain: ["componentSVGLines", "textElement"], transform: ".xmlEscaped"))
        failures += check("componentSVGLines", verbatim["componentSVGLines"], Expected(
            admitted: true, tier: "helper", candidate: true, chain: ["textElement"]))
        for (label, name, source, expected) in synthetic {
            failures += check(label, rows(sources: [("synthetic.swift", source)])[name], expected)
        }
        return failures
    }
}
