import Foundation
import SwiftInferCore

/// **Which modules must the verify stub import?**
///
/// The stub `@testable`-imports the module the *function* lives in. That is necessary and not
/// sufficient: a derived generator for a carrier names the carrier's members, its members'
/// members, and so on — and any of those can be declared in another module. `@testable import`
/// does not re-export, so the stub sees a type it cannot name and the build fails.
///
/// Measured 2026-08-03 over all 126 `predicate` entries: **37 failed exactly this way**, 31 of
/// them on `FunctionSummary` alone.
///
/// ## Why a structural closure rather than scanning the generated source
///
/// The obvious cheap answer is to string-match the emitted recipe against every known type name.
/// It would mostly work and it would be wrong in a way that is hard to see: the recipe is source
/// text, so a type named in a comment counts, a type whose name is a substring of another counts
/// twice, and a type reached only at a later derivation tier does not count at all until someone
/// changes an emitter. The dependency is a fact about the *shape*, so it is read off the shape.
///
/// `GeneratorResolver` already walks these same three edges to derive nested carriers
/// recursively; this walks them to find out who must be imported, which is the same graph asked
/// a different question.
///
/// ## Over-collecting is safe, and that is the design
///
/// Type text is not parsed into a type — it is scanned for identifiers, so `[String: Foo]?`
/// yields `String`, `Foo`, and any other word in it. Nothing is lost by being liberal, because
/// **the declaration-site map is the filter**: an identifier that no scanned declaration claims
/// resolves to no file, and therefore to no import. Stdlib names, generic parameters, and
/// keywords all fall out for free rather than needing a denylist that would go stale.
enum VerifyImportSet {

    /// Every type name reachable from `carrier` through stored members, initializer parameters,
    /// and enum associated values — including `carrier` itself.
    ///
    /// Breadth-first with a visited set, so a recursive type (`indirect enum Tree`) or a cycle
    /// between two shapes terminates rather than walking forever. `IndexedTypeShape` carries no
    /// depth limit and the corpus contains genuine cycles, so this is load-bearing.
    static func referencedTypeNames(
        carrier: String,
        shapes: [String: IndexedTypeShape]
    ) -> Set<String> {
        var seen: Set<String> = []
        var frontier = [bareName(carrier)]
        var collected: Set<String> = []

        while let next = frontier.popLast() {
            guard seen.insert(next).inserted else { continue }
            collected.insert(next)
            guard let shape = shapes[next] else { continue }
            for text in referencedTypeTexts(of: shape) {
                for identifier in identifiers(in: text) {
                    collected.insert(identifier)
                    // Only a name the scan actually has a shape for can lead anywhere further.
                    if shapes[identifier] != nil { frontier.append(identifier) }
                }
            }
        }
        return collected
    }

    /// The three edges a generator traverses when it builds a value of this type.
    private static func referencedTypeTexts(of shape: IndexedTypeShape) -> [String] {
        shape.storedMembers.map(\.typeName)
            + shape.initializers.flatMap { $0.parameters.map(\.typeName) }
            + shape.enumCases.flatMap { $0.associatedValues.map(\.typeName) }
    }

    /// Modules to `@testable import`, given where each type is declared.
    ///
    /// `entryModule` is always included when present — it is the module the law's own function
    /// lives in, and it stays first so the common single-module case emits exactly what it did
    /// before this existed. The rest are sorted, because an import list that reorders between
    /// runs would make two otherwise-identical stubs differ and defeat replay.
    ///
    /// A type whose declaration site resolves to no module is **silently skipped**, and that is
    /// correct rather than lenient: `VerifyTargetInference` declines nested packages, dependency
    /// checkouts and non-`Sources/` layouts, and every one of those is a type the stub genuinely
    /// cannot reach by importing something. Failing loudly here would turn a build error that
    /// names the missing type into an argument error that does not.
    static func modules(
        forTypes typeNames: Set<String>,
        entryModule: String?,
        sourceFileByTypeName: [String: String],
        packageRoot: URL
    ) -> [String] {
        var resolved: Set<String> = []
        for name in typeNames {
            guard let file = sourceFileByTypeName[name],
                  let module = VerifyTargetInference.module(
                      forLocation: file,
                      packageRoot: packageRoot
                  )
            else { continue }
            resolved.insert(module)
        }
        guard let entryModule else { return resolved.sorted() }
        resolved.remove(entryModule)
        return [entryModule] + resolved.sorted()
    }

    /// Identifier-shaped runs in a type's source text. `[String: Foo]?` → `String`, `Foo`.
    ///
    /// Leading underscores are admitted because Swift permits them in type names; digits are
    /// admitted after the first character for the same reason.
    static func identifiers(in typeText: String) -> [String] {
        var found: [String] = []
        var current = ""
        for character in typeText {
            if character.isLetter || character == "_" || (!current.isEmpty && character.isNumber) {
                current.append(character)
            } else if !current.isEmpty {
                found.append(current)
                current = ""
            }
        }
        if !current.isEmpty { found.append(current) }
        return found
    }

    /// `Box<Int>` → `Box`. Shapes are keyed by the bare name, so lookups must be too.
    private static func bareName(_ typeName: String) -> String {
        identifiers(in: typeName).first ?? typeName
    }
}
