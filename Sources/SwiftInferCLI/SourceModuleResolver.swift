import Foundation

/// The module a source file belongs to, read from the package manifest before its path.
///
/// **The path heuristic is a convention, not a rule.** `InteractiveTriage.moduleName(fromSourceFile:)`
/// answers `Sources/<Module>/…`, which is right for a conventional package and wrong for a target
/// declared with its own `path:`. Harbeth declares one target, `Harbeth`, at `path: "Sources"`, with
/// its files in `Sources/Basic/`, `Sources/Compute/`, `Sources/MPS/` — so every stub imported
/// `Basic`, a module that does not exist, and **0 of 230** compiled. The run already resolved the
/// right module from the manifest (`GeneratedStubDestination.module(forScanDirectory:)`) and the
/// heuristic outranked it. This is the *target says what to build, sources says what to scan* trap
/// `VerifyTargetInference.manifestModule` exists for, in the accept path.
///
/// The manifest is read once. A file inside a declared (non-test) target's directory takes that
/// target's name, the longest directory first so a nested target wins over one enclosing it. A file
/// no declared target contains — a nested package, an app, a fixture — falls back to the heuristic
/// unchanged, so only a manifest answer can move a result.
struct SourceModuleResolver {

    private let targets: [(module: String, directory: String)]

    init(packageRoot: URL?) {
        guard let packageRoot else {
            targets = []
            return
        }
        let root = packageRoot.resolvingSymlinksInPath().standardizedFileURL
        targets = TargetIsolation.declaredTargetDirectories(packageRoot: packageRoot)
            .filter { !$0.isTest }
            .map { target in
                (InteractiveTriage.moduleIdentifier(from: target.name),
                 root.appendingPathComponent(target.path).standardizedFileURL.path)
            }
            .sorted { $0.directory.count > $1.directory.count }
    }

    func module(forSourceFile path: String) -> String? {
        let file = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        if let owner = targets.first(where: { file.hasPrefix($0.directory + "/") }) {
            return owner.module
        }
        return InteractiveTriage.moduleName(fromSourceFile: path)
    }
}
