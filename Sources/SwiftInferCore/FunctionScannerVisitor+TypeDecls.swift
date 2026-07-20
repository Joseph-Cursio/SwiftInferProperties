import PropertyLawCore
import SwiftSyntax

extension FunctionScannerVisitor {

    /// Build a `TypeDecl` from a type-bearing decl's name, kind,
    /// inheritance clause, introducer keyword, and member block.
    /// Centralizes inheritance-clause parsing, location calculation,
    /// and the M4.1 member-block inspection (stored properties, user-
    /// declared init, user-declared `gen()`).
    func makeTypeDecl(
        name: String,
        kind: TypeDecl.Kind,
        inheritanceClause: InheritanceClauseSyntax?,
        keywordToken: TokenSyntax,
        memberBlock: MemberBlockSyntax
    ) -> TypeDecl {
        let inheritedTypes = inheritanceClause?.inheritedTypes.map(\.type.trimmedDescription) ?? []
        let position = keywordToken.positionAfterSkippingLeadingTrivia
        let sourceLocation = converter.location(for: position)
        let location = SourceLocation(
            file: file,
            line: sourceLocation.line,
            column: sourceLocation.column
        )
        // hasUserInit: extensions don't suppress synthesised memberwise
        // init even when they declare an init, so the strategist
        // contract per `DerivationStrategy.swift:147` requires we leave
        // it false for extension records regardless of body content.
        let hasUserInit = (kind == .extension) ? false : MemberBlockInspector.hasUserInit(in: memberBlock)
        // storedMembers: extensions can't add stored properties to a
        // struct (compile error), so always empty for `.extension`.
        let storedMembers = (kind == .extension) ? [] : MemberBlockInspector.storedMembers(in: memberBlock)
        // M14.0 — enumCaseNames: populated for primary enum decls AND
        // extensions that add cases to a same-name enum. Other kinds
        // (.struct / .class / .actor) get [] — they can't declare
        // `case` members. The M14.1 detector unions cases across
        // primary + extension records keyed by `name`.
        let enumCaseNames: [String]
        let enumCases: [EnumCase]
        switch kind {
        case .enum, .extension:
            enumCaseNames = MemberBlockInspector.enumCaseNames(in: memberBlock)
            enumCases = MemberBlockInspector.enumCases(in: memberBlock)

        case .struct, .class, .actor:
            enumCaseNames = []
            enumCases = []
        }
        // Tier 6 — init signatures captured for structs (the only kind the
        // strategist lifts a memberwise/init generator through, via
        // `TypeShapeBuilder`'s `primary.initializers`) AND for extensions, whose
        // records `TypeShapeBuilder` never reads for inits but which carry the
        // idiomatic `init(from: Decoder)` half of a custom `Codable` conformance
        // (`CodableRoundTripTemplate`). `InitializerDecodeSynthesizer` stays
        // struct-gated, so extension inits reach only the codable-round-trip
        // recogniser, which hard-filters to `Decoder`-typed inits.
        let initializers = (kind == .struct || kind == .extension)
            ? MemberBlockInspector.initializers(in: memberBlock)
            : []
        return TypeDecl(
            name: name,
            kind: kind,
            inheritedTypes: inheritedTypes,
            location: location,
            hasUserGen: MemberBlockInspector.hasUserGen(in: memberBlock),
            storedMembers: storedMembers,
            hasUserInit: hasUserInit,
            enumCaseNames: enumCaseNames,
            initializers: initializers,
            enumCases: enumCases
        )
    }
}
