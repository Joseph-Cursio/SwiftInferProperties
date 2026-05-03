import SwiftSyntax
import Testing
@testable import SwiftInferTestLifter

/// PRD §15 hard contract for the slicer: never throws regardless of
/// the input body shape. M1.6 backs this with a fuzz pass over 100
/// procedurally generated test bodies that combine random `let` decls,
/// random function calls, conditional statements, and optional
/// terminal assertions.
@Suite("Slicer — PRD §15 non-throwing fuzz (M1.6)")
struct SlicerFuzzTests {

    @Test("100 random test-body ASTs all slice without throwing")
    func hundredRandomBodiesSlice() {
        var generator = SeededGenerator(seed: 0xC0FFEE)
        for index in 0..<100 {
            let source = randomTestBodySource(index: index, generator: &generator)
            // The slicer is non-throwing by signature — this is a
            // smoke that confirms no fatalError / precondition crash
            // bubbles up under hostile input either.
            _ = SlicerTestHelper.sliceFirstBody(in: source)
        }
    }

    // MARK: - Random body generation

    private func randomTestBodySource(
        index: Int,
        generator: inout SeededGenerator
    ) -> String {
        var statements: [String] = []
        let stmtCount = Int.random(in: 1...8, using: &generator)
        for _ in 0..<stmtCount {
            statements.append(randomStatement(generator: &generator))
        }
        let bodyText = statements.joined(separator: "\n        ")
        return """
        import XCTest

        final class FuzzTests: XCTestCase {
            func testFuzz\(index)() {
                \(bodyText)
            }
        }
        """
    }

    private func randomStatement(generator: inout SeededGenerator) -> String {
        switch Int.random(in: 0..<7, using: &generator) {
        case 0:
            return "let \(randomIdent(generator: &generator)) = \(randomLiteral(generator: &generator))"
        case 1:
            let name = randomIdent(generator: &generator)
            let arg = randomIdent(generator: &generator)
            return "let \(name) = \(randomCallee(generator: &generator))(\(arg))"
        case 2:
            return "\(randomCallee(generator: &generator))()"
        case 3:
            let lhs = randomIdent(generator: &generator)
            let rhs = randomIdent(generator: &generator)
            return "XCTAssertEqual(\(lhs), \(rhs))"
        case 4:
            return "XCTAssertTrue(true)"
        case 5:
            let arg = randomIdent(generator: &generator)
            return "if \(arg) > 0 { print(\"positive\") }"
        case 6:
            // Deliberately weird: bare literal expression.
            return randomLiteral(generator: &generator)
        default:
            return ""
        }
    }

    private func randomLiteral(generator: inout SeededGenerator) -> String {
        let kinds = ["42", "\"hello\"", "true", "false", "3.14"]
        return kinds[Int.random(in: 0..<kinds.count, using: &generator)]
    }

    private func randomCallee(generator: inout SeededGenerator) -> String {
        let names = ["encode", "decode", "merge", "fold", "transform", "compute"]
        return names[Int.random(in: 0..<names.count, using: &generator)]
    }

    private func randomIdent(generator: inout SeededGenerator) -> String {
        let names = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta"]
        return names[Int.random(in: 0..<names.count, using: &generator)]
    }
}

/// Linear-congruential PRNG so the fuzz corpus is byte-identical
/// across runs — supports the PRD §16 #6 reproducibility guarantee
/// even for the test layer.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed | 1
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
