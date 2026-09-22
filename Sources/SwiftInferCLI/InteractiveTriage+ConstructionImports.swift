import Foundation
import SwiftInferCore

/// The imports a copied receiver construction brings with it.
///
/// A construction copied from a test names what that test file imports, and nothing else in the
/// emitter knows where those names live: `Parser` is `SwiftParser`, `SyntaxPattern` is a nested
/// package's module, `MockSwiftLintCLIActor` is a test-support target. The carrier-import resolver
/// reads the scanned index, and none of these is a scanned type. Measured on the 22 September
/// census, 17 stubs failed `cannot find '…' in scope` on exactly these names.
extension InteractiveTriage {

    /// Test frameworks a generated stub must not pull in: it is a Swift Testing file, and a
    /// harvested `import XCTest` would only add a framework the stub does not use.
    static let constructionImportExclusions: Set<String> = ["XCTest", "Testing"]

    /// Each harvested import line for a construction `stub` uses, one per line, skipping a module
    /// the stub already imports.
    ///
    /// Deduplicated by MODULE rather than by line, so a test's `import SwiftProjectLintRules` is not
    /// added beside the stub's own `@testable import SwiftProjectLintRules`.
    static func constructionImportLines(
        usedIn stub: String,
        constructions: [ReceiverConstructionHarvester.Harvested],
        alreadyImported: Set<String>
    ) -> String {
        var imported = alreadyImported.union(constructionImportExclusions)
        return importLines(of: constructions, usedIn: stub)
            .filter { line in
                guard let module = importedModule(in: line) else { return false }
                return imported.insert(module).inserted
            }
            .map { "\($0)\n" }
            .joined()
    }

    /// Every import a stub needs beyond its fixed set: the modules declaring the types it names,
    /// then those a copied construction's test file imported. `emitted` is the import text already
    /// assembled, whose modules count as imported.
    static func namedTypeImportLines(
        for suggestion: Suggestion,
        stub: String,
        entryModule: String?,
        carrierImports: CarrierImports?,
        beside emitted: String
    ) -> String {
        let carrier = carrierImportLines(for: suggestion, entryModule: entryModule, resolving: carrierImports)
        return carrier + constructionImportLines(
            usedIn: stub,
            constructions: carrierImports?.receiverConstructions ?? [],
            alreadyImported: alwaysImported.union(importedModules(in: emitted + carrier))
        )
    }

    /// The modules every stub imports unconditionally.
    static let alwaysImported: Set<String> = ["Foundation", "Testing", "PropertyBased", "PropertyLawKit"]

    /// The imports of every construction `stub` uses, in a stable order, deduplicated by line.
    ///
    /// Keyed on the expression's text appearing in the stub rather than on which types were asked
    /// for, because the stub text is what has to compile: a construction that was looked up and not
    /// emitted needs nothing imported.
    static func importLines(
        of constructions: [ReceiverConstructionHarvester.Harvested],
        usedIn stub: String
    ) -> [String] {
        var seen: Set<String> = []
        return constructions
            .filter { stub.contains($0.expression) }
            .sorted { $0.expression < $1.expression }
            .flatMap(\.imports)
            .filter { seen.insert($0).inserted }
    }

    /// The module names imported by a block of import lines.
    static func importedModules(in lines: String) -> Set<String> {
        Set(lines.split(separator: "\n").compactMap { importedModule(in: String($0)) })
    }

    /// The module an import declaration names — `SwiftParser` from `import SwiftParser`,
    /// `@testable import SwiftParser` or `import struct SwiftParser.Parser` — or `nil` for a line
    /// that is not an import.
    static func importedModule(in line: String) -> String? {
        let kinds: Set<Substring> = ["typealias", "struct", "class", "enum", "protocol", "let", "var", "func"]
        var words = line.split(separator: " ").drop { $0.hasPrefix("@") }[...]
        guard words.first == "import" else { return nil }
        words = words.dropFirst()
        if let kind = words.first, kinds.contains(kind) { words = words.dropFirst() }
        guard let path = words.first, let module = path.split(separator: ".").first else { return nil }
        return String(module)
    }
}
