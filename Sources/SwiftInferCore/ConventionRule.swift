/// A data-driven recognition rule for a convention-based state architecture
/// (VIPER / MVP / MVC). These paradigms have no language-level marker like
/// `@Observable` — a presenter is recognized by its *name* (`*Presenter`) and/or
/// the *protocol* it conforms to (`*Presenting`), and it calls out to an
/// **output collaborator** (`view` / `output` / `presenter`) that Slice B will
/// fake as a *recording* sink to check output determinism.
///
/// Phase 2 of `docs/stateful-role-discoverer-design.md` proposes these live in a
/// project's `[roles.*]` config so a house naming convention needs no new code.
/// This ships the *built-in defaults* first (`builtInDefaults`); the config-file
/// plumbing that lets a project override them is a later follow-up. The rule is
/// already data — wiring a TOML decoder onto it is additive.
public struct ConventionRule: Sendable, Equatable {

    /// The architecture a match belongs to.
    public let paradigm: Paradigm

    /// Type-name suffixes that recognize the role (`["Presenter"]`). A class
    /// whose name ends with any of these matches.
    public let nameSuffixes: [String]

    /// Conformance suffixes that *also* recognize the role — a class inheriting
    /// a type whose name ends with any of these matches even if its own name
    /// doesn't (VIPER `LoginInteractor: LoginInteractorInput`).
    public let conformanceSuffixes: [String]

    /// Property names treated as the assertable **output collaborator** — the
    /// protocol the role pushes results to, which Slice B records against for
    /// output-determinism. Every other protocol dependency is a plain no-op
    /// fake.
    public let outputCollaboratorNames: [String]

    public init(
        paradigm: Paradigm,
        nameSuffixes: [String],
        conformanceSuffixes: [String] = [],
        outputCollaboratorNames: [String]
    ) {
        self.paradigm = paradigm
        self.nameSuffixes = nameSuffixes
        self.conformanceSuffixes = conformanceSuffixes
        self.outputCollaboratorNames = outputCollaboratorNames
    }

    /// Does a class named `typeName` conforming to `inheritedTypeNames` match
    /// this rule? Name-suffix OR conformance-suffix — either convention signal
    /// is enough (both are recorded as `.convention` recognition).
    public func matches(typeName: String, inheritedTypeNames: [String]) -> Bool {
        if nameSuffixes.contains(where: { typeName.hasSuffix($0) }) { return true }
        return conformanceSuffixes.contains { suffix in
            inheritedTypeNames.contains { $0.hasSuffix(suffix) }
        }
    }

    /// The shipped defaults: MVP presenters (output → `view`) and VIPER
    /// interactors (output → `presenter` / `output`). Conservative — keyed on
    /// the canonical suffixes; a project with other conventions overrides via
    /// config (follow-up).
    public static let builtInDefaults: [Self] = [
        Self(
            paradigm: .mvp,
            nameSuffixes: ["Presenter"],
            conformanceSuffixes: ["Presenting", "PresenterInput", "PresenterProtocol"],
            outputCollaboratorNames: ["view"]
        ),
        Self(
            paradigm: .viper,
            nameSuffixes: ["Interactor"],
            conformanceSuffixes: ["InteractorInput", "InteractorProtocol"],
            outputCollaboratorNames: ["presenter", "output"]
        )
    ]
}
