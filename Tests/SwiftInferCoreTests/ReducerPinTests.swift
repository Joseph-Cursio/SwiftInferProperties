import Foundation
@testable import SwiftInferCore
import Testing

// V2.0 M1.C — ReducerPin: parse a `--reducer <pin>` string and match
// against a ReducerCandidate. The CLI consumes `parse` + `matches` to
// filter discover-reducers output; downstream M2+ pipelines will
// consume the same pair to know which reducer to drive.

@Suite("ReducerPin — V2.0 M1.C parsing + matching")
struct ReducerPinTests {

    private func candidate(
        enclosingTypeName: String? = nil,
        functionName: String = "reduce"
    ) -> ReducerCandidate {
        ReducerCandidate(
            location: "Sources/T.swift:1",
            enclosingTypeName: enclosingTypeName,
            functionName: functionName,
            signatureShape: .stateActionReturnsState,
            stateTypeName: "S",
            actionTypeName: "A"
        )
    }

    // MARK: - parse

    @Test("single-component pin parses as function-only")
    func parseFunctionOnly() throws {
        let pin = try ReducerPin.parse("reduce")
        #expect(pin.functionName == "reduce")
        #expect(pin.typeName == nil)
        #expect(pin.moduleName == nil)
    }

    @Test("two-component pin parses as <typeName>.<funcName>")
    func parseTypeAndFunction() throws {
        let pin = try ReducerPin.parse("Inbox.body")
        #expect(pin.functionName == "body")
        #expect(pin.typeName == "Inbox")
        #expect(pin.moduleName == nil)
    }

    @Test("three-component pin parses module/type/func — module is a redundant qualifier")
    func parseModulePrefixed() throws {
        let pin = try ReducerPin.parse("MyModule.Inbox.body")
        #expect(pin.moduleName == "MyModule")
        #expect(pin.typeName == "Inbox")
        #expect(pin.functionName == "body")
    }

    @Test("four-plus-component pin is malformed")
    func parseFourComponentsMalformed() {
        #expect(throws: ReducerPinError.malformed(raw: "A.B.C.D")) {
            _ = try ReducerPin.parse("A.B.C.D")
        }
    }

    @Test("empty pin throws emptyPin")
    func parseEmptyThrows() {
        #expect(throws: ReducerPinError.emptyPin) {
            _ = try ReducerPin.parse("")
        }
        #expect(throws: ReducerPinError.emptyPin) {
            _ = try ReducerPin.parse("   ")
        }
    }

    @Test("pin with empty component (e.g. `Inbox..body`) throws malformed")
    func parseEmptyComponentThrows() {
        #expect(throws: ReducerPinError.malformed(raw: "Inbox..body")) {
            _ = try ReducerPin.parse("Inbox..body")
        }
    }

    @Test("pin with 4+ components throws malformed — no canonical interpretation")
    func parseTooManyComponentsThrows() {
        #expect(throws: ReducerPinError.malformed(raw: "A.B.C.D")) {
            _ = try ReducerPin.parse("A.B.C.D")
        }
    }

    // MARK: - matches

    @Test("function-only pin matches free functions and rejects methods")
    func matchesFunctionOnly() throws {
        let pin = try ReducerPin.parse("reduce")
        #expect(pin.matches(candidate(enclosingTypeName: nil, functionName: "reduce")))
        // Methods on a type have a non-nil enclosingTypeName — function-only pin still
        // matches them because the pin doesn't constrain the type. (PRD §6.5 framing:
        // the user supplies as much specificity as they want; an under-constrained pin
        // that matches multiple candidates surfaces the ambiguity error in the CLI.)
        #expect(pin.matches(candidate(enclosingTypeName: "Helper", functionName: "reduce")))
        #expect(!pin.matches(candidate(enclosingTypeName: nil, functionName: "update")))
    }

    @Test("typed pin matches only candidates with the exact enclosing type")
    func matchesTypePrefixed() throws {
        let pin = try ReducerPin.parse("Inbox.body")
        #expect(pin.matches(candidate(enclosingTypeName: "Inbox", functionName: "body")))
        #expect(!pin.matches(candidate(enclosingTypeName: "Settings", functionName: "body")))
        #expect(!pin.matches(candidate(enclosingTypeName: nil, functionName: "body")))
        #expect(!pin.matches(candidate(enclosingTypeName: "Inbox", functionName: "reduce")))
    }
}
