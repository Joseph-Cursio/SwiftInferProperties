import Testing
@testable import SwiftInferTestLifter

@Suite("DomainCallSiteExtractor — consumer call-site classification (M10.1)")
struct DomainCallSiteExtractorTests {

    @Test("Empty body produces no call sites")
    func emptyBodyNoSites() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testNothing() { }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        let sites = DomainCallSiteExtractor.extract(consumer: "decode", in: slice)
        #expect(sites.isEmpty)
    }

    @Test("Body with no consumer call sites produces no sites")
    func noConsumerCalls() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testEncodeOnly() {
                let result = encode(value)
                XCTAssertEqual(result, expected)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        let sites = DomainCallSiteExtractor.extract(consumer: "decode", in: slice)
        #expect(sites.isEmpty)
    }

    @Test("Direct producer call as first arg classifies as .callOutput")
    func directCallOutputClassification() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testRoundTrip() {
                XCTAssertEqual(decode(encode(t)), t)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        let sites = DomainCallSiteExtractor.extract(consumer: "decode", in: slice)
        #expect(sites.count == 1)
        #expect(sites.first?.argument == .callOutput(producerName: "encode"))
    }

    @Test("Bare identifier as first arg classifies as .identifier")
    func bareIdentifierClassification() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testRoundTrip() {
                let x = encode(t)
                XCTAssertEqual(decode(x), t)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        let sites = DomainCallSiteExtractor.extract(consumer: "decode", in: slice)
        #expect(sites.count == 1)
        #expect(sites.first?.argument == .identifier(name: "x"))
    }

    @Test("Literal as first arg classifies as .other")
    func literalClassification() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testLiteral() {
                XCTAssertEqual(decode("hi"), expected)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        let sites = DomainCallSiteExtractor.extract(consumer: "decode", in: slice)
        #expect(sites.count == 1)
        #expect(sites.first?.argument == .other)
    }

    @Test("Closure as first arg classifies as .other")
    func closureClassification() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testClosure() {
                XCTAssertEqual(decode({ "x" }), expected)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        let sites = DomainCallSiteExtractor.extract(consumer: "decode", in: slice)
        #expect(sites.count == 1)
        #expect(sites.first?.argument == .other)
    }

    @Test("Member-access producer trailing identifier matches as .callOutput")
    func memberAccessProducer() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testRoundTrip() {
                XCTAssertEqual(decode(Codec.encode(t)), t)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        let sites = DomainCallSiteExtractor.extract(consumer: "decode", in: slice)
        #expect(sites.count == 1)
        #expect(sites.first?.argument == .callOutput(producerName: "encode"))
    }

    @Test("Member-access consumer trailing identifier still matches")
    func memberAccessConsumer() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testRoundTrip() {
                XCTAssertEqual(codec.decode(encode(t)), t)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        let sites = DomainCallSiteExtractor.extract(consumer: "decode", in: slice)
        #expect(sites.count == 1)
        #expect(sites.first?.argument == .callOutput(producerName: "encode"))
    }

    @Test("Method-call producer (Codec.encode → t.encode()) still matches")
    func methodCallProducer() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testRoundTrip() {
                XCTAssertEqual(decode(t.encode()), t)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        let sites = DomainCallSiteExtractor.extract(consumer: "decode", in: slice)
        #expect(sites.count == 1)
        #expect(sites.first?.argument == .callOutput(producerName: "encode"))
    }

    @Test("Multiple matching call sites are all captured")
    func multipleSites() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testTwoCalls() {
                let a = decode(encode(t))
                let b = decode(encode(u))
                XCTAssertEqual(a, t)
                XCTAssertEqual(b, u)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        let sites = DomainCallSiteExtractor.extract(consumer: "decode", in: slice)
        #expect(sites.count == 2)
        #expect(sites.allSatisfy { $0.argument == .callOutput(producerName: "encode") })
    }

    @Test("Mixed call sites surface mixed classifications")
    func mixedClassifications() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testMixed() {
                let a = decode(encode(t))
                let b = decode("literal")
                XCTAssertEqual(a, t)
                XCTAssertEqual(b, expected)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        let sites = DomainCallSiteExtractor.extract(consumer: "decode", in: slice)
        #expect(sites.count == 2)
        #expect(sites.contains { $0.argument == .callOutput(producerName: "encode") })
        #expect(sites.contains { $0.argument == .other })
    }

    @Test("Zero-arg consumer call classifies first arg as .other")
    func zeroArgCall() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testZeroArg() {
                XCTAssertEqual(decode(), expected)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        let sites = DomainCallSiteExtractor.extract(consumer: "decode", in: slice)
        #expect(sites.count == 1)
        #expect(sites.first?.argument == .other)
    }

    @Test("Outer-call consumer captures only the consumer-matching call")
    func nestedCallOnlyConsumerCaptured() {
        // process(decode(encode(t))) — only the decode call captures;
        // the inner encode and outer process are not consumer matches.
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testNested() {
                let result = process(decode(encode(t)))
                XCTAssertEqual(result, expected)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        let sites = DomainCallSiteExtractor.extract(consumer: "decode", in: slice)
        #expect(sites.count == 1)
        #expect(sites.first?.argument == .callOutput(producerName: "encode"))
    }
}
