import ProtoLawCore
import SwiftSyntax

extension FunctionScannerVisitor {

    /// Emit one `IdentityCandidate` per binding inside a static `let` / `var`
    /// whose name is in the curated identity-shaped list AND that has an
    /// explicit type annotation. M2.5 conservative scope skips
    /// type-inferred decls — pairing requires textual type comparison
    /// against `(T, T) -> T` op signatures, and inferring `T` from an
    /// initializer expression isn't tractable without semantic resolution.
    ///
    /// In multi-binding decls (`static let zero, empty: IntSet = .init()`),
    /// SwiftSyntax attaches the type annotation only to the last binding;
    /// earlier bindings inherit it. The loop therefore looks forward to
    /// the next-annotated binding for any unannotated entry.
    func captureIdentityCandidates(from node: VariableDeclSyntax) {
        let modifiers = node.modifiers.map { $0.name.text }
        guard modifiers.contains("static") || modifiers.contains("class") else {
            return
        }
        let bindings = Array(node.bindings)
        let position = node.bindingSpecifier.positionAfterSkippingLeadingTrivia
        let sourceLocation = converter.location(for: position)
        let location = SourceLocation(
            file: file,
            line: sourceLocation.line,
            column: sourceLocation.column
        )
        for (index, binding) in bindings.enumerated() {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let typeText = inheritedTypeText(at: index, in: bindings) else {
                continue
            }
            let name = unescaped(pattern.identifier.text)
            guard IdentityNames.curated.contains(name) else {
                continue
            }
            identities.append(
                IdentityCandidate(
                    name: name,
                    typeText: typeText,
                    containingTypeName: typeStack.last,
                    location: location
                )
            )
        }
    }

    private func inheritedTypeText(
        at index: Int,
        in bindings: [PatternBindingSyntax]
    ) -> String? {
        for forwardIndex in index..<bindings.count {
            if let annotation = bindings[forwardIndex].typeAnnotation {
                return annotation.type.trimmedDescription
            }
        }
        return nil
    }

    private func unescaped(_ identifier: String) -> String {
        guard identifier.count >= 2,
              identifier.hasPrefix("`"),
              identifier.hasSuffix("`") else {
            return identifier
        }
        return String(identifier.dropFirst().dropLast())
    }
}
