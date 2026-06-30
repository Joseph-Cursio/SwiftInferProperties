import SwiftSyntax

/// Per-file context a `RolePolicy` consults during recognition: the file's
/// imports (to gate framework-specific recognition the way `ReducerDiscoverer`
/// gates on `import ComposableArchitecture`) and a source-location helper.
///
/// Not `Sendable`: it holds a `SourceLocationConverter`, which isn't. Policies
/// consult it synchronously during a single-threaded walk, so this is fine.
public struct FileContext {
    public let file: String
    public let imports: Set<String>
    let converter: SourceLocationConverter

    public init(file: String, imports: Set<String>, converter: SourceLocationConverter) {
        self.file = file
        self.imports = imports
        self.converter = converter
    }

    /// `<file>:<line>` for a node's first significant token.
    public func locationString(of node: some SyntaxProtocol) -> String {
        let location = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        return "\(file):\(location.line)"
    }
}

/// What a `RolePolicy.recognize` returns when a declaration is its role. Carries
/// the matched syntax plus the basics the engine and `buildRole` need. Not
/// `Sendable` — it holds a `DeclSyntax`.
public struct RoleMatch {
    public let decl: DeclSyntax
    public let typeName: String
    public let location: String
    public let recognizedBy: RecognitionKind

    public init(
        decl: DeclSyntax,
        typeName: String,
        location: String,
        recognizedBy: RecognitionKind
    ) {
        self.decl = decl
        self.typeName = typeName
        self.location = location
        self.recognizedBy = recognizedBy
    }
}

/// The pluggable seam of `StatefulRoleDiscoverer`. Each architecture supplies
/// one policy: a cheap structural `recognize`, then `buildRole` to extract the
/// state surface / actions / construction / collaborators.
///
/// Phase 1 reimplements the existing `ReducerDiscoverer` / `ViewModelDiscoverer`
/// as `TCAReducerPolicy` / `MVVMPolicy` behind this seam; Phase 2 adds
/// `ReduxPolicy` and the convention-driven VIPER/MVP/MVC policies. Phase 0 only
/// defines the contract (and exercises it with a stub in tests).
///
/// `Sendable` so a fixed policy set can be shared; its methods take/return the
/// non-`Sendable` syntax-bearing types above, which is allowed (they never
/// cross a concurrency boundary).
public protocol RolePolicy: Sendable {

    /// Which architecture this policy recognizes.
    var paradigm: Paradigm { get }

    /// Is `decl` an instance of this role? Returns `nil` if not — a cheap
    /// structural check (imports, inheritance clause, attributes, name).
    func recognize(_ decl: DeclSyntax, in context: FileContext) -> RoleMatch?

    /// Build the full role from a successful match. Runs the (potentially more
    /// expensive) state/action extraction only for declarations that matched.
    func buildRole(from match: RoleMatch, in context: FileContext) -> StatefulRole

    /// The paradigm-specific property families this role supports, layered on
    /// the shared interaction-invariant families.
    var distinctiveProperties: [PropertyKind] { get }
}
