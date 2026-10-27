// The toy's own test target exists so `swift-infer discover` has a target to write its stubs into;
// the funnel's manifest rewrite drops it, as it drops every subject's test targets.
//
// It also holds the one construction of `Registry` the accept path can harvest. Without it the
// actor has no derivable generator, its stub draws `Registry.gen()` and never compiles; with it
// the stub holds a constructed receiver, `await Registry().holds(value)` (measured at `fef2971d`).
import Testing
@testable import PredicateReachToy

@Test func placeholder() {
    #expect(Rules.isEven(2))
}

@Test func registryHolds() async {
    let registry = Registry()
    #expect(await registry.holds(3))
}
