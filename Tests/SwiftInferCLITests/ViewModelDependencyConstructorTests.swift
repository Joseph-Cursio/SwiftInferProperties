@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// PROTOTYPE — protocol scanning + dependency-faking construction.
@Suite("ViewModel dependency faking (prototype)")
struct ViewModelDependencyConstructorTests {

    private func candidate(
        initParameters: [ViewModelInitParameter],
        constructibility: ViewModelConstructibility
    ) -> ViewModelCandidate {
        ViewModelCandidate(
            location: "VM.swift:1",
            typeName: "VM",
            observability: .observableObject,
            stateFields: [],
            actions: [],
            constructibility: constructibility,
            initParameters: initParameters
        )
    }

    @Test("faker stubs property + non-Void method requirements with defaults")
    func fakesPropertyAndNonVoid() {
        let store = ViewModelProtocolScanner.scan(
            source: "protocol Store { var name: String { get }; "
                + "func save(_ id: Int) async throws; func count() -> Int; func latest() -> Int? }"
        )[0]
        let fake = ViewModelProtocolFaker.fakeStruct(for: store)
        #expect(fake?.contains("struct Fake_Store: Store") == true)
        #expect(fake?.contains("var name: String = \"\"") == true)
        #expect(fake?.contains("func save(_ id: Int) async throws { }") == true)
        #expect(fake?.contains("func count() -> Int { return 0 }") == true)
        #expect(fake?.contains("func latest() -> Int? { return nil }") == true)
    }

    @Test("non-defaultable return / associatedtype / static → not fakeable")
    func nonFakeable() {
        let custom = ViewModelProtocolScanner.scan(source: "protocol Maker { func make() -> Widget }")[0]
        #expect(ViewModelProtocolFaker.fakeStruct(for: custom) == nil)

        let assoc = ViewModelProtocolScanner.scan(source: "protocol Box { associatedtype Item }")[0]
        #expect(ViewModelProtocolFaker.fakeStruct(for: assoc) == nil)

        let staticReq = ViewModelProtocolScanner.scan(source: "protocol Shared { static func make() }")[0]
        #expect(ViewModelProtocolFaker.fakeStruct(for: staticReq) == nil)
    }

    @Test("zero-arg view model constructs as Type() with no preamble")
    func zeroArgConstruction() {
        let construction = ViewModelDependencyConstructor.resolve(
            candidate(initParameters: [], constructibility: .zeroArgument),
            protocols: []
        )
        #expect(construction?.expression == "VM()")
        #expect(construction?.preamble.isEmpty == true)
    }

    @Test("protocol dependency is satisfied by a synthesized no-op fake")
    func fakesProtocolDependency() {
        let protocols = ViewModelProtocolScanner.scan(source: "protocol Store { func clearAll() }")
        let construction = ViewModelDependencyConstructor.resolve(
            candidate(
                initParameters: [.init(label: "store", typeText: "Store")],
                constructibility: .requiresArguments(["store"])
            ),
            protocols: protocols
        )
        #expect(construction?.expression == "VM(store: Fake_Store())")
        #expect(construction?.preamble.contains("struct Fake_Store: Store") == true)
        #expect(construction?.preamble.contains("func clearAll() { }") == true)
    }

    @Test("Optional + scalar dependencies use nil / defaults; existential strips `any`")
    func optionalAndScalar() {
        let protocols = ViewModelProtocolScanner.scan(source: "protocol Store {}")
        let construction = ViewModelDependencyConstructor.resolve(
            candidate(
                initParameters: [
                    .init(label: "store", typeText: "any Store"),
                    .init(label: "fallback", typeText: "Workspace?"),
                    .init(label: "limit", typeText: "Int")
                ],
                constructibility: .requiresArguments(["store", "limit"])
            ),
            protocols: protocols
        )
        #expect(construction?.expression == "VM(store: Fake_Store(), fallback: nil, limit: 0)")
    }

    @Test("non-fakeable dependency gates construction")
    func gatesNonFakeable() {
        // A protocol with a non-defaultable return type can't be faked.
        let protocols = ViewModelProtocolScanner.scan(source: "protocol Store { func make() -> Widget }")
        let construction = ViewModelDependencyConstructor.resolve(
            candidate(
                initParameters: [.init(label: "store", typeText: "Store")],
                constructibility: .requiresArguments(["store"])
            ),
            protocols: protocols
        )
        #expect(construction == nil)
    }
}
