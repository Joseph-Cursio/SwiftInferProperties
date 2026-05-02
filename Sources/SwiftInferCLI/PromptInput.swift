import Foundation

/// Test seam over the single `readLine()` call `InteractiveTriage`
/// (M6.4) makes per prompt. Production code uses `StdinPromptInput`;
/// tests can supply a scripted `RecordingPromptInput`-style stub to
/// drive the prompt loop without attaching a real terminal.
///
/// `Sendable` so the protocol composes with `Discover.run`'s
/// closure-passed dependencies under Swift 6 strict concurrency.
public protocol PromptInput: Sendable {
    /// Read one line of input. Returns `nil` on EOF (e.g. piped
    /// input ran out, or the user pressed Ctrl-D). The terminating
    /// newline is stripped — same shape as `Swift.readLine()`.
    func readLine() -> String?
}

/// Production `PromptInput` — direct passthrough to `Swift.readLine()`.
/// Quoted spelling (`Swift.readLine()`) avoids the recursive
/// shadowing that would happen if the method were just `readLine()`.
public struct StdinPromptInput: PromptInput {
    public init() {}
    public func readLine() -> String? {
        Swift.readLine()
    }
}
