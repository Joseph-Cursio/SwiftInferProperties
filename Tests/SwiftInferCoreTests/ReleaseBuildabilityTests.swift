import Foundation
import SwiftParser
import SwiftSyntax
import Testing

/// **Nothing in the suite release-builds the package, so a release-only break is
/// invisible to it.**
///
/// `make test` runs `swift build` in **debug**. On 2026-08-18 the `soundness-probe`
/// target shipped using `@testable import`, which needs `-enable-testing` — a flag a
/// release build does not pass. `swift build -c release` failed outright with *"module
/// 'SwiftInferCLI' was not compiled for testing"*, and it was found only because the
/// whole-corpus survey needs a release binary. Every test had been green throughout.
///
/// ## Why a static guard rather than a release build in `make test`
///
/// Adding `swift build -c release` to the standard target costs a full second
/// optimised build on every run — minutes, on the developer loop this repo deliberately
/// keeps at ~35s. This guard costs milliseconds and catches the specific mechanism.
///
/// It does **not** catch every way a release build can break. That is the trade, stated
/// rather than implied: what it catches is `@testable` outside a `#if DEBUG` guard, which
/// is the one that actually happened.
///
/// ## It parses, because a text match over-matched
///
/// The first version tested `text.contains("@testable")` and reported **29 offenders**,
/// every one a false positive: this package emits `@testable import` *into generated
/// stubs*, so `VerifyImportSet`, `KitSuiteEmitter` and two dozen others carry the string
/// in a literal or a doc comment. An `ImportDeclSyntax` carrying the `testable` attribute
/// is the thing that breaks a release build; a string that spells it is not.
///
/// Third detector in this repo to over-match on a text window before being given a
/// parser — see `docs/measurements/modify-accessor-misclassification.md`.
@Suite("Sources — nothing needs testability outside a DEBUG guard")
struct ReleaseBuildabilityTests {

    @Test("no shipped source uses `@testable` without a DEBUG guard")
    func testableImportsAreDebugGuarded() throws {
        let sources = PurityRefutationCensusMeasuredTests.packageRoot
            .appendingPathComponent("Sources")
        let walker = try #require(
            FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        )

        var scanned = 0
        var offenders: [String] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            scanned += 1
            let collector = TestableImportCollector(viewMode: .sourceAccurate)
            collector.walk(Parser.parse(source: text))
            if collector.unguarded { offenders.append(url.lastPathComponent) }
        }

        #expect(scanned > 100, """
        Only \(scanned) files scanned under `Sources/`. The walk is not reaching the \
        package, so the pass below means nothing — this repo's confident zero.
        """)
        #expect(offenders.isEmpty, """
        These shipped sources use `@testable` outside a `#if DEBUG` guard, so \
        `swift build -c release` will fail with "module … was not compiled for testing": \
        \(offenders.sorted().joined(separator: ", "))
        """)
    }
}

/// A real `@testable import` declaration that is **not** inside a `#if`.
///
/// Both halves are read off the syntax rather than the text, and the second half is why:
/// the first version asked whether the file *contained* the string `#if DEBUG`, which
/// `//#if DEBUG` satisfies. Commenting the guard out would have kept the test green while
/// breaking the release build — a guard defeated by the exact edit it exists to catch.
final class TestableImportCollector: SyntaxVisitor {
    private(set) var unguarded = false

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let isTestable = node.attributes.contains { attribute in
            attribute.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "testable"
        }
        guard isTestable, !Self.isInsideIfConfig(node) else { return .skipChildren }
        unguarded = true
        return .skipChildren
    }

    /// Any enclosing `#if` counts. Which condition it tests is deliberately not checked:
    /// the failure is an unconditional testable import, and a project that guards one on
    /// something other than `DEBUG` has still thought about it.
    static func isInsideIfConfig(_ node: some SyntaxProtocol) -> Bool {
        var parent = node.parent
        while let current = parent {
            if current.is(IfConfigDeclSyntax.self) { return true }
            parent = current.parent
        }
        return false
    }
}
