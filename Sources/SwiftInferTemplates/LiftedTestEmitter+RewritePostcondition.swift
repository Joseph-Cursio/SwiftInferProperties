import SwiftInferCore

public extension LiftedTestEmitter {

    /// `rewrite-postcondition`: the output lacks the tokens the body removes — none of them in a
    /// rewritten `String`, or the separator in no element of a split `[String]`.
    ///
    /// The input is drawn from the String carrier's generator, which carries the subject's own
    /// literals (kit 4.8.0), so the replaced tokens themselves are among the draws; a law about a
    /// token no input contains would pass without checking anything.
    static func rewritePostcondition(
        callee: CalleeReference,
        postcondition: RewritePostcondition,
        typeName: String,
        seed: SamplingSeed.Value,
        generator: String
    ) -> String {
        let check: String
        switch postcondition.guarantee {
        case .outputLacks(let tokens):
            check = tokens.map { "!result.contains(\(swiftLiteral($0)))" }.joined(separator: " && ")

        case .elementsLack(let separator):
            check = "!result.contains { $0.contains(\(swiftLiteral(separator))) }"
        }
        let body = "let result = \(callee.call("value")); return \(check)"
        return makeTestStub(
            testFunctionName: "\(callee.bareName)_lacksWhatItRemoves",
            seed: seed,
            generator: generator,
            propertyExpression: callee.isolated(body),
            failureLabel: "\(callee.displaySignature) broke its rewrite: "
                + RewritePostconditionTemplate.sentence(postcondition, function: callee.bareName),
            carrierType: typeName
        )
    }

    /// `text` as a Swift string literal, quotes included, with every character a single-line literal
    /// cannot hold escaped — a replaced token is often a newline or a tab.
    static func swiftLiteral(_ text: String) -> String {
        var escaped = ""
        for character in text {
            switch character {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            case "\0": escaped += "\\0"
            default: escaped.append(character)
            }
        }
        return "\"\(escaped)\""
    }
}
