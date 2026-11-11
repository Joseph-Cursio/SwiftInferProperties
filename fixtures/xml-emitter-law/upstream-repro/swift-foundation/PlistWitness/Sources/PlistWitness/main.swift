// Encodes with swift-foundation's own PropertyListEncoder (FoundationEssentials, built from source),
// writes each XML plist to a file, and decodes it back with the same package's PropertyListDecoder.
import FoundationEssentials

struct Settings: Codable, Equatable { var title: String }

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let encoder = PropertyListEncoder()
encoder.outputFormat = .xml

func run(_ name: String, _ value: Settings) {
    do {
        let data = try encoder.encode(value)
        let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(name).plist")
        try data.write(to: url)
        let back: String
        do {
            let decoded = try PropertyListDecoder().decode(Settings.self, from: data)
            back = decoded == value ? "decodes back equal" : "decodes back DIFFERENT: \(decoded.title.unicodeScalars.map { String($0.value, radix: 16) })"
        } catch {
            back = "decode throws: \(error)"
        }
        print("\(name): encoded \(data.count) bytes; \(back)")
    } catch {
        print("\(name): encode throws: \(error)")
    }
}

run("control-u0001", Settings(title: "a\u{1}b"))
run("control-esc", Settings(title: "\u{1B}[0m"))
run("nonchar-ufffe", Settings(title: "a\u{FFFE}b"))
run("nul", Settings(title: "a\u{0}b"))
run("plain", Settings(title: "a<b&c"))

// Sweep: every C0 control, DEL, U+0085, U+FFFD, U+FFFE, U+FFFF and U+1FFFE, as a value and as a dictionary key.
let sweepDir = URL(fileURLWithPath: outDir).appendingPathComponent("sweep")
try? FileManager.default.createDirectory(at: sweepDir, withIntermediateDirectories: true)
let scalars: [UInt32] = Array(0x00...0x20) + [0x7F, 0x85, 0xFFFD, 0xFFFE, 0xFFFF, 0x1FFFE]
for v in scalars {
    let s = "x" + String(Character(Unicode.Scalar(v)!)) + "y"
    for (kind, value) in [("value", ["k": s]), ("key", [s: "v"])] {
        let hex = String(v, radix: 16, uppercase: true)
        let name = kind + "-" + String(repeating: "0", count: 5 - hex.count) + hex
        do {
            try encoder.encode(value).write(to: sweepDir.appendingPathComponent("\(name).plist"))
        } catch {
            print("\(name): encode throws")
        }
    }
}
