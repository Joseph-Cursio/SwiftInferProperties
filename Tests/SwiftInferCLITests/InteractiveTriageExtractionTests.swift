import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

@Suite("InteractiveTriage — parameter parsing (determinism stub, any arity)")
struct InteractiveTriageParameterParsingTests {

    @Test func parameterTypesSplitsTopLevelCommasOnly() {
        #expect(InteractiveTriage.parameterTypes(from: "(String) -> Int") == ["String"])
        #expect(InteractiveTriage.parameterTypes(from: "(Money, Money) -> Money") == ["Money", "Money"])
        #expect(InteractiveTriage.parameterTypes(from: "() -> Int").isEmpty)
        // Comma inside generic brackets stays one parameter.
        #expect(
            InteractiveTriage.parameterTypes(from: "(Dictionary<String, Int>, Bool) -> Int")
                == ["Dictionary<String, Int>", "Bool"]
        )
        #expect(InteractiveTriage.parameterTypes(from: "(any Backend) -> Env") == ["any Backend"])
    }

    @Test func parameterLabelsMapUnderscoreToNil() {
        #expect(InteractiveTriage.parameterLabels(from: "describe(_:)") == [nil])
        #expect(InteractiveTriage.parameterLabels(from: "memberGenerator(forTypeName:)") == ["forTypeName"])
        #expect(InteractiveTriage.parameterLabels(from: "combine(_:with:)") == [nil, "with"])
        #expect(InteractiveTriage.parameterLabels(from: "make()").isEmpty)
    }

    @Test func functionParametersZipsLabelsAndTypes() throws {
        let params = try #require(
            InteractiveTriage.functionParameters(displayName: "combine(_:with:)", signature: "(Int, String) -> Int")
        )
        #expect(params.count == 2)
        #expect(params[0].label == nil)
        #expect(params[0].type == "Int")
        #expect(params[1].label == "with")
        #expect(params[1].type == "String")
    }

    @Test func functionParametersReturnsNilForZeroParamsOrMismatch() {
        #expect(InteractiveTriage.functionParameters(displayName: "make()", signature: "() -> Int") == nil)
        // Label/type count disagree → untrusted parse.
        #expect(
            InteractiveTriage.functionParameters(displayName: "f(_:)", signature: "(Int, Int) -> Int") == nil
        )
    }
}

@Suite("InteractiveTriage — module import in generated stubs (#1 drop-in compile)")
struct InteractiveTriageModuleImportTests {

    @Test func derivesModuleFromSpmSourcePath() {
        #expect(InteractiveTriage.moduleName(fromSourceFile: "/repo/Sources/Demo/Calc.swift") == "Demo")
        #expect(
            InteractiveTriage.moduleName(fromSourceFile: "/a/b/Sources/MyKit/Sub/File.swift") == "MyKit"
        )
    }

    @Test func returnsNilForNonSpmPaths() {
        #expect(InteractiveTriage.moduleName(fromSourceFile: "Source.swift") == nil)
        #expect(InteractiveTriage.moduleName(fromSourceFile: "/tmp/fixture-xyz/Source.swift") == nil)
        #expect(InteractiveTriage.moduleName(fromSourceFile: "/repo/Sources/File.swift") == nil)
    }

    @Test func usesTheLastSourcesComponentForNestedPackages() {
        #expect(
            InteractiveTriage.moduleName(fromSourceFile: "/p/Sources/Outer/Sources/Inner/F.swift")
                == "Inner"
        )
    }

    @Test func sanitizesTargetDirectoryToASwiftModuleIdentifier() {
        // SwiftPM imports the target `swift-clone-detector` as
        // `swift_clone_detector`; emitting the raw directory name produced a
        // `@testable import swift-clone-detector` syntax error.
        #expect(
            InteractiveTriage.moduleName(fromSourceFile: "/r/Sources/swift-clone-detector/F.swift")
                == "swift_clone_detector"
        )
        #expect(
            InteractiveTriage.moduleName(fromSourceFile: "/r/Sources/My.Odd.Target/F.swift")
                == "My_Odd_Target"
        )
        // An already-valid identifier is untouched.
        #expect(
            InteractiveTriage.moduleName(fromSourceFile: "/r/Sources/MyKit/F.swift") == "MyKit"
        )
    }

    @Test func wrappedFileAddsTestableImportForSpmPath() {
        let suggestion = makeIdempotentSuggestion(
            funcName: "normalize",
            typeName: "String",
            file: "/repo/Sources/Demo/Calc.swift"
        )
        let wrapped = InteractiveTriage.wrappedFileContents(stub: "\n@Test func x() async {}", suggestion: suggestion)
        #expect(wrapped.contains("@testable import Demo"))
        // Placed after the kit imports, before the test body.
        #expect(wrapped.contains("import PropertyLawKit\n@testable import Demo"))
    }

    /// **This test used to pin the defect it was named for** (#415). Omitting the import for a
    /// non-`Sources/` path was described as leaving "synthetic fixtures" alone; it also silently
    /// dropped the import for every Xcode-originated layout, which is the case `--sources` exists
    /// to serve. 0 of 19 stubs emitted for SwiftMarkdownWiki named the module under test.
    ///
    /// A path the per-file heuristic cannot read now says so on the line that will fail.
    @Test func wrappedFileSaysSoWhenNoModuleCanBeResolved() {
        let suggestion = makeIdempotentSuggestion(funcName: "normalize", typeName: "String", file: "Source.swift")
        let wrapped = InteractiveTriage.wrappedFileContents(stub: "\n@Test func x() async {}", suggestion: suggestion)
        // Asserted per line, not on the whole file: the emitted advice *names* `@testable
        // import`, which is the point of it — a substring check would pass on the advice itself.
        let importLines = wrapped.split(separator: "\n").filter { $0.hasPrefix("@testable import") }
        #expect(importLines.isEmpty)
        #expect(wrapped.contains("TODO: no module resolved"))
    }

    /// The run's manifest-resolved module answers where the path cannot — the Xcode layout that
    /// produced #415, with target sources rooted at `SwiftMarkdownWiki/` and no `Sources/`.
    @Test func wrappedFileFallsBackToTheRunsResolvedModule() {
        let suggestion = makeIdempotentSuggestion(
            funcName: "normalize",
            typeName: "String",
            file: "/repo/SwiftMarkdownWiki/Editor/EditorFormatter.swift"
        )
        let wrapped = InteractiveTriage.wrappedFileContents(
            stub: "\n@Test func x() async {}",
            suggestion: suggestion,
            moduleUnderTest: "SwiftMarkdownWiki"
        )
        #expect(wrapped.contains("@testable import SwiftMarkdownWiki"))
        #expect(wrapped.contains("TODO: no module resolved") == false)
    }

    /// The per-file layout wins over the run's module: a run may scan a directory containing more
    /// than one target, and the file's own path is the more specific answer.
    @Test func theFilesOwnLayoutOutranksTheRunsModule() {
        let suggestion = makeIdempotentSuggestion(
            funcName: "normalize",
            typeName: "String",
            file: "/repo/Sources/Demo/Calc.swift"
        )
        let wrapped = InteractiveTriage.wrappedFileContents(
            stub: "\n@Test func x() async {}",
            suggestion: suggestion,
            moduleUnderTest: "SomethingElse"
        )
        #expect(wrapped.contains("@testable import Demo"))
    }

    /// **The access caveat is shown at triage and used to be dropped at emission** (#428). A
    /// `private` subject surfaces on purpose — `SeededPrivateFunctionTests` records why — and the
    /// accepted file then compiled into `'trimmed' is inaccessible due to 'private' protection
    /// level`, with nothing in it saying which refactor fixes that.
    ///
    /// Measured over `PropertyLawCore`: 2 of 5 emitted stubs are `private static func` subjects.
    @Test func anAccessRestrictedSubjectCarriesItsCaveat() {
        var suggestion = makeIdempotentSuggestion(funcName: "trimmed", typeName: "String")
        suggestion.score = Score(advisorySignals: suggestion.score.signals + [
            Signal(
                kind: .subjectNotVisibleToTests,
                weight: 0,
                detail: "no test can name the subject: it is `private` or `fileprivate`"
            )
        ])
        let wrapped = InteractiveTriage.wrappedFileContents(stub: "\n@Test func x() async {}", suggestion: suggestion)
        #expect(wrapped.contains("// Access: no test can name the subject"))
        #expect(wrapped.contains("will not compile until"))
    }

    /// The line is absent for a reachable subject — an unconditional caveat would be noise on
    /// every file and would stop meaning anything on the two that need it.
    @Test func areachableSubjectCarriesNoAccessCaveat() {
        let suggestion = makeIdempotentSuggestion(funcName: "normalize", typeName: "String")
        let wrapped = InteractiveTriage.wrappedFileContents(stub: "\n@Test func x() async {}", suggestion: suggestion)
        #expect(wrapped.contains("// Access:") == false)
    }

    /// **Two templates on one function produced two files with the same basename**, and SwiftPM
    /// names object files per basename within a module — so the test target failed to build
    /// entirely with `couldn't build …/union.swift.o because of multiple producers`, taking the
    /// other seventeen stubs down with it.
    ///
    /// Invisible until #414 and #415: before those, the files went somewhere nothing compiled.
    /// Measured on SwiftMarkdownWiki: 19 stubs, two collisions — `union` (associativity +
    /// commutativity) and `modificationDate` (idempotence + monotonicity).
    @Test func twoTemplatesOnOneFunctionGetDistinctFileNames() throws {
        let suggestion = makeIdempotentSuggestion(funcName: "union", typeName: "String")
        let idempotence = try #require(InteractiveTriage.stubFileName(for: suggestion))

        var other = suggestion
        other.templateName = "commutativity"
        let commutativity = try #require(InteractiveTriage.stubFileName(for: other))

        #expect(idempotence == "union_idempotence.swift")
        #expect(commutativity == "union_commutativity.swift")
        #expect(idempotence != commutativity)
    }

    /// Foundation is imported unconditionally. It used to ride only on the Codable round-trip
    /// generator, and a package enabling `MemberImportVisibility` — this one does — fails to
    /// build a generated file that touches any Foundation member without it.
    @Test func foundationIsAlwaysImported() {
        let suggestion = makeIdempotentSuggestion(funcName: "normalize", typeName: "String")
        let wrapped = InteractiveTriage.wrappedFileContents(stub: "\n@Test func x() async {}", suggestion: suggestion)
        #expect(wrapped.contains("import Foundation"))
    }
}

@Suite("InteractiveTriage — chooseGenerator custom-type resolution (#2)")
struct InteractiveTriageChooseGeneratorTests {

    @Test func usesCustomResolverForAProjectType() {
        let suggestion = makeIdempotentSuggestion(funcName: "f", typeName: "Point")
        let resolver: (String) -> String? = { $0 == "Point" ? "DERIVED_POINT_GEN" : nil }
        #expect(
            InteractiveTriage.chooseGenerator(for: suggestion, typeName: "Point", customGenerator: resolver)
                == "DERIVED_POINT_GEN"
        )
    }

    @Test func fallsThroughToStdlibMappingWhenResolverReturnsNil() {
        let suggestion = makeIdempotentSuggestion(funcName: "f", typeName: "Int")
        // A stdlib type has no project shape → resolver returns nil → stdlib generator.
        let resolver: (String) -> String? = { _ in nil }
        #expect(
            InteractiveTriage.chooseGenerator(for: suggestion, typeName: "Int", customGenerator: resolver)
                == "Gen<Int>.int()"
        )
    }

    @Test func fallsBackToGenForCustomTypeWithoutAResolver() {
        let suggestion = makeIdempotentSuggestion(funcName: "f", typeName: "Widget")
        // No resolver supplied → the `Type.gen()` fallback, which now carries the marker saying
        // it is the fallback (#416): four of nineteen emitted stubs were this arm and nothing
        // distinguished them from a resolved generator.
        let generator = InteractiveTriage.chooseGenerator(for: suggestion, typeName: "Widget")
        #expect(generator.hasPrefix("Widget.gen()"))
        #expect(generator.contains("no generator derived"))
    }
}

@Suite("InteractiveTriage — bounded determinism generator (#3 overflow)")
struct InteractiveTriageBoundedGeneratorTests {

    @Test func boundsIntToAvoidOverflowTraps() {
        #expect(
            InteractiveTriage.boundedDeterminismGenerator(forTypeName: "Int")
                == "Gen<Int>.int(in: -10_000 ... 10_000)"
        )
    }

    @Test func leavesNonNumericTypesToTheNormalChooser() {
        #expect(InteractiveTriage.boundedDeterminismGenerator(forTypeName: "String") == nil)
        #expect(InteractiveTriage.boundedDeterminismGenerator(forTypeName: "Point") == nil)
        #expect(InteractiveTriage.boundedDeterminismGenerator(forTypeName: "Double") == nil)
    }
}
