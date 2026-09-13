import Foundation

/// Which protocols confer `@MainActor` on their conformers, resolved as a **fixed point** over
/// the project's own protocol graph.
///
/// ## Why a fixed point and not a list
///
/// SwiftProjectLint reached this shape first, with `Sendable`, and recorded what a literal match
/// costs: its skip rule *"matched a literal string, and was wrong 673 times in one module"* —
/// every swift-syntax node declares `: SyntaxProtocol` and never names `Sendable`, so the rule's
/// documented blind spot **was the entire library**. Its fix computes the refining set as a fixed
/// point, noting that two passes would miss a three-deep chain.
///
/// **No depth-2 case exists in the measured corpus, and that is stated rather than implied.**
/// All three hops this added to SwiftMarkdownWiki are *direct* conformances to a seed protocol,
/// so a flat `Set.contains` would have produced the same six stubs. The fixed point is here
/// because the seed cannot be completed — a project is free to declare
/// `protocol Pane: View` and conform to that — and because the alternative was measured
/// elsewhere: SwiftProjectLint's literal match was wrong 673 times in one module. Depth is
/// covered by unit tests, not by the corpus (SwiftInferProperties#440).
///
/// It does **not** resolve typealiases, and the corpus contains one:
/// `typealias PreviewViewRepresentable = NSViewRepresentable`, conformed to by
/// `MarkdownPreviewView`. That type carries no suggestion today, so closing it would be
/// speculative work under the same rule the seed follows. #440's issue body names
/// `MarkdownPreviewView.mimeType(forExtension:)` as the blocked case; the carrier is actually
/// `KaTeXSchemeHandler`, which merely *lives in* `MarkdownPreviewView.swift`.
///
/// ## The failure direction decides the seed
///
/// Missing an actor costs one emitted stub that does not compile — the behaviour before any of
/// this existed. Inventing one emits `await NotAnActor.run { … }` and breaks a stub that worked.
/// So the seed is a short list of framework protocols that are `@MainActor` by declaration, and
/// growth happens only through **conformance the project itself wrote**. A heuristic — "the name
/// ends in `View`" — would grow it in the unsafe direction and is deliberately absent.
public enum MainActorProtocols {

    /// Framework protocols annotated `@MainActor` at their declaration.
    ///
    /// **Incomplete by construction, and the direction of that incompleteness is the point.**
    /// Apple's SDKs annotate a long tail of delegate protocols, and enumerating them from source
    /// is not possible for a syntactic scan — the annotation lives in a `.swiftinterface` this
    /// tool never reads. A missing entry costs one emitted stub that does not compile, which is
    /// the behaviour before any of this existed. A wrong entry emits `await X.run { … }` for a
    /// type that is not isolated and breaks a stub that worked.
    ///
    /// So an entry is added only once the compiler has been asked. Each of these was confirmed by
    /// typechecking a conforming type's method call from a `nonisolated` function under
    /// `-swift-version 6` and observing the main-actor-isolation diagnostic; a protocol that
    /// produces no diagnostic does not belong here. WebKit's four arrived that way after
    /// `KaTeXSchemeHandler: NSObject, WKURLSchemeHandler` showed the SwiftUI-only seed was too
    /// narrow within minutes of it being written.
    ///
    /// `ObservableObject` is deliberately absent: a Combine protocol with no isolation of its
    /// own, which a great many non-isolated view models conform to. `NSObjectProtocol` likewise.
    public static let frameworkSeed: Set<String> = [
        // SwiftUI
        "View", "App", "Scene", "ViewModifier",
        "NSViewRepresentable", "UIViewRepresentable",
        "NSViewControllerRepresentable", "UIViewControllerRepresentable",
        // WebKit
        "WKURLSchemeHandler", "WKNavigationDelegate", "WKUIDelegate", "WKScriptMessageHandler"
    ]

    /// Every protocol name that confers main-actor isolation, seed plus the project's own
    /// refinements, to any depth.
    ///
    /// Monotone and therefore safe in the direction that matters: the set starts at the seed and
    /// only grows, so a protocol joins only once something it refines is already in. A cycle in
    /// the inheritance clauses simply never promotes — a refusal, not a wrong answer.
    public static func conferring(in typeDecls: [TypeDecl]) -> Set<String> {
        let protocols = typeDecls.filter { $0.kind == .protocol }
        var found = frameworkSeed
        while true {
            var grew = false
            for declaration in protocols where !found.contains(declaration.name) {
                guard declaration.inheritedTypes.contains(where: { found.contains(baseName(of: $0)) })
                else { continue }
                found.insert(declaration.name)
                grew = true
            }
            guard grew else { return found }
        }
    }

    /// The global actor a type is isolated to by its conformances, or `nil`.
    ///
    /// Always `"MainActor"` when it answers, because every seed entry is main-actor and a
    /// refinement inherits the actor of what it refines. A protocol isolated to some *other*
    /// global actor would need the seed to carry the actor name alongside the protocol name —
    /// a wider change than any measured case needs, and the reason this returns a `String`
    /// rather than a `Bool`, so that widening does not change the signature.
    public static func isolation(
        ofTypeNamed name: String,
        conferring: Set<String>,
        in typeDecls: [TypeDecl]
    ) -> String? {
        let conformances = typeDecls
            .filter { $0.name == name }
            .flatMap(\.inheritedTypes)
            .map(baseName(of:))
        return conformances.contains(where: conferring.contains) ? "MainActor" : nil
    }

    /// `Foo` from `Foo<Bar>` — an inheritance clause may name a generic protocol.
    static func baseName(of type: String) -> String {
        let trimmed = type.trimmingCharacters(in: .whitespaces)
        guard let angle = trimmed.firstIndex(of: "<") else { return trimmed }
        return String(trimmed[trimmed.startIndex ..< angle])
    }
}
