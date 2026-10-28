//
//  AnchorCollisionTests.swift
//  Yams
//
//  Copyright (c) 2026 Yams. All rights reserved.
//

import XCTest
import Yams

/// A RedundancyAliasingStrategy must never give one anchor to two different values.
/// YAML resolves an alias to the most recent node declaring its anchor, so when a second value
/// declares an anchor already given to a first value, every later alias to the first value
/// decodes as the second one.
class AnchorCollisionTests: XCTestCase {

    // MARK: - The strategies never return one anchor for two values

    /// A value's own `yamlAnchor` must not reuse an anchor the strategy generated for another value.
    func testCounterAnchorThenUserAnchor_HashableAliasingStrategy() throws {
        try _testCounterAnchorThenUserAnchor(strategy: HashableAliasingStrategy())
    }

    /// A value's own `yamlAnchor` must not reuse an anchor the strategy generated for another value.
    func testCounterAnchorThenUserAnchor_StrictEncodableAliasingStrategy() throws {
        try _testCounterAnchorThenUserAnchor(strategy: StrictEncodableAliasingStrategy())
    }

    /// A generated anchor must not reuse a name that a value's own `yamlAnchor` has already claimed.
    func testUserAnchorThenCounterAnchor_HashableAliasingStrategy() throws {
        try _testUserAnchorThenCounterAnchor(strategy: HashableAliasingStrategy())
    }

    /// A generated anchor must not reuse a name that a value's own `yamlAnchor` has already claimed.
    func testUserAnchorThenCounterAnchor_StrictEncodableAliasingStrategy() throws {
        try _testUserAnchorThenCounterAnchor(strategy: StrictEncodableAliasingStrategy())
    }

    private func _testCounterAnchorThenUserAnchor(strategy: any RedundancyAliasingStrategy) throws {
        let generated = try XCTUnwrap(anchor(of: strategy.alias(for: 42)))
        let value = Named(name: "b", yamlAnchor: Anchor(rawValue: generated.rawValue))
        let dictated = try XCTUnwrap(anchor(of: strategy.alias(for: value)))
        XCTAssertNotEqual(generated, dictated)
    }

    private func _testUserAnchorThenCounterAnchor(strategy: any RedundancyAliasingStrategy) throws {
        let dictated = try XCTUnwrap(anchor(of: strategy.alias(for: Named(name: "b", yamlAnchor: "1"))))
        let generated = try XCTUnwrap(anchor(of: strategy.alias(for: 42)))
        XCTAssertEqual(dictated, "1")
        XCTAssertNotEqual(dictated, generated)
    }

    // MARK: - Every alias decodes to the value it was written for

    /// `Named(b)` dictates anchor "2", which the strategy has already generated for `Named(a)`.
    func testAliasDecodesToItsValue_userAnchorMatchesCounterAnchor_HashableAliasingStrategy() throws {
        try _testUserAnchorMatchesCounterAnchor(strategy: HashableAliasingStrategy())
    }

    /// `Named(b)` dictates anchor "2", which the strategy has already generated for `Named(a)`.
    func testAliasDecodesToItsValue_userAnchorMatchesCounterAnchor_StrictEncodableAliasingStrategy() throws {
        try _testUserAnchorMatchesCounterAnchor(strategy: StrictEncodableAliasingStrategy())
    }

    /// `Named(a)` dictates anchor "2", which the strategy then generates for the string "a" inside it.
    /// Unpatched, YAMLDecoder throws a typeMismatch on this output.
    func testAliasDecodesToItsValue_userAnchorMatchesNestedCounterAnchor_HashableAliasingStrategy() throws {
        try _testUserAnchorMatchesNestedCounterAnchor(strategy: HashableAliasingStrategy())
    }

    /// `Named(a)` dictates anchor "2", which the strategy then generates for the string "a" inside it.
    /// Unpatched, YAMLDecoder throws a typeMismatch on this output.
    func testAliasDecodesToItsValue_userAnchorMatchesNestedCounterAnchor_StrictEncodableAliasingStrategy() throws {
        try _testUserAnchorMatchesNestedCounterAnchor(strategy: StrictEncodableAliasingStrategy())
    }

    /// Two different values dictate the same anchor.
    func testAliasDecodesToItsValue_sharedUserAnchor_HashableAliasingStrategy() throws {
        try _testSharedUserAnchor(strategy: HashableAliasingStrategy())
    }

    /// Two different values dictate the same anchor.
    func testAliasDecodesToItsValue_sharedUserAnchor_StrictEncodableAliasingStrategy() throws {
        try _testSharedUserAnchor(strategy: StrictEncodableAliasingStrategy())
    }

    /// Yams's own output, decoded into YamlAnchorCoding values and encoded again with a new repeated value.
    func testAliasDecodesToItsValue_reencodedOutput_HashableAliasingStrategy() throws {
        try _testReencodedOutput(makeStrategy: HashableAliasingStrategy.init)
    }

    /// Yams's own output, decoded into YamlAnchorCoding values and encoded again with a new repeated value.
    func testAliasDecodesToItsValue_reencodedOutput_StrictEncodableAliasingStrategy() throws {
        try _testReencodedOutput(makeStrategy: StrictEncodableAliasingStrategy.init)
    }

    private func _testUserAnchorMatchesCounterAnchor(strategy: any RedundancyAliasingStrategy) throws {
        let first = Named(name: "a")
        let second = Named(name: "b", yamlAnchor: "2")
        try _testAliasesDecodeToTheirValues([first, second, first], strategy: strategy)
    }

    private func _testUserAnchorMatchesNestedCounterAnchor(strategy: any RedundancyAliasingStrategy) throws {
        let first = Named(name: "a", yamlAnchor: "2")
        let second = Named(name: "a")
        try _testAliasesDecodeToTheirValues([first, second], strategy: strategy)
    }

    private func _testSharedUserAnchor(strategy: any RedundancyAliasingStrategy) throws {
        let first = Named(name: "a", yamlAnchor: "label")
        let second = Named(name: "b", yamlAnchor: "label")
        try _testAliasesDecodeToTheirValues([first, second, first], strategy: strategy)
    }

    private func _testReencodedOutput(makeStrategy: () -> any RedundancyAliasingStrategy) throws {
        let shared = Named(name: "shared")
        let firstPass = try YAMLEncoder.encoding([shared, shared], strategy: makeStrategy())
        XCTAssertEqual(firstPass, """
                                  - &2
                                    name: shared
                                  - *2

                                  """)

        var values = try YAMLDecoder().decode([Named].self, from: firstPass)
        XCTAssertEqual(values.map(\.yamlAnchor), ["2", "2"])
        let fresh = Named(name: "fresh")
        values.insert(fresh, at: 0)
        values.append(fresh)
        try _testAliasesDecodeToTheirValues(values, strategy: makeStrategy())
    }

    // MARK: - Output without a collision is unchanged

    /// A strategy reused for a second document forgets the anchors it gave out for the first one,
    /// so a value in the second document keeps its own `yamlAnchor`.
    func testReusedStrategyKeepsUserAnchor_HashableAliasingStrategy() throws {
        try _testReusedStrategyKeepsUserAnchor(strategy: HashableAliasingStrategy())
    }

    /// A strategy reused for a second document forgets the anchors it gave out for the first one,
    /// so a value in the second document keeps its own `yamlAnchor`.
    func testReusedStrategyKeepsUserAnchor_StrictEncodableAliasingStrategy() throws {
        try _testReusedStrategyKeepsUserAnchor(strategy: StrictEncodableAliasingStrategy())
    }

    /// An anchor the encoder remits (here "3", generated for the raw value inside `Shade.light`)
    /// is not in the document, so a value may still dictate that anchor.
    /// StrictEncodableAliasingStrategy aliases that raw value to `Shade.light`'s own anchor and remits nothing.
    func testRemittedAnchorCanBeDictated_HashableAliasingStrategy() throws {
        let subject = ShadeAndNamed(shade: .light, named: Named(name: "b", yamlAnchor: "3"))
        let yaml = try YAMLEncoder.encoding(subject, strategy: HashableAliasingStrategy())
        XCTAssertEqual(yaml, """
                             shade: light
                             named: &3
                               name: b

                             """)
    }

    private func _testReusedStrategyKeepsUserAnchor(strategy: any RedundancyAliasingStrategy) throws {
        let encoder = YAMLEncoder()
        encoder.options = YAMLEncoder.Options(redundancyAliasingStrategy: strategy)

        let shared = Named(name: "shared")
        XCTAssertEqual(try encoder.encode([shared, shared]), """
                                                             - &2
                                                               name: shared
                                                             - *2

                                                             """)

        let labelled = Named(name: "labelled", yamlAnchor: "2")
        XCTAssertEqual(try encoder.encode([labelled, labelled]), """
                                                                 - &2
                                                                   name: labelled
                                                                 - *2

                                                                 """)
    }

    // MARK: - An encode that throws leaves no anchors behind

    // StrictEncodableAliasingStrategy encodes the whole value inside `alias(for:)`,
    // so an encode that throws fails there, before that strategy gives out any anchor.

    /// A strategy reused after an encode that throws forgets the anchor names it gave out during that encode,
    /// so a value in the next document keeps its own `yamlAnchor`.
    func testFailedEncodeReleasesAnchorNames_HashableAliasingStrategy() throws {
        let encoder = YAMLEncoder()
        encoder.options = YAMLEncoder.Options(redundancyAliasingStrategy: HashableAliasingStrategy())
        XCTAssertThrowsError(try encoder.encode(Failing(named: Named(name: "a", yamlAnchor: "x"))))

        XCTAssertEqual(try encoder.encode([Named(name: "b", yamlAnchor: "x")]), """
                                                                                - &x
                                                                                  name: b

                                                                                """)
    }

    /// A strategy reused after an encode that throws must not alias a value
    /// to an anchor that only the failed document declared.
    func testFailedEncodeLeavesNoDanglingAlias_HashableAliasingStrategy() throws {
        let encoder = YAMLEncoder()
        encoder.options = YAMLEncoder.Options(redundancyAliasingStrategy: HashableAliasingStrategy())
        let labelled = Named(name: "a", yamlAnchor: "x")
        XCTAssertThrowsError(try encoder.encode(Failing(named: labelled)))

        XCTAssertEqual(try encoder.encode([labelled, labelled]), """
                                                                 - &x
                                                                   name: a
                                                                 - *x

                                                                 """)
    }

    // MARK: - Helpers

    private func _testAliasesDecodeToTheirValues(_ values: [Named],
                                                 strategy: any RedundancyAliasingStrategy,
                                                 file: StaticString = #filePath,
                                                 line: UInt = #line) throws {
        let yaml = try YAMLEncoder.encoding(values, strategy: strategy)
        let anchors = yaml.split(whereSeparator: \.isWhitespace).filter { $0.hasPrefix("&") }
        XCTAssertEqual(anchors.count, Set(anchors).count, "an anchor is declared twice:\n\(yaml)",
                       file: file, line: line)

        let decoded = try YAMLDecoder().decode([Named].self, from: yaml)
        XCTAssertEqual(decoded.map(\.name), values.map(\.name), "decoded from:\n\(yaml)",
                       file: file, line: line)
    }

    private func anchor(of outcome: RedundancyAliasingOutcome) -> Anchor? {
        guard case let .anchor(anchor) = outcome else {
            return nil
        }
        return anchor
    }
}

private extension YAMLEncoder {
    static func encoding<T: Encodable>(_ value: T, strategy: any RedundancyAliasingStrategy) throws -> String {
        let encoder = YAMLEncoder()
        encoder.options = YAMLEncoder.Options(redundancyAliasingStrategy: strategy)
        return try encoder.encode(value)
    }
}

// MARK: - Types used for anchor collision tests.

private struct Named: Codable, Hashable, YamlAnchorCoding {
    let name: String
    var yamlAnchor: Anchor?
}

private enum Shade: String, Codable, Hashable {
    case light
}

private struct ShadeAndNamed: Codable, Hashable {
    let shade: Shade
    let named: Named
}

/// Encodes `named`, then throws.
private struct Failing: Encodable {
    let named: Named

    private enum CodingKeys: String, CodingKey {
        case named
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(named, forKey: .named)
        throw EncodingError.invalidValue(named, .init(codingPath: encoder.codingPath,
                                                      debugDescription: "fails after encoding `named`"))
    }
}
