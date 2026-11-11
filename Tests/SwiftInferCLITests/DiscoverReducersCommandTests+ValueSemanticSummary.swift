import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// MARK: - renderValueSemanticSummary
//
// In a same-file extension: extension bodies are exempt from
// `type_body_length`, keeping the primary suite under the 250-line cap
// (cycle-145 precedent). Same-file extensions still reach the `private`
// `Command` typealias.
extension DiscoverReducersCommandTests {

    private func valueSemanticCandidate(
        typeName: String = "Inventory",
        equatability: EquatableEvidence = .notEquatable
    ) -> ValueSemanticCandidate {
        ValueSemanticCandidate(
            typeName: typeName,
            location: SourceLocation(file: "Sources/\(typeName).swift", line: 10, column: 1),
            referenceBackedMembers: [
                ReferenceBackedMember(name: "items", typeName: "NSMutableArray", kind: .referenceContainer),
                ReferenceBackedMember(name: "onChange", typeName: "() -> Void", kind: .closure),
            ],
            mutationSurface: [
                MutationMethod(name: "add", isMutating: false, parameterCount: 1),
                MutationMethod(name: "removeAll", isMutating: true, parameterCount: 0),
            ],
            equatability: equatability
        )
    }

    @Test("empty candidates yields the value-semantics sentinel")
    func renderValueSemanticEmpty() {
        let rendered = Command.renderValueSemanticSummary([])
        #expect(rendered == "swift-infer discover-reducers: no value-semantics carriers detected.\n")
    }

    @Test("value-semantics block carries members (with kind), mutation surface, and Equatability note")
    func renderValueSemanticPopulated() {
        let rendered = Command.renderValueSemanticSummary([valueSemanticCandidate()])
        #expect(rendered.contains("detected 1 value-semantics carrier (reference-backed structs):"))
        #expect(rendered.contains("Inventory"))
        #expect(rendered.contains("items: NSMutableArray [referenceContainer]"))
        #expect(rendered.contains("onChange: () -> Void [closure]"))
        #expect(rendered.contains("add (non-mutating)"))
        #expect(rendered.contains("removeAll"))
        // A non-Equatable candidate is surfaced but flagged not-verify-ready.
        #expect(rendered.contains("[not verify-ready: notEquatable]"))
    }

    @Test("plural header + no verify-ready note for an Equatable candidate")
    func renderValueSemanticPluralEquatable() {
        let rendered = Command.renderValueSemanticSummary([
            valueSemanticCandidate(typeName: "A", equatability: .equatable),
            valueSemanticCandidate(typeName: "B"),
        ])
        #expect(rendered.contains("detected 2 value-semantics carriers (reference-backed structs):"))
        // The Equatable candidate carries no not-verify-ready note on its line.
        let lineA = rendered.split(separator: "\n").first { $0.contains("  A") }
        #expect(lineA?.contains("not verify-ready") == false)
    }

    // MARK: - Convention-role (VIPER/MVP) section

    @Test("empty roles yields the convention-role sentinel")
    func renderConventionRoleEmpty() {
        let rendered = Command.renderConventionRoleSummary([])
        #expect(rendered == "swift-infer discover-reducers: no convention roles (VIPER/MVP) detected.\n")
    }

    @Test("convention-role block carries paradigm, state, actions, and the output sink")
    func renderConventionRolePopulated() {
        let source = """
        final class LoginPresenter {
            var title: String = ""
            weak var view: LoginViewProtocol?
            let service: AuthServiceProtocol
            init(service: AuthServiceProtocol) { self.service = service }
            func present(_ user: String) { title = user }
        }
        """
        let roles = ConventionRoleDiscoverer.discover(source: source, file: "F.swift")
        let rendered = Command.renderConventionRoleSummary(roles)
        #expect(rendered.contains("detected 1 convention role (VIPER/MVP, by naming/conformance):"))
        #expect(rendered.contains("LoginPresenter  [mvp]"))
        #expect(rendered.contains("state (1): title"))
        #expect(rendered.contains("- present(String)"))
        #expect(rendered.contains("view: LoginViewProtocol?  → output sink [assertable]"))
        #expect(rendered.contains("service: AuthServiceProtocol  → dependency"))
    }
}
