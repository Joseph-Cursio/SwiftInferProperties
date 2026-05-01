import Foundation
import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

// swiftlint:disable type_body_length file_length
// Test suites cohere around their subject — splitting along the 250-line
// body / 400-line file limits would scatter the registry-orchestration
// assertions across multiple files for no reader benefit.
@Suite("TemplateRegistry — discovery orchestration over multiple summaries")
struct TemplateRegistryTests {

    @Test("Empty corpus produces no suggestions")
    func emptyCorpus() {
        #expect(TemplateRegistry.discover(in: []).isEmpty)
    }

    @Test("Idempotence suggestions are sorted by (file, line) for byte-stable output")
    func sortedByLocation() {
        let early = makeIdempotentSummary(file: "B.swift", line: 1)
        let middle = makeIdempotentSummary(file: "A.swift", line: 100)
        let late = makeIdempotentSummary(file: "B.swift", line: 50)
        let suggestions = TemplateRegistry.discover(in: [early, middle, late])
        // Three String -> String functions also cross-pair via round-trip;
        // filter to idempotence so the sort assertion stays focused.
        let locations = suggestions
            .filter { $0.templateName == "idempotence" }
            .compactMap { $0.evidence.first?.location }
        #expect(locations.map(\.file) == ["A.swift", "B.swift", "B.swift"])
        #expect(locations.map(\.line) == [100, 1, 50])
    }

    @Test("Functions that don't match any template are dropped from output")
    func nonMatchingDropped() {
        let matching = makeIdempotentSummary(file: "A.swift", line: 1)
        // Mismatched parameter and return types — no idempotence (1 param
        // needed), no commutativity (params would need to match each
        // other and the return type), and there's no second function to
        // pair with for round-trip.
        let nonMatching = FunctionSummary(
            name: "tickle",
            parameters: [
                Parameter(label: "from", internalName: "src", typeText: "Int", isInout: false),
                Parameter(label: "to", internalName: "dst", typeText: "String", isInout: false)
            ],
            returnTypeText: "Bool",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "B.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let suggestions = TemplateRegistry.discover(in: [matching, nonMatching])
        #expect(suggestions.count == 1)
        #expect(suggestions.first?.evidence.first?.location.file == "A.swift")
    }

    @Test("Directory scan integration over a single fixture file")
    func directoryScanIntegration() throws {
        let directory = try writeFixture(named: "RegistryDirScan", contents: """
        struct Sanitizer {
            func normalize(_ s: String) -> String {
                return normalize(normalize(s))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestions = try TemplateRegistry.discover(in: directory)
        #expect(suggestions.count == 1)
        let suggestion = try #require(suggestions.first)
        #expect(suggestion.templateName == "idempotence")
        #expect(suggestion.score.tier == .strong)
    }

    @Test("Both idempotence and round-trip fire over a mixed corpus")
    func bothTemplatesFire() {
        let normalize = makeIdempotentSummary(file: "A.swift", line: 1)
        let encode = FunctionSummary(
            name: "encode",
            parameters: [Parameter(label: nil, internalName: "v", typeText: "MyType", isInout: false)],
            returnTypeText: "Data",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "B.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let decode = FunctionSummary(
            name: "decode",
            parameters: [Parameter(label: nil, internalName: "d", typeText: "Data", isInout: false)],
            returnTypeText: "MyType",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "B.swift", line: 5, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let suggestions = TemplateRegistry.discover(in: [normalize, encode, decode])
        let templates = suggestions.map(\.templateName)
        #expect(templates.contains("idempotence"))
        #expect(templates.contains("round-trip"))
        #expect(suggestions.count == 2)
    }

    @Test("Associativity reducer-fold signal aggregates corpus-wide via TemplateRegistry.discover")
    func associativityReducerOpsAggregateAcrossSummaries() throws {
        // `combine` is in the curated commutativity list (shared with
        // associativity per v0.2 §5.2 naming), and its name appears as
        // the closure-position arg of `.reduce(0, combine)` in `driver`'s
        // body. The registry must union reducer-op references across
        // summaries before invoking the associativity template — the
        // signal then fires even though `combine` itself never calls
        // reduce in its own body.
        let combine = FunctionSummary(
            name: "combine",
            parameters: [
                Parameter(label: nil, internalName: "lhs", typeText: "Int", isInout: false),
                Parameter(label: nil, internalName: "rhs", typeText: "Int", isInout: false)
            ],
            returnTypeText: "Int",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "A.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let driver = FunctionSummary(
            name: "driver",
            parameters: [Parameter(label: nil, internalName: "xs", typeText: "[Int]", isInout: false)],
            returnTypeText: "Int",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "A.swift", line: 10, column: 1),
            containingTypeName: nil,
            bodySignals: BodySignals(
                hasNonDeterministicCall: false,
                hasSelfComposition: false,
                nonDeterministicAPIsDetected: [],
                reducerOpsReferenced: ["combine"]
            )
        )
        let suggestions = TemplateRegistry.discover(in: [combine, driver])
        let associativity = try #require(suggestions.first { $0.templateName == "associativity" })
        // 30 type + 40 curated `combine` + 20 reducer = 90 → Strong.
        #expect(associativity.score.total == 90)
        #expect(associativity.score.tier == .strong)
    }

    @Test("Identity-element fires on (T, T) -> T op + same-typed static identity via discover(in:directory:)")
    func identityElementFromDirectoryScan() throws {
        // End-to-end: a single .swift file with a binary-op merge plus an
        // identity-shaped `empty` constant on the same type, plus a driver
        // that uses `merge` as a reducer with `.empty` as the seed. The
        // registry should compose the identity-element suggestion at
        // Strong (30 + 40 + 20 = 90) without any explicit identities
        // parameter — directory scan threads through `scanCorpus`.
        let directory = try writeFixture(named: "IdentityElementCorpus", contents: """
        struct IntSet {
            static let empty: IntSet = IntSet()
            func merge(_ lhs: IntSet, _ rhs: IntSet) -> IntSet { return lhs }
        }
        struct Driver {
            func fold(_ xs: [IntSet]) -> IntSet {
                return xs.reduce(.empty, IntSet.merge)
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestions = try TemplateRegistry.discover(in: directory)
        let identityElement = try #require(
            suggestions.first { $0.templateName == "identity-element" }
        )
        #expect(identityElement.score.total == 90)
        #expect(identityElement.score.tier == .strong)
    }

    @Test("Idempotence and round-trip suggestions interleave by (file, line)")
    func interleavedSorting() {
        let earlyNormalize = makeIdempotentSummary(file: "A.swift", line: 50)
        let encode = FunctionSummary(
            name: "encode",
            parameters: [Parameter(label: nil, internalName: "v", typeText: "MyType", isInout: false)],
            returnTypeText: "Data",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "A.swift", line: 10, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let decode = FunctionSummary(
            name: "decode",
            parameters: [Parameter(label: nil, internalName: "d", typeText: "Data", isInout: false)],
            returnTypeText: "MyType",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "A.swift", line: 20, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let suggestions = TemplateRegistry.discover(in: [earlyNormalize, encode, decode])
        // round-trip is anchored at encode (line 10), idempotence at line 50.
        #expect(suggestions.map(\.templateName) == ["round-trip", "idempotence"])
    }

    @Test("Contradiction pass drops commutativity over non-Equatable return + emits stderr diagnostic")
    func contradictionDropsCommutativityForNonEquatableReturn() {
        // `merge(_:_:)` over `Any` matches the commutativity type pattern
        // (param[0] == param[1] == return) but `Any` is in the curated
        // non-Equatable shape list, so the contradiction pass drops it
        // and emits a `contradiction:` diagnostic per M3 plan §M3.4.
        let merge = FunctionSummary(
            name: "merge",
            parameters: [
                Parameter(label: nil, internalName: "a", typeText: "Any", isInout: false),
                Parameter(label: nil, internalName: "b", typeText: "Any", isInout: false)
            ],
            returnTypeText: "Any",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Mixer.swift", line: 3, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        var diagnostics: [String] = []
        let suggestions = TemplateRegistry.discover(
            in: [merge],
            diagnostic: { diagnostics.append($0) }
        )
        #expect(suggestions.allSatisfy { $0.templateName != "commutativity" })
        #expect(diagnostics.count == 1)
        let line = diagnostics.first ?? ""
        #expect(line.hasPrefix("contradiction: "))
        #expect(line.contains("commutativity"))
        #expect(line.contains("merge"))
        #expect(line.contains("Mixer.swift:3"))
        #expect(line.contains("PRD §5.6 #2"))
    }

    @Test("Contradiction pass drops round-trip pair when domain is non-Equatable function type")
    func contradictionDropsRoundTripForNonEquatableDomain() {
        // wrap: ((Int) -> Int) -> Data, unwrap: (Data) -> (Int) -> Int.
        // Both halves traffic in `(Int) -> Int`, which classifies as
        // .notEquatable; the round-trip property is structurally
        // untestable.
        let wrap = FunctionSummary(
            name: "wrap",
            parameters: [Parameter(label: nil, internalName: "f", typeText: "(Int) -> Int", isInout: false)],
            returnTypeText: "Data",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Wrap.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let unwrap = FunctionSummary(
            name: "unwrap",
            parameters: [Parameter(label: nil, internalName: "d", typeText: "Data", isInout: false)],
            returnTypeText: "(Int) -> Int",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Wrap.swift", line: 5, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        var diagnostics: [String] = []
        let suggestions = TemplateRegistry.discover(
            in: [wrap, unwrap],
            diagnostic: { diagnostics.append($0) }
        )
        #expect(suggestions.allSatisfy { $0.templateName != "round-trip" })
        #expect(diagnostics.count == 1)
        let line = diagnostics.first ?? ""
        #expect(line.contains("round-trip"))
        #expect(line.contains("PRD §5.6 #3"))
    }

    @Test("@Discoverable(group:) on both halves of a round-trip pair fires the +35 signal end-to-end (M5.1)")
    func discoverableGroupSignalFiresEndToEnd() throws {
        // Both halves carry @Discoverable(group: "codec") — the +35
        // signal should land on the round-trip suggestion that
        // discover produces from the on-disk fixture.
        let directory = try writeFixture(named: "DiscoverableE2E", contents: """
        struct MyType {}
        struct Codec {
            @Discoverable(group: "codec")
            func encode(_ value: MyType) -> Data {
                return Data()
            }
            @Discoverable(group: "codec")
            func decode(_ data: Data) -> MyType {
                return MyType()
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestions = try TemplateRegistry.discover(in: directory)
        let roundTrip = try #require(suggestions.first { $0.templateName == "round-trip" })
        let discoverable = try #require(
            roundTrip.score.signals.first { $0.kind == .discoverableAnnotation }
        )
        #expect(discoverable.weight == 35)
        #expect(discoverable.detail.contains("codec"))
        // 30 type + 40 curated encode/decode + 35 discoverable = 105 → Strong.
        #expect(roundTrip.score.total == 105)
    }

    @Test("Mismatched @Discoverable groups across the pair leave the +35 signal off")
    func discoverableGroupMismatchSkipsTheSignal() throws {
        let directory = try writeFixture(named: "DiscoverableMismatch", contents: """
        struct MyType {}
        struct Codec {
            @Discoverable(group: "codec")
            func encode(_ value: MyType) -> Data {
                return Data()
            }
            @Discoverable(group: "queue")
            func decode(_ data: Data) -> MyType {
                return MyType()
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestions = try TemplateRegistry.discover(in: directory)
        let roundTrip = try #require(suggestions.first { $0.templateName == "round-trip" })
        #expect(!roundTrip.score.signals.contains { $0.kind == .discoverableAnnotation })
        #expect(roundTrip.score.total == 70)
    }

    @Test("GeneratorSelection populates derivedMemberwise from corpus TypeShapes (M4.2)")
    func generatorSelectionPopulatesDerivedMemberwise() throws {
        // End-to-end: discover sees a Money struct with stdlib members
        // plus a normalize idempotence candidate over Money. The
        // generator-selection pass calls DerivationStrategist on the
        // Money TypeShape and rebuilds the suggestion with
        // .derivedMemberwise / .medium.
        let directory = try writeFixture(named: "GenSelectMemberwise", contents: """
        struct Money {
            let amount: Int
            let currency: String
        }
        struct Sanitizer {
            func normalize(_ value: Money) -> Money {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestions = try TemplateRegistry.discover(in: directory)
        let idempotence = try #require(suggestions.first { $0.templateName == "idempotence" })
        #expect(idempotence.generator.source == .derivedMemberwise)
        #expect(idempotence.generator.confidence == .medium)
        #expect(idempotence.generator.sampling == .notRun)
    }

    @Test("GeneratorSelection skips stdlib-typed properties — open decision #2 default")
    func generatorSelectionSkipsStdlibTypedProperties() throws {
        // String isn't in the corpus's TypeShape index — selection
        // skips, generator stays .notYetComputed. Matches the existing
        // CLI byte-stable assertions.
        let directory = try writeFixture(named: "GenSelectSkipStdlib", contents: """
        struct Sanitizer {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestions = try TemplateRegistry.discover(in: directory)
        let idempotence = try #require(suggestions.first { $0.templateName == "idempotence" })
        #expect(idempotence.generator.source == .notYetComputed)
        #expect(idempotence.generator.confidence == nil)
    }

    @Test("GeneratorSelection populates registered for static gen() corpus types")
    func generatorSelectionPopulatesRegisteredForUserGen() throws {
        // Widget declares a static gen() in its primary body — strategist
        // returns .userGen → .registered with .high confidence.
        let directory = try writeFixture(named: "GenSelectUserGen", contents: """
        struct Widget {
            let id: Int
            static func gen() -> Int { 0 }
        }
        struct Sanitizer {
            func normalize(_ value: Widget) -> Widget {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestions = try TemplateRegistry.discover(in: directory)
        let idempotence = try #require(suggestions.first { $0.templateName == "idempotence" })
        #expect(idempotence.generator.source == .registered)
        #expect(idempotence.generator.confidence == .high)
    }

    @Test("Cross-validation seam adds +20 signal to matching identities (M3.5)")
    func crossValidationLiftsScoreOnMatchingIdentity() throws {
        let normalize = makeIdempotentSummary(file: "A.swift", line: 1)
        let baseline = TemplateRegistry.discover(in: [normalize])
        let target = try #require(baseline.first { $0.templateName == "idempotence" })
        let baselineTotal = target.score.total

        let crossValidated = TemplateRegistry.discover(
            in: [normalize],
            crossValidationFromTestLifter: [target.identity]
        )
        let lifted = try #require(crossValidated.first { $0.templateName == "idempotence" })
        #expect(lifted.score.total == baselineTotal + 20)
        #expect(lifted.score.signals.contains { $0.kind == .crossValidation && $0.weight == 20 })
        #expect(lifted.identity == target.identity)
        #expect(lifted.explainability.whySuggested.contains { $0.contains("Cross-validated by TestLifter") })
    }

    @Test("Cross-validation set with no matches leaves suggestions byte-stable")
    func crossValidationNoMatchIsByteStable() {
        let normalize = makeIdempotentSummary(file: "A.swift", line: 1)
        let baseline = TemplateRegistry.discover(in: [normalize])
        let unrelated = SuggestionIdentity(canonicalInput: "irrelevant|never-matches")
        let withCrossValidation = TemplateRegistry.discover(
            in: [normalize],
            crossValidationFromTestLifter: [unrelated]
        )
        #expect(baseline == withCrossValidation)
    }

    @Test("Cross-validation does not resurrect a contradiction-dropped suggestion")
    func crossValidationDoesNotResurrectDroppedSuggestion() {
        // Commutativity over Any → dropped by the §5.6 #2 detector.
        // Even with the suggestion's identity in the cross-validation
        // set, it stays gone — drops happen before cross-validation.
        let merge = FunctionSummary(
            name: "merge",
            parameters: [
                Parameter(label: nil, internalName: "a", typeText: "Any", isInout: false),
                Parameter(label: nil, internalName: "b", typeText: "Any", isInout: false)
            ],
            returnTypeText: "Any",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Mixer.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        // We compute the would-be identity by reaching into the template
        // directly — this is deliberately a white-box test so we can
        // assert the cross-validation seam doesn't override the §5.6
        // drop layered above it.
        let droppedSuggestion = CommutativityTemplate.suggest(for: merge)
        let crossValidated = TemplateRegistry.discover(
            in: [merge],
            crossValidationFromTestLifter: droppedSuggestion.map { [$0.identity] } ?? []
        )
        #expect(crossValidated.allSatisfy { $0.templateName != "commutativity" })
    }

    @Test("Directory scan threads typeDecls through discover and emits contradiction diagnostics")
    func directoryScanFiresContradictionDiagnostic() throws {
        // End-to-end: scanCorpus emits typeDecls, discover builds the
        // resolver, and a non-Equatable param type triggers a drop with
        // a stderr diagnostic. Composer's compose(_:_:) shape is
        // `((Int) -> Int, (Int) -> Int) -> (Int) -> Int` — commutativity
        // type pattern matches but the non-Equatable shape vetoes.
        let directory = try writeFixture(named: "ContradictionDirScan", contents: """
        struct Composer {
            func compose(_ a: (Int) -> Int, _ b: (Int) -> Int) -> (Int) -> Int { return a }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        var diagnostics: [String] = []
        let suggestions = try TemplateRegistry.discover(
            in: directory,
            diagnostic: { diagnostics.append($0) }
        )
        #expect(suggestions.allSatisfy { $0.templateName != "commutativity" })
        #expect(diagnostics.contains { line in
            line.hasPrefix("contradiction: ")
                && line.contains("commutativity")
                && line.contains("compose")
        })
    }

    private func makeIdempotentSummary(file: String, line: Int) -> FunctionSummary {
        FunctionSummary(
            name: "normalize",
            parameters: [Parameter(label: nil, internalName: "v", typeText: "String", isInout: false)],
            returnTypeText: "String",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: file, line: line, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
    }

    private func writeFixture(named name: String, contents: String) throws -> URL {
        let directoryName = "SwiftInferTests-\(name)-\(UUID().uuidString)"
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(directoryName)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let file = base.appendingPathComponent("Sanitizer.swift")
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return base
    }
}
// swiftlint:enable type_body_length file_length
