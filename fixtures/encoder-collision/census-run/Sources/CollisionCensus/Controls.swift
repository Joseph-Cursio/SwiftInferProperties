import Foundation

/// §4: the controls, asserted before any subject is read.
enum Controls {
    static func record(_ sources: [(String, String)]) -> CensusRecord {
        var record = CensusRecord()
        let files = sources.map { Census.parse(source: $0.1, path: "/control/\($0.0)", repositoryRoot: "/control") }
        _ = Census.read(repository: "/control", files: files, into: &record)
        _ = Census.foundationFailures(&record)
        return record
    }

    static func run(controlSources: URL) -> [String] {
        var failures: [String] = []
        func load(_ name: String) -> (String, String) {
            let text = (try? String(contentsOf: controlSources.appendingPathComponent(name + ".swift.txt"), encoding: .utf8)) ?? ""
            if text.isEmpty { failures.append("missing control source \(name)") }
            return (name + ".swift", text)
        }
        func check(_ condition: Bool, _ message: String) { if !condition { failures.append(message) } }

        // Verbatim, e36da59.
        let before = record(["DepsScript", "ComponentScript", "ActivityScript"].map { load("e36da59-\($0)") })
        var foundationFailures = before
        check(Census.foundationFailures(&foundationFailures).isEmpty, "e36da59: a witness disagrees with Foundation")
        let admitted = before.sites.filter { $0.filing == "admitted" }
        let expected: Set<String> = ["DepsScript.buildMermaidText mermaidId", "ComponentScript.buildPlantUMLText safeAlias",
                                     "ComponentScript.buildMermaidText safeAlias"]
        let got = Set(admitted.map { "\($0.ownerType ?? "?").\($0.owner) \($0.callee)" })
        check(got == expected && admitted.count == 3, "e36da59 admitted \(admitted.map { "\($0.ownerType ?? "?").\($0.owner):\($0.line) \($0.literal)" })")
        check(admitted.contains { $0.owner == "buildMermaidText" && $0.idExpression == "mermaidId(node)" && $0.literal.contains("label") },
              "e36da59: the DepsScript site is not read through `safeId` and `label`")
        check(admitted.contains { $0.owner == "buildMermaidText" && $0.literal.contains("subgraph") },
              "e36da59: the ComponentScript Mermaid site is not the `subgraph` line")
        for name in ["mermaidId", "safeAlias"] {
            let chain = before.candidates.first { $0.candidate.name == name }?.candidate
            check(chain?.witness != nil, "e36da59: \(name) has no witness")
            check(!(chain?.identifierWitnesses.isEmpty ?? true), "e36da59: \(name) has no identifier witness")
        }
        let escape = before.candidates.first { $0.candidate.name == "mermaidEscape" }?.candidate
        check(escape?.isChain == true && escape?.witness == nil, "e36da59: mermaidEscape is not a chain without a witness")
        check(!before.sites.contains { $0.literal.contains("interfaceName") }, "e36da59: the interface line is a site")
        check(!before.sites.contains { $0.literal.contains("-->") || $0.literal.contains("style") || $0.literal.contains("-.->") },
              "e36da59: an edge or style line is a site")

        // Verbatim, 9ad7631.
        let after = record(["DepsScript", "ComponentScript", "ActivityScript"].map { load("9ad7631-\($0)") })
        check(!after.sites.contains { $0.filing == "admitted" }, "9ad7631 admitted \(after.sites.filter { $0.filing == "admitted" }.map(\.literal))")

        // Synthetic.
        let synthetic = record([("Synthetic.swift", syntheticSource)])
        let filings = Dictionary(grouping: synthetic.sites, by: \.owner).mapValues { $0.map(\.filing) }
        let expectations: [(String, [String]?)] = [
            ("printed", ["refused: no returned buffer"]),
            ("trapped", ["refused: no returned buffer"]),
            ("setSkip", ["skipped: set member (insert)"]),
            ("dictSkip", ["skipped: dictionary key"]),
            ("compared", ["skipped: compared"]),
            ("twoArms", ["admitted"]),
            ("armWithout", nil),
            ("charMap", ["recall: not a chain"]),
            ("unresolved", nil),
            ("trailing", ["admitted"]),
            ("ambiguous", ["refused: ambiguous"]),
            ("description", nil),
        ]
        for (owner, filing) in expectations {
            check(filings[owner] == filing, "synthetic \(owner): expected \(filing ?? []), got \(filings[owner] ?? [])")
        }
        check((synthetic.tally["not a site: no declaration in the repository"] ?? 0) >= 1, "synthetic: the unresolved call was not tallied")
        if ProcessInfo.processInfo.environment["CONTROLS_DUMP"] != nil {
            for (label, rec) in [("e36da59", before), ("9ad7631", after), ("synthetic", synthetic)] {
                for site in rec.sites { print("\(label) \(site.ownerType ?? "?").\(site.owner):\(site.line) [\(site.filing)] \(site.idExpression) | \(site.literal)") }
                for row in rec.candidates { print("\(label) candidate \(row.candidate.typeName ?? "-").\(row.candidate.name) chain=\(row.candidate.isChain) witness=\(String(describing: row.candidate.witness)) ids=\(row.candidate.identifierWitnesses.map { "\($0.first)/\($0.second)" })") }
                print("\(label) tally \(rec.tally)")
            }
        }
        return failures
    }

    static let syntheticSource = #"""
    struct Node { let name: String; let kind: String? }

    enum Sanitize {
        static func sid(_ name: String) -> String {
            name.replacingOccurrences(of: ".", with: "_").replacingOccurrences(of: " ", with: "_")
        }
        static func cid(_ name: String) -> String {
            String(name.map { $0.isLetter ? $0 : "_" })
        }
    }

    extension Sanitize {
        static func printed(_ nodes: [Node]) {
            for node in nodes { print("\(sid(node.name)) \(node.name)") }
        }
        static func trapped(_ nodes: [Node]) -> String {
            for node in nodes { precondition(!node.name.isEmpty, "\(sid(node.name)) \(node.name)") }
            return ""
        }
        static func setSkip(_ nodes: [Node]) -> String {
            var lines: [String] = []
            var seen = Set<String>()
            for node in nodes {
                let id = sid(node.name)
                seen.insert(id)
                lines.append("\(id)[\(node.name)]")
            }
            return lines.joined(separator: "\n")
        }
        static func dictSkip(_ nodes: [Node]) -> String {
            var lines: [String] = []
            var byId: [String: Node] = [:]
            for node in nodes {
                byId[sid(node.name)] = node
                lines.append("\(sid(node.name))[\(node.name)]")
            }
            return lines.joined()
        }
        static func compared(_ nodes: [Node], root: String) -> String {
            var out = ""
            for node in nodes {
                if sid(node.name) == root { continue }
                out += "\(sid(node.name)) \(node.name)\n"
            }
            return out
        }
        static func twoArms(_ nodes: [Node]) -> String {
            var lines = ["graph"]
            for node in nodes {
                let label: String
                if let kind = node.kind { label = "\(node.name) <<\(kind)>>" } else { label = node.name }
                lines.append("  \(sid(node.name))[\"\(label)\"]")
            }
            return lines.joined(separator: "\n")
        }
        static func armWithout(_ nodes: [Node]) -> String {
            var lines = ["graph"]
            for node in nodes {
                let label: String
                if let kind = node.kind { label = "\(node.name) <<\(kind)>>" } else { label = "anonymous" }
                lines.append("  \(sid(node.name))[\"\(label)\"]")
            }
            return lines.joined(separator: "\n")
        }
        static func charMap(_ nodes: [Node]) -> String {
            var lines: [String] = []
            for node in nodes { lines.append("\(cid(node.name)) [label=\"\(node.name)\"]") }
            return lines.joined(separator: "\n")
        }
        static func unresolved(_ nodes: [Node]) -> String {
            var lines: [String] = []
            for node in nodes { lines.append("\(escapedName(node.name)) \(node.name)") }
            return lines.joined(separator: "\n")
        }
        static func trailing(_ nodes: [Node]) -> String {
            var lines: [String] = []
            for node in nodes { lines.append("\(Sanitize.sid(node.name)) : \(node.name)") }
            return lines.joined(separator: "\n") + "\n"
        }
    }

    struct Labelled {
        let name: String
        var description: String { "\(Sanitize.sid(name)) \(name)" }
    }

    enum First { static func tid(_ s: String) -> String { s.replacingOccurrences(of: "-", with: "_") } }
    enum Second { static func tid(_ s: String) -> String { s.replacingOccurrences(of: "+", with: "_") } }
    enum Third {
        static func ambiguous(_ nodes: [Node]) -> String {
            var lines: [String] = []
            for node in nodes { lines.append("\(tid(node.name)) \(node.name)") }
            return lines.joined()
        }
    }
    """#
}
