import Foundation
import SwiftInferCore
import SwiftInferTemplates

// Reads every census subject (`uniquifier-law-census-scope.md` §2) with the census's own skip rules, and
// records each function the uniquifier reader shapes: whether the template proposes it, declines it (and
// why), or finds no state kept across calls. `inDiscover` says whether `TemplateRegistry.discover` keeps
// the suggestion after the pipeline's own vetoes.

struct Subject: Decodable {
    let name: String
    let group: String
    let root: String
    let revision: String?
}

struct Census: Decodable {
    let subjects: [Subject]
}

struct Row: Encodable {
    let subject: String
    let group: String
    let file: String
    let line: Int
    let function: String
    let owner: String?
    let status: String
    let reason: String?
    let form: String?
    let memoizing: Bool
    let nameParameter: Int?
    let testedBases: [String]
    let inDiscover: Bool
    let score: Int?
}

struct SubjectRecord: Encodable {
    let name: String
    let group: String
    let root: String
    let censusRevision: String?
    let revision: String?
    let files: Int
    let rows: [Row]
}

let skippedNames: Set<String> = [
    "Tests", "tests", "test", "validation-test", ".build", "build", "DerivedData", "checkouts", "Pods", "Carthage",
]

func isSkipped(_ component: String) -> Bool {
    component.hasPrefix(".") || skippedNames.contains(component) || component.hasSuffix("Tests")
        || component.hasSuffix("UITests") || component.lowercased() == "fixtures"
}

func swiftFiles(under root: URL) -> [URL] {
    guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
        return []
    }
    var found: [URL] = []
    for case let url as URL in walker {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            if isSkipped(url.lastPathComponent) { walker.skipDescendants() }
        } else if url.pathExtension == "swift" {
            found.append(url)
        }
    }
    return found.sorted { $0.path < $1.path }
}

func head(of root: URL) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", root.path, "rev-parse", "HEAD"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    guard (try? process.run()) != nil else { return nil }
    process.waitUntilExit()
    let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    return text?.trimmingCharacters(in: .whitespacesAndNewlines)
}

func describe(_ form: UniquifierForm) -> String {
    switch form {
    case .instance: "instance"
    case .mutating: "mutating"
    case .inoutParameter(let index, let type): "inout(\(index): \(type))"
    }
}

func rows(for subject: Subject, root: URL, files: [URL]) -> [Row] {
    var summaries: [FunctionSummary] = []
    var typeDecls: [TypeDecl] = []
    for file in files {
        guard let corpus = try? FunctionScanner.scanCorpus(file: file) else { continue }
        summaries += corpus.summaries
        typeDecls += corpus.typeDecls
    }
    let shaped = summaries.filter { $0.bodySignals.uniquifierShape != nil }
    guard !shaped.isEmpty else { return [] }
    let kept = Set(
        TemplateRegistry.discover(in: summaries, typeDecls: typeDecls, templateFilter: [UniquifierTemplate.name])
            .compactMap { $0.evidence.first.map { "\($0.location)" } }
    )
    let owners = UniquifierOwners(typeDecls: typeDecls)
    let byType = Dictionary(grouping: summaries) { $0.qualifiedContainingTypeName ?? $0.containingTypeName ?? "" }
    return shaped.map { summary in
        let siblings = summary.containingTypeName == nil
            ? []
            : byType[summary.qualifiedContainingTypeName ?? summary.containingTypeName ?? ""] ?? []
        let reason = UniquifierTemplate.declineReason(for: summary, siblings: siblings)
        let match = UniquifierTemplate.match(for: summary, owners: owners)
        let suggestion = reason == nil
            ? UniquifierTemplate.suggest(for: summary, siblings: siblings, owners: owners)
            : nil
        let status = reason != nil ? "declined" : match == nil ? "no-state" : "proposed"
        let resolved = root.resolvingSymlinksInPath().path
        let file = URL(fileURLWithPath: summary.location.file).resolvingSymlinksInPath().path
        let relative = file.hasPrefix(resolved + "/") ? String(file.dropFirst(resolved.count + 1)) : file
        return Row(
            subject: subject.name,
            group: subject.group,
            file: relative,
            line: summary.location.line,
            function: summary.name,
            owner: summary.qualifiedContainingTypeName,
            status: status,
            reason: reason,
            form: match.map { describe($0.form) },
            memoizing: summary.bodySignals.uniquifierShape?.isMemoizing ?? false,
            nameParameter: match?.nameParameter,
            testedBases: summary.bodySignals.uniquifierShape?.testedBases ?? [],
            inDiscover: kept.contains("\(summary.location)"),
            score: suggestion?.score.total
        )
    }
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: UniquifierTemplateRun <census.json> <out.json> [group…]\n".utf8))
    exit(2)
}
let census = try JSONDecoder().decode(Census.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
let groups = Set(arguments.dropFirst(3))
var records: [SubjectRecord] = []
for subject in census.subjects where groups.isEmpty || groups.contains(subject.group) {
    let root = URL(fileURLWithPath: (subject.root as NSString).expandingTildeInPath)
    let files = swiftFiles(under: root)
    let found = rows(for: subject, root: root, files: files)
    FileHandle.standardError.write(Data("\(subject.group) \(subject.name): \(files.count) files, \(found.count) shaped\n".utf8))
    records.append(SubjectRecord(
        name: subject.name, group: subject.group, root: subject.root, censusRevision: subject.revision,
        revision: head(of: root), files: files.count, rows: found
    ))
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(records).write(to: URL(fileURLWithPath: arguments[2]))
