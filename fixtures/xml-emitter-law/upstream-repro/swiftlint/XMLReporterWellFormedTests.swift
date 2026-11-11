// Drop into Tests/FileSystemAccessTests/ and run `swift test --filter XMLReporterWellFormedTests`.
// Each case builds one violation, renders it with an XML reporter and asks XMLParser whether the report is
// well-formed. On `main` the control-character, noncharacter, combining-mark and GitLab rule-identifier cases fail.
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import Testing

@testable import SwiftLintFramework

struct XMLReporterWellFormedTests {
    private static let reporters: [any Reporter.Type] = [
        CheckstyleReporter.self, JUnitReporter.self, GitLabJUnitReporter.self,
    ]

    private static func violation(
        identifier: String = "todo", reason: String, file: String? = "Todo.swift"
    ) -> StyleViolation {
        StyleViolation(
            ruleDescription: RuleDescription(identifier: identifier, name: "Todo", description: "", kind: .lint),
            location: Location(file: file.map { URL(fileURLWithPath: $0) }, line: 1, character: 4),
            reason: reason
        )
    }

    private static func isWellFormed(_ report: String) -> Bool {
        XMLParser(data: Data(report.utf8)).parse()
    }

    @Test(arguments: [
        "TODOs should be resolved (\u{1B}[1mbold\u{1B}[0m later)", // a pasted ANSI escape, as the `todo` rule copies it
        "Avoid print\u{1}",                                       // a custom rule's message
        "a\u{FFFE}b",                                             // a noncharacter
        "use a <\u{301} b",                                       // '<' + U+0301 COMBINING ACUTE ACCENT
        "x &\u{301} y",
        "say \"\u{301}hi\"",
        "a < b & \"c\" 'd' > e",                                  // control: what is escaped today
    ])
    func reasonKeepsReportWellFormed(reason: String) {
        for reporter in Self.reporters {
            let report = reporter.generateReport([Self.violation(reason: reason)])
            #expect(Self.isWellFormed(report), "\(reporter.identifier): \(report)")
        }
    }

    @Test
    func filePathKeepsReportWellFormed() {
        for reporter in Self.reporters {
            let report = reporter.generateReport([Self.violation(reason: "r", file: "/tmp/a\u{1}b.swift")])
            #expect(Self.isWellFormed(report), "\(reporter.identifier): \(report)")
        }
    }

    /// A `custom_rules` key is used as the rule identifier unchanged.
    @Test(arguments: ["a<b", "a&b", "it's"])
    func ruleIdentifierKeepsReportWellFormed(identifier: String) {
        for reporter in Self.reporters {
            let report = reporter.generateReport([Self.violation(identifier: identifier, reason: "Avoid print")])
            #expect(Self.isWellFormed(report), "\(reporter.identifier): \(report)")
        }
    }
}
