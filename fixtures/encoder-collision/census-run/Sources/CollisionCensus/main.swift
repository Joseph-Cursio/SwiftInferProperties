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
    var order: [String] = []
    var byRepository: [String: [Subject]] = [:]
    for subject in subjects {
        if byRepository[subject.repository] == nil { order.append(subject.repository) }
        byRepository[subject.repository, default: []].append(subject)
    }
    var seen: Set<String> = []
    for repository in order {
        var parsed: [Census.Parsed] = []
        var counts: [SubjectCount] = []
        for subject in byRepository[repository]! {
            var count = SubjectCount(group: subject.group, name: subject.name, repository: repository,
                                     revision: subject.revision, dirty: subject.dirty)
            for path in subject.files where seen.insert(path).inserted {
                guard let source = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) else { continue }
                let file = Census.parse(source: source, path: path, repositoryRoot: repository)
                count.files += 1
                count.loops += file.loops.count
                parsed.append(file)
            }
            counts.append(count)
        }
        _ = Census.read(repository: repository, files: parsed, into: &record)
        for count in counts {
            record.files += count.files
            record.loops += count.loops
            record.subjects.append(count)
            print("\(count.name): \(count.files) files, \(count.loops) loops")
        }
    }
    let failures = Census.foundationFailures(&record)
    for failure in failures { print("FOUNDATION DISAGREES: \(failure)") }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(record).write(to: URL(fileURLWithPath: arguments[3]))
    let chains = record.candidates.filter { $0.candidate.isChain }
    print("\(record.files) files, \(record.loops) loops; \(record.candidates.count) candidates, \(chains.count) chains, "
        + "\(chains.filter { $0.candidate.witness != nil }.count) colliding; \(record.sites.count) site rows, "
        + "\(record.sites.filter { $0.filing == "admitted" }.count) admitted; "
        + "\(record.foundationChecked) witnesses checked against Foundation; \(record.probe.count) probe rows, \(record.uses.count) uses of a colliding chain")
    exit(failures.isEmpty ? 0 : 1)

default:
    print("usage: CollisionCensus controls | run <subjects.json> <out.json>")
    exit(2)
}
