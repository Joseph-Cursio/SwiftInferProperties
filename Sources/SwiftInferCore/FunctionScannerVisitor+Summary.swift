import PropertyLawCore
import SwiftEffectInference
import SwiftSyntax

extension FunctionScannerVisitor {

    /// Build a `FunctionSummary` from a `FunctionDeclSyntax`. Combines
    /// signature info (parameters / return / effects / modifiers), the
    /// `BodySignalVisitor` walk over the body, and the M5.3 + M7.2.a
    /// attribute scans for `@Discoverable(group:)` and
    /// `@CheckProperty(.preservesInvariant(\..))`.
    func makeSummary(from node: FunctionDeclSyntax) -> FunctionSummary {
        let name = node.name.text
        let parameters = node.signature.parameterClause.parameters.map(makeParameter(from:))
        let returnTypeText = node.signature.returnClause?.type.trimmedDescription
        let effects = node.signature.effectSpecifiers
        let isThrows = effects?.throwsClause != nil
        let isAsync = effects?.asyncSpecifier != nil
        let modifiers = node.modifiers.map(\.name.text)
        let isMutating = modifiers.contains("mutating")
        let isStatic = modifiers.contains("static") || modifiers.contains("class")

        let position = node.funcKeyword.positionAfterSkippingLeadingTrivia
        let sourceLocation = converter.location(for: position)
        let location = SourceLocation(
            file: file,
            line: sourceLocation.line,
            column: sourceLocation.column
        )

        let containingTypeName = typeStack.last
        let bodySignals = scanBody(of: node)
        let discoverableGroup = AttributeScanner.discoverableGroup(in: node.attributes)
        let invariantKeypath = AttributeScanner.invariantKeypath(in: node.attributes)
        // Sound purity verdict — computed here, the one place the live
        // `FunctionDeclSyntax` is available, and carried on the summary for the
        // `@lint.effect pure` advisory channel.
        let isInferredPure = SoundPurity.isPure(node)
        // Clock-determinism claim — same scan-time posture as the purity
        // verdict above; consumed by the async-veto relaxation (workplan
        // Phase 4). First EffectAnnotationParser use in this repo.
        let isClockDeterministic = EffectAnnotationParser.isClockDeterministic(declaration: node)
        // The leading doc comment — carried on the summary as a candidate
        // reference definition for the docstring advisory. Unclassified here.
        let docComment = DocCommentExtractor.docComment(from: node.leadingTrivia)

        return FunctionSummary(
            name: name,
            parameters: parameters,
            returnTypeText: returnTypeText,
            isThrows: isThrows,
            isAsync: isAsync,
            isMutating: isMutating,
            isStatic: isStatic,
            location: location,
            containingTypeName: containingTypeName,
            bodySignals: bodySignals,
            discoverableGroup: discoverableGroup,
            invariantKeypath: invariantKeypath,
            isInferredPure: isInferredPure,
            isClockDeterministic: isClockDeterministic,
            docComment: docComment
        )
    }

    /// Build a `FunctionSummary` from a read-only COMPUTED PROPERTY, modelled as
    /// a nullary `self -> T` method (0 parameters, returns the property type). A
    /// getter is a pure `self -> T` map, so a computed property named like an
    /// involution (`var conjugate: Self`) is exactly the involution template's
    /// instance shape. `nil` for anything that isn't a single read-only computed
    /// property with a declared type — a stored property, a `get set` pair, or an
    /// `async`/`throws` getter. Recall-widening epic #1 (2026-07).
    func makeSummary(fromComputedProperty node: VariableDeclSyntax) -> FunctionSummary? {
        guard node.bindings.count == 1,
              let binding = node.bindings.first,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
              let typeAnnotation = binding.typeAnnotation,
              let accessorBlock = binding.accessorBlock,
              Self.isReadOnlyGetter(accessorBlock) else {
            return nil
        }
        // Instance member only: the involution shape is `self -> Self`, so it
        // needs a containing type. A top-level computed `var` has none.
        guard let containingTypeName = typeStack.last else {
            return nil
        }
        let modifiers = node.modifiers.map(\.name.text)
        let isStatic = modifiers.contains("static") || modifiers.contains("class")
        let position = node.bindingSpecifier.positionAfterSkippingLeadingTrivia
        let sourceLocation = converter.location(for: position)
        return FunctionSummary(
            name: pattern.identifier.text,
            parameters: [],
            returnTypeText: typeAnnotation.type.trimmedDescription,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: isStatic,
            location: SourceLocation(file: file, line: sourceLocation.line, column: sourceLocation.column),
            containingTypeName: containingTypeName,
            bodySignals: .empty,
            isInferredPure: true,
            isComputedProperty: true,
            docComment: DocCommentExtractor.docComment(from: node.leadingTrivia)
        )
    }

    /// A read-only computed accessor: the implicit-getter form `var x: T { … }`,
    /// or an explicit block containing `get` and no `set` — and no `async` /
    /// `throws` getter (a getter that can fail or suspend isn't the pure
    /// `self -> T` map the templates assume).
    private static func isReadOnlyGetter(_ block: AccessorBlockSyntax) -> Bool {
        switch block.accessors {
        case .getter:
            return true

        case let .accessors(list):
            let specifiers = list.map(\.accessorSpecifier.text)
            guard specifiers.contains("get"), !specifiers.contains("set") else {
                return false
            }
            return !list.contains { accessor in
                accessor.effectSpecifiers?.asyncSpecifier != nil
                    || accessor.effectSpecifiers?.throwsClause != nil
            }
        }
    }

    private func makeParameter(from syntax: FunctionParameterSyntax) -> Parameter {
        // Swift parameter shapes:
        //   `func f(a: Int)`       → firstName=a, secondName=nil → label=a, name=a
        //   `func f(_ a: Int)`     → firstName=_, secondName=a   → label=nil, name=a
        //   `func f(label a: Int)` → firstName=label, secondName=a → label=label, name=a
        let firstName = syntax.firstName.text
        let secondName = syntax.secondName?.text

        let label: String?
        let internalName: String
        if let secondName {
            label = (firstName == "_") ? nil : firstName
            internalName = secondName
        } else {
            label = firstName
            internalName = firstName
        }

        let (typeText, isInout) = Self.strippingParameterSpecifiers(syntax.type.trimmedDescription)

        return Parameter(
            label: label,
            internalName: internalName,
            typeText: typeText,
            isInout: isInout
        )
    }

    /// Strip leading parameter specifiers so the type text is the bare type.
    /// `inout` is tracked separately (it changes value semantics); the ownership
    /// sigils (`__owned` / `__shared` / `consuming` / `borrowing` / `sending` /
    /// `_const`) are erased — they are calling-convention detail the property
    /// never sees. Without this, `__owned Self` reads as the literal type text
    /// `"__owned Self"` and matches no template, so the value-semantic
    /// `union(_ other: __owned Self) -> Self` idiom of `SetAlgebra` / OrderedSet
    /// was silent (B26). Plain `Self` already works via textual `Self == Self`,
    /// so this stripping — not `Self`-resolution — is the actual fix on the
    /// swift-infer side.
    static func strippingParameterSpecifiers(_ raw: String) -> (typeText: String, isInout: Bool) {
        var text = Substring(raw)
        var isInout = false
        let ownership = ["__owned ", "__shared ", "consuming ", "borrowing ", "sending ", "_const "]
        stripping: while true {
            if text.hasPrefix("inout ") {
                isInout = true
                text = text.dropFirst("inout ".count)
                continue
            }
            for specifier in ownership where text.hasPrefix(specifier) {
                text = text.dropFirst(specifier.count)
                continue stripping
            }
            break
        }
        return (String(text), isInout)
    }

    private func scanBody(of node: FunctionDeclSyntax) -> BodySignals {
        guard let body = node.body else {
            return .empty
        }
        let scanner = BodySignalVisitor(funcName: node.name.text)
        scanner.walk(body)
        return BodySignals(
            hasNonDeterministicCall: !scanner.detectedAPIs.isEmpty,
            hasSelfComposition: scanner.foundSelfComposition,
            nonDeterministicAPIsDetected: scanner.detectedAPIs.sorted(),
            reducerOpsReferenced: scanner.reducerOps.sorted(),
            reducerOpsWithIdentitySeed: scanner.reducerOpsWithIdentitySeed.sorted()
        )
    }
}
