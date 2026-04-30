import SwiftInferCLI

/// Thin entry point for the `swift-infer` executable. All command routing
/// lives in `SwiftInferCLI`'s `SwiftInferCommand` so the surface stays
/// reachable from tests without launching a subprocess.
@main
struct SwiftInferEntry {
    static func main() async {
        await SwiftInferCommand.main()
    }
}
