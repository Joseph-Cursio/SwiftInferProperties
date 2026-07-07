// Output-determinism corpus — the nondeterministic case (→ defaultFails).
//
// `LeakyPresenter`'s output embeds a fresh `UUID()` per call, so two runs driven
// with the same action produce *different* recorded output-call logs — the
// output-determinism check catches it (the recording fake distinguishes the two
// runs; a no-op fake never could).

import Foundation

public protocol StatusViewProtocol {
    func render(_ id: String)
}

public final class LeakyPresenter {
    private var ticks: Int = 0
    private let view: StatusViewProtocol

    public init(view: StatusViewProtocol) {
        self.view = view
    }

    public func refresh() {
        ticks += 1
        view.render(UUID().uuidString)
    }
}
