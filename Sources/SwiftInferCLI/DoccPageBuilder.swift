import Foundation
import SwiftInferCore

/// V1.142 — verified-only DocC generation. Reads the SemanticIndex + the
/// measured verify-evidence log and produces DocC documentation ONLY for
/// properties backed by an executed property test (`measured-bothPass`).
///
/// **The deliberate gate.** Published documentation is trusted as
/// authoritative, so it must be *provable*, not inferred — the useful
/// subset is exactly the subset the verify pipeline confirmed. Rows that
/// are merely `.likely` / `.possible` (inferred, unverified) are never
/// documented: a guess that reads as a guarantee is worse than silence.
/// Jargon (`monoid`, `semilattice`) is translated to the behavioral
/// consequence a caller actually cares about.

/// One verified property, container-grouped, ready to render.
public struct DoccProperty: Equatable, Sendable {
    /// Enclosing type name (the DocC symbol the property attaches to), or
    /// `nil` for a top-level function.
    public let container: String?
    /// Plain-language headline, e.g. "Idempotent".
    public let headline: String
    /// Plain-language consequence sentence (jargon translated to behavior).
    public let consequence: String

    public init(container: String?, headline: String, consequence: String) {
        self.container = container
        self.headline = headline
        self.consequence = consequence
    }
}

/// One DocC output file (a symbol-extension `.md` or the free-function
/// article).
public struct DoccPage: Equatable, Sendable {
    public let fileName: String
    public let markdown: String

    public init(fileName: String, markdown: String) {
        self.fileName = fileName
        self.markdown = markdown
    }
}

public enum DoccPageBuilder {

    // MARK: - Verified gate

    /// Normalized identity hashes (no `0x`) with a `measured-bothPass`
    /// outcome — the verified set. This is the whole gate: only these rows
    /// become documentation.
    public static func verifiedHashes(in log: VerifyEvidenceLog) -> Set<String> {
        Set(
            log.records
                .filter { $0.outcome == .measuredBothPass }
                .map(\.identityHash)
        )
    }

    // MARK: - Index → properties

    /// Both index surfaces, filtered to verified rows and mapped to
    /// container-grouped properties. Deduplicated by
    /// (container, headline, consequence).
    public static func verifiedProperties(
        in index: IndexStore.Index,
        verified: Set<String>
    ) -> [DoccProperty] {
        var seen = Set<String>()
        var out: [DoccProperty] = []
        func add(_ property: DoccProperty) {
            let key = "\(property.container ?? "")|\(property.headline)|\(property.consequence)"
            if seen.insert(key).inserted { out.append(property) }
        }
        for entry in index.entries where verified.contains(normalizeHash(entry.identityHash)) {
            add(algebraicProperty(entry))
        }
        for entry in index.interactionEntries where verified.contains(normalizeHash(entry.identityHash)) {
            add(interactionProperty(entry))
        }
        return out
    }

    // MARK: - Properties → pages

    /// Group properties into output files: one symbol-extension per
    /// containing type (alphabetical), plus a single free-function article
    /// last (only when there are top-level-function properties).
    public static func pages(from properties: [DoccProperty]) -> [DoccPage] {
        var pages: [DoccPage] = []
        let containers = properties.compactMap(\.container).sorted()
        var emitted = Set<String>()
        for container in containers where emitted.insert(container).inserted {
            let forType = properties.filter { $0.container == container }
            pages.append(
                DoccPage(
                    fileName: "\(bareTypeName(container)).md",
                    markdown: renderTypePage(container: container, properties: forType)
                )
            )
        }
        let free = properties.filter { $0.container == nil }
        if !free.isEmpty {
            pages.append(
                DoccPage(fileName: "VerifiedProperties.md", markdown: renderArticle(properties: free))
            )
        }
        return pages
    }

    /// Write `pages` into `directory` (created on demand), returning the
    /// written file URLs. Used by `swift-infer docc`; separated so tests can
    /// drive the write without the ArgumentParser shell.
    @discardableResult
    public static func write(_ pages: [DoccPage], to directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try pages.map { page in
            let url = directory.appendingPathComponent(page.fileName)
            try Data(page.markdown.utf8).write(to: url, options: .atomic)
            return url
        }
    }

    // MARK: - Consequence mapping (jargon → behavior)

    private static let algebraicDescriptions: [String: (headline: String, template: String)] = [
        "idempotence": ("Idempotent", "Applying `{sym}` twice is the same as applying it once."),
        "round-trip": ("Round-trip", "`{sym}` and `{sec}` are inverses — the original value is recovered."),
        "commutativity": ("Commutative", "The order of arguments to `{sym}` does not change the result."),
        "associativity": ("Associative", "How calls to `{sym}` are grouped does not change the result."),
        "monotonicity": ("Monotonic", "`{sym}` preserves ordering — larger inputs map to larger or equal outputs."),
        "dual-style-consistency": (
            "Consistent in-place / returning forms",
            "The mutating and non-mutating forms of `{sym}` agree."
        ),
        "composition": ("Composes", "Repeated `{sym}` calls combine into a single equivalent step."),
        "identity-element": ("Has an identity element", "`{sym}` has a neutral element that leaves values unchanged."),
        "inverse-pair": ("Invertible", "`{sym}` and `{sec}` undo each other."),
        "invariant-preservation": ("Preserves its invariant", "`{sym}` always maintains the type's invariant.")
    ]

    private static let interactionDescriptions: [String: (headline: String, template: String)] = [
        "idempotence": (
            "Idempotent action",
            "Dispatching the action twice leaves state as if it were dispatched once."
        ),
        "referential-integrity": (
            "Referential integrity",
            "A selected reference always points at a live element and never dangles."
        ),
        "cardinality": ("Mutual exclusion", "At most one of the tracked options is active at a time."),
        "biconditional": (
            "Kept in lockstep",
            "Two pieces of state stay consistent — one is set exactly when the other is."
        ),
        "conservation": ("Conserved count", "A stored count stays in sync with the collection it counts.")
    ]

    private static func algebraicProperty(_ entry: SemanticIndexEntry) -> DoccProperty {
        let symbol = entry.primaryFunctionName
        let secondary = entry.secondaryFunctionName ?? "its inverse"
        let described = algebraicDescriptions[entry.templateName]
            ?? ("Verified property", "SwiftInfer verified a `\(entry.templateName)` property of `{sym}`.")
        let consequence = described.template
            .replacingOccurrences(of: "{sym}", with: symbol)
            .replacingOccurrences(of: "{sec}", with: secondary)
        return DoccProperty(container: entry.typeName, headline: described.headline, consequence: consequence)
    }

    private static func interactionProperty(_ entry: InteractionIndexEntry) -> DoccProperty {
        let described = interactionDescriptions[entry.family]
            ?? ("Verified invariant", "SwiftInfer verified a `\(entry.family)` invariant.")
        let consequence = "\(described.template) `\(entry.predicate)`"
        return DoccProperty(
            container: enclosingType(entry.reducerQualifiedName),
            headline: described.headline,
            consequence: consequence
        )
    }

    // MARK: - Rendering

    private static func renderTypePage(container: String, properties: [DoccProperty]) -> String {
        """
        # ``\(bareTypeName(container))``

        @Metadata {
            @DocumentationExtension(mergeBehavior: append)
        }

        ## Verified Properties

        Behavioral properties SwiftInfer verified by executed property tests.

        \(bulletList(properties))

        \(provenanceNote)
        """ + "\n"
    }

    private static func renderArticle(properties: [DoccProperty]) -> String {
        """
        # Verified Properties

        @Metadata {
            @PageKind(article)
        }

        Behavioral properties SwiftInfer verified by executed property tests for top-level functions.

        \(bulletList(properties))

        \(provenanceNote)
        """ + "\n"
    }

    private static func bulletList(_ properties: [DoccProperty]) -> String {
        properties
            .map { "- **\($0.headline)** — \($0.consequence)" }
            .joined(separator: "\n")
    }

    private static let provenanceNote =
        "- Note: Generated by `swift-infer docc` from measured verify evidence — "
            + "every property here is backed by a passing property test. "
            + "Regenerate after `swift-infer verify`; do not edit by hand."

    // MARK: - Helpers

    private static func normalizeHash(_ hash: String) -> String {
        hash.hasPrefix("0x") ? String(hash.dropFirst(2)) : hash
    }

    /// The enclosing type of a reducer qualified name: everything before the
    /// last `.` (`"NavFeature.reduce"` → `"NavFeature"`), or `nil` for a
    /// top-level function (`"reduce"`).
    private static func enclosingType(_ qualifiedName: String) -> String? {
        guard let dot = qualifiedName.lastIndex(of: ".") else { return nil }
        return String(qualifiedName[..<dot])
    }

    /// Strip a generic argument list so the DocC symbol link + filename use
    /// the bare declaration name (`"Complex<Double>"` → `"Complex"`).
    private static func bareTypeName(_ name: String) -> String {
        if let openAngle = name.firstIndex(of: "<") {
            return String(name[..<openAngle])
        }
        return name
    }
}
