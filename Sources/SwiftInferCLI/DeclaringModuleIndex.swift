import Foundation

/// Which module declares each type name, read from a package's own `Sources/` directories.
///
/// A receiver construction is copied from a test file, and that file may reach a type through an
/// import the generated stub cannot make: SwiftProjectLint's root tests `@testable import Core`,
/// which re-exports `SyntaxPattern` and `PatternCategory`, while a stub for a rule lives in the
/// nested `SwiftProjectLintRules` package, where `Core` does not exist. `keepingResolvable` rightly
/// drops that import, and the name goes with it — 10 census stubs failed on exactly this. The type
/// is declared in `SwiftProjectLintVisitors` / `SwiftProjectLintModels`, which the nested package
/// CAN import, and nothing looked there.
///
/// A text scan, not a parse: it answers "which `Sources/<Module>` spells a declaration of this
/// name", and an ambiguous answer (two modules) is never used.
enum DeclaringModuleIndex {

    static func index(root: URL) -> [String: Set<String>] {
        var modules: [String: Set<String>] = [:]
        for (module, text) in sourceFiles(under: root) {
            for name in declaredNames(in: text) {
                modules[name, default: []].insert(module)
            }
        }
        return modules
    }

    /// Every Swift file under a `Sources/<Module>/` directory beneath `root`, with its module —
    /// skipping build products, checkouts, tests and generated stubs.
    static func sourceFiles(under root: URL) -> [(module: String, text: String)] {
        let skipped: Set<String> = [".build", ".git", "Tests", "Generated", "checkouts", ".swiftpm"]
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else {
            return []
        }
        var files: [(module: String, text: String)] = []
        for case let url as URL in walker {
            if skipped.contains(url.lastPathComponent) {
                walker.skipDescendants()
                continue
            }
            guard url.pathExtension == "swift",
                  let module = InteractiveTriage.moduleName(fromSourceFile: url.path),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            files.append((module, text))
        }
        return files
    }

    private static let declaration = try? NSRegularExpression(
        pattern: #"\b(?:struct|class|enum|actor|protocol|typealias)\s+([A-Z][A-Za-z0-9_]*)"#
    )

    static func declaredNames(in text: String) -> [String] {
        guard let declaration else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return declaration.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    /// The capitalised names an expression uses — the candidates for a declaring-module import.
    static func typeNames(in expression: String) -> Set<String> {
        Set(expression.split { !($0.isLetter || $0.isNumber || $0 == "_") }
            .map(String.init)
            .filter { $0.first?.isUppercase == true })
    }
}
