import Foundation
import SwiftInferCore

/// PROTOTYPE — synthesizes a no-op `struct Fake_<P>: <P> { … }` conformer
/// for a scanned protocol, stubbing every requirement with a default:
///   - `Void` method → `{ }`
///   - non-`Void` method → `{ return <default> }`
///   - property → a stored `var name: Type = <default>` (satisfies `get`
///     and `get set`)
/// Returns `nil` (not fakeable) when a requirement's type isn't defaultable
/// (a custom/concrete type with no synthesizable value) or the protocol has
/// an unsupported requirement (`init` / `subscript` / `associatedtype` /
/// `static`).
public enum ViewModelProtocolFaker {

    public static func fakeStruct(for proto: ViewModelProtocolScanner.ProtocolDecl) -> String? {
        guard !proto.hasUnsupportedRequirement else { return nil }
        var members: [String] = []
        for property in proto.properties {
            guard let value = ViewModelDefaultValue.value(for: property.typeText) else { return nil }
            members.append("    var \(property.name): \(property.typeText) = \(value)")
        }
        for method in proto.methods {
            guard let returnType = method.returnType else {
                members.append("    \(method.signature) { }")
                continue
            }
            guard let value = ViewModelDefaultValue.value(for: returnType) else { return nil }
            members.append("    \(method.signature) { return \(value) }")
        }
        guard !members.isEmpty else {
            return "struct Fake_\(proto.name): \(proto.name) {}"
        }
        return "struct Fake_\(proto.name): \(proto.name) {\n\(members.joined(separator: "\n"))\n}"
    }
}

/// PROTOTYPE — a synthesizable default literal for a (defaultable) type, or
/// `nil`. Covers Optionals (`nil`), collections (`[]` / `[:]`), and the
/// curated scalars. A custom/concrete type returns `nil` (gates faking +
/// scalar dependency satisfaction).
public enum ViewModelDefaultValue {

    public static func value(for type: String) -> String? {
        let trimmed = type.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("?") || trimmed.hasSuffix("!") {
            return "nil"
        }
        if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
            return trimmed.contains(":") ? "[:]" : "[]"
        }
        if trimmed.hasPrefix("Set<") || trimmed.hasPrefix("Array<") {
            return "[]"
        }
        if trimmed.hasPrefix("Dictionary<") {
            return "[:]"
        }
        switch trimmed {
        case "Int", "Int8", "Int16", "Int32", "Int64",
             "UInt", "UInt8", "UInt16", "UInt32", "UInt64":
            return "0"

        case "Double", "Float", "CGFloat":
            return "0"

        case "Bool":
            return "false"

        case "String":
            return "\"\""

        default:
            return nil
        }
    }
}
