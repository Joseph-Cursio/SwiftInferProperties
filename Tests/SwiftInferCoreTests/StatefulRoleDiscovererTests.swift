@testable import SwiftInferCore
import SwiftParser
import SwiftSyntax
import Testing

/// Stub policy: claims any `struct` whose name ends in "Feature".
private struct StubFeaturePolicy: RolePolicy {
    let paradigm = Paradigm.tca

    func recognize(_ decl: DeclSyntax, in context: FileContext) -> RoleMatch? {
        guard let structDecl = decl.as(StructDeclSyntax.self),
              structDecl.name.text.hasSuffix("Feature") else {
            return nil
        }
        return RoleMatch(
            decl: decl,
            typeName: structDecl.name.text,
            location: context.locationString(of: structDecl),
            recognizedBy: .convention
        )
    }

    func buildRole(from match: RoleMatch, in _: FileContext) -> StatefulRole {
        StatefulRole(
            location: match.location,
            typeName: match.typeName,
            paradigm: paradigm,
            recognizedBy: match.recognizedBy,
            state: .namedType("State"),
            actions: [RoleAction(name: "tick", parameterTypes: [])],
            construction: .freeFunction(name: "reduce")
        )
    }

    var distinctiveProperties: [PropertyKind] { [.idempotence] }
}

/// A second policy that also matches "*Feature" — used to test precedence.
private struct SecondaryFeaturePolicy: RolePolicy {
    let paradigm = Paradigm.mvvm

    func recognize(_ decl: DeclSyntax, in context: FileContext) -> RoleMatch? {
        guard let structDecl = decl.as(StructDeclSyntax.self),
              structDecl.name.text.hasSuffix("Feature") else {
            return nil
        }
        return RoleMatch(
            decl: decl,
            typeName: structDecl.name.text,
            location: context.locationString(of: structDecl),
            recognizedBy: .conformance
        )
    }

    func buildRole(from match: RoleMatch, in _: FileContext) -> StatefulRole {
        StatefulRole(
            location: match.location,
            typeName: match.typeName,
            paradigm: paradigm,
            recognizedBy: match.recognizedBy,
            state: .namedType("S"),
            actions: [],
            construction: .freeFunction(name: "r")
        )
    }

    var distinctiveProperties: [PropertyKind] { [] }
}

/// Phase 0 — proves the `StatefulRoleDiscoverer` engine drives the `RolePolicy`
/// seam end to end (walk → recognize → buildRole) using stub policies. No
/// production policy is wired yet (that is Phase 1), so the engine ships inert.
@Suite("StatefulRoleDiscoverer engine")
struct StatefulRoleDiscovererTests {

    private func discover(_ source: String, policies: [RolePolicy]) -> [StatefulRole] {
        let tree = Parser.parse(source: source)
        return StatefulRoleDiscoverer(policies: policies).discover(in: tree, file: "Test.swift")
    }

    @Test("Engine applies a policy and produces a role for a matching decl")
    func enginePicksUpMatchingDecl() throws {
        let roles = discover(
            """
            struct CounterFeature {
                var count = 0
            }
            struct PlainThing {
                var x = 0
            }
            """,
            policies: [StubFeaturePolicy()]
        )
        #expect(roles.count == 1)
        let role = try #require(roles.first)
        #expect(role.typeName == "CounterFeature")
        #expect(role.recognizedBy == .convention)
        #expect(role.location == "Test.swift:1")
    }

    @Test("No matching decls → no roles")
    func noMatchNoRoles() {
        #expect(discover("struct Plain { var x = 0 }", policies: [StubFeaturePolicy()]).isEmpty)
    }

    @Test("First policy to claim a decl wins (precedence order)")
    func firstPolicyWins() {
        let roles = discover(
            "struct AppFeature { var x = 0 }",
            policies: [StubFeaturePolicy(), SecondaryFeaturePolicy()]
        )
        #expect(roles.count == 1)
        #expect(roles.first?.paradigm == .tca)   // StubFeaturePolicy (first) won
    }

    @Test("Engine collects file imports into the context")
    func collectsImports() {
        let tree = Parser.parse(source: """
        import ComposableArchitecture
        import SwiftUI
        struct X {}
        """)
        #expect(StatefulRoleDiscoverer.imports(in: tree) == ["ComposableArchitecture", "SwiftUI"])
    }
}
