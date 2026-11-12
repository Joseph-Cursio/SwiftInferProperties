import Foundation

let arguments = CommandLine.arguments
let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let repositoryRoot = here.appendingPathComponent("../../..").standardized

func runControls() -> Bool {
    let failures = Controls.run(repositoryRoot: repositoryRoot)
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
    for subject in subjects {
        var count = SubjectCount(name: subject.name, repository: subject.repository, revision: subject.revision,
                                 dirty: subject.dirty)
        for root in subject.roots {
            let rootURL = URL(fileURLWithPath: root).resolvingSymlinksInPath()
            for file in Census.swiftFiles(under: rootURL, sourcesComponentOnly: subject.sourcesComponentOnly)
            where seen.insert(file.resolvingSymlinksInPath().path).inserted {
                guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
                count.files += 1
                count.functions += Census.read(source: source, path: file.resolvingSymlinksInPath().path,
                                               repository: subject.repository,
                                               repositoryRoot: URL(fileURLWithPath: subject.repositoryRoot)
                                                   .resolvingSymlinksInPath().path,
                                               into: &record)
            }
        }
        record.files += count.files
        record.functions += count.functions
        record.subjects.append(count)
        print("\(subject.name): \(count.files) files, \(count.functions) functions")
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(record).write(to: URL(fileURLWithPath: arguments[3]))
    print("\(record.functions) functions, \(record.rows.count) rows, "
        + "\(record.rows.filter(\.admitted).count) admitted")

default:
    print("usage: SanitizerCensus controls | run <subjects.json> <out.json>")
    exit(2)
}
