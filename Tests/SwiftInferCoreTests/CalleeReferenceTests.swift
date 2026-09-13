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
        isMutatingMethod: Bool = false,
        isComputedProperty: Bool = false,
        globalActor: String? = nil
    ) -> Evidence {
        Evidence(
            displayName: displayName,
            signature: "(String) -> String",
            location: SourceLocation(file: "F.swift", line: 1, column: 1),
            isInstanceMethod: isInstanceMethod,
            isMutatingMethod: isMutatingMethod,
            isComputedProperty: isComputedProperty,
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

    /// **An instance method takes a receiver, and the receiver is the first argument.**
    /// `Formatter.trimmed(value)` is the curried `(Formatter) -> (String) -> String` and does not
    /// type-check, so qualification is the wrong repair here — the caller supplies one more
    /// argument and the first becomes the receiver.
    ///
    /// This test previously asserted `call("value") == "trimmed(value)"`, pinning the bare
    /// spelling as intended behaviour. It was pinning the defect: a receiverless call to an
    /// instance method cannot compile from a free-standing test function, whatever the template.
    @Test func anInstanceMethodIsCalledOnItsReceiver() {
        let callee = CalleeReference(evidence: evidence(
            "trimmed(_:)", qualifiedTypeName: "Formatter", isInstanceMethod: true
        ))
        #expect(callee?.call("lhs", "rhs") == "lhs.trimmed(rhs)")
        #expect(callee?.qualifier == nil)
    }

    /// An instance method's labels still apply — to its own arguments, not to the receiver.
    @Test func anInstanceMethodKeepsItsLabels() {
        let callee = CalleeReference(evidence: evidence(
            "merging(with:)", qualifiedTypeName: "Doc", isInstanceMethod: true
        ))
        #expect(callee?.call("lhs", "rhs") == "lhs.merging(with: rhs)")
    }

    /// A nullary instance method needs only its receiver, so it fits a one-argument template —
    /// and nests, which is what `idempotence` asks of it.
    @Test func aNullaryInstanceMethodFitsAOneArgumentTemplate() {
        let callee = try? #require(CalleeReference(evidence: evidence(
            "normalized()", qualifiedTypeName: "Doc", isInstanceMethod: true
        )))
        #expect(callee?.applicationArity == 1)
        #expect(callee?.call("value") == "value.normalized()")
        #expect(callee.map { $0.call($0.call("value")) } == "value.normalized().normalized()")
    }

    // MARK: - Arity, and declining what cannot be called

    /// The rule the whole withdrawal rests on: a one-parameter instance method costs two
    /// arguments, so it fits `commutativity` and cannot fit `idempotence`.
    @Test func aOneParameterInstanceMethodCostsTwoArguments() {
        let callee = CalleeReference(evidence: evidence(
            "union(_:)", qualifiedTypeName: "Ranges", isInstanceMethod: true
        ))
        #expect(callee?.applicationArity == 2)
        #expect(callee?.accepts(applicationArity: 2) == true)
        #expect(callee?.accepts(applicationArity: 1) == false)
    }

    @Test func aStaticMemberCostsExactlyItsParameters() {
        let callee = CalleeReference(evidence: evidence(
            "strippingHeadingMarkers(from:)", qualifiedTypeName: "EditorFormatter"
        ))
        #expect(callee?.applicationArity == 1)
        #expect(callee?.accepts(applicationArity: 1) == true)
    }

    /// A mutating method returns `Void` and edits in place, so no value law states anything
    /// about it. Declining at construction means every caller declines without repeating why.
    @Test func aMutatingMethodIsNotACallee() {
        #expect(CalleeReference(evidence: evidence(
            "normalize()", qualifiedTypeName: "Doc", isInstanceMethod: true, isMutatingMethod: true
        )) == nil)
    }

    // MARK: - Shapes that are not calls

    /// A computed property is accessed. Emitting `value.count()` is a different error from the
    /// one qualification fixes, and it cost swift-system 5 of 6 build failures on the verify side.
    @Test func aComputedPropertyIsAccessedNotCalled() {
        let callee = CalleeReference(evidence: evidence(
            "trimmed()", qualifiedTypeName: "Doc", isInstanceMethod: true, isComputedProperty: true
        ))
        #expect(callee?.applicationArity == 1)
        #expect(callee?.call("value") == "value.trimmed")
    }

    @Test func aStaticComputedPropertyTakesNoArgumentsAtAll() {
        let callee = CalleeReference(evidence: evidence(
            "shared()", qualifiedTypeName: "Doc", isComputedProperty: true
        ))
        #expect(callee?.applicationArity == 0)
        #expect(callee?.accepts(applicationArity: 1) == false)
    }

    /// `Money.+` is not a spelling; `+(lhs, rhs)` is. An operator is left unqualified even when
    /// the row records a declaring type.
    @Test func anOperatorIsNeverQualified() {
        let callee = CalleeReference(evidence: evidence("+(_:_:)", qualifiedTypeName: "Money"))
        #expect(callee?.qualifier == nil)
        #expect(callee?.call("lhs", "rhs") == "+(lhs, rhs)")
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
