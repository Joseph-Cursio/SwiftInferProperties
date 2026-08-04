import Foundation
@testable import SwiftInferCLI
@testable import SwiftInferCore
import Testing

/// **Where each type is declared** — the third sidecar map, and the one rule in it that can be
/// wrong without ever failing to compile.
///
/// The map exists because verify's stub `@testable`-imports the module the *function* lives in,
/// which is not enough: a law over `f(_ s: FunctionSummary)` names a type from another module,
/// `@testable import` does not re-export, and the build fails. Measured 2026-08-03, **37 of 126**
/// `predicate` entries failed exactly that way — 31 on `FunctionSummary` alone.
@Suite("Source-file index — where each type is declared")
struct SourceFileIndexTests {

    private func decl(
        _ name: String,
        kind: TypeDecl.Kind,
        file: String,
        line: Int = 1
    ) -> TypeDecl {
        TypeDecl(
            name: name,
            kind: kind,
            inheritedTypes: [],
            location: SourceLocation(file: file, line: line, column: 1)
        )
    }

    @Test func aDeclarationRecordsItsFile() {
        let index = SwiftInferCommand.Discover.sourceFileIndex(from: [
            decl("FunctionSummary", kind: .struct, file: "/p/Sources/Core/FunctionSummary.swift")
        ])
        #expect(index["FunctionSummary"] == "/p/Sources/Core/FunctionSummary.swift")
    }

    /// **The load-bearing rule.** A declaration says where a type *lives*; an extension only says
    /// where somebody *reached* it. This repo writes `extension String` inside `SwiftInferCore`,
    /// and counting it would attribute `String` to a module that does not define it.
    ///
    /// The consequence is not a stray import but a **wrong** one: the stub would name a module
    /// for a stdlib type and stop looking. Nothing would fail to compile — the import is real and
    /// the type resolves anyway — so this rule can only be protected by a test.
    @Test func anExtensionDoesNotClaimTheType() {
        let index = SwiftInferCommand.Discover.sourceFileIndex(from: [
            decl("String", kind: .extension, file: "/p/Sources/Core/String+Extras.swift")
        ])
        #expect(index["String"] == nil, "an extension is not a declaration site")
    }

    /// And it must not win merely by being seen first.
    @Test func anExtensionDoesNotShadowTheRealDeclaration() {
        let index = SwiftInferCommand.Discover.sourceFileIndex(from: [
            decl("Widget", kind: .extension, file: "/p/Sources/Other/Widget+Sugar.swift"),
            decl("Widget", kind: .struct, file: "/p/Sources/Core/Widget.swift")
        ])
        #expect(index["Widget"] == "/p/Sources/Core/Widget.swift")
    }

    /// Every declaration kind is a declaration site. `protocol` is included deliberately — it has
    /// been scanned since 2026-07-30 and a law can name one as a parameter type.
    @Test func everyDeclarationKindCounts() {
        let kinds: [TypeDecl.Kind] = [.struct, .class, .enum, .actor, .protocol]
        for (offset, kind) in kinds.enumerated() {
            let file = "/p/Sources/Core/T\(offset).swift"
            let index = SwiftInferCommand.Discover.sourceFileIndex(from: [
                decl("T\(offset)", kind: kind, file: file)
            ])
            #expect(index["T\(offset)"] == file, "\(kind.rawValue) declares a type")
        }
    }

    /// Ties among genuine declarations keep the first seen, matching `genericParametersIndex`.
    /// Two modules declaring the same type name collide — an existing limitation of
    /// `typeShapesByName`, which is keyed the same way, inherited here rather than introduced.
    @Test func aCollisionKeepsTheFirstDeclaration() {
        let index = SwiftInferCommand.Discover.sourceFileIndex(from: [
            decl("Parameter", kind: .struct, file: "/p/Sources/A/Parameter.swift"),
            decl("Parameter", kind: .struct, file: "/p/Sources/B/Parameter.swift")
        ])
        #expect(index["Parameter"] == "/p/Sources/A/Parameter.swift")
    }

    /// Keyed by the bare name, so a generic carrier resolves the same as a concrete one — the
    /// same stripping `genericParametersIndex` applies, and for the same reason.
    @Test func aGenericTypeIsKeyedByItsBareName() {
        let index = SwiftInferCommand.Discover.sourceFileIndex(from: [
            decl("Box<T>", kind: .struct, file: "/p/Sources/Core/Box.swift")
        ])
        #expect(index["Box"] == "/p/Sources/Core/Box.swift")
    }
}
