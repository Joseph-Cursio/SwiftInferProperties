import Foundation
import SwiftInferCore

/// Where the scan sees `==` arrive without an inheritance clause saying so.
///
/// *No clause in the scan reaches `Equatable`* is not *no `==`*. Two sources the scan does see
/// supply one with no clause (both compile, `swiftc`, Swift 6.4), and the gate withdrew stubs over
/// them that compiled:
///
/// - a hand-written `static func ==` and no `Equatable` — operator lookup finds the member;
/// - an attached macro — SwiftData's `@Model` conforms its class to `PersistentModel`, which
///   refines `Hashable`, and nothing in the source text says so.
extension UnequatableResultGate {

    /// Attributes a type declaration can carry that add no conformance: the compiler's own, and the
    /// macros known to add none. Any other attribute may be a macro, and a macro may add `Equatable`.
    static let attributesAddingNoConformance: Set<String> = [
        "available", "objc", "objcMembers", "nonobjc", "frozen", "usableFromInline", "inlinable",
        "dynamicMemberLookup", "dynamicCallable", "propertyWrapper", "resultBuilder", "globalActor",
        "MainActor", "preconcurrency", "main", "requires_stored_property_inits", "unchecked",
        "_spi", "_fixed_layout", "_documentation", "_nonSendable", "_originallyDefinedIn", "_marker",
        "_typeEraser", "IBDesignable", "NSApplicationMain", "UIApplicationMain", "Observable", "Suite"
    ]

    /// Every name the scan saw get `==` without an inheritance clause, for `declineReason`'s
    /// `equalityOutsideInheritance`.
    ///
    /// - A hand-written `==`: its owner under both spellings, for a member of the type or of an
    ///   extension of it (an `==` in a protocol extension names the protocol, which a conformer's
    ///   chain then reaches); a free `==` names each parameter's type.
    /// - A declaration carrying an attribute not in `attributesAddingNoConformance`, under its bare
    ///   and its qualified name.
    ///
    /// Generic arguments are stripped, so `Box<Int>`'s `==` lets `Box<String>` through too — the
    /// direction that writes the stub.
    static func equalityOutsideInheritance(
        typeDecls: [TypeDecl],
        summaries: [FunctionSummary]
    ) -> Set<String> {
        var names: [String] = []
        for summary in summaries where summary.name == "==" {
            if let owner = summary.containingTypeName {
                names += [owner, summary.qualifiedContainingTypeName ?? owner]
            } else {
                names += summary.parameters.map(\.typeText)
            }
        }
        for decl in typeDecls where decl.attributeNames.contains(where: mayAddConformance) {
            names += [decl.name, decl.qualifiedName]
        }
        return Set(names.map {
            ProtocolCoverageMap.strippingGenericParameters($0.trimmingCharacters(in: .whitespaces))
        })
    }

    /// Whether an attribute, written without `@`, may be a macro that adds a conformance.
    static func mayAddConformance(_ attribute: String) -> Bool {
        let name = attribute.split(separator: ".").last.map(String.init) ?? attribute
        return attributesAddingNoConformance.contains(name) == false
    }
}
