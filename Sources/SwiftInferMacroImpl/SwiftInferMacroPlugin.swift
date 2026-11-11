import SwiftCompilerPlugin
import SwiftSyntaxMacros

/// Compiler-plugin entry point — registers `CheckPropertyMacro` so
/// the Swift compiler picks it up at macro-expansion time. The plugin
/// runs as a separate process invoked by the compiler; everything in
/// `SwiftInferMacroImpl` compiles into that subprocess only and never
/// links into the user's binary or test target.
@main
struct SwiftInferMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        CheckPropertyMacro.self
    ]
}
