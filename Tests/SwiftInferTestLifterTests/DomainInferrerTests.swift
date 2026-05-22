import SwiftInferCore
@testable import SwiftInferTestLifter
import Testing

@Suite("DomainInferrer — round-trip-pair domain inference (M10.2)")
struct DomainInferrerTests {

    // MARK: - Fixtures

    private static let pair = RoundTripPair(
        forwardName: "encode",
        reverseName: "decode",
        domainTypeName: "MyType"
    )

    /// Build a `FunctionSummary` that passes every veto check by
    /// default — single non-throwing non-async parameter. Tests
    /// override individual fields for the negative-path veto cases.
    private static func unaryNonThrowing(
        name: String = "encode",
        isThrows: Bool = false,
        isAsync: Bool = false,
        parameterCount: Int = 1
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: (0..<parameterCount).map { idx in
                Parameter(label: nil, internalName: "p\(idx)", typeText: "MyType", isInout: false)
            },
            returnTypeText: "Data",
            isThrows: isThrows,
            isAsync: isAsync,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Codec.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
    }

    private static func directSites(_ count: Int, producer: String = "encode") -> [DomainCallSite] {
        (0..<count).map { _ in
            DomainCallSite(argument: .callOutput(producerName: producer))
        }
    }

    private static func identifierSites(_ count: Int, name: String) -> [DomainCallSite] {
        (0..<count).map { _ in
            DomainCallSite(argument: .identifier(name: name))
        }
    }

    // MARK: - Threshold

    @Test("Below threshold (2 sites) produces no hint")
    func belowThresholdNoHint() {
        let hint = DomainInferrer.infer(
            pair: Self.pair,
            forwardSummary: Self.unaryNonThrowing(),
            sites: Self.directSites(2),
            setupBindings: [:],
            producerArgGeneratable: true
        )
        #expect(hint == nil)
    }

    @Test("At threshold (3 sites all callOutput(forward)) produces unvetoed hint")
    func atThresholdHomogeneousHintFires() throws {
        let hint = try #require(DomainInferrer.infer(
            pair: Self.pair,
            forwardSummary: Self.unaryNonThrowing(),
            sites: Self.directSites(3),
            setupBindings: [:],
            producerArgGeneratable: true
        ))
        #expect(hint.forwardName == "encode")
        #expect(hint.reverseName == "decode")
        #expect(hint.producerName == "encode")
        #expect(hint.domainTypeName == "MyType")
        #expect(hint.siteCount == 3)
        #expect(hint.producerVeto == nil)
        #expect(hint.suggestedGenerator == "Gen<MyType>.map(encode)")
    }

    @Test("Above threshold (5 homogeneous sites) produces hint with siteCount = 5")
    func aboveThresholdHintFires() throws {
        let hint = try #require(DomainInferrer.infer(
            pair: Self.pair,
            forwardSummary: Self.unaryNonThrowing(),
            sites: Self.directSites(5),
            setupBindings: [:],
            producerArgGeneratable: true
        ))
        #expect(hint.siteCount == 5)
    }

    // MARK: - Homogeneity

    @Test("Outlier callOutput to a different producer kills the hint")
    func differentProducerKillsHint() {
        var sites = Self.directSites(4)
        sites.append(DomainCallSite(argument: .callOutput(producerName: "encodeXML")))
        let hint = DomainInferrer.infer(
            pair: Self.pair,
            forwardSummary: Self.unaryNonThrowing(),
            sites: sites,
            setupBindings: [:],
            producerArgGeneratable: true
        )
        #expect(hint == nil)
    }

    @Test("Single .other site kills the hint")
    func otherSiteKillsHint() {
        var sites = Self.directSites(4)
        sites.append(DomainCallSite(argument: .other))
        let hint = DomainInferrer.infer(
            pair: Self.pair,
            forwardSummary: Self.unaryNonThrowing(),
            sites: sites,
            setupBindings: [:],
            producerArgGeneratable: true
        )
        #expect(hint == nil)
    }

    // MARK: - Identifier resolution

    @Test("Identifier sites resolve through setup bindings to callOutput")
    func identifiersResolveToHint() throws {
        let hint = try #require(DomainInferrer.infer(
            pair: Self.pair,
            forwardSummary: Self.unaryNonThrowing(),
            sites: Self.identifierSites(3, name: "x"),
            setupBindings: ["x": .callOutput(producerName: "encode")],
            producerArgGeneratable: true
        ))
        #expect(hint.siteCount == 3)
        #expect(hint.producerVeto == nil)
    }

    @Test("Unresolved identifier (not in setupBindings) kills the hint")
    func unresolvedIdentifierKillsHint() {
        let hint = DomainInferrer.infer(
            pair: Self.pair,
            forwardSummary: Self.unaryNonThrowing(),
            sites: Self.identifierSites(3, name: "missing"),
            setupBindings: [:],
            producerArgGeneratable: true
        )
        #expect(hint == nil)
    }

    @Test("Identifier resolving to callOutput of a different producer kills the hint")
    func identifierResolvingWrongProducerKillsHint() {
        let hint = DomainInferrer.infer(
            pair: Self.pair,
            forwardSummary: Self.unaryNonThrowing(),
            sites: Self.identifierSites(3, name: "y"),
            setupBindings: ["y": .callOutput(producerName: "encodeXML")],
            producerArgGeneratable: true
        )
        #expect(hint == nil)
    }

    @Test("Mixed identifier + direct sites all resolving to callOutput(forward) fires hint")
    func mixedIdentifierAndDirectResolves() throws {
        let sites: [DomainCallSite] = [
            DomainCallSite(argument: .callOutput(producerName: "encode")),
            DomainCallSite(argument: .callOutput(producerName: "encode")),
            DomainCallSite(argument: .identifier(name: "x"))
        ]
        let hint = try #require(DomainInferrer.infer(
            pair: Self.pair,
            forwardSummary: Self.unaryNonThrowing(),
            sites: sites,
            setupBindings: ["x": .callOutput(producerName: "encode")],
            producerArgGeneratable: true
        ))
        #expect(hint.siteCount == 3)
    }

    @Test("Transitive identifier chain (x → y → callOutput(forward)) resolves correctly")
    func transitiveIdentifierResolution() throws {
        let hint = try #require(DomainInferrer.infer(
            pair: Self.pair,
            forwardSummary: Self.unaryNonThrowing(),
            sites: Self.identifierSites(3, name: "x"),
            setupBindings: [
                "x": .identifier(name: "y"),
                "y": .callOutput(producerName: "encode")
            ],
            producerArgGeneratable: true
        ))
        #expect(hint.siteCount == 3)
    }

    @Test("Cyclic setup binding chain degrades to .other and kills the hint")
    func cyclicChainKillsHint() {
        let hint = DomainInferrer.infer(
            pair: Self.pair,
            forwardSummary: Self.unaryNonThrowing(),
            sites: Self.identifierSites(3, name: "x"),
            setupBindings: [
                "x": .identifier(name: "y"),
                "y": .identifier(name: "x")
            ],
            producerArgGeneratable: true
        )
        #expect(hint == nil)
    }

    // MARK: - Producer vetoes

    @Test("Throwing producer surfaces hint with .producerThrows veto")
    func throwsVeto() throws {
        let hint = try #require(DomainInferrer.infer(
            pair: Self.pair,
            forwardSummary: Self.unaryNonThrowing(isThrows: true),
            sites: Self.directSites(3),
            setupBindings: [:],
            producerArgGeneratable: true
        ))
        #expect(hint.producerVeto == .producerThrows)
    }

    @Test("Async producer surfaces hint with .producerAsync veto")
    func asyncVeto() throws {
        let hint = try #require(DomainInferrer.infer(
            pair: Self.pair,
            forwardSummary: Self.unaryNonThrowing(isAsync: true),
            sites: Self.directSites(3),
            setupBindings: [:],
            producerArgGeneratable: true
        ))
        #expect(hint.producerVeto == .producerAsync)
    }

    @Test("Multi-arg producer surfaces hint with .producerMultiArg veto")
    func multiArgVeto() throws {
        let hint = try #require(DomainInferrer.infer(
            pair: Self.pair,
            forwardSummary: Self.unaryNonThrowing(parameterCount: 2),
            sites: Self.directSites(3),
            setupBindings: [:],
            producerArgGeneratable: true
        ))
        #expect(hint.producerVeto == .producerMultiArg)
    }

    @Test("Zero-arg producer (parameterCount != 1) surfaces .producerMultiArg veto")
    func zeroArgVeto() throws {
        let hint = try #require(DomainInferrer.infer(
            pair: Self.pair,
            forwardSummary: Self.unaryNonThrowing(parameterCount: 0),
            sites: Self.directSites(3),
            setupBindings: [:],
            producerArgGeneratable: true
        ))
        #expect(hint.producerVeto == .producerMultiArg)
    }

    @Test("Non-generatable producer arg surfaces .producerArgNotGeneratable veto")
    func nonGeneratableVeto() throws {
        let hint = try #require(DomainInferrer.infer(
            pair: Self.pair,
            forwardSummary: Self.unaryNonThrowing(),
            sites: Self.directSites(3),
            setupBindings: [:],
            producerArgGeneratable: false
        ))
        #expect(hint.producerVeto == .producerArgNotGeneratable)
    }

    @Test("Veto priority — throws beats async beats multi-arg beats non-generatable")
    func vetoPriorityOrder() throws {
        // throws + async + multi-arg + non-generatable all true → throws wins
        let hint = try #require(DomainInferrer.infer(
            pair: Self.pair,
            forwardSummary: Self.unaryNonThrowing(isThrows: true, isAsync: true, parameterCount: 2),
            sites: Self.directSites(3),
            setupBindings: [:],
            producerArgGeneratable: false
        ))
        #expect(hint.producerVeto == .producerThrows)
    }
}
