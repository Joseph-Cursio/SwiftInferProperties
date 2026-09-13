import Foundation
import Testing

@testable import SwiftInferCore

/// Global-actor isolation that a type inherits from a **conformance** rather than from an
/// attribute it carries (SwiftInferProperties#440).
///
/// The depth this suite exercises is deliberately deeper than the corpus does. Every hop the
/// change added to SwiftMarkdownWiki was a *direct* conformance to a seed protocol, so a flat
/// `Set.contains` would have produced the same six stubs — the fixed point's reason for existing
/// is a project that declares `protocol Pane: View`, and no corpus subject has yet. Unit tests
/// are therefore the only place the transitive behaviour is stated, which is exactly why the
/// cycle and multi-hop cases below are here rather than left to a later road test.
@Suite("MainActorProtocols — isolation inherited through conformance")
struct MainActorProtocolsTests {

    private func decl(_ name: String, _ kind: TypeDecl.Kind, _ inherits: [String]) -> TypeDecl {
        TypeDecl(
            name: name,
            kind: kind,
            inheritedTypes: inherits,
            location: SourceLocation(file: "F.swift", line: 1, column: 1)
        )
    }

    @Test("An empty project confers exactly the seed")
    func emptyProjectConfersTheSeed() {
        #expect(MainActorProtocols.conferring(in: []) == MainActorProtocols.frameworkSeed)
    }

    @Test("A protocol refining a seed protocol joins the set")
    func oneHopJoins() {
        let conferring = MainActorProtocols.conferring(in: [decl("Pane", .protocol, ["View"])])
        #expect(conferring.contains("Pane"))
    }

    /// The case a flat list cannot reach, and the one SwiftProjectLint measured as costing 673
    /// false skips when the equivalent rule matched a literal string.
    @Test("Refinement is transitive to three levels")
    func threeHopsJoin() {
        let conferring = MainActorProtocols.conferring(in: [
            decl("Pane", .protocol, ["View"]),
            decl("SplitPane", .protocol, ["Pane"]),
            decl("EditorPane", .protocol, ["SplitPane"])
        ])
        #expect(conferring.isSuperset(of: ["Pane", "SplitPane", "EditorPane"]))
    }

    /// Order independence is the property that makes this a fixed point rather than a pass.
    /// Declared leaf-first, a single sweep would promote nothing.
    @Test("Declaration order does not change the answer")
    func declarationOrderIsIrrelevant() {
        let leafFirst = MainActorProtocols.conferring(in: [
            decl("EditorPane", .protocol, ["SplitPane"]),
            decl("SplitPane", .protocol, ["Pane"]),
            decl("Pane", .protocol, ["View"])
        ])
        #expect(leafFirst.isSuperset(of: ["Pane", "SplitPane", "EditorPane"]))
    }

    /// Monotone growth means a cycle simply never promotes. It is a refusal, not a hang and not
    /// a wrong answer — the loop terminates because the set only ever grows and is bounded.
    @Test("A cycle among protocols promotes none of them")
    func aCycleRefusesRatherThanHangs() {
        let conferring = MainActorProtocols.conferring(in: [
            decl("Alpha", .protocol, ["Beta"]),
            decl("Beta", .protocol, ["Alpha"])
        ])
        #expect(conferring.contains("Alpha") == false)
        #expect(conferring.contains("Beta") == false)
    }

    /// A *conformer* must not become a conferrer. `SearchResultRow: View` is main-actor, but
    /// nothing conforming to `SearchResultRow` inherits that — it is a struct, not a protocol.
    /// Promoting it would grow the set in the unsafe direction, which is the whole reason the
    /// walk filters on `kind == .protocol`.
    @Test("A struct conforming to a seed protocol does not itself confer")
    func aConformerIsNotAConferrer() {
        let conferring = MainActorProtocols.conferring(in: [
            decl("SearchResultRow", .struct, ["View"])
        ])
        #expect(conferring.contains("SearchResultRow") == false)
    }

    @Test("A type conforming to a conferring protocol is isolated")
    func conformerIsIsolated() {
        let typeDecls = [
            decl("Pane", .protocol, ["View"]),
            decl("EditorPane", .struct, ["Pane"])
        ]
        let conferring = MainActorProtocols.conferring(in: typeDecls)
        #expect(
            MainActorProtocols.isolation(
                ofTypeNamed: "EditorPane", conferring: conferring, in: typeDecls
            ) == "MainActor"
        )
    }

    /// The direction that matters: inventing an actor breaks a stub that worked, so a type with
    /// no route to the seed must answer `nil` rather than guess from its name.
    @Test("A type named like a view but conforming to nothing is not isolated")
    func anUnrelatedTypeIsNotIsolated() {
        let typeDecls = [decl("PreviewView", .struct, ["Equatable"])]
        #expect(
            MainActorProtocols.isolation(
                ofTypeNamed: "PreviewView",
                conferring: MainActorProtocols.conferring(in: typeDecls),
                in: typeDecls
            ) == nil
        )
    }

    /// Conformances are routinely added in an extension rather than the primary declaration,
    /// and `isolation(ofTypeNamed:)` reads every decl carrying the name for that reason.
    @Test("A conformance declared in an extension isolates the type")
    func extensionConformanceCounts() {
        let typeDecls = [
            decl("Sidebar", .struct, []),
            decl("Sidebar", .extension, ["View"])
        ]
        #expect(
            MainActorProtocols.isolation(
                ofTypeNamed: "Sidebar",
                conferring: MainActorProtocols.conferring(in: typeDecls),
                in: typeDecls
            ) == "MainActor"
        )
    }

    @Test("A generic protocol in an inheritance clause matches on its base name")
    func genericConformanceMatchesBaseName() {
        let typeDecls = [
            decl("Box", .protocol, ["View"]),
            decl("Wrapper", .struct, ["Box<Int>"])
        ]
        #expect(
            MainActorProtocols.isolation(
                ofTypeNamed: "Wrapper",
                conferring: MainActorProtocols.conferring(in: typeDecls),
                in: typeDecls
            ) == "MainActor"
        )
    }

    /// Pins the corpus shape that prompted the WebKit half of the seed: a delegate conformance
    /// alongside `NSObject`, where the isolation comes from the protocol and `NSObject`
    /// contributes nothing.
    @Test("The KaTeXSchemeHandler shape resolves through the WebKit seed")
    func theMeasuredWebKitShapeResolves() {
        let typeDecls = [decl("KaTeXSchemeHandler", .class, ["NSObject", "WKURLSchemeHandler"])]
        #expect(
            MainActorProtocols.isolation(
                ofTypeNamed: "KaTeXSchemeHandler",
                conferring: MainActorProtocols.conferring(in: typeDecls),
                in: typeDecls
            ) == "MainActor"
        )
    }

    /// `NSObject` is in no seed and must not be, or every Objective-C bridging class in a
    /// project would be declared main-actor and get a hop it does not need.
    @Test("NSObject alone confers nothing")
    func nsObjectAloneConfersNothing() {
        let typeDecls = [decl("Coordinator", .class, ["NSObject"])]
        #expect(
            MainActorProtocols.isolation(
                ofTypeNamed: "Coordinator",
                conferring: MainActorProtocols.conferring(in: typeDecls),
                in: typeDecls
            ) == nil
        )
    }

    /// `ObservableObject` is the entry most likely to be added by someone reaching for the
    /// "obvious" missing protocol. It is a Combine protocol with no isolation of its own, and a
    /// great many non-isolated view models conform to it.
    @Test("ObservableObject is deliberately absent from the seed")
    func observableObjectIsNotSeeded() {
        #expect(MainActorProtocols.frameworkSeed.contains("ObservableObject") == false)
        #expect(MainActorProtocols.frameworkSeed.contains("NSObjectProtocol") == false)
    }
}
