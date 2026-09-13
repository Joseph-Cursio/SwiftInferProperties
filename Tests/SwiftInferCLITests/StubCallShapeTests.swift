import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Accept-path stubs spliced the BARE function name into the property expression, which is
/// right for a free function and wrong for a type member — and on this repo's own
/// `SwiftInferCore`, 25 of 25 emitted subjects were type members and 0 were free functions
/// (#415). Compiler-confirmed on a four-shape control before this existed: the free arm built
/// clean, both member arms failed `cannot find 'staticTrim' in scope`.
///
/// Every expectation below was watched fail against the unfixed emitter.
@Suite("StubCallShape — how an accepted suggestion's subject is called (#415)")
struct StubCallShapeTests {

    // MARK: - Free and static

    @Test("a free function is called by bare name, exactly as before")
    func freeFunctionIsUnchanged() {
        let call = StubCallShape.callExpression(
            for: evidence(displayName: "freeTrim(_:)"),
            applicationArity: 1
        )
        #expect(call == "freeTrim")
    }

    @Test("a static member is qualified by its declaring type")
    func staticMemberIsQualified() {
        let call = StubCallShape.callExpression(
            for: evidence(displayName: "staticTrim(_:)", qualifiedTypeName: "Formatter"),
            applicationArity: 1
        )
        #expect(call == "Formatter.staticTrim")
    }

    /// The label half. `stripping(from:)` cannot be called `stripping(x)`, so the shape is a
    /// trampoline closure the stub applies positionally — `VerifyCommand`'s rule, on this side.
    @Test("an argument label becomes a trampoline closure")
    func labelBecomesTrampoline() {
        let call = StubCallShape.callExpression(
            for: evidence(displayName: "stripping(from:)", qualifiedTypeName: "Formatter"),
            applicationArity: 1
        )
        #expect(call == "{ Formatter.stripping(from: $0) }")
    }

    /// The lexical path, not the bare carrier name — a nested type is only nameable in full.
    @Test("a nested type's full path is used")
    func nestedTypePathIsUsed() {
        let call = StubCallShape.callExpression(
            for: evidence(displayName: "trim(_:)", qualifiedTypeName: "Outer.Inner"),
            applicationArity: 1
        )
        #expect(call == "Outer.Inner.trim")
    }

    // MARK: - Instance

    /// `Doc.merge(lhs, rhs)` does not type-check — `Doc.merge` is the curried
    /// `(Doc) -> (Doc) -> Doc`. The receiver comes first and the method's own arguments follow.
    @Test("a binary instance method becomes a receiver closure")
    func binaryInstanceMethodUsesReceiver() {
        let call = StubCallShape.callExpression(
            for: evidence(
                displayName: "merge(_:)", qualifiedTypeName: "Doc", isInstanceMethod: true
            ),
            applicationArity: 2
        )
        #expect(call == "{ $0.merge($1) }")
    }

    @Test("a nullary instance method fits a one-argument template")
    func nullaryInstanceMethodFitsUnaryTemplate() {
        let call = StubCallShape.callExpression(
            for: evidence(
                displayName: "squeezed()", qualifiedTypeName: "Doc", isInstanceMethod: true
            ),
            applicationArity: 1
        )
        #expect(call == "{ $0.squeezed() }")
    }

    @Test("a computed property is accessed, not called")
    func computedPropertyIsAccessed() {
        let call = StubCallShape.callExpression(
            for: evidence(
                displayName: "conjugate()",
                qualifiedTypeName: "Complex",
                isInstanceMethod: true,
                isComputedProperty: true
            ),
            applicationArity: 1
        )
        #expect(call == "{ $0.conjugate }")
    }

    // MARK: - Declines

    /// The withdrawal this change makes, and the reason it is a withdrawal rather than a bug
    /// fix: `idempotence` applies one argument, and a one-parameter instance method needs two
    /// (receiver + argument). There is no correct stub, so none is written.
    @Test("a one-parameter instance method declines a one-argument template")
    func arityMismatchDeclines() {
        let call = StubCallShape.callExpression(
            for: evidence(
                displayName: "merge(_:)", qualifiedTypeName: "Doc", isInstanceMethod: true
            ),
            applicationArity: 1
        )
        #expect(call == nil)
    }

    /// A mutating method returns `Void`, so it is not the value-returning receiver shape.
    @Test("a mutating instance method declines")
    func mutatingMethodDeclines() {
        let call = StubCallShape.callExpression(
            for: evidence(
                displayName: "formUnion(_:)",
                qualifiedTypeName: "Bag",
                isInstanceMethod: true,
                isMutatingMethod: true
            ),
            applicationArity: 2
        )
        #expect(call == nil)
    }

    // MARK: - Left alone

    /// `Money.+` is not a spelling, and the operator arms have their own emitter path. Changing
    /// two things at once would make the corpus A/B unreadable.
    @Test("an operator is left exactly as it was")
    func operatorIsUntouched() {
        let call = StubCallShape.callExpression(
            for: evidence(displayName: "+(_:_:)", qualifiedTypeName: "Money"),
            applicationArity: 2
        )
        #expect(call == "+")
    }

    // MARK: - Fixture

    private func evidence(
        displayName: String,
        qualifiedTypeName: String? = nil,
        isInstanceMethod: Bool = false,
        isMutatingMethod: Bool = false,
        isComputedProperty: Bool = false
    ) -> Evidence {
        Evidence(
            displayName: displayName,
            signature: "(String) -> String",
            location: SourceLocation(file: "/tmp/Subject.swift", line: 1, column: 1),
            isInstanceMethod: isInstanceMethod,
            isMutatingMethod: isMutatingMethod,
            isComputedProperty: isComputedProperty,
            qualifiedTypeName: qualifiedTypeName
        )
    }
}
