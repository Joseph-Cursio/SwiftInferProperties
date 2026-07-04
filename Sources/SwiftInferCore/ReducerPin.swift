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
///   - `"MyModule.Inbox.body"` → `("MyModule", "Inbox", "body")`.
///     Parses and matches exactly like `"Inbox.body"`: every run is
///     already scoped to one module via `--target`, so the module
///     component is a *redundant qualifier* — accepted (a developer
///     pasting a fully-qualified name doesn't hit an error) but not
///     matched against candidates (they carry no module). Real
///     cross-module disambiguation is deferred to multi-module
///     discovery (would tag candidates by module and match on it).
///
/// **Why not `module/typeName/funcName` or another separator.** PRD
/// §3.6 + §6.5 both use the dotted form, matching the Swift-Argument-
/// Parser convention developers already see in `--reducer Inbox.body`
/// across the wider ecosystem. The dotted form is also unambiguous
/// against Swift's qualified-name vocabulary (no separator collision).
public struct ReducerPin: Sendable, Equatable {

    /// Module name, when present. Matched against `ReducerCandidate.moduleName`
    /// when **both** are set — a multi-module discovery run (`--target` given
    /// more than once) tags each candidate by its source module. In a
    /// single-target run candidates are untagged, so the module component stays
    /// a redundant qualifier (accepted, not matched).
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
    public static func parse(_ raw: String) throws -> Self {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ReducerPinError.emptyPin }
        let components = trimmed.split(separator: ".", omittingEmptySubsequences: false)
            .map(String.init)
        // Reject empty components — `"Inbox..body"` is malformed.
        if components.contains(where: \.isEmpty) {
            throw ReducerPinError.malformed(raw: raw)
        }
        switch components.count {
        case 1:
            return Self(functionName: components[0])

        case 2:
            return Self(typeName: components[0], functionName: components[1])

        case 3:
            // Module prefix accepted as a redundant qualifier — the run is
            // already scoped to one `--target` module. Retained on the pin
            // but ignored in `matches` (candidates carry no module).
            return Self(
                moduleName: components[0],
                typeName: components[1],
                functionName: components[2]
            )

        default:
            // 4+ components — no canonical interpretation.
            throw ReducerPinError.malformed(raw: raw)
        }
    }

    /// Does this pin match `candidate`? Function name must match exactly; type
    /// name must match if the pin specifies one. A `moduleName` is matched only
    /// when **both** the pin and the candidate carry one: a single-target run
    /// leaves candidates untagged (`moduleName == nil`), so a module-qualified
    /// pin still matches (the module component stays a redundant qualifier); a
    /// multi-module run tags candidates by their source module, so the module
    /// then disambiguates same-named reducers across modules.
    public func matches(_ candidate: ReducerCandidate) -> Bool {
        guard functionName == candidate.functionName else { return false }
        if let typeName, typeName != candidate.enclosingTypeName {
            return false
        }
        if let moduleName, let candidateModule = candidate.moduleName,
           moduleName != candidateModule {
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

    public var description: String {
        switch self {
        case .emptyPin:
            return "--reducer pin is empty; expected `<funcName>`, `<typeName>.<funcName>`, "
                + "or `<module>.<typeName>.<funcName>`"

        case let .malformed(raw):
            return "--reducer pin '\(raw)' is malformed; expected `<funcName>`, "
                + "`<typeName>.<funcName>`, or `<module>.<typeName>.<funcName>`"
        }
    }
}
