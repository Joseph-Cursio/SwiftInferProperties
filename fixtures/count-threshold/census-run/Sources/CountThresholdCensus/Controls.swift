import Foundation
import SwiftInferCore
import SwiftParser
import SwiftSyntax

/// The scope's §4 controls, on in-memory sources. The run refuses to start unless every one holds.
enum Controls {
    struct Expectation: Sendable {
        let name: String
        let source: String
        let check: @Sendable (Row?) -> String?
    }

    static let compactE36 = """
        struct ActivityGraphBuilder {
            static func compactText(_ text: String) -> String {
                let stripped = text
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\\n", with: " ")
                let collapsed = stripped
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                if collapsed.count > 80 {
                    return String(collapsed.prefix(77)) + "…"
                }
                return collapsed
            }
        }
        """

    static let compact9ad = """
        struct ActivityGraphBuilder {
            static func compactText(_ text: String) -> String {
                let collapsed = text
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                if collapsed.count > 80 {
                    return String(collapsed.prefix(77)) + "…"
                }
                return collapsed
            }
        }
        """

    static let expectations: [Expectation] = [
        Expectation(name: "compactText", source: compactE36) { compactCheck($0) },
        Expectation(name: "compactText", source: compact9ad) { compactCheck($0) },
        Expectation(name: "truncateURL", source: """
            final class InsecureTransportVisitor {
                func truncateURL(_ urlString: String) -> String {
                    if urlString.count > 60 {
                        return String(urlString.prefix(57)) + "..."
                    }
                    return urlString
                }
            }
            """) { row in
            guard let row, let extended = row.extended, let today = row.today else { return "not read" }
            guard extended.isNew, extended.needs == ["b"], extended.walkEligible else { return "extended: \(extended)" }
            guard today.notApplied, today.reach == 11, today.n == 60 else { return "today: \(today)" }
            return nil
        },
        Expectation(name: "preview", source: """
            struct MLXValidateCommand {
                func preview(_ text: String) -> String {
                    let oneLine = text.replacingOccurrences(of: "\\n", with: " ")
                    return oneLine.count > 80 ? String(oneLine.prefix(80)) + "…" : oneLine
                }
            }
            """) { row in
            guard let extended = row?.extended else { return "not admitted: \(row?.refusal ?? "no row")" }
            guard extended.isNew, extended.needs == ["b", "c"], extended.walkEligible, extended.n == 80 else {
                return "extended: \(extended)"
            }
            return nil
        },
        Expectation(name: "truncateOutput", source: """
            public actor CIAdapter {
                static let maxErrorOutputLength = 10_000
                func truncateOutput(_ output: String) -> String {
                    if output.count <= Self.maxErrorOutputLength { return output }
                    let truncated = String(output.prefix(Self.maxErrorOutputLength))
                    return truncated + "\\n... [truncated at \\(Self.maxErrorOutputLength) chars]"
                }
            }
            """) { row in
            guard let row, let today = row.today, let extended = row.extended else { return "not read" }
            guard today.n == 10_000, today.beyondReach, today.lawSide == "≤10000", !today.notApplied else {
                return "today: \(today)"
            }
            guard !extended.isNew, row.walkEligible, !row.emittableCandidate else { return "extended: \(extended)" }
            return nil
        },
        Expectation(name: "trimStep", source: """
            enum ThinkingRecipeExtractor {
                public static let maximumStepLength = 240
                private static func trimStep(_ raw: String) -> String {
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed.count > maximumStepLength else { return trimmed }
                    let end = trimmed.index(trimmed.startIndex, offsetBy: maximumStepLength)
                    return trimmed[..<end].trimmingCharacters(in: .whitespaces) + "…"
                }
            }
            """) { row in
            guard let row, let extended = row.extended else { return "not admitted: \(row?.refusal ?? "no row")" }
            guard extended.isNew, extended.needs == ["c"], extended.cReasons.contains("lets"),
                  extended.cReasons.contains("bareStatic"), extended.walkEligible, extended.n == 240,
                  !extended.lawWhenConditionHolds else { return "extended: \(extended)" }
            guard !row.emittableCandidate else { return "a private function is a candidate" }
            return nil
        },
        Expectation(name: "deriveName", source: """
            enum ThinkingRecipeExtractor {
                static let maximumNameLength = 60
                static func deriveName(from steps: [String]) -> String {
                    guard let first = steps.first else { return "Extracted Recipe" }
                    let stripped = first.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard stripped.count > maximumNameLength else { return stripped }
                    let end = stripped.index(stripped.startIndex, offsetBy: maximumNameLength)
                    return stripped[..<end].trimmingCharacters(in: .whitespaces) + "…"
                }
            }
            """) { row in
            row?.extended == nil && row?.refusal != nil ? nil : "not refused: \(String(describing: row?.extended))"
        },
        Expectation(name: "shout", source: """
            enum Shouter {
                static func shout(_ s: String) -> String {
                    if s.count > 8 { return String(s.prefix(8)) }
                    return s.uppercased()
                }
            }
            """) { row in
            row?.extended == nil ? nil : "admitted although the identity branch is not the counted value"
        },
        Expectation(name: "firstFields", source: """
            enum Fields {
                static func firstFields(_ s: String) -> [Substring] {
                    let parts = s.split(separator: ",")
                    if parts.count > 4 { return Array(parts.prefix(4)) }
                    return parts
                }
            }
            """) { row in
            guard let extended = row?.extended else { return "not admitted: \(row?.refusal ?? "no row")" }
            return extended.walkEligible ? "a derived count is walk-eligible" : nil
        },
    ]

    static func compactCheck(_ row: Row?) -> String? {
        guard let row, let extended = row.extended else { return "not admitted: \(row?.refusal ?? "no row")" }
        guard extended.isNew, extended.form == "cut-first", extended.needs == ["b", "c"], extended.walkEligible,
              extended.n == 80, extended.op == ">", extended.cutForm == "prefix + marker", row.inScan,
              row.emittableCandidate else { return "extended: \(extended), candidate \(row.emittableCandidate)" }
        return nil
    }

    /// Runs every control; returns the failures.
    static func run(testsDirectory: URL) -> [String] {
        var failures: [String] = []
        for (index, expectation) in expectations.enumerated() {
            var record = CensusRecord()
            _ = Census.read(source: expectation.source, path: "/control/\(index).swift", repository: "control",
                            repositoryRoot: "/control", into: &record)
            let row = record.rows.first { $0.name == expectation.name }
            if let failure = expectation.check(row) { failures.append("\(expectation.name) [\(index)]: \(failure)") }
            if !record.replicaDisagreements.isEmpty { failures.append("\(expectation.name): replica disagrees") }
        }
        failures += replicaOnReaderFixtures(testsDirectory)
        return failures
    }

    /// The replica with today's gate against the shipped reader on every function in every source literal of
    /// guard-domain's own reader tests.
    static func replicaOnReaderFixtures(_ directory: URL) -> [String] {
        let siblings = [directory, directory.deletingLastPathComponent().appendingPathComponent("SwiftInferTemplatesTests")]
        let files = siblings.flatMap {
            (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? []
        }
        let readerTests = files.filter { $0.lastPathComponent.hasPrefix("GuardDomain") && $0.pathExtension == "swift" }
        guard !readerTests.isEmpty else { return ["no GuardDomain*Tests.swift under \(directory.path)"] }
        var failures: [String] = []
        var compared = 0
        for file in readerTests {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let literals = LiteralCollector(viewMode: .sourceAccurate)
            literals.walk(Parser.parse(source: text))
            for literal in literals.found where literal.contains("func ") {
                let collector = FunctionCollector(viewMode: .sourceAccurate)
                collector.walk(Parser.parse(source: literal))
                for function in collector.functions {
                    compared += 1
                    let shipped = GuardDomainReader.read(function)
                    let replica = ReplicaReader.read(function, gate: .text)
                    let agree = shipped?.condition == replica?.condition
                        && shipped?.returnedExpression == replica?.returnedExpression
                        && shipped?.firesWhenConditionHolds == replica?.firesWhenConditionHolds
                    if !agree { failures.append("replica disagrees on \(file.lastPathComponent): \(function.name.text)") }
                }
            }
        }
        print("replica compared with the shipped reader on \(compared) guard-domain test functions, "
            + "\(failures.count) disagreements")
        // The plain (non-interpolating) source literals in those files hold 17 functions on 2026-11-11.
        if compared < 15 { failures.append("only \(compared) reader-test functions compared") }
        return failures
    }

    private final class LiteralCollector: SyntaxVisitor {
        var found: [String] = []

        override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
            if let value = node.representedLiteralValue { found.append(value) }
            return .skipChildren
        }
    }
}
