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

    @Test("protocol scanner: Void-method protocol is fakeable; non-Void / property is not")
    func protocolFakeability() {
        let fakeable = ViewModelProtocolScanner.scan(
            source: "protocol Store { func save(_ id: Int) async throws; func clearAll() }"
        )
        #expect(fakeable.first?.name == "Store")
        #expect(fakeable.first?.isFakeable == true)

        let nonVoid = ViewModelProtocolScanner.scan(source: "protocol Counter { func count() -> Int }")
        #expect(nonVoid.first?.isFakeable == false)

        let property = ViewModelProtocolScanner.scan(source: "protocol HasName { var name: String { get } }")
        #expect(property.first?.isFakeable == false)
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
        // A protocol with a non-Void requirement can't be no-op faked.
        let protocols = ViewModelProtocolScanner.scan(source: "protocol Store { func count() -> Int }")
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
