import Foundation
import SwiftOperators
import SwiftParser
import SwiftSyntax

/// One subject from `scripts/encoder_collision_census.py controls`: its files are already chosen by #668's
/// skip rule (`layering_census.subject_files`, `xml_emitter_census.without_fixtures`).
struct Subject: Codable {
    let group: String
    let name: String
    let repository: String
    let root: String
    let revision: String?
    let dirty: Bool
    let files: [String]
}

struct SubjectCount: Codable {
    let group: String
    let name: String
    let repository: String
    let revision: String?
    let dirty: Bool
    var files = 0
    var loops = 0
}

/// Every candidate (§1.1) the run indexed, with the repository it belongs to.
struct ChainRow: Codable {
    let repository: String
    let candidate: Candidate
}

struct CensusRecord: Codable {
    var files = 0
    var loops = 0
    var subjects: [SubjectCount] = []
    var candidates: [ChainRow] = []
    var sites: [SiteRow] = []
    var tally: [String: Int] = [:]
    var foundationChecked = 0
    var probe: [ProbeRow] = []
    var uses: [UseRow] = []
}

enum Census {
    struct Parsed {
        let path: String
        let relative: String
        let tree: SourceFileSyntax
        let converter: SourceLocationConverter
        let loops: [ForStmtSyntax]
    }

    static func parse(source: String, path: String, repositoryRoot: String) -> Parsed {
        let raw = Parser.parse(source: source)
        let tree = OperatorTable.standardOperators.foldAll(raw, errorHandler: { _ in }).as(SourceFileSyntax.self) ?? raw
        let converter = SourceLocationConverter(fileName: path, tree: tree)
        let relative = path.hasPrefix(repositoryRoot + "/") ? String(path.dropFirst(repositoryRoot.count + 1)) : path
        return Parsed(path: path, relative: relative, tree: tree, converter: converter,
                      loops: Collect<ForStmtSyntax>.all(in: tree, intoClosures: true))
    }

    /// One repository: index every file's candidates first (§2.3), then read every loop.
    static func read(repository: String, files: [Parsed], into record: inout CensusRecord) -> CandidateIndex {
        var index = CandidateIndex()
        for file in files { CandidateReader.read(file.tree, file: file.relative, converter: file.converter, into: &index) }
        for candidates in index.byName.values {
            for candidate in candidates { record.candidates.append(ChainRow(repository: repository, candidate: candidate)) }
        }
        for file in files { SiteReader.read(file, repository: repository, index: index, into: &record.sites, tally: &record.tally) }
        for file in files { Probe.read(file, repository: repository, index: index, sites: record.sites, into: &record.probe) }
        for file in files { Probe.uses(file, repository: repository, index: index, into: &record.uses) }
        return index
    }

    /// §4's Foundation check over every witness the record carries.
    static func foundationFailures(_ record: inout CensusRecord) -> [String] {
        var failures: [String] = []
        for row in record.candidates {
            guard let steps = row.candidate.steps else { continue }
            for witness in [row.candidate.witness].compactMap({ $0 }) + row.candidate.identifierWitnesses {
                record.foundationChecked += 1
                if !Collision.agreesWithFoundation(steps, witness) {
                    failures.append("\(row.repository) \(row.candidate.name): \(witness)")
                }
            }
        }
        return failures
    }
}
