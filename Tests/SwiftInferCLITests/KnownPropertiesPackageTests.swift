@testable import SwiftInferCLI
import Testing

/// The package-based `known-properties --verify` infrastructure — the module →
/// package-dependency mapping, the stdlib/package partition, and the catalog
/// consistency guard that every external law's imported module is mapped (so a
/// typo can't silently drop a law from verification).
@Suite("known-properties — external-package verify infrastructure")
struct KnownPropertiesPackageTests {

    @Test("a single numerics module resolves to one package + product")
    func resolvesNumerics() throws {
        let resolved = try KnownPropertiesPackages.resolve(modules: ["ComplexModule"])
        #expect(resolved.packages.count == 1)
        #expect(resolved.packages.first?.packageIdentity == "swift-numerics")
        #expect(resolved.products.contains { $0.0 == "ComplexModule" && $0.1 == "swift-numerics" })
    }

    @Test("two modules from one package dedupe to a single dependency")
    func dedupesPackage() throws {
        let resolved = try KnownPropertiesPackages.resolve(modules: ["DequeModule", "OrderedCollections"])
        // Both live in swift-collections → one package dependency, two products.
        #expect(resolved.packages.count == 1)
        #expect(resolved.packages.first?.packageIdentity == "swift-collections")
        #expect(resolved.products.count == 2)
    }

    @Test("an unmapped module throws rather than silently dropping the law")
    func unmappedModuleThrows() {
        #expect(throws: KnownPropertiesVerifyError.self) {
            _ = try KnownPropertiesPackages.resolve(modules: ["NoSuchModule"])
        }
    }

    @Test("every external law's imported modules are all mapped")
    func everyImportedModuleIsMapped() {
        for law in StandardLibraryProperties.all where law.needsPackage {
            for module in law.imports {
                #expect(
                    KnownPropertiesPackages.byModule[module] != nil,
                    "law '\(law.displayName)' imports unmapped module '\(module)'"
                )
            }
        }
    }

    @Test("needsPackage partitions stdlib from external laws")
    func needsPackagePartitions() {
        let complex = StandardLibraryProperties.all.first { $0.type == "Complex" }
        let intLaw = StandardLibraryProperties.all.first { $0.type == "Int" }
        #expect(complex?.needsPackage == true)
        #expect(intLaw?.needsPackage == false)
    }

    @Test("Foundation laws run on the fast path (no imports)")
    func foundationLawsAreStdlibPath() {
        let dataLaws = StandardLibraryProperties.all.filter { $0.type == "Data" }
        #expect(!dataLaws.isEmpty)
        #expect(dataLaws.allSatisfy { !$0.needsPackage })
    }

    @Test("rendering with imports prepends the module import lines")
    func renderPrependsImports() {
        let laws = StandardLibraryProperties.all.filter { $0.type == "Complex" }
        let program = KnownPropertiesRenderer.renderVerifyProgram(laws, imports: ["ComplexModule"])
        #expect(program.contains("import ComplexModule"))
        #expect(program.contains("import Foundation"))
    }
}
