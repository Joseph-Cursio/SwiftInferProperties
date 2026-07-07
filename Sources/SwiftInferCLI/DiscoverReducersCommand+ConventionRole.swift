import SwiftInferCore

// Convention-role (VIPER/MVP) render section for `discover-reducers`, in an
// extension so the primary `DiscoverReducers` body stays under the
// type_body_length / file_length caps (cycle-145 precedent).
extension SwiftInferCommand.DiscoverReducers {

    /// PROTOTYPE — renders convention-recognized VIPER/MVP roles: a `*Presenter`
    /// / `*Interactor` class, its State surface + action alphabet, and its
    /// collaborators (flagging the assertable output sink Slice B will record
    /// against). Recognition only — no invariant emitted yet.
    static func renderConventionRoleSummary(_ roles: [StatefulRole]) -> String {
        if roles.isEmpty {
            return "swift-infer discover-reducers: no convention roles (VIPER/MVP) detected.\n"
        }
        let suffix = roles.count == 1 ? "" : "s"
        var lines: [String] = [
            "swift-infer discover-reducers — detected \(roles.count) "
                + "convention role\(suffix) (VIPER/MVP, by naming/conformance):",
            ""
        ]
        for role in roles {
            lines.append(contentsOf: renderConventionRole(role))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func renderConventionRole(_ role: StatefulRole) -> [String] {
        var lines = ["  \(role.location)  \(role.typeName)  [\(role.paradigm.rawValue)]"]

        let stateNames: [String]
        switch role.state {
        case let .storedFields(fields): stateNames = fields.map(\.name)
        case let .namedType(name): stateNames = [name]
        }
        let stateText = stateNames.isEmpty ? "(none)" : stateNames.joined(separator: ", ")
        lines.append("    state (\(stateNames.count)): \(stateText)")

        if role.actions.isEmpty {
            lines.append("    actions: (none detected)")
        } else {
            lines.append("    action alphabet (\(role.actions.count)):")
            for action in role.actions {
                let async = action.isAsync ? " async" : ""
                let throwsText = action.isThrows ? " throws" : ""
                let transitive = action.mutatesStateDirectly ? "" : " (transitive)"
                lines.append("      - \(action.signature)\(async)\(throwsText)\(transitive)")
            }
        }

        if !role.collaborators.isEmpty {
            lines.append("    collaborators (\(role.collaborators.count)):")
            for collaborator in role.collaborators {
                let kind: String
                switch collaborator.role {
                case .output: kind = "output sink [assertable]"
                case .dependency: kind = "dependency"
                }
                lines.append("      - \(collaborator.propertyName): \(collaborator.protocolType)  → \(kind)")
            }
        }
        return lines
    }
}
