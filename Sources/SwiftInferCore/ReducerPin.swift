import Foundation

/// V1.C — parsed `--reducer <module>.<typeName>.<funcName>` pin
/// used by `swift-infer discover-reducers` (to filter the candidate
/// list to one entry) and by downstream M2+ pipelines (to know which
/// reducer to feed into the action-sequence generator / verify
/// harness / interaction-template scoring).
///
/// **Pin syntax (right-to-left).** The string is split on `.`. The
/// last component is always the function name. The previous one (if
/// present) is the enclosing type name. The one before that (if
/// present) is the module name.
///
///   - `"reduce"` → `(moduleName: nil, typeName: nil,
///     functionName: "reduce")`. Matches free functions only.
///   - `"Inbox.body"` → `(nil, "Inbox", "body")`. Matches methods
///     and TCA candidates with `enclosingTypeName == "Inbox"`.
///   - `"MyModule.Inbox.body"` → throws
///     `.moduleResolutionUnsupported`. Module-name resolution
///     requires multi-module plumbing that doesn't exist yet;
///     deferred to M2+.
///
/// **Why not `module/typeName/funcName` or another separator.** PRD
/// §3.6 + §6.5 both use the dotted form, matching the Swift-Argument-
/// Parser convention developers already see in `--reducer Inbox.body`
/// across the wider ecosystem. The dotted form is also unambiguous
/// against Swift's qualified-name vocabulary (no separator collision).
public struct ReducerPin: Sendable, Equatable {

    /// Module name, when present. Currently rejected at parse time
    /// (M1.C: module resolution not yet available). Reserved for
    /// M2+ plumbing.
    public let moduleName: String?

    /// Enclosing type name, when present. Matched verbatim against
    /// `ReducerCandidate.enclosingTypeName`.
    public let typeName: String?

    /// Function name (or synthetic name `"body"` for TCA closure
    /// candidates). Required.
    public let functionName: String

    public init(
        moduleName: String? = nil,
        typeName: String? = nil,
        functionName: String
    ) {
        self.moduleName = moduleName
        self.typeName = typeName
        self.functionName = functionName
    }

    /// V1.C — split the raw `--reducer` value on `.` and route the
    /// components right-to-left. Throws for empty pins and for
    /// module-prefixed pins (M2+ deferral).
    public static func parse(_ raw: String) throws -> ReducerPin {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ReducerPinError.emptyPin }
        let components = trimmed.split(separator: ".", omittingEmptySubsequences: false)
            .map(String.init)
        // Reject empty components — `"Inbox..body"` is malformed.
        if components.contains(where: { $0.isEmpty }) {
            throw ReducerPinError.malformed(raw: raw)
        }
        switch components.count {
        case 1:
            return ReducerPin(functionName: components[0])
        case 2:
            return ReducerPin(typeName: components[0], functionName: components[1])
        case 3:
            // V1.C — module resolution deferred. The shape is parsed
            // far enough to give the user a clear error.
            throw ReducerPinError.moduleResolutionUnsupported(raw: raw)
        default:
            // 4+ components — no canonical interpretation.
            throw ReducerPinError.malformed(raw: raw)
        }
    }

    /// Does this pin match `candidate`? Function name must match
    /// exactly; type name must match if the pin specifies one.
    /// Module-name matching is unreachable at M1.C — `parse` throws
    /// before constructing a pin with a non-nil `moduleName`.
    public func matches(_ candidate: ReducerCandidate) -> Bool {
        guard functionName == candidate.functionName else { return false }
        if let typeName, typeName != candidate.enclosingTypeName {
            return false
        }
        return true
    }
}

/// V1.C — errors thrown by `ReducerPin.parse`. Each carries the raw
/// input so the CLI can echo it back in the error message.
public enum ReducerPinError: Error, CustomStringConvertible, Equatable {
    case emptyPin
    case malformed(raw: String)
    case moduleResolutionUnsupported(raw: String)

    public var description: String {
        switch self {
        case .emptyPin:
            return "--reducer pin is empty; expected `<funcName>` or `<typeName>.<funcName>`"
        case let .malformed(raw):
            return "--reducer pin '\(raw)' is malformed; expected `<funcName>` or `<typeName>.<funcName>`"
        case let .moduleResolutionUnsupported(raw):
            return "--reducer pin '\(raw)' uses a module prefix; module-name resolution "
                + "lands at v2.0 M2+. Drop the module prefix for now."
        }
    }
}
