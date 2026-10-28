// @acceptor NSRegularExpression(pattern:options: [])
// Control PC9 only: a stub that does not compile is UNSTUBBABLE, recorded with its first error, and the
// run goes on.
import Foundation

func produce(_ input: String) -> String? { undefinedHelper(input) }

func accepts(_ pattern: String) -> Bool { (try? NSRegularExpression(pattern: pattern, options: [])) != nil }
