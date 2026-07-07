import Foundation
import SwiftParser
import SwiftSyntax

/// PROTOTYPE — recognizes convention-based state roles (VIPER interactors / MVP
/// presenters) and emits each as a `StatefulRole`. These paradigms are
/// structurally view-models-minus-`@Observable`: a reference type with stored
/// state, state-mutating methods (the action alphabet), and injected protocol
/// collaborators. So this reuses the MVVM scanning machinery wholesale —
/// `ViewModelDiscoveryVisitor` (cross-file accumulate), `classifyExclusion`
/// (State vs dependency), `resolveActions` (the two-pass action alphabet) — and
/// differs only in *recognition* (a `ConventionRule` name/conformance match
/// instead of the `@Observable` marker) and in surfacing the **output
/// collaborator** as an assertable recording sink (Slice B's capability).
///
/// Candidate-only (Slice A): produces roles for discovery / surfacing. Verify
/// (recording-output-fake + `outputDeterminism`) is Slice B.
public enum ConventionRoleDiscoverer {

    public static func discover(
        source: String,
        file: String,
        rules: [ConventionRule] = ConventionRule.builtInDefaults
    ) -> [StatefulRole] {
        var table: [String: RawTypeInfo] = [:]
        accumulate(source: source, file: file, into: &table)
        return assemble(table, rules: rules)
    }

    /// Recursively scan every `.swift` file under `directory`, merging per-type
    /// info across files (so a presenter's methods in `Foo+Handlers.swift`
    /// attribute to the class declared in `Foo.swift`) before assembling roles.
    public static func discover(
        directory: URL,
        rules: [ConventionRule] = ConventionRule.builtInDefaults
    ) throws -> [StatefulRole] {
        var table: [String: RawTypeInfo] = [:]
        for fileURL in SwiftSourceFiles.sorted(in: directory) {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            accumulate(source: source, file: fileURL.path, into: &table)
        }
        return assemble(table, rules: rules)
    }

    // MARK: - Accumulate (reuses the MVVM visitor)

    private static func accumulate(
        source: String,
        file: String,
        into table: inout [String: RawTypeInfo]
    ) {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: file, tree: tree)
        let visitor = ViewModelDiscoveryVisitor(file: file, converter: converter)
        visitor.walk(tree)
        for (typeName, partial) in visitor.collected {
            table[typeName, default: RawTypeInfo()].merge(partial)
        }
    }

    // MARK: - Assemble

    static func assemble(_ table: [String: RawTypeInfo], rules: [ConventionRule]) -> [StatefulRole] {
        var roles: [StatefulRole] = []
        for (typeName, info) in table {
            // `@Observable` / `ObservableObject` types are MVVM's — let
            // `ViewModelDiscoverer` own them (no double-count). A convention
            // role must be a class (`classLocation != nil`) matching a rule.
            guard info.observability == nil,
                  let location = info.classLocation,
                  let rule = rules.first(where: {
                      $0.matches(typeName: typeName, inheritedTypeNames: info.inheritedTypeNames)
                  })
            else { continue }

            let (state, collaborators) = partitionFields(info.rawFields, rule: rule)
            let storedNames = Set(state.map(\.name))
            let vmActions = ViewModelDiscoverer.resolveActions(
                methods: info.methods,
                storedNames: storedNames
            )
            let actions = vmActions.map { action in
                RoleAction(
                    name: action.name,
                    parameterTypes: action.parameterTypes,
                    firstParameterLabel: action.firstParameterLabel,
                    isAsync: action.isAsync,
                    isThrows: action.isThrows,
                    mutatesStateDirectly: action.mutatesStateDirectly
                )
            }
            let initParameters = (info.declaredInits.first ?? []).map {
                RoleInitParameter(label: $0.label, typeText: $0.typeText)
            }

            roles.append(
                StatefulRole(
                    location: location,
                    typeName: typeName,
                    paradigm: rule.paradigm,
                    recognizedBy: .convention,
                    state: .storedFields(state.sorted { $0.name < $1.name }),
                    actions: actions,
                    construction: .instance(
                        initParameters: initParameters,
                        fakedCollaborators: collaborators
                    ),
                    collaborators: collaborators,
                    effect: nil
                )
            )
        }
        return roles.sorted { lhs, rhs in
            if lhs.location != rhs.location { return lhs.location < rhs.location }
            return lhs.typeName < rhs.typeName
        }
    }

    /// Split stored fields into genuine mutable State vs collaborators (protocol
    /// dependencies). The field whose name is the rule's output collaborator
    /// becomes an assertable `.output` sink; other dependencies are plain no-op
    /// fakes. `@ObservationIgnored`-style transient flags are dropped (neither).
    private static func partitionFields(
        _ fields: [RawStoredField],
        rule: ConventionRule
    ) -> (state: [RoleStateField], collaborators: [Collaborator]) {
        var state: [RoleStateField] = []
        var collaborators: [Collaborator] = []
        for field in fields {
            switch ViewModelDiscoverer.classifyExclusion(field) {
            case nil:
                state.append(
                    RoleStateField(name: field.name, typeText: field.typeText, isMutable: field.isMutable)
                )

            case .dependency:
                let isOutput = rule.outputCollaboratorNames.contains(field.name)
                collaborators.append(
                    Collaborator(
                        propertyName: field.name,
                        protocolType: field.typeText,
                        role: isOutput ? .output(assertable: true) : .dependency
                    )
                )

            case .observationIgnored:
                break
            }
        }
        return (state, collaborators.sorted { $0.propertyName < $1.propertyName })
    }
}
