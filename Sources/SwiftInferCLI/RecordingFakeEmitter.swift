import Foundation
import SwiftInferCore

/// PROTOTYPE (Slice B) — synthesizes a *recording* fake for a role's assertable
/// output protocol: a `final class Recording_<P>: <P>` that appends a
/// deterministic `"<method>(<args>)"` string to `callLog` on every call (and
/// returns a default for non-`Void` requirements). Two runs of the role driven
/// with the same input must produce equal `callLog`s — that's the
/// output-determinism check.
///
/// Sibling to the no-op `ViewModelProtocolFaker` (which discards calls); this
/// one captures the call *sequence + arguments*, the capability MVP/VIPER need
/// that MVVM's no-op faking didn't. Reuses `ViewModelDefaultValue` for property
/// / non-`Void`-return defaults, and gates on the same conditions plus
/// `async` / `throws` requirements (not reconstructed from the scan).
public enum RecordingFakeEmitter {

    /// The recording fake's type name for protocol `P` → `Recording_P`.
    public static func typeName(for protocolName: String) -> String {
        "Recording_\(protocolName)"
    }

    /// Emit the recording-fake class, or `nil` when the protocol can't be
    /// recorded (unsupported requirement, a non-defaultable property /
    /// non-`Void` return, or an `async` / `throws` method).
    public static func recordingClass(for proto: ViewModelProtocolScanner.ProtocolDecl) -> String? {
        guard !proto.hasUnsupportedRequirement else { return nil }
        var members: [String] = ["    var callLog: [String] = []"]
        for property in proto.properties {
            guard let value = ViewModelDefaultValue.value(for: property.typeText) else { return nil }
            members.append("    var \(property.name): \(property.typeText) = \(value)")
        }
        for method in proto.methods {
            guard let member = recordingMethod(method) else { return nil }
            members.append(member)
        }
        return "final class \(typeName(for: proto.name)): \(proto.name) {\n"
            + members.joined(separator: "\n") + "\n}"
    }

    /// One recording method. Rebuilds a conforming signature with our own
    /// internal parameter names (`arg0`, `arg1`, …) and a body that logs the
    /// call. `nil` if the method is `async` / `throws` (not reconstructable from
    /// the scan) or has a non-defaultable return type.
    private static func recordingMethod(_ method: ViewModelProtocolScanner.MethodRequirement) -> String? {
        if method.signature.contains(" async") || method.signature.contains("throws") {
            return nil
        }
        var paramDecls: [String] = []
        var recordExprs: [String] = []
        for (index, parameter) in method.parameters.enumerated() {
            let internalName = "arg\(index)"
            let labelPart = parameter.label.map { "\($0) " } ?? "_ "
            paramDecls.append("\(labelPart)\(internalName): \(parameter.type)")
            recordExprs.append("\\(\(internalName))")
        }
        let paramList = paramDecls.joined(separator: ", ")
        let log = "callLog.append(\"\(method.name)(\(recordExprs.joined(separator: ", ")))\")"
        guard let returnType = method.returnType else {
            return "    func \(method.name)(\(paramList)) { \(log) }"
        }
        guard let value = ViewModelDefaultValue.value(for: returnType) else { return nil }
        return "    func \(method.name)(\(paramList)) -> \(returnType) { \(log); return \(value) }"
    }
}
