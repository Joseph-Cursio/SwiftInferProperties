@testable import SwiftInferTestLifter
import Testing

@Suite("TestStoreTraceExtractor — TCA TestStore trace mining (Slice 1)")
struct TestStoreTraceExtractorTests {

    /// Parse `source`, mine traces from the first test method.
    private func mineFirst(_ source: String) -> [MinedActionTrace] {
        let summaries = TestSuiteParser.scan(source: source, file: "T.swift")
        guard let first = summaries.first else {
            return []
        }
        return TestStoreTraceExtractor.extract(from: first)
    }

    @Test("Body with no TestStore yields no traces")
    func noTestStore() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testNothing() {
                let x = 1
                XCTAssertEqual(x, 1)
            }
        }
        """
        #expect(mineFirst(source).isEmpty)
    }

    @Test("Payload-free sends mine in source order with the reducer type")
    func payloadFreeOrdered() throws {
        let source = """
        import ComposableArchitecture
        import XCTest
        final class T: XCTestCase {
            func testFlow() async {
                let store = TestStore(initialState: Feature.State()) { Feature() }
                await store.send(.dismiss)
                await store.send(.refresh)
            }
        }
        """
        let traces = mineFirst(source)
        #expect(traces.count == 1)
        let trace = try #require(traces.first)
        #expect(trace.reducerTypeName == "Feature")
        #expect(trace.sent.map(\.caseName) == ["dismiss", "refresh"])
        let allPayloadFree = trace.sent.allSatisfy(\.isPayloadFree)
        #expect(allPayloadFree)
        #expect(trace.received.isEmpty)
    }

    @Test("Payload-bearing send captures case name + verbatim argument text")
    func payloadBearing() throws {
        let source = """
        import ComposableArchitecture
        import XCTest
        final class T: XCTestCase {
            func testSelect() async {
                let store = TestStore(initialState: Feature.State(items: [a, b])) { Feature() }
                await store.send(.select(a.id))
            }
        }
        """
        let traces = mineFirst(source)
        let action = try #require(traces.first?.sent.first)
        #expect(action.caseName == "select")
        #expect(action.argumentTexts == ["a.id"])
        #expect(!action.isPayloadFree)
        #expect(traces.first?.initialStateExpr == "Feature.State(items: [a, b])")
    }

    @Test("receive is routed to `received`, not `sent`")
    func receiveSeparated() throws {
        let source = """
        import ComposableArchitecture
        import XCTest
        final class T: XCTestCase {
            func testEffect() async {
                let store = TestStore(initialState: Feature.State()) { Feature() }
                await store.send(.begin)
                await store.receive(.finished)
            }
        }
        """
        let trace = try #require(mineFirst(source).first)
        #expect(trace.sent.map(\.caseName) == ["begin"])
        #expect(trace.received.map(\.caseName) == ["finished"])
    }

    @Test("Reducer type resolves through a modifier chain")
    func reducerThroughModifier() {
        let source = """
        import ComposableArchitecture
        import XCTest
        final class T: XCTestCase {
            func testFlow() async {
                let store = TestStore(initialState: Feature.State()) { Feature()._printChanges() }
                await store.send(.tap)
            }
        }
        """
        #expect(mineFirst(source).first?.reducerTypeName == "Feature")
    }

    @Test("Reducer supplied via a reducer: argument (no trailing closure)")
    func reducerArgumentForm() throws {
        let source = """
        import ComposableArchitecture
        import XCTest
        final class T: XCTestCase {
            func testFlow() async {
                let store = TestStore(initialState: Feature.State(), reducer: Feature())
                await store.send(.tap)
            }
        }
        """
        let trace = try #require(mineFirst(source).first)
        #expect(trace.reducerTypeName == "Feature")
        #expect(trace.sent.map(\.caseName) == ["tap"])
    }

    @Test("send/receive inside a state-mutation trailing closure still mines the action")
    func trailingMutationClosure() throws {
        let source = """
        import ComposableArchitecture
        import XCTest
        final class T: XCTestCase {
            func testFlow() async {
                let store = TestStore(initialState: Feature.State()) { Feature() }
                await store.send(.select(a.id)) { $0.selectedID = a.id }
            }
        }
        """
        let trace = try #require(mineFirst(source).first)
        #expect(trace.sent.map(\.caseName) == ["select"])
    }

    // MARK: - Precision guards

    @Test("A .send on an unrelated object is not mined")
    func unrelatedSendNotMined() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testFlow() {
                let socket = Socket()
                socket.send(.ping)
                XCTAssertTrue(socket.isOpen)
            }
        }
        """
        // No TestStore construction, and the receiver is `socket`, not the
        // conventional bare `store` — nothing to mine.
        #expect(mineFirst(source).isEmpty)
    }

    @Test("send of a bare variable (not a case literal) is skipped")
    func nonLiteralActionSkipped() {
        let source = """
        import ComposableArchitecture
        import XCTest
        final class T: XCTestCase {
            func testFlow() async {
                let store = TestStore(initialState: Feature.State()) { Feature() }
                let action = Feature.Action.tap
                await store.send(action)
            }
        }
        """
        // The store is constructed but its only send is a bare variable, so
        // it yields no minable action → the actionless trace is dropped.
        #expect(mineFirst(source).isEmpty)
    }

    @Test("Two TestStores in one body keep their sequences separate")
    func multipleStoresSeparated() {
        let source = """
        import ComposableArchitecture
        import XCTest
        final class T: XCTestCase {
            func testTwo() async {
                let store = TestStore(initialState: Alpha.State()) { Alpha() }
                await store.send(.one)
                let other = TestStore(initialState: Beta.State()) { Beta() }
                await other.send(.two)
                await store.send(.three)
            }
        }
        """
        let traces = mineFirst(source)
        #expect(traces.count == 2)
        let alpha = traces.first { $0.reducerTypeName == "Alpha" }
        let beta = traces.first { $0.reducerTypeName == "Beta" }
        #expect(alpha?.sent.map(\.caseName) == ["one", "three"])
        #expect(beta?.sent.map(\.caseName) == ["two"])
    }

    @Test("Bare `store` sends with no resolvable construction fall back to a nil-reducer trace")
    func bareStoreFallback() throws {
        // `store` is a parameter here (no visible TestStore(...) construction),
        // exercising the conventional-name fallback path.
        let source = """
        import ComposableArchitecture
        import XCTest
        final class T: XCTestCase {
            func testHelper() async {
                await store.send(.alpha)
                await store.send(.beta)
            }
        }
        """
        let trace = try #require(mineFirst(source).first)
        #expect(trace.reducerTypeName == nil)
        #expect(trace.sent.map(\.caseName) == ["alpha", "beta"])
    }
}
