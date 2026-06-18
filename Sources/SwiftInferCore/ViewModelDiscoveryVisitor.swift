import SwiftSyntax

/// PROTOTYPE — single-pass walker collecting per-type view-model info for
/// one source file. Tracks an enclosing-type stack so members in
/// `class` / `extension` blocks attribute to the right type name. The
/// `@Observable` / `ObservableObject` signal + the type's declaration
/// location are recorded only from the `ClassDeclSyntax` (extensions
/// can't add stored state or re-declare conformance for this purpose).
final class ViewModelDiscoveryVisitor: SyntaxVisitor {

    private(set) var collected: [String: RawTypeInfo] = [:]
    private let file: String
    private let converter: SourceLocationConverter
    private var typeStack: [String] = []

    init(file: String, converter: SourceLocationConverter) {
        self.file = file
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Type-stack maintenance

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        typeStack.append(name)
        if let observability = Self.observability(
            attributes: node.attributes,
            inheritanceClause: node.inheritanceClause
        ) {
            let line = converter.location(
                for: node.name.positionAfterSkippingLeadingTrivia
            ).line
            collected[name, default: RawTypeInfo()].observability = observability
            collected[name, default: RawTypeInfo()].declLocation = "\(file):\(line)"
        }
        return .visitChildren
    }
    override func visitPost(_: ClassDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.extendedType.trimmedDescription)
        return .visitChildren
    }
    override func visitPost(_: ExtensionDeclSyntax) { typeStack.removeLast() }

    // Push struct/enum/actor too, so their members aren't mis-attributed
    // to an enclosing view-model type. They never set `observability`.
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text); return .visitChildren
    }
    override func visitPost(_: StructDeclSyntax) { typeStack.removeLast() }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text); return .visitChildren
    }
    override func visitPost(_: EnumDeclSyntax) { typeStack.removeLast() }
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text); return .visitChildren
    }
    override func visitPost(_: ActorDeclSyntax) { typeStack.removeLast() }

    // MARK: - Stored properties (State)

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let typeName = typeStack.last else { return .skipChildren }
        let modifiers = node.modifiers.map(\.name.text)
        if modifiers.contains("static") || modifiers.contains("class") {
            return .skipChildren
        }
        let isMutable = node.bindingSpecifier.text == "var"
        let isObservationIgnored = node.attributes.contains { attribute in
            attribute.as(AttributeSyntax.self)?
                .attributeName.trimmedDescription == "ObservationIgnored"
        }
        for binding in node.bindings {
            guard Self.isStored(binding),
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                continue
            }
            let typeText = binding.typeAnnotation?.type.trimmedDescription ?? "?"
            collected[typeName, default: RawTypeInfo()].rawFields.append(
                RawStoredField(
                    name: pattern.identifier.text,
                    typeText: typeText,
                    isMutable: isMutable,
                    isObservationIgnored: isObservationIgnored
                )
            )
        }
        return .skipChildren
    }

    // MARK: - Methods (Action alphabet candidates)

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let typeName = typeStack.last else { return .skipChildren }
        let modifiers = node.modifiers.map(\.name.text)
        if modifiers.contains("private") || modifiers.contains("fileprivate")
            || modifiers.contains("static") || modifiers.contains("class") {
            return .skipChildren
        }
        // Need a body to analyse mutation; protocol requirements / stubs skip.
        guard let body = node.body else { return .skipChildren }

        let effects = node.signature.effectSpecifiers
        let parameterTypes = node.signature.parameterClause.parameters
            .map(\.type.trimmedDescription)
        let method = RawMethod(
            name: node.name.text,
            parameterTypes: parameterTypes,
            isAsync: effects?.asyncSpecifier != nil,
            isThrows: effects?.throwsClause != nil,
            signals: ViewModelMethodBodyWalker.signals(for: body)
        )
        collected[typeName, default: RawTypeInfo()].methods.append(method)
        return .skipChildren
    }

    // MARK: - Detection helpers

    /// `@Observable` macro attribute, or `: ObservableObject` conformance.
    static func observability(
        attributes: AttributeListSyntax,
        inheritanceClause: InheritanceClauseSyntax?
    ) -> ViewModelObservability? {
        for attribute in attributes {
            if let attr = attribute.as(AttributeSyntax.self),
               attr.attributeName.trimmedDescription == "Observable" {
                return .observableMacro
            }
        }
        if let inherited = inheritanceClause?.inheritedTypes {
            for type in inherited where type.type.trimmedDescription == "ObservableObject" {
                return .observableObject
            }
        }
        return nil
    }

    /// A binding is stored if it has no accessor block, or only
    /// `willSet`/`didSet` observers (a computed `get` makes it derived).
    static func isStored(_ binding: PatternBindingSyntax) -> Bool {
        guard let accessorBlock = binding.accessorBlock else { return true }
        switch accessorBlock.accessors {
        case .getter:
            return false  // `var x: T { … }` — computed

        case let .accessors(list):
            return list.allSatisfy { accessor in
                let kind = accessor.accessorSpecifier.text
                return kind == "willSet" || kind == "didSet"
            }
        }
    }
}
