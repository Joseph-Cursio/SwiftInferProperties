// swift repro.swift — PropertyListEncoder (.xml) with a C0 control in a String, judged by XMLParser.
import Foundation

struct Settings: Codable, Equatable { var title: String }

final class FirstError: NSObject, XMLParserDelegate {
    var message = ""
    func parser(_ parser: XMLParser, parseErrorOccurred error: Error) {
        if message.isEmpty {
            let ns = error as NSError
            message = "code \(ns.code), line \(parser.lineNumber): "
                + ((ns.userInfo["NSXMLParserErrorMessage"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

let encoder = PropertyListEncoder()
encoder.outputFormat = .xml
let value = Settings(title: "\u{1B}[0m")             // a terminal colour code, pasted
let data = try encoder.encode(value)
print(String(decoding: data, as: UTF8.self).debugDescription)

let parser = XMLParser(data: data)
let delegate = FirstError()
parser.delegate = delegate
print("XMLParser.parse():", parser.parse(), delegate.message)
print("PropertyListDecoder reads it back:", try PropertyListDecoder().decode(Settings.self, from: data) == value)
