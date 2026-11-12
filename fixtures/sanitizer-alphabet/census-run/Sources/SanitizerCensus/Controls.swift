import Foundation
import SwiftParser
import SwiftSyntax

/// §4's controls. Five are read verbatim from their files; the rest are written here.
enum Controls {
    struct Expected {
        var admitted: Bool
        var core: String?
        var law1: Bool?
        var candidate: Bool?
        var refusal: String?
        var fallback: Bool?
        var preTransform: Bool?
        var prefixRule: Bool?
    }

    static func function(named name: String, in source: String) -> FunctionDeclSyntax? {
        let collector = FunctionCollector(viewMode: .sourceAccurate)
        collector.walk(Parser.parse(source: source))
        return collector.functions.first { $0.name.text == name }
    }

    static let synthetic: [(String, String, String, Expected)] = [
        ("key-path filter", "lettersOnly", "func lettersOnly(_ s: String) -> String { s.filter(\\.isLetter) }",
         Expected(admitted: true, core: "F3", law1: true, candidate: true)),
        ("helper predicate", "clean", "func clean(_ s: String) -> String { s.filter { isAllowed($0) } }",
         Expected(admitted: false, refusal: "predicate: other")),
        ("instance state", "clean",
         "struct S { let allowed: Set<Character>; func clean(_ s: String) -> String { s.filter { allowed.contains($0) } } }",
         Expected(admitted: false, refusal: "predicate: other")),
        ("decoration", "suite", "func suite(_ s: String) -> String { s.filter(\\.isLetter) + \"Tests\" }",
         Expected(admitted: false)),
        ("split/join", "slug",
         "func slug(_ s: String) -> String { s.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: \"-\") }",
         Expected(admitted: false, refusal: "core: none")),
        ("token wrapping", "wrap", """
         func wrap(_ s: String) -> String {
             var out = ""
             for c in s {
                 if c.isLetter { out.append(c) } else { out += "\\"" + String(c) + "\\"" }
             }
             return out
         }
         """, Expected(admitted: false)),
        ("prefix cap", "short", "func short(_ s: String) -> String { String(s.filter(\\.isLetter).prefix(8)) }",
         Expected(admitted: false)),
        ("instance method", "clean", "struct T { func clean(_ s: String) -> String { s.filter(\\.isLetter) } }",
         Expected(admitted: true, core: "F3", candidate: false)),
    ]

    /// `(label, path from this repository's root, function, expected)`, read verbatim.
    static let verbatim: [(String, String, String, Expected)] = [
        ("sanitizeType", "../SwiftUMLStudio/SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Emitters/ERScript.swift",
         "sanitizeType", Expected(admitted: true, core: "F1", law1: true, candidate: true, fallback: true)),
        ("moduleIdentifier", "Sources/SwiftInferCLI/InteractiveTriage+StubFile.swift", "moduleIdentifier",
         Expected(admitted: true, core: "F2", law1: true, candidate: true)),
        ("sanitizeForFileName", "Sources/SwiftInferCLI/InteractiveTriage+StubName.swift", "sanitizeForFileName",
         Expected(admitted: true, core: "F2", law1: true, candidate: false)),
        ("alphanumericsOnly",
         "../SwiftProjectLint/Packages/SwiftProjectLintRules/Sources/SwiftProjectLintRules/Security/Visitors/SecurityVisitor.swift",
         "alphanumericsOnly", Expected(admitted: true, core: "F3", law1: false, candidate: true, preTransform: true)),
        ("c99Identifier",
         "../SwiftProjectLint/Packages/SwiftProjectLintRules/Sources/SwiftProjectLintRules/Architecture/Models/PackageManifest.swift",
         "c99Identifier", Expected(admitted: true, core: "F2", law1: false, candidate: true, prefixRule: true)),
    ]

    static func check(_ label: String, _ function: FunctionDeclSyntax?, _ expected: Expected) -> [String] {
        guard let function else { return ["\(label): function not found"] }
        let verdict = Census.judge(function)
        var failures: [String] = []
        func expect<T: Equatable>(_ field: String, _ actual: T, _ wanted: T) {
            if actual != wanted { failures.append("\(label): \(field) is \(actual), expected \(wanted)") }
        }
        expect("admitted", verdict.admitted, expected.admitted)
        if expected.admitted, !verdict.admitted { failures.append("\(label): refused by \(verdict.refusal ?? "?")") }
        if let core = expected.core { expect("core", verdict.reading?.core, core) }
        if let law1 = expected.law1 { expect("law1", verdict.reading?.law1, law1) }
        if let candidate = expected.candidate { expect("candidate", verdict.candidate, candidate) }
        if let refusal = expected.refusal { expect("refusal", verdict.refusal, refusal) }
        if let fallback = expected.fallback { expect("fallback", verdict.reading?.fallback, fallback) }
        if let pre = expected.preTransform { expect("preTransform", verdict.reading?.preTransform, pre) }
        if let prefix = expected.prefixRule { expect("prefixRule", verdict.reading?.prefixRule, prefix) }
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
