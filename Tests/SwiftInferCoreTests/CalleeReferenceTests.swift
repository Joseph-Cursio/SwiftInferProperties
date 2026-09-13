@testable import SwiftInferCore
import Testing

/// How an emitted stub spells a call to the function it tests (#415).
///
/// The measured defect: 19 stubs emitted for SwiftMarkdownWiki, 0 compiling, because every call
/// came out bare — no declaring type, no argument labels. `EditorFormatter.strippingHeadingMarkers(from:)`
/// was emitted as `strippingHeadingMarkers(strippingHeadingMarkers(value))`.
@Suite("Callee spelling for emitted stubs")
struct CalleeReferenceTests {

    private func evidence(
        _ displayName: String,
        qualifiedTypeName: String? = nil,
        isInstanceMethod: Bool = false,
        globalActor: String? = nil
    ) -> Evidence {
        Evidence(
            displayName: displayName,
            signature: "(String) -> String",
            location: SourceLocation(file: "F.swift", line: 1, column: 1),
            isInstanceMethod: isInstanceMethod,
            qualifiedTypeName: qualifiedTypeName,
            globalActor: globalActor
        )
    }

    // MARK: - The measured case

    @Test func aStaticMemberIsQualifiedAndLabelled() {
        let callee = CalleeReference(evidence: evidence(
            "strippingHeadingMarkers(from:)", qualifiedTypeName: "EditorFormatter"
        ))
        #expect(callee?.call("value") == "EditorFormatter.strippingHeadingMarkers(from: value)")
        #expect(callee?.bareName == "strippingHeadingMarkers")
        #expect(callee?.displaySignature == "EditorFormatter.strippingHeadingMarkers(from:)")
    }

    /// The nested-type path is carried whole — `qualifiedTypeName` is the full lexical path, so a
    /// member of a nested type is still nameable from a test file.
    @Test func aNestedDeclaringTypeKeepsItsWholePath() {
        let callee = CalleeReference(evidence: evidence(
            "render(_:)", qualifiedTypeName: "SwiftInferCommand.Scaffold"
        ))
        #expect(callee?.call("value") == "SwiftInferCommand.Scaffold.render(value)")
    }

    // MARK: - What must not change

    /// **A free function renders byte-identically to the old splice**, which is what keeps every
    /// pre-existing golden honest instead of re-baselined alongside the fix.
    @Test func aFreeFunctionRendersExactlyAsBefore() {
        let callee = CalleeReference(evidence: evidence("normalize(_:)"))
        #expect(callee?.call("value") == "normalize(value)")
        #expect(callee?.callPrefix.isEmpty == true)
    }

    /// **An instance method is deliberately left unqualified.** It needs a receiver, which these
    /// value-law templates do not generate; `EditorFormatter.selectedText(value)` would be a
    /// different error from the one being fixed, not a fix.
    @Test func anInstanceMethodIsNotQualified() {
        let callee = CalleeReference(evidence: evidence(
            "trimmed(_:)", qualifiedTypeName: "Formatter", isInstanceMethod: true
        ))
        #expect(callee?.call("value") == "trimmed(value)")
    }

    // MARK: - Label parsing

    @Test("labels are read out of the display name", arguments: [
        ("f()", [String?]()),
        ("f(_:)", [nil]),
        ("f(from:)", ["from"]),
        ("f(_:_:)", [nil, nil]),
        ("f(of:with:)", ["of", "with"]),
        ("f(_:to:)", [nil, "to"])
    ])
    func labelParsing(displayName: String, expected: [String?]) {
        #expect(CalleeReference(evidence: evidence(displayName))?.argumentLabels == expected)
    }

    /// More arguments than recorded labels renders positionally rather than wrongly. Every
    /// hand-built `Evidence` in a test fixture has whatever `displayName` its author typed, and a
    /// mismatch must not produce a label on the wrong argument.
    @Test func argumentsBeyondTheRecordedLabelsAreUnlabelled() {
        let callee = CalleeReference(evidence: evidence("combine(of:)"))
        #expect(callee?.call("a", "b") == "combine(of: a, b)")
    }

    // MARK: - Actor isolation

    /// **The hop goes around the whole property, not around each call.** `MainActor.run` takes a
    /// *synchronous* `@MainActor` closure, so `await` cannot appear inside one — wrapping each
    /// call individually would emit `await MainActor.run { f(await MainActor.run { f(x) }) }`,
    /// which does not compile.
    @Test func anIsolatedCalleeWrapsTheWholeExpression() {
        let callee = CalleeReference(evidence: evidence(
            "strippingHeadingMarkers(from:)", qualifiedTypeName: "EditorFormatter", globalActor: "MainActor"
        ))
        let inner = callee!.call(callee!.call("value"))
        #expect(callee?.isolated("\(inner) == x") == "await MainActor.run { \(inner) == x }")
        // The calls themselves are untouched — one hop, not three.
        #expect(inner.contains("MainActor") == false)
    }

    @Test func aNonisolatedCalleeIsNotWrapped() {
        let callee = CalleeReference(evidence: evidence("normalize(_:)"))
        #expect(callee?.isolated("a == b") == "a == b")
    }

    /// Any global actor, not just `MainActor` — the scanner reads the attribute name.
    @Test func aCustomGlobalActorIsCarried() {
        let callee = CalleeReference(evidence: evidence("f(_:)", globalActor: "DatabaseActor"))
        #expect(callee?.isolated("a == b") == "await DatabaseActor.run { a == b }")
    }

    @Test func aDisplayNameWithNoParenthesesIsNotACallee() {
        #expect(CalleeReference(evidence: evidence("normalize")) == nil)
    }
}
