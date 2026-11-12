import Foundation

let arguments = CommandLine.arguments
let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func runControls() -> Bool {
    let failures = Controls.run(controlSources: here.appendingPathComponent("control-sources"))
    for failure in failures { print("CONTROL FAILED: \(failure)") }
    print(failures.isEmpty ? "all controls pass" : "\(failures.count) controls failed")
    return failures.isEmpty
}

switch arguments.dropFirst().first {
case "controls":
    exit(runControls() ? 0 : 1)

case "run" where arguments.count == 4:
    guard runControls() else { exit(1) }
    let subjects = try JSONDecoder().decode([Subject].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[2])))
    var record = CensusRecord()
    var seen: Set<String> = []
    // Helper hops resolve within a repository (§2.6), so each repository's files are parsed before any is read.
    var order: [String] = []
    var byRepository: [String: [Subject]] = [:]
    for subject in subjects {
        if byRepository[subject.repository] == nil { order.append(subject.repository) }
        byRepository[subject.repository, default: []].append(subject)
    }
    for repository in order {
        var parsedBySubject: [(Subject, [Census.Parsed])] = []
        for subject in byRepository[repository]! {
            let repositoryRoot = URL(fileURLWithPath: subject.repositoryRoot).resolvingSymlinksInPath().path
            var parsed: [Census.Parsed] = []
            for root in subject.roots {
                let rootURL = URL(fileURLWithPath: root).resolvingSymlinksInPath()
                for file in Census.swiftFiles(under: rootURL, sourcesComponentOnly: subject.sourcesComponentOnly)
                where seen.insert(file.resolvingSymlinksInPath().path).inserted {
                    guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
                    parsed.append(Census.parse(source: source, path: file.resolvingSymlinksInPath().path,
                                               repositoryRoot: repositoryRoot))
                }
            }
            parsedBySubject.append((subject, parsed))
        }
        let index = Census.index(parsedBySubject.flatMap(\.1))
        for (subject, parsed) in parsedBySubject {
            var count = SubjectCount(name: subject.name, repository: subject.repository, revision: subject.revision,
                                     dirty: subject.dirty)
            for file in parsed {
                count.files += 1
                count.functions += file.functions.count
                Census.read(file, repository: repository, index: index, into: &record)
            }
            record.files += count.files
            record.functions += count.functions
            record.subjects.append(count)
            print("\(subject.name): \(count.files) files, \(count.functions) functions")
        }
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(record).write(to: URL(fileURLWithPath: arguments[3]))
    print("\(record.functions) functions, \(record.rows.count) rows, "
        + "\(record.rows.filter(\.admitted).count) admitted")

default:
    print("usage: EmitterCensus controls | run <subjects.json> <out.json>")
    exit(2)
}
