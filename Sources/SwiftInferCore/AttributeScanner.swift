import SwiftSyntax

/// Scans function-decl attribute lists for the `@Discoverable(group:)` and
/// `@CheckProperty(.preservesInvariant(\..))` attributes that downstream
/// templates and bridge arms consume. Recognize-only per PRD v0.4 §5.7 —
/// SwiftInferProperties does not take a runtime dependency on
/// `ProtoLawMacro`'s definitions; attribute-name matching tolerates
/// fully-qualified `@ProtoLawMacro.Discoverable(...)` by checking the
/// trailing identifier component.
enum AttributeScanner {

    /// `@Discoverable(group: "...")` group string-literal value, or
    /// `nil` when the attribute is absent or carries no `group:`
    /// argument. When the same decl carries multiple `@Discoverable`
    /// attributes, the first one wins (Swift compile-time semantics
    /// would also flag duplicates, so this is a conservative tie-break).
    static func discoverableGroup(in attributes: AttributeListSyntax) -> String? {
        for element in attributes {
            guard let attribute = element.as(AttributeSyntax.self) else { continue }
            let nameText = attribute.attributeName.trimmedDescription
            let lastComponent = nameText.split(separator: ".").last.map(String.init) ?? nameText
            guard lastComponent == "Discoverable" else { continue }
            guard case let .argumentList(arguments) = attribute.arguments else { continue }
            for argument in arguments where argument.label?.text == "group" {
                if let group = stringLiteralValue(of: argument.expression) {
                    return group
                }
            }
        }
        return nil
    }

    /// `@CheckProperty(.preservesInvariant(\.foo))` keypath source text
    /// (e.g. `"\.isValid"`), or `nil` when the attribute is absent or
    /// malformed. M7.2 plan row: scanner-side recognition only, mirroring
    /// `discoverableGroup`'s posture (PRD v0.4 §5.7) — match the
    /// attribute by name (`CheckProperty`) and capture the keypath
    /// opaquely per M7 plan open decision #5(a).
    ///
    /// Multiple `@CheckProperty(.preservesInvariant(...))` attributes on
    /// the same decl: the first well-formed one wins (consistent with
    /// `discoverableGroup`'s tie-break). Other `@CheckProperty` arms
    /// (`.idempotent`, `.roundTrip`) are ignored here; this scan is
    /// invariant-specific.
    static func invariantKeypath(in attributes: AttributeListSyntax) -> String? {
        for element in attributes {
            guard let attribute = element.as(AttributeSyntax.self) else { continue }
            let nameText = attribute.attributeName.trimmedDescription
            let lastComponent = nameText.split(separator: ".").last.map(String.init) ?? nameText
            guard lastComponent == "CheckProperty" else { continue }
            guard case let .argumentList(arguments) = attribute.arguments,
                  let firstArgument = arguments.first else { continue }
            guard let call = firstArgument.expression.as(FunctionCallExprSyntax.self),
                  let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self),
                  memberAccess.declName.baseName.text == "preservesInvariant" else { continue }
            guard let keyPathArgument = call.arguments.first,
                  let keyPath = keyPathArgument.expression.as(KeyPathExprSyntax.self) else {
                continue
            }
            return keyPath.trimmedDescription
        }
        return nil
    }

    /// Pull the literal string value out of a single-segment
    /// `StringLiteralExprSyntax`. Returns `nil` for interpolated or
    /// multi-segment literals — interpolation in attribute arguments
    /// would resolve at expansion time and isn't representable as a
    /// stable group name during scan.
    private static func stringLiteralValue(of expression: ExprSyntax) -> String? {
        guard let literal = expression.as(StringLiteralExprSyntax.self) else { return nil }
        guard literal.segments.count == 1,
              let segment = literal.segments.first?.as(StringSegmentSyntax.self) else {
            return nil
        }
        return segment.content.text
    }
}
