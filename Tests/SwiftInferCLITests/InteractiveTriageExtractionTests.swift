import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

@Suite("InteractiveTriage — singleParameterType extraction (determinism stub gate)")
struct InteractiveTriageSingleParamTypeTests {

    @Test func returnsTheTypeForASingleParameter() {
        #expect(InteractiveTriage.singleParameterType(from: "(String) -> Int") == "String")
    }

    @Test func returnsNilForMultipleParameters() {
        #expect(InteractiveTriage.singleParameterType(from: "(Money, Money) -> Money") == nil)
    }

    @Test func returnsNilForZeroParameters() {
        #expect(InteractiveTriage.singleParameterType(from: "() -> Int") == nil)
    }

    @Test func keepsAGenericSingleParameterWhole() {
        // The comma is inside the generic brackets — still one parameter.
        #expect(
            InteractiveTriage.singleParameterType(from: "(Dictionary<String, Int>) -> Int")
                == "Dictionary<String, Int>"
        )
    }

    @Test func handlesAnExistentialParameter() {
        #expect(InteractiveTriage.singleParameterType(from: "(any Backend) -> Env") == "any Backend")
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
