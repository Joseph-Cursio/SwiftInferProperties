import PropertyLawCore

extension TypeAliasMap {

    /// `shapes` with every type an initializer parameter or stored member names through an alias of
    /// its OWN type rewritten to what the alias finally means.
    ///
    /// **An alias means something only in the scope that declares it.** BigInt declares four `Word`s —
    /// `BigUInt.Word = UInt`, `BigInt.Word = BigUInt.Word`, and two generic element aliases — so the
    /// bare name is ambiguous and `merged` rightly drops it. But `BigUInt(words: [Word])` is written
    /// inside `BigUInt`, where `Word` is `BigUInt.Word`, which is `UInt`. The resolver looks names up
    /// bare and has no scope, so the scope is applied here: `[Word]` on `BigUInt` becomes `[UInt]`.
    public static func resolvingNestedAliases(in shapes: [TypeShape], aliases: [String: String]) -> [TypeShape] {
        guard !aliases.isEmpty else { return shapes }
        return shapes.map { shape in
            let rewrite = { (type: String) in
                resolvingNestedAliases(in: type, declaredOn: shape.name, aliases: aliases)
            }
            return TypeShape(
                name: shape.name,
                kind: shape.kind,
                inheritedTypes: shape.inheritedTypes,
                hasUserGen: shape.hasUserGen,
                storedMembers: shape.storedMembers.map {
                    StoredMember(name: $0.name, typeName: rewrite($0.typeName), accessLevel: $0.accessLevel)
                },
                hasUserInit: shape.hasUserInit,
                initializers: shape.initializers.map { initializer in
                    InitializerSignature(
                        parameters: initializer.parameters.map {
                            InitializerParameter(label: $0.label, typeName: rewrite($0.typeName))
                        },
                        isFailable: initializer.isFailable,
                        isThrowing: initializer.isThrowing,
                        assertsPrecondition: initializer.assertsPrecondition,
                        delegatesToSelf: initializer.delegatesToSelf,
                        accessLevel: initializer.accessLevel
                    )
                },
                enumCases: shape.enumCases,
                accessLevel: shape.accessLevel,
                hasPrimaryDeclaration: shape.hasPrimaryDeclaration
            )
        }
    }

    /// `type` with each bare identifier that names an alias declared on `owner` replaced by the
    /// alias's final meaning. A member after a dot (`Foo.Word`) is never touched.
    public static func resolvingNestedAliases(
        in type: String, declaredOn owner: String, aliases: [String: String]
    ) -> String {
        var result = ""
        var token = ""
        var previous: Character = " "
        func flush() {
            if !token.isEmpty, previous != ".", aliases["\(owner).\(token)"] != nil {
                result += finalMeaning(of: "\(owner).\(token)", aliases: aliases)
            } else {
                result += token
            }
            token = ""
        }
        for character in type {
            if character.isLetter || character.isNumber || character == "_" {
                if token.isEmpty { previous = result.last ?? " " }
                token.append(character)
            } else {
                flush()
                result.append(character)
            }
        }
        flush()
        return result
    }

    /// Follows `name` through qualified aliases to what it finally means — `BigInt.Word` →
    /// `BigUInt.Word` → `UInt` — stopping after a few steps so a cycle cannot loop.
    static func finalMeaning(of name: String, aliases: [String: String]) -> String {
        var current = aliases[name] ?? name
        for _ in 0..<8 {
            guard let next = aliases[current], next != current else { break }
            current = next
        }
        return current
    }
}
