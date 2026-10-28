// @acceptor NSRegularExpression(pattern:options: [])
// Control PC8 only, not a subject's code: a producer that traps on one input, `{a}`. The run must
// record `{a}` as TRAPPED and resume after it; the escaper makes every other non-empty input valid.
import Foundation

func produce(_ input: String) -> String? {
    precondition(input != "{a}", "PC8 traps here")
    return NSRegularExpression.escapedPattern(for: input)
}

func accepts(_ pattern: String) -> Bool { (try? NSRegularExpression(pattern: pattern, options: [])) != nil }
