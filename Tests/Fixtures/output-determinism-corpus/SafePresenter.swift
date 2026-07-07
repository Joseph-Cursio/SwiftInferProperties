// Output-determinism corpus — the deterministic case (→ bothPass).
//
// `SafePresenter`'s output is a pure function of its own state (a per-instance
// counter reset on each fresh construction), so two runs driven with the same
// action produce the identical recorded output-call log.

public protocol GreetingViewProtocol {
    func display(_ text: String)
}

public final class SafePresenter {
    private var count: Int = 0
    private let view: GreetingViewProtocol

    public init(view: GreetingViewProtocol) {
        self.view = view
    }

    public func greet() {
        count += 1
        view.display("Hello #\(count)")
    }
}
