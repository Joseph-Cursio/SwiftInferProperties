import SwiftInferCore

/// Two functions a cross-function template can score together —
/// `forward: T -> U` paired with `reverse: U -> T`.
///
/// Orientation is canonical: `forward` is the function that comes first by
/// `(file, line)` so output is byte-stable across runs (PRD §16 #6). The
/// per-template scorer treats the pair as unordered for naming purposes —
/// `RoundTripTemplate` matches the curated inverse list against
/// `(forward.name, reverse.name)` *and* the swapped order.
public struct FunctionPair: Sendable, Equatable {

    public let forward: FunctionSummary
    public let reverse: FunctionSummary

    public init(forward: FunctionSummary, reverse: FunctionSummary) {
        self.forward = forward
        self.reverse = reverse
    }

    /// Common `@Discoverable(group:)` value when both halves of the
    /// pair carry the same non-nil group; `nil` otherwise. Computed
    /// pure-property — consumers like `RoundTripTemplate` (M5.1) read
    /// it to decide whether to fire the `+35` PRD §4.1
    /// `.discoverableAnnotation` cross-pair signal. Mismatched groups
    /// (one pair half tagged `"codec"`, the other tagged `"queue"`)
    /// return `nil` — the user explicitly grouped these into different
    /// scopes, so the annotation is *not* evidence of a cross-pair
    /// property; conversely, both-untagged is the M1-default case.
    public var sharedDiscoverableGroup: String? {
        guard let forwardGroup = forward.discoverableGroup,
              let reverseGroup = reverse.discoverableGroup,
              forwardGroup == reverseGroup else {
            return nil
        }
        return forwardGroup
    }
}

/// Type-driven candidate-pair finder. Implements PRD §5.5's first
/// tier — the type filter — at module scope (the entire scanned corpus).
/// Naming and explicit-`@Discoverable` filters live in the per-template
/// scorers (M1.4 only ships the type filter; naming is a *signal*, not a
/// pre-filter, so the scoring engine can still see Possible-tier pairs).
public enum FunctionPairing {

    /// Every candidate pair `(forward, reverse)` such that
    ///   - both are single-parameter, non-`inout`, non-`mutating`,
    ///   - both have a non-`Void` return,
    ///   - `forward.return == reverse.param[0]` and
    ///     `forward.param[0] == reverse.return`.
    /// Pairs are returned exactly once, oriented by `(file, line)` so the
    /// list is deterministic.
    /// `conformances` is the corpus-wide `name -> inherited types` index. It is
    /// consulted only by the protocol-printer relaxation below; the strict type
    /// filter needs nothing. Defaults to empty so existing call sites and the
    /// pairing test suites compile unchanged.
    public static func candidates(
        in summaries: [FunctionSummary],
        conformances: [String: Set<String>] = [:]
    ) -> [FunctionPair] {
        let pairable = summaries.filter(isPairable)
        var pairs: [FunctionPair] = []
        for (lhsIndex, lhs) in pairable.enumerated() {
            for rhs in pairable.dropFirst(lhsIndex + 1)
                where hasInverseTypeShape(lhs, rhs, conformances: conformances)
                    && initializerPairAdmissible(lhs, rhs) {
                pairs.append(orientedPair(lhs, rhs))
            }
        }
        return pairs.sorted(by: lessThan)
    }

    /// A **printer half**: a nullary instance member returning `String` under
    /// one of the two names `CustomStringConvertible` defines.
    ///
    /// This is the gate that keeps the protocol relaxation from multiplying.
    /// Relaxing the type filter to "codomain *conforms to* the other half's
    /// domain" in general would pair every `X -> Concrete` against every
    /// `Protocol -> X` the corpus declares — a combinatorial flood of the kind
    /// the cross-type counter exists to stop. Scoped to printers it admits one
    /// extra shape: the idiomatic Swift printer, declared once on a protocol.
    static func isPrinterHalf(_ summary: FunctionSummary) -> Bool {
        summary.parameters.isEmpty
            && !summary.isStatic
            && !summary.isMutating
            && summary.returnTypeText == "String"
            && (summary.name == "description" || summary.name == "debugDescription")
    }

    /// A synthetic init-derived decode half (`isInitializer`, produced only by
    /// `InitializerDecodeSynthesizer`) exists solely to complete a codec
    /// round-trip: it may pair ONLY with an encode half whose name embeds the
    /// init's argument-label stem (`base64EncodedString` embeds `base64Encoded`).
    /// Without that relationship a synthetic init pairs by bare type-shape with
    /// every same-typed getter on its carrier — e.g.
    /// `CustomRuleConflict(ruleIdentifier:)` × `id()` / `message()` — which is
    /// pure noise (SwiftLintRuleStudio road-test #10). Real scanned functions
    /// never carry `isInitializer` (see its doc comment), so this gate is scoped
    /// precisely to the synthetic halves and does NOT reintroduce a naming
    /// pre-filter for ordinary pairs ("naming is a signal, not a pre-filter",
    /// cycle-4).
    static func initializerPairAdmissible(
        _ lhs: FunctionSummary,
        _ rhs: FunctionSummary
    ) -> Bool {
        let initHalf: FunctionSummary
        let encodeHalf: FunctionSummary
        if lhs.isInitializer {
            initHalf = lhs
            encodeHalf = rhs
        } else if rhs.isInitializer {
            initHalf = rhs
            encodeHalf = lhs
        } else {
            return true   // neither half is a synthetic init — no gate
        }
        return initializerLabelStemMatches(label: initHalf.name, encodeName: encodeHalf.name)
    }

    /// Whether a synthetic init-decode half named `label` (its argument-label
    /// stem) is embedded, case-insensitively, in `encodeName` — the codec
    /// relationship `base64EncodedString` ⊃ `base64Encoded`. An unlabelled init
    /// synthesizes to the bare name `"init"` (no stem to match); a <3-char label
    /// is too short to be a meaningful stem. Shared by the pairing admission gate
    /// above and `RoundTripTemplate.initializerLabelStemSignal`'s `+40` name
    /// signal, so the pairing filter and the scorer can't drift.
    static func initializerLabelStemMatches(label: String, encodeName: String) -> Bool {
        guard label != "init", label.count >= 3 else { return false }
        return encodeName.lowercased().contains(label.lowercased())
    }

    /// The **domain** of `summary` viewed as a transformation
    /// `domain -> codomain`:
    ///   - a function with an explicit first parameter → that parameter's type
    ///     (free / static / instance binary-op — unchanged behaviour);
    ///   - a **0-parameter, non-`static` instance method** → the receiver type
    ///     (`self`), so an instance-method encode
    ///     `func base64EncodedString() -> String` reads as `Blob -> String`
    ///     and can pair with a free / static `decode(String) -> Blob`. This is
    ///     the idiomatic Swift codec shape the pairing was previously blind to
    ///     (it keyed on `parameters.first`).
    /// `nil` for a shape with no domain (a 0-parameter free or `static`
    /// function has no receiver to stand in as the input).
    public static func transformationDomain(_ summary: FunctionSummary) -> String? {
        if let param = summary.parameters.first {
            return param.typeText
        }
        guard summary.parameters.isEmpty,
              !summary.isStatic,
              let container = summary.containingTypeName else {
            return nil
        }
        return container
    }

    private static func isPairable(_ summary: FunctionSummary) -> Bool {
        guard !summary.isMutating,
              let returnType = summary.returnTypeText,
              returnType != "Void",
              returnType != "()",
              transformationDomain(summary) != nil else {
            return false
        }
        // With an explicit parameter it must be a *single*, non-`inout` one; a
        // multi-argument function is not a simple `domain -> codomain`
        // transformation. A 0-parameter instance method (domain = receiver) is
        // already gated by `transformationDomain`.
        if let param = summary.parameters.first {
            return summary.parameters.count == 1 && !param.isInout
        }
        return true
    }

    private static func hasInverseTypeShape(
        _ lhs: FunctionSummary,
        _ rhs: FunctionSummary,
        conformances: [String: Set<String>] = [:]
    ) -> Bool {
        guard let lhsDomain = transformationDomain(lhs),
              let rhsDomain = transformationDomain(rhs),
              let lhsReturn = lhs.returnTypeText,
              let rhsReturn = rhs.returnTypeText else {
            return false
        }
        if lhsReturn == rhsDomain, lhsDomain == rhsReturn {
            return true
        }
        // Protocol-mediated printer half — `docs/parsing-catalog-gap.md` §3c.
        //
        // swift-syntax's printer is declared ONCE, on an extension of the
        // protocol:
        //
        //     extension SyntaxProtocol { public var description: String }
        //     public static func parse(source: String) -> SourceFileSyntax
        //
        // The scanner records the printer's domain as `SyntaxProtocol`, which
        // never meets `String -> SourceFileSyntax` under the strict test, so
        // the pair never formed and the fidelity law
        // `parse(source).description == source` was unreachable at any tier —
        // even after §3a curated the name pair and §3b relieved the cross-type
        // counter. This is the last of the three §3 blockers.
        //
        // The relaxation is exactly: the concrete codomain may CONFORM to the
        // printer's declaring protocol, rather than equalling it. Same
        // admissibility idea as the erased self-form (§5) — the two halves
        // compose because the conformance says they do.
        if lhsDomain == rhsReturn,
           isPrinterHalf(rhs),
           conforms(lhsReturn, to: rhsDomain, conformances) {
            return true
        }
        if lhsReturn == rhsDomain,
           isPrinterHalf(lhs),
           conforms(rhsReturn, to: lhsDomain, conformances) {
            return true
        }
        return false
    }

    /// Whether `type` is recorded as conforming to `protocolName` in the
    /// scanned corpus. Unresolvable means `false` — silence rather than a
    /// guessed pair, the same conservative direction the erased self-form and
    /// `ProtocolCoverageMap` take.
    private static func conforms(
        _ type: String,
        to protocolName: String,
        _ conformances: [String: Set<String>]
    ) -> Bool {
        guard type != protocolName else { return false }
        return conformances[type]?.contains(protocolName) ?? false
    }

    private static func orientedPair(
        _ lhs: FunctionSummary,
        _ rhs: FunctionSummary
    ) -> FunctionPair {
        if locationLessThan(lhs.location, rhs.location) {
            return FunctionPair(forward: lhs, reverse: rhs)
        }
        return FunctionPair(forward: rhs, reverse: lhs)
    }

    private static func lessThan(_ lhs: FunctionPair, _ rhs: FunctionPair) -> Bool {
        locationLessThan(lhs.forward.location, rhs.forward.location)
    }

    private static func locationLessThan(
        _ lhs: SourceLocation,
        _ rhs: SourceLocation
    ) -> Bool {
        if lhs.file != rhs.file {
            return lhs.file < rhs.file
        }
        return lhs.line < rhs.line
    }
}
