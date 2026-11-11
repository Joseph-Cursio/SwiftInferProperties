// Usage: swift xmlparser-check.swift FILE...
// Parses each file with Foundation's XMLParser and prints whether it is well-formed, with the first error
// libxml2 reported (the final `parserError` is often code 111, the stop raised after the first error).
import Foundation

final class FirstError: NSObject, XMLParserDelegate {
    var first: (code: Int, line: Int, column: Int, message: String)?
    func parser(_ parser: XMLParser, parseErrorOccurred error: Error) {
        guard first == nil else { return }
        let ns = error as NSError
        let message = (ns.userInfo["NSXMLParserErrorMessage"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ns.localizedDescription
        first = (ns.code, parser.lineNumber, parser.columnNumber, message)
    }
}

for path in CommandLine.arguments.dropFirst() {
    guard let data = FileManager.default.contents(atPath: path) else {
        print("\(path): cannot read"); continue
    }
    let parser = XMLParser(data: data)
    let delegate = FirstError()
    parser.delegate = delegate
    if parser.parse() {
        print("\(path): well-formed")
    } else if let e = delegate.first {
        print("\(path): NOT well-formed — XMLParser error \(e.code) at line \(e.line), column \(e.column): \(e.message)")
    } else {
        print("\(path): NOT well-formed — \(parser.parserError.map { String(describing: $0) } ?? "no error")")
    }
}
