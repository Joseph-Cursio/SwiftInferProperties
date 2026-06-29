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

    @Test func wrappedFileOmitsImportForNonSpmPath() {
        let suggestion = makeIdempotentSuggestion(funcName: "normalize", typeName: "String", file: "Source.swift")
        let wrapped = InteractiveTriage.wrappedFileContents(stub: "\n@Test func x() async {}", suggestion: suggestion)
        #expect(wrapped.contains("@testable import") == false)
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
        // No resolver supplied → the existing `Type.gen()` fallback.
        #expect(InteractiveTriage.chooseGenerator(for: suggestion, typeName: "Widget") == "Widget.gen()")
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
