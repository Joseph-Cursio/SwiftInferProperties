import PropertyLawCore
import SwiftEffectInference
import SwiftSyntax

extension FunctionScannerVisitor {

    /// A single non-`inout` parameter whose type the idempotence template can
    /// propose a law for, so the scan does not classify bodies no template will
    /// ask about.
    ///
    /// **The shape test is `IdempotenceCandidateShape`, not a local copy.** This
    /// gate used to require exact `parameter == return` while the template also
    /// accepts the narrowing `T? -> T`, so `idempotenceReturnShape` was `nil` for
    /// every optional-narrowing candidate and `returnShapeVeto` could not tell
    /// *never computed* from *computed and not extending*. See that type for the
    /// witness.
    static func isUnaryEndomorphism(_ node: FunctionDeclSyntax) -> Bool {
        let parameters = node.signature.parameterClause.parameters
        guard parameters.count == 1, let parameter = parameters.first else { return false }
        guard parameter.type.as(AttributedTypeSyntax.self)?.specifiers.isEmpty ?? true else { return false }
        guard let returnType = node.signature.returnClause?.type else { return false }
        return IdempotenceCandidateShape.admitsIdempotenceLaw(
            parameterType: parameter.type.trimmedDescription,
            returnType: returnType.trimmedDescription
        )
    }

    /// Build a `FunctionSummary` from a `FunctionDeclSyntax`. Combines
    /// signature info (parameters / return / effects / modifiers), the
    /// `BodySignalVisitor` walk over the body, and the M5.3 + M7.2.a
    /// attribute scans for `@Discoverable(group:)` and
    /// `@CheckProperty(.preservesInvariant(\..))`.
    /// Source position of the `func` keyword, converted to this scanner's file coordinates.
    /// Extracted from `makeSummary(from:)` when adding the body fingerprint took that
    /// function past SwiftLint's 50-line body cap — the conversion is self-contained and
    /// reads better named than inline.
    private func funcKeywordLocation(of node: FunctionDeclSyntax) -> SourceLocation {
        let position = node.funcKeyword.positionAfterSkippingLeadingTrivia
        let converted = converter.location(for: position)
        return SourceLocation(file: file, line: converted.line, column: converted.column)
    }

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

        let location = funcKeywordLocation(of: node)

        let containingTypeName = typeStack.last
        // The whole stack, not just its last frame — see
        // `FunctionSummary.qualifiedContainingTypeName` for why both are kept.
        let qualifiedContainingTypeName = typeStack.isEmpty
            ? nil
            : typeStack.joined(separator: ".")
        let bodySignals = scanBody(of: node)
        // Free-shape callee names, for `PackagePurityJoin`. A second walk of the
        // body rather than a signal folded into `scanBody`: the join is a
        // package-wide post-pass with no business inside the per-declaration
        // signal scan, and keeping them apart means a change to either cannot
        // silently move the other.
        let calleeCollector = CalleeNameCollector(viewMode: .sourceAccurate)
        if let body = node.body { calleeCollector.walk(body) }
        let discoverableGroup = AttributeScanner.discoverableGroup(in: node.attributes)
        let invariantKeypath = AttributeScanner.invariantKeypath(in: node.attributes)
        // Sound purity verdict — computed here, the one place the live
        // `FunctionDeclSyntax` is available, and carried on the summary for the
        // `@lint.effect pure` advisory channel.
        // One call, both answers — `isInferredPure` is this verdict's two-state
        // collapse, so computing them separately would walk the body twice and
        // could drift.
        let purityVerdict = SoundPurity.verdict(for: node)
        let isInferredPure = purityVerdict == .pure
        // Clock-determinism claim — same scan-time posture as the purity
        // verdict above; consumed by the async-veto relaxation (workplan
        // Phase 4). First EffectAnnotationParser use in this repo.
        let isClockDeterministic = EffectAnnotationParser.isClockDeterministic(declaration: node)
        let declaresUnknownEffect = EffectAnnotationParser.declaresUnknownEffect(declaration: node)
        // The author's own retry-safety claim, in either spelling. Same
        // scan-time posture and the same parser as the determinism claim
        // above — but a DIFFERENT axis: `@lint.determinism` says the result
        // does not vary with time, `@lint.effect` says what re-running costs.
        // Until this line the parser was called for determinism alone, so
        // `@Idempotent` / `@NonIdempotent` / `@ExternallyIdempotent` were
        // parsed by a linked dependency and read by nothing.
        let declaredEffect = EffectAnnotationParser.parseEffect(declaration: node)
        // The leading doc comment — carried on the summary as a candidate
        // reference definition for the docstring advisory. Unclassified here.
        let docComment = DocCommentExtractor.docComment(from: node.leadingTrivia)
        // Fingerprint of the body as it is RIGHT NOW, so verify evidence can later be
        // checked against the code it was measured on. Computed here because this is the
        // one place the live body syntax exists. `nil` for a bodyless declaration (a
        // protocol requirement), which reads downstream as "cannot validate" — see
        // `SubjectFingerprint` for why that withholds evidence rather than trusting it.
        let bodyFingerprint = node.body.map { SubjectFingerprint.of(bodyText: $0.description) }

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
            qualifiedContainingTypeName: qualifiedContainingTypeName,
            discoverableGroup: discoverableGroup,
            invariantKeypath: invariantKeypath,
            isInferredPure: isInferredPure,
            isClockDeterministic: isClockDeterministic,
            declaresUnknownEffect: declaresUnknownEffect,
            docComment: docComment,
            declaredEffect: declaredEffect,
            purityVerdict: purityVerdict,
            bodyFingerprint: bodyFingerprint,
            calledFreeFunctionNames: calleeCollector.names
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
        // Same posture as the function path above: the verdict is computed here,
        // the one place the live accessor syntax exists, and `isInferredPure` is
        // DERIVED from it rather than asserted alongside it. Until 2026-08-17
        // this passed `isInferredPure: true` with no oracle consulted and no
        // verdict at all — so every computed property claimed purity while
        // taking the `.refuted` default, and the `@lint.effect pure` advisory
        // (which filters on exactly this Bool) advised all of them unchecked.
        let purityVerdict = SoundPurity.verdict(forGetter: accessorBlock)
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
            isInferredPure: purityVerdict == .pure,
            isComputedProperty: true,
            docComment: DocCommentExtractor.docComment(from: node.leadingTrivia),
            // The accessor block is this subject's body — a computed property reached by a
            // law is verified by executing its getter, so it must be fingerprinted like any
            // other body or its evidence could outlive a rewritten getter.
            purityVerdict: purityVerdict,
            bodyFingerprint: SubjectFingerprint.of(bodyText: accessorBlock.description)
        )
    }

    /// A read-only computed accessor: the implicit-getter form `var x: T { … }`,
    /// or an explicit block containing `get` and no `set` — and no `async` /
    /// `throws` getter (a getter that can fail or suspend isn't the pure
    /// `self -> T` map the templates assume).
    /// Accessor kinds that leave a property read-only. Everything else — `set`,
    /// `_modify`, `unsafeMutableAddress`, `willSet`, `didSet`, `init` — makes it writable.
    private static let readOnlyAccessors: Set<String> = ["get", "_read", "unsafeAddress"]

    private static func isReadOnlyGetter(_ block: AccessorBlockSyntax) -> Bool {
        switch block.accessors {
        case .getter:
            return true

        case let .accessors(list):
            let specifiers = Set(list.map(\.accessorSpecifier.text))
            // **An ALLOWLIST, not a `!contains("set")` check.** Swift has more mutating
            // accessors than `set`: `_modify` is a coroutine that yields an inout
            // projection, `unsafeMutableAddress` hands back a writable pointer, and
            // `willSet`/`didSet` only appear on stored properties but cost nothing to
            // exclude. Naming the read-only ones means an accessor kind this does not
            // know about makes the property NOT read-only, which is the conservative
            // direction; naming the mutating ones would admit each new kind by default.
            //
            // Open item 50: the previous `!contains("set")` admitted **8 mutable
            // properties** in OrderedCollections alone — `unordered`, `elements`,
            // `keys`, `values`, `header`, `__unstable` — every one of them writable
            // through `_modify`, and each carrying a law that assumes a pure `self -> T`
            // map. `set.unordered.insert(x)` writes through exactly that accessor.
            guard specifiers.contains("get"), specifiers.isSubset(of: Self.readOnlyAccessors) else {
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
            isInout: isInout,
            hasDefault: syntax.defaultValue != nil
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
        // Trim up front and after every strip: a reformatter can put any run of whitespace (or a
        // newline) between a specifier and the type, and the bare type text must not depend on it.
        // Matching `keyword + one literal space` and dropping a fixed count missed that — inflated
        // trivia leaked a leading space into `typeText`, which the trivia-insensitivity experiment
        // catches now that `private` helpers (the only ones taking `inout` dictionaries) surface.
        var text = Substring(raw).drop(while: \.isWhitespace)
        var isInout = false
        let ownership = ["__owned", "__shared", "consuming", "borrowing", "sending", "_const"]
        stripping: while true {
            if let rest = Self.afterSpecifier("inout", in: text) {
                isInout = true
                text = rest.drop(while: \.isWhitespace)
                continue
            }
            for specifier in ownership {
                if let rest = Self.afterSpecifier(specifier, in: text) {
                    text = rest.drop(while: \.isWhitespace)
                    continue stripping
                }
            }
            break
        }
        return (String(text), isInout)
    }

    /// `text` past `keyword` when it leads as a *specifier* — the keyword followed by whitespace, so
    /// a type spelled `borrowingBox` is not mis-stripped. `nil` when `keyword` does not lead.
    private static func afterSpecifier(_ keyword: String, in text: Substring) -> Substring? {
        guard text.hasPrefix(keyword) else { return nil }
        let rest = text.dropFirst(keyword.count)
        guard let next = rest.first, next.isWhitespace else { return nil }
        return rest
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
            reducerOpsWithIdentitySeed: scanner.reducerOpsWithIdentitySeed.sorted(),
            // Only for `==`. Classifying every body would pay a walk per function
            // for a signal exactly one template family reads.
            equalityBodyShape: node.name.text == "=="
                ? EqualityBodyClassifier.classify(
                    body: body,
                    operands: node.signature.parameterClause.parameters.map {
                        ($0.secondName ?? $0.firstName).text
                    }
                )
                : nil,
            // Only for a `T -> T` shape — the one the idempotence template can
            // even propose for. Same bargain as `equalityBodyShape` above: pay
            // the read where a template will use it, nowhere else.
            idempotenceReturnShape: Self.isUnaryEndomorphism(node)
                ? IdempotenceReturnShapeClassifier.classify(body: body)
                : nil,
            // Only for `throws`/`async` functions — the effectful handler shape a
            // replay-idempotency gate lives in. Keeps the statement walk off the
            // pure-sync majority (and the discover-time budget), same bargain.
            dedupGateShape: Self.couldCarryDedupGate(node)
                ? DedupGateClassifier.classify(body: body)
                : nil,
            // M6: the key-from-entity builder marker. Not behind the throws/async
            // gate — the builder is typically a pure sync function.
            buildsIdempotencyKey: scanner.buildsIdempotencyKey,
            callsIdempotentWrite: scanner.callsIdempotentWrite
        )
    }

    /// The `throws`/`async` gate for `dedupGateShape`: a replay-idempotency dedup
    /// gate guards a side effect, so it lives in an effectful handler. Skipping
    /// pure-sync functions keeps the extra statement walk off most of the corpus.
    static func couldCarryDedupGate(_ node: FunctionDeclSyntax) -> Bool {
        let effects = node.signature.effectSpecifiers
        return effects?.throwsClause != nil || effects?.asyncSpecifier != nil
    }
}
