#!/usr/bin/env python3
"""Which functions assign a graph's nodes to layers? — `docs/plans/layering-law-census-scope.md`.

#667's law: for every edge `u → v` the layering covers, with `v` unable to reach `u`, `layer(v) > layer(u)`.
This pass finds the functions that might owe it, by four cues read off the declaration (§1.2), and hands each
candidate to a blind hand-check (§4). It never decides that a function IS a layering; the judges do.

Section numbers below are the scope's.

  --self-test                 the scope's pass and decision controls, C1-C55 (no siblings; joins `make measurement-selftest`)
  run <out.json>              census the frozen universe (§2), and choose what §4 judges
  packets <census.json> <dir> write §4's blind judging packets, at most eight rows each, in seeded order
  join <index.json> <workflow.json> <judgements.json>       §4.3: the judge workflow's labels joined to row ids
  decide <census.json> <judgements.json> <kill-arm.json>   §8's outcome, figures and sensitivity lines

`layering-law-graph-layout-corpus-scope.md` reruns the same pass over a graph-layout corpus (C56-C61):

  run-corpus <out.json>       census the 18 clones as the decision group, every candidate judged
  decide-corpus <census.json> <judgements.json> <kill-arm.json>   §8 over the corpus, the lines beside it, and R5
"""
import collections
import hashlib
import json
import os
import random
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from budgeted_truncation_census import (  # noqa: E402
    DECL, FUNC, INT_TYPES, VISIBILITY, base_name, brace_pairs, parameters, result_head, revision, split_top,
    strip_type, subjects, words,
)
from mutation_check import mask  # noqa: E402
from regex_acceptor_census import FROZEN_UNIVERSE  # noqa: E402

HOME = os.path.expanduser("~")
SEED = 20261027
PACKET_SIZE = 8
# §4: what is judged. Above DECISION_CAP decision candidates, the NAME ∧ GRAPH-only stratum is sampled.
DECISION_CAP, NAME_GRAPH_SAMPLE, WIDE_CAP, R4_CAP = 300, 40, 60, 40
GROUP_ORDER = {"decision": 0, "unmet": 1, "wide": 2}

# §2: SwiftUMLStudio is read at the revision the kill arm exports.
SWIFTUMLSTUDIO = "c6c82e3"

# §2: the wide group, frozen on 2026-10-27 from directory listings and `origin` URLs. Each entry is the
# directory under `~` and its `origin` (None for a directory with no remote). Deduplicated by `origin`, keeping
# the `~/github_projects` copy. WIDE_SHA256 is the scope's hash of the sorted entries.
WIDE = [
    ("github_projects/aider", "https://github.com/aider-ai/aider"),
    ("github_projects/Alamofire", "https://github.com/alamofire/alamofire"),
    ("github_projects/algoliasearch-client-swift", "https://github.com/algolia/algoliasearch-client-swift"),
    ("github_projects/AnyCodable", "https://github.com/flight-school/anycodable"),
    ("github_projects/apollo-ios", "https://github.com/apollographql/apollo-ios"),
    ("github_projects/async-http-client", "https://github.com/swift-server/async-http-client"),
    ("github_projects/BigInt", "https://github.com/attaswift/bigint"),
    ("github_projects/CombineExt", "https://github.com/combinecommunity/combineext"),
    ("github_projects/exhaust", "https://github.com/nesevis/exhaust"),
    ("github_projects/FHIRModels", "https://github.com/apple/fhirmodels"),
    ("github_projects/fluent-kit", "https://github.com/vapor/fluent-kit"),
    ("github_projects/IceCubesApp", "https://github.com/dimillian/icecubesapp"),
    ("github_projects/indexstore-db", "https://github.com/swiftlang/indexstore-db"),
    ("github_projects/KeychainAccess", "https://github.com/kishikawakatsumi/keychainaccess"),
    ("github_projects/Kingfisher", "https://github.com/onevcat/kingfisher"),
    ("github_projects/lottie-ios", "https://github.com/airbnb/lottie-ios"),
    ("github_projects/Mastermind", "https://github.com/jonreid/mastermind"),
    ("github_projects/Moya", "https://github.com/moya/moya"),
    ("github_projects/Nimble", "https://github.com/quick/nimble"),
    ("github_projects/OpenAI", "https://github.com/macpaw/openai"),
    ("github_projects/opentelemetry-swift", "https://github.com/open-telemetry/opentelemetry-swift"),
    ("github_projects/pkl-swift", "https://github.com/apple/pkl-swift"),
    ("github_projects/postgres-nio", "https://github.com/vapor/postgres-nio"),
    ("github_projects/Quick", "https://github.com/quick/quick"),
    ("github_projects/RxSwift", "https://github.com/reactivex/rxswift"),
    ("github_projects/SnapKit", "https://github.com/snapkit/snapkit"),
    ("github_projects/soto-core", "https://github.com/soto-project/soto-core"),
    ("github_projects/sourcekit-lsp", "https://github.com/swiftlang/sourcekit-lsp"),
    ("github_projects/supabase-swift", "https://github.com/supabase/supabase-swift"),
    ("github_projects/SwaggerParser", "https://github.com/attilathefun/swaggerparser"),
    ("github_projects/swift-asn1", "https://github.com/apple/swift-asn1"),
    ("github_projects/swift-async-algorithms", "https://github.com/apple/swift-async-algorithms"),
    ("github_projects/swift-atomics", "https://github.com/apple/swift-atomics"),
    ("github_projects/swift-aws-lambda-events", "https://github.com/swift-server/swift-aws-lambda-events"),
    ("github_projects/swift-certificates", "https://github.com/apple/swift-certificates"),
    ("github_projects/swift-composable-architecture", "https://github.com/pointfreeco/swift-composable-architecture"),
    ("github_projects/swift-configuration", "https://github.com/apple/swift-configuration"),
    ("github_projects/swift-crypto", "https://github.com/apple/swift-crypto"),
    ("github_projects/swift-docc-symbolkit", "https://github.com/swiftlang/swift-docc-symbolkit"),
    ("github_projects/swift-http-types", "https://github.com/apple/swift-http-types"),
    ("github_projects/swift-markdown", "https://github.com/swiftlang/swift-markdown"),
    ("github_projects/swift-openapi-generator", "https://github.com/apple/swift-openapi-generator"),
    ("github_projects/swift-openapi-runtime", "https://github.com/apple/swift-openapi-runtime"),
    ("github_projects/swift-property-based", "https://github.com/x-sheep/swift-property-based"),
    ("github_projects/swift-protobuf", "https://github.com/apple/swift-protobuf"),
    ("github_projects/swift-sdk", "https://github.com/modelcontextprotocol/swift-sdk"),
    ("github_projects/swift-service-lifecycle", "https://github.com/swift-server/swift-service-lifecycle"),
    ("github_projects/swift-testing", "https://github.com/swiftlang/swift-testing"),
    ("github_projects/SwiftLint", "https://github.com/realm/swiftlint"),
    ("github_projects/SwiftPackageIndex-Server", "https://github.com/swiftpackageindex/swiftpackageindex-server"),
    ("github_projects/SwiftPlantUML", "https://github.com/marcoeidinger/swiftplantuml"),
    ("github_projects/SwiftyJSON", "https://github.com/swiftyjson/swiftyjson"),
    ("github_projects/TestableView", "https://github.com/jonreid/testableview"),
    ("github_projects/vapor", "https://github.com/vapor/vapor"),
    ("github_projects/ViewInspector", "https://github.com/nalexn/viewinspector"),
    ("github_projects/XcodeGen", "https://github.com/yonaskolb/xcodegen"),
    ("github_projects/XcodeProj", "https://github.com/tuist/xcodeproj"),
    ("github_projects/Yams", "https://github.com/jpsim/yams"),
    ("xcode_projects/Checkout", "https://github.com/joseph-cursio/checkout"),
    ("xcode_projects/Hudson_ProSwiftUI_1_1", None),
    ("xcode_projects/Hummingbird", "https://github.com/hummingbird-project/hummingbird"),
    ("xcode_projects/IdempotencySpike", None),
    ("xcode_projects/muter-upstream", "https://github.com/joseph-cursio/muter"),
    ("xcode_projects/Sitrep", "https://github.com/twostraws/sitrep"),
    ("xcode_projects/swift-aws-lambda-runtime", "https://github.com/swift-server/swift-aws-lambda-runtime"),
    ("xcode_projects/SwiftCompilerFlagStudio", "https://github.com/joseph-cursio/swiftcompilerflagstudio"),
    ("xcode_projects/SwiftMutator", "https://github.com/joseph-cursio/swiftmutator"),
]
WIDE_SHA256 = "c7ad7e6c379c03144bc370d778edc97632f09318219065b7155e723471d5f270"

# The graph-layout corpus (`layering-law-graph-layout-corpus-scope.md` §2): 18 public packages found by a GitHub
# search of names and descriptions only, cloned `--depth 1` with the user's approval on 2026-10-28. Each entry is
# the directory under CORPUS_DIR, its `origin`, the revision read, and its kind from its description (layout,
# dependency or commit). CORPUS_SHA256 is the hash that scope's §2.3 records.
CORPUS_DIR = "github_projects/graph-layout-corpus"
CORPUS = [
    ("lukilabs__dagre-swift", "https://github.com/lukilabs/dagre-swift",
     "92efb78b73a8b665ee74bacfb0f1f5b17bbe1b38", "layout"),
    ("lukilabs__elk-swift", "https://github.com/lukilabs/elk-swift",
     "32f8042e3509a4819f00ff9cd46e829ec2b26da0", "layout"),
    ("lukilabs__beautiful-mermaid-swift", "https://github.com/lukilabs/beautiful-mermaid-swift",
     "6a23a29e91af8f5b3e9fc09945332ca193bd69ec", "layout"),
    ("2389-research__MermaidKit", "https://github.com/2389-research/mermaidkit",
     "64c19fbddf5604122b01563b3ab727dbadf0ee95", "layout"),
    ("Australware__swift-mermaid", "https://github.com/australware/swift-mermaid",
     "ee4b50bc15ad6e9b9f88bc320f2c42ba9a55a804", "layout"),
    ("nmandica__DirectedGraph", "https://github.com/nmandica/directedgraph",
     "4aba72560eafae0f778666d0bc08376737dacd9a", "layout"),
    ("1amageek__swift-flow", "https://github.com/1amageek/swift-flow",
     "538588ebc739e945826c0ba8b4309a630ea0a61a", "layout"),
    ("aaurelions__SwiftFlow", "https://github.com/aaurelions/swiftflow",
     "3515701fad73d3c6f8722bd65c22ef0813dc11a0", "layout"),
    ("yahirvitelugardo__Graffle", "https://github.com/yahirvitelugardo/graffle",
     "53b93b0560d89d3e97acdb6b020e9ef73054a83d", "layout"),
    ("Vithanco__SwiftGraphvizLayout", "https://github.com/vithanco/swiftgraphvizlayout",
     "083fb3cf0c32b5e83adf4432eb3b0fc742789fa5", "layout"),
    ("Ryu0118__swift-module-graph", "https://github.com/ryu0118/swift-module-graph",
     "86c7dde938409df1bb3d8ef8bb75133d74d3e9a7", "dependency"),
    ("getyourguide__spmgraph", "https://github.com/getyourguide/spmgraph",
     "47ad8ac436a4f342145f3a3a612736d91e4882cd", "dependency"),
    ("simonbs__dependency-graph", "https://github.com/simonbs/dependency-graph",
     "6c89d4be7c90bdaea7feecf979f9ccab947c3188", "dependency"),
    ("leejungyeob__TuistSpider", "https://github.com/leejungyeob/tuistspider",
     "01aaa140dbcccabfcea90b04d099439cae2dd118", "dependency"),
    ("GlitchLoom__SwiftDependencyGraphExplorer", "https://github.com/glitchloom/swiftdependencygraphexplorer",
     "f93a3430a4fedd6872907fb0939180efb11d352a", "dependency"),
    ("swift-compositions__swift-package-graph", "https://github.com/swift-compositions/swift-package-graph",
     "d783a2c9fe3a02c507fd7ec398b61fe07632caf2", "dependency"),
    ("poolcamacho__Maple", "https://github.com/poolcamacho/maple",
     "9255de96fd57c7d28bb7876616a8a0ddb3b8aa5a", "commit"),
    ("tengla__GitGraphRender", "https://github.com/tengla/gitgraphrender",
     "1197ce47afd1b765f4d4b3bf7016bc4e11ef773d", "commit"),
]
CORPUS_SHA256 = "7272bb357b918c606dde71690763adf474d8c9034bcd2adfeae57177b6b45046"

# ── The cues (§1.2) ───────────────────────────────────────────────────────────────────────────────
NAME_PREFIXES = ("layer", "rank", "tier", "stratif", "topo", "sugiyama", "coffman")
NAME_WORDS = {"row", "rows", "level", "levels", "depth", "depths", "stratum", "strata"}
NAME_PAIRS = (("longest", "path"),)
GRAPH_WORDS = {
    "graph", "graphs", "digraph", "dag", "edge", "edges", "node", "nodes", "vertex", "vertices", "dependency",
    "dependencies", "adjacency", "successor", "successors", "predecessor", "predecessors", "arc", "arcs",
    "parent", "parents", "dependent", "dependents", "deps", "prerequisite", "prerequisites",
}
DOC_PHRASES = ("longest path", "longest-path", "layering", "layered", "layer assignment", "rank assignment",
               "sugiyama", "topological", "coffman", "network simplex", "kahn", "critical path")
# §1.4: #667's own evidence.
GATE_PREFIXES = ("layer", "rank")
GATE_PHRASES = ("longest path", "longest-path", "layering", "layered")

SKIP_EXACT = {"Tests", "tests", "test", "validation-test", ".build", "build", "DerivedData", "checkouts"}
SKIP_FOLDED = {"pods", "carthage"}
TYPE_KINDS = ("struct", "class", "enum", "actor")
# `class func`, `class var` …: `class` as a modifier, not a type (§1.2's owner).
CLASS_MODIFIED = {"func", "var", "let", "subscript", "init", "override", "final", "static", "private",
                  "fileprivate", "internal", "public", "open", "package", "convenience", "required", "deinit"}
CALL = re.compile(r"\b([A-Za-z_]\w*)\s*\(")


def name_cue(name_words):
    found = [word for word in name_words if word.startswith(NAME_PREFIXES) or word in NAME_WORDS]
    for first, second in NAME_PAIRS:
        if any(a == first and b == second for a, b in zip(name_words, name_words[1:])):
            found.append(f"{first} {second}")
    return found


def is_int(text):
    return strip_type(text).replace("Swift.", "") in INT_TYPES


def _unbracket(text):
    """`X` for `[X]`, or None."""
    text = text.strip()
    return text[1:-1].strip() if text.startswith("[") and text.endswith("]") else None


def _generic(text, name):
    """The arguments of `name<…>` as a list, or None."""
    match = re.match(rf"^(?:Swift\.|Collections\.)?{name}\s*<(.*)>$", text.strip(), re.S)
    return split_top(match.group(1)) if match else None


def _top_colon(text):
    depth = 0
    for index, character in enumerate(text):
        if character in "([<{":
            depth += 1
        elif character in ")]>}":
            depth -= 1
        elif character == ":" and depth == 0:
            return index
    return -1


def _is_group(text):
    """`[T]`, `Array<T>`, `Set<T>` or `OrderedSet<T>`: a level's members (§1.2 SHAPE)."""
    inner = _unbracket(text)
    if inner is not None:
        return _top_colon(inner) < 0
    return any(_generic(text, name) is not None for name in ("Array", "Set", "OrderedSet"))


def _map_shape(key, value):
    if is_int(value):
        return "[K: I]"
    if is_int(key) and _is_group(value):
        return "[I: [T]]"
    return None


def shape(result):
    """§1.2 SHAPE of a result's head (a tuple's first element): `[K: I]`, `[I: [T]]`, `[[T]]` or `[I]`, in
    their bracket and `Dictionary`/`Array` spellings, with `Set` and `OrderedSet` as groups; else None."""
    head = result_head(result) if result else ""
    inner = _unbracket(head)
    if inner is not None:
        colon = _top_colon(inner)
        if colon >= 0:
            return _map_shape(inner[:colon], inner[colon + 1:])
        if _is_group(inner):
            return "[[T]]"
        return "[I]" if is_int(inner) else None
    arguments = _generic(head, "Dictionary")
    if arguments and len(arguments) == 2:
        return _map_shape(arguments[0], arguments[1])
    arguments = _generic(head, "Array")
    if arguments and len(arguments) == 1:
        if _is_group(arguments[0]):
            return "[[T]]"
        return "[I]" if is_int(arguments[0]) else None
    return None


def doc_block(text, offset):
    """The doc comment directly above the declaration line at `offset`: a `///` run, or one `/** … */` block.
    Attribute lines, and blank lines between the comment and the declaration, are skipped."""
    line_start = text.rfind("\n", 0, offset) + 1
    cursor = line_start - 1
    lines = []
    while cursor > 0:
        previous = text.rfind("\n", 0, cursor) + 1
        line = text[previous:cursor].strip()
        if line.startswith("///"):
            lines.append(line[3:].strip())
        elif line.endswith("*/") and not lines:
            closing = text.rfind("*/", 0, cursor + 1)
            opening = text.rfind("/*", 0, closing)
            own_line = text[text.rfind("\n", 0, opening) + 1:opening].strip() == ""
            if opening < 0 or not text.startswith("/**", opening) or text.startswith("/**/", opening) or not own_line:
                break
            block = text[opening + 3:closing]
            return " ".join(part.strip().lstrip("*").strip() for part in block.splitlines()).strip()
        elif line.startswith("@") or (line == "" and not lines):
            pass
        else:
            break
        cursor = previous - 1
    return " ".join(reversed(lines))


def has_phrase(doc, phrases):
    lowered = " ".join(doc.lower().split())
    return [phrase for phrase in phrases if phrase in lowered]


# ── Declarations (§1.1) ───────────────────────────────────────────────────────────────────────────
def declarations(text):
    """`(types, functions)` in one file. A type is `(kind, name, doc)`. A function is a dict with its name,
    labels, parameter text, result text, owner, raw text, the names it calls, and its copy key."""
    masked, _ = mask(text)
    pairs = brace_pairs(masked)
    spans, types = [], []
    for match in DECL.finditer(masked):
        if match.group(1) == "class" and match.group(2) in CLASS_MODIFIED:
            continue
        brace = masked.find("{", match.end())
        if brace < 0 or masked[match.end():brace].count("\n") > 3:
            continue
        name = base_name(match.group(2))
        spans.append((match.start(), pairs.get(brace, len(masked) - 1), name, match.group(1)))
        if match.group(1) in TYPE_KINDS:
            types.append((match.group(1), name, doc_block(text, match.start())))
    functions = []
    for match in FUNC.finditer(masked):
        open_paren = match.end() - 1
        depth, index = 0, open_paren
        while index < len(masked):
            if masked[index] == "(":
                depth += 1
            elif masked[index] == ")":
                depth -= 1
                if depth == 0:
                    break
            index += 1
        brace = masked.find("{", index)
        if brace < 0:
            continue
        tail = masked[index + 1:brace]
        if tail.count("\n") > 4 or any(token in tail for token in (";", "}", "func ", " var ", " let ")):
            continue
        end = pairs.get(brace, len(masked) - 1)
        owners = [span for span in spans if span[0] < match.start() < span[1]]
        owner = min(owners, key=lambda span: span[1] - span[0]) if owners else None
        result = tail.split("->", 1)[1] if "->" in tail else ""
        result = re.split(r"\bwhere\b", result)[0]
        for effect in ("async", "throws", "rethrows"):
            result = re.sub(rf"\b{effect}\b(\s*\([^)]*\))?", "", result)
        line_start = masked.rfind("\n", 0, match.start()) + 1
        visibility = VISIBILITY.findall(masked[line_start:match.start()])
        body = masked[brace + 1:end]
        name = match.group(1).strip("`")
        labels = [label for label, _, _ in parameters(masked[open_paren + 1:index])]
        copy_key = "\x00".join([name, ",".join(labels), " ".join(body.split())])
        functions.append({
            "name": name,
            "labels": labels,
            "parameters": masked[open_paren + 1:index],
            "result": result.strip(),
            "owner": owner[2] if owner else "",
            "owner_kind": owner[3] if owner else "",
            "owner_doc": doc_block(text, owner[0]) if owner else "",
            "doc": doc_block(text, match.start()),
            "visibility": visibility[-1] if visibility else "",
            "line": text.count("\n", 0, match.start()) + 1,
            "text": text[line_start:end + 1],
            "calls": sorted(set(CALL.findall(body))),
            "key": hashlib.sha256(copy_key.encode()).hexdigest()[:16],
        })
    return types, functions


def cues(function, type_docs):
    """§1.2's cues for one function. `type_docs` maps a type name to the docs of every declaration of it in
    the repository, for DOC-OWNER through an extension."""
    name_words = words(function["name"])
    param_words = [word for label, name, kind in parameters(function["parameters"])
                   for part in (label, name, kind) for word in words(part)]
    graph_words = set(param_words) | set(words(function["result"])) | set(words(function["owner"]))
    owner_docs = [function["owner_doc"]]
    if function["owner_kind"] == "extension":
        owner_docs += type_docs.get(function["owner"], [])
    found = {
        "NAME": name_cue(name_words),
        "SHAPE": shape(function["result"]),
        "GRAPH": sorted(graph_words & GRAPH_WORDS),
        "DOC-OWN": has_phrase(function["doc"], DOC_PHRASES),
        "DOC-OWNER": sorted({phrase for doc in owner_docs for phrase in has_phrase(doc, DOC_PHRASES)}),
    }
    gate_phrases = has_phrase(" ".join([function["doc"]] + owner_docs), GATE_PHRASES)
    gated = any(word.startswith(GATE_PREFIXES) for word in name_words) or bool(gate_phrases)
    return found, gated, " ".join(doc for doc in dict.fromkeys(owner_docs) if doc)


def is_candidate(found):
    """§1.3."""
    name, shaped = bool(found["NAME"]), bool(found["SHAPE"])
    return ((name and shaped) or (name and found["GRAPH"]) or bool(found["DOC-OWN"])
            or (bool(found["DOC-OWNER"]) and (name or shaped)))


def type_docs_of(files):
    """`{type name: [doc, …]}` over `{path: text}`, for DOC-OWNER through an extension (§1.2)."""
    docs = collections.defaultdict(list)
    for text in files.values():
        for _, name, doc in declarations(text)[0]:
            if doc:
                docs[name].append(doc)
    return docs


def census(files, type_docs=None):
    """`(candidates, others)` over one subject's `{path: text}`. `type_docs` defaults to the subject's own;
    `run` passes its repository's, every subject sharing the git toplevel. Every row carries its same-file
    one-hop callers and callees (§4); `others` are the non-candidate functions, for R2 and R4 (§6)."""
    parsed = {path: declarations(text) for path, text in files.items()}
    if type_docs is None:
        type_docs = type_docs_of(files)
    candidates, others = [], []
    for path in sorted(parsed):
        _, functions = parsed[path]
        defined = {function["name"] for function in functions}
        for function in functions:
            found, gated, owner_docs = cues(function, type_docs)
            row = {"path": path, "line": function["line"], "owner": function["owner"], "name": function["name"],
                   "labels": function["labels"], "visibility": function["visibility"], "result": function["result"],
                   "cues": found, "gated": gated, "doc": function["doc"], "owner_doc": owner_docs,
                   "text": function["text"], "key": function["key"],
                   "callees": sorted((set(function["calls"]) & defined) - {function["name"]}),
                   "callers": sorted({other["name"] for other in functions
                                      if other is not function and function["name"] in other["calls"]})}
            (candidates if is_candidate(found) else others).append(row)
    return candidates, others


def merge_copies(rows):
    """§1.3: copies (same name, labels and masked body) count once, at the first in group order (decision,
    unmet, wide), then repository (git toplevel), subject, path and line. Every other copy is listed on it."""
    first = collections.OrderedDict()
    order = sorted(rows, key=lambda row: (GROUP_ORDER.get(row.get("group"), 0), row.get("toplevel", ""),
                                          row.get("repo", ""), row["path"], row["line"]))
    for row in order:
        where = f"{row.get('repo', '')}:{row['path']}:{row['line']}".lstrip(":")
        if row["key"] in first:
            first[row["key"]]["copies"].append(where)
        else:
            first[row["key"]] = dict(row, copies=[])
    return list(first.values())


# ── Files (§2) ────────────────────────────────────────────────────────────────────────────────────
def skip_reason(component):
    if component.startswith("."):
        return "hidden"
    if component in SKIP_EXACT:
        return component
    if component.lower() in SKIP_FOLDED:
        return component.lower()
    if component.endswith("UITests"):
        return "*UITests"
    if component.endswith("Tests"):
        return "*Tests"
    return None


def subject_files(subject_root, roots):
    """`({realpath: text}, skipped)`, with §2's skip rule on each directory component below the subject root."""
    files, skipped, seen_skipped = {}, collections.Counter(), set()
    for root in roots:
        for current, _, names in os.walk(root):
            relative = os.path.relpath(current, subject_root)
            parts = [] if relative == "." else relative.split(os.sep)
            reasons = [reason for part in parts if (reason := skip_reason(part))]
            for name in names:
                if not name.endswith(".swift"):
                    continue
                path = os.path.realpath(os.path.join(current, name))
                if reasons:
                    if path not in seen_skipped:
                        seen_skipped.add(path)
                        skipped[reasons[0]] += 1
                    continue
                if path not in files:
                    try:
                        files[path] = open(path, encoding="utf-8", errors="ignore").read()
                    except OSError:
                        skipped["unreadable"] += 1
    return files, dict(skipped)


def git(root, *arguments):
    out = subprocess.run(["git", "-C", root, *arguments], capture_output=True, text=True)
    return out.stdout.strip() if out.returncode == 0 else None


def origin(root):
    url = (git(root, "remote", "get-url", "origin") or "").lower()
    return re.sub(r"\.git$", "", url).rstrip("/") or None


def toplevel(root):
    """§2's repository: the real path of the git toplevel, or of the root when there is none."""
    return os.path.realpath(git(root, "rev-parse", "--show-toplevel") or root)


def wide_hash():
    text = "\n".join(f"{relative} {url}" for relative, url in sorted(WIDE, key=lambda entry: entry[0].lower()))
    return hashlib.sha256(text.encode()).hexdigest()


def universe():
    """`[(group, name, root, roots)]`: §2's three groups, asserted."""
    found, _ = subjects()
    resolved = {group: [name for g, name, _, _ in found if g == group] for group in FROZEN_UNIVERSE}
    if resolved != FROZEN_UNIVERSE:
        raise SystemExit(f"the universe is not §2's frozen list:\n  resolved {resolved}\n  frozen   {FROZEN_UNIVERSE}")
    uml = [root for g, name, root, _ in found if name == "SwiftUMLStudio"]
    if not uml or not (revision(uml[0]) or "").startswith(SWIFTUMLSTUDIO) or git(uml[0], "status", "--porcelain"):
        raise SystemExit(f"§2 reads SwiftUMLStudio at {SWIFTUMLSTUDIO}, with a clean working tree")
    if wide_hash() != WIDE_SHA256:
        raise SystemExit(f"§2's wide list hashes to {wide_hash()}, not the frozen {WIDE_SHA256}")
    groups = [(("decision" if g in ("manifest", "funnel") else g), name, root, roots) for g, name, root, roots in found]
    for relative, url in WIDE:
        root = os.path.join(HOME, relative)
        if not os.path.isdir(root):
            raise SystemExit(f"§2's wide group lacks {relative}")
        if url is not None and origin(root) != url:
            raise SystemExit(f"§2's wide member {relative} has origin {origin(root)}, not {url}")
        groups.append(("wide", os.path.basename(relative), root, [root]))
    return groups


def corpus_hash():
    text = "\n".join(" ".join(entry) for entry in sorted(CORPUS, key=lambda entry: entry[0].lower()))
    return hashlib.sha256(text.encode()).hexdigest()


def corpus_universe():
    """The corpus scope's §2, asserted: the 18 clones, each at its frozen revision with a clean tree, all in the
    decision group. The witness is not read again; its first-run groups are reported beside (§2.2)."""
    if corpus_hash() != CORPUS_SHA256:
        raise SystemExit(f"the corpus list hashes to {corpus_hash()}, not the frozen {CORPUS_SHA256}")
    groups = []
    for directory, url, sha, _ in CORPUS:
        root = os.path.join(HOME, CORPUS_DIR, directory)
        if not os.path.isdir(root):
            raise SystemExit(f"the corpus lacks {directory}")
        if origin(root) != url or revision(root) != sha or git(root, "status", "--porcelain"):
            raise SystemExit(f"{directory} is not {url} at {sha} with a clean tree")
        groups.append(("decision", directory, root, [root]))
    return groups


# R5 (the corpus scope's §5): a declaration named for a layering role, and which of its functions the cues reach.
ROLE_ENDINGS = {("layerer",), ("layerers",), ("layering",), ("layerings",), ("ranker",), ("rankers",), ("ranking",),
                ("rankings",), ("longest", "path"), ("layer", "assigner"), ("layer", "assignment"), ("rank", "assigner"),
                ("rank", "assignment")}


def is_role(name):
    """A role name ends in one of ROLE_ENDINGS, word by word: `LongestPathLayerer`, never `LayeringStrategy`."""
    found = words(name)
    return any(tuple(found[-len(ending):]) == ending for ending in ROLE_ENDINGS if len(found) >= len(ending))


def type_spans(text):
    """`[(first line, last line, kind, name)]`: every type, extension and protocol declaration with a body, as
    `declarations` finds them."""
    masked, _ = mask(text)
    pairs = brace_pairs(masked)
    spans = []
    for match in DECL.finditer(masked):
        if match.group(1) == "class" and match.group(2) in CLASS_MODIFIED:
            continue
        brace = masked.find("{", match.end())
        if brace < 0 or masked[match.end():brace].count("\n") > 3:
            continue
        end = pairs.get(brace, len(masked) - 1)
        spans.append((text.count("\n", 0, match.start()) + 1, text.count("\n", 0, end) + 1, match.group(1),
                      base_name(match.group(2))))
    return spans


def role_types(files, candidates, others, root, repo):
    """R5 over one subject: `[{repo, path, line, kind, name, functions, candidates}]`, one per role-named
    declaration. Its functions are those whose innermost declaration is it and which are not nested in another
    function; `candidates` names those of them that are candidates. Never judged and never in N."""
    is_candidate_row = {id(row): True for row in candidates}
    rows_by_path = collections.defaultdict(list)
    for row in candidates + others:
        rows_by_path[row["path"]].append(row)
    entries = []
    for path in sorted(files):
        relative = os.path.relpath(path, root)
        spans = type_spans(files[path])
        functions = rows_by_path.get(relative, []) or rows_by_path.get(path, [])
        ranges = [(row["line"], row["line"] + row["text"].count("\n"), row) for row in functions]
        direct = [row for first, _, row in ranges
                  if not any(other is not row and start < first <= stop for start, stop, other in ranges)]
        for first, last, kind, name in spans:
            if not is_role(name):
                continue
            mine = [row for row in direct if first <= row["line"] <= last
                    and min((span for span in spans if span[0] <= row["line"] <= span[1]),
                            key=lambda span: span[1] - span[0]) == (first, last, kind, name)]
            entries.append({"repo": repo, "path": relative, "line": first, "kind": kind, "name": name,
                            "functions": [row["name"] for row in mine],
                            "candidates": [row["name"] for row in mine if is_candidate_row.get(id(row))]})
    return entries


def witness_groups():
    """§2.2: SwiftUMLStudio's LAYERING ∧ EXPRESSIBLE groups as the first run judged them, from its fixtures."""
    here = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fixtures", "layering-law")
    report = json.load(open(os.path.join(here, "census-2026-10-28.json"), encoding="utf-8"))
    judgements = json.load(open(os.path.join(here, "judgements.json"), encoding="utf-8"))
    verdicts = {entry["id"]: final_record(entry) for entry in judgements}
    rows = [row for row in report["candidates"] if row["repo"] == WITNESS and row.get("judged")]
    return tally(rows, verdicts)[1]


WITNESS = "SwiftUMLStudio"
CORPUS_KIND = {directory: kind for directory, _, _, kind in CORPUS}
CORPUS_OWNER = {directory: url.split("/")[-2] for directory, url, _, _ in CORPUS}


# The corpus scope's §4: the kill report it reads, by the sha256 of its JSON with sorted keys.
KILL_ARM_SHA256 = "83aeacfa3ec829f133ef624b9379a1a0252f12ab6ca78f8ee40925bcfc235b0c"


def content_hash(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def body_flags(rows, judgements):
    """The corpus scope's §4: the ids of `rows` whose final verdict is LAYERING and which a judge holding that final
    verdict flagged *body disagrees* — A or B when they agree, the third judge otherwise."""
    by_id = {entry["id"]: entry for entry in judgements}
    flagged = []
    for row in rows:
        entry = by_id.get(row["id"])
        final = final_record(entry) if entry else {}
        if final.get("verdict") != "LAYERING":
            continue
        holders = [entry.get("A"), entry.get("B")] if final is entry.get("A") else [entry.get("C")]
        if any(holder and holder.get("body_disagrees") for holder in holders):
            flagged.append(row["id"])
    return sorted(flagged)


def decide_corpus(report, judgements, kills, witness=None, frozen_kills=True):
    """The corpus scope's §4: §8's `decide` over the corpus, which alone decides, then the lines beside it. Refuses
    a census of another universe or corpus list, and any kill report but the 2026-10-28 one (`frozen_kills`)."""
    if report.get("universe") != "graph-layout corpus" or report.get("corpus_sha256") != CORPUS_SHA256:
        raise SystemExit("decide-corpus reads a run-corpus census of the frozen corpus only")
    if not kills or (frozen_kills and content_hash(kills) != KILL_ARM_SHA256):
        raise SystemExit("decide-corpus reads the 2026-10-28 kill report only")
    outcome, figures, sensitivity = decide(report, judgements, kills)
    witness = witness_groups() if witness is None else witness
    by_id = {row["id"]: row for row in report["candidates"]}
    groups = [[by_id[row_id] for row_id in ids] for ids in figures["groups"]]

    def places(group):
        """Every subject holding a member of the group or a copy of one, first copy first."""
        found = []
        for row in group:
            for repo in [row["repo"]] + [where.split(":", 1)[0] for where in row.get("copies", [])]:
                if repo not in found:
                    found.append(repo)
        return found

    layout = [next(repo for repo in places(group) if CORPUS_KIND.get(repo) == "layout") for group in groups
              if any(CORPUS_KIND.get(repo) == "layout" for repo in places(group))]
    first_repos = [group[0]["repo"] for group in groups]
    owner_named = {(CORPUS_OWNER.get(group[0]["repo"], group[0]["repo"]), group[0]["name"]) for group in groups}
    by_judgement = {entry["id"]: entry for entry in judgements}
    judged = [row for row in report["candidates"] if row.get("judged") and row["group"] == "decision"]
    beside = {
        "with_witness": {"N": figures["N"] + len(witness),
                         "repositories": figures["repositories"] + len(toplevels(witness))},
        "layout_only": {"N": len(layout), "repositories": len(set(layout))},
        "by_kind": {kind: sum(CORPUS_KIND.get(repo) == kind for repo in first_repos)
                    for kind in ("layout", "dependency", "commit")},
        "owners": len({CORPUS_OWNER.get(repo, repo) for repo in first_repos}),
        "owner_merged": {"N": len(owner_named), "owners": len({owner for owner, _ in owner_named})},
        "verdicts": dict(collections.Counter(final_record(by_judgement[row["id"]])["verdict"] for row in judged)),
        "body_disagrees": body_flags(judged, judgements),
    }
    return outcome, figures, sensitivity, beside


def choose(report, cap=DECISION_CAP):
    """§4.1: mark what is judged. Decision and unmet candidates in full, unless decision candidates exceed
    `cap` (DECISION_CAP; the corpus scope's §4 passes None, judging every decision candidate): then every candidate with SHAPE, a doc cue or GATED is judged in full and the rest (the
    NAME ∧ GRAPH-only stratum) is sampled. Wide in full up to WIDE_CAP, else sampled; R4 in full up to R4_CAP,
    else sampled. Each sample is its own `random.Random(SEED)` over the rows sorted by id."""
    def sample(rows, size):
        rows = sorted(rows, key=lambda row: row["id"])
        return rows if len(rows) <= size else random.Random(SEED).sample(rows, size)

    rows = report["candidates"]
    for row in rows:
        full = row["gated"] or row["cues"]["SHAPE"] or row["cues"]["DOC-OWN"] or row["cues"]["DOC-OWNER"]
        row["stratum"] = "full" if full else "name-graph"
    decision = [row for row in rows if row["group"] == "decision"]
    judged = set()
    if cap is not None and len(decision) > cap:
        judged |= {row["id"] for row in decision if row["stratum"] == "full"}
        judged |= {row["id"] for row in sample([r for r in decision if r["stratum"] == "name-graph"], NAME_GRAPH_SAMPLE)}
    else:
        judged |= {row["id"] for row in decision}
    judged |= {row["id"] for row in rows if row["group"] == "unmet"}
    judged |= {row["id"] for row in sample([r for r in rows if r["group"] == "wide"], WIDE_CAP)}
    for row in rows:
        row["judged"] = row["id"] in judged
    r4 = {row["id"] for row in sample(report["probes"]["R4"], R4_CAP)}
    for row in report["probes"]["R4"]:
        row["judged"] = row["id"] in r4


def run(out_path, groups=None):
    """§1–§4 over `groups`, §2's frozen universe by default; `run-corpus` passes the corpus scope's."""
    if not self_test():
        raise SystemExit("a control failed — not reporting candidates")
    by_root = collections.OrderedDict()
    for group, name, root, roots in (universe() if groups is None else groups):
        key = os.path.realpath(root)
        entry = by_root.setdefault(key, {"group": group, "name": name, "root": root, "roots": [], "also": []})
        if entry["name"] != name:
            entry["also"].append(name)
        entry["roots"].extend(roots)
    report = {"subjects": [], "candidates": [], "probes": {"R2": [], "R3": [], "R4": [], "R5": []},
              "wide_sha256": wide_hash(), "universe": "frozen" if groups is None else "graph-layout corpus"}
    if groups is not None:
        report["corpus_sha256"] = corpus_hash()
    # §1.2: an extension's type docs come from the whole repository, every subject sharing its git toplevel.
    read = {key: subject_files(entry["root"], entry["roots"]) for key, entry in by_root.items()}
    tops = {key: toplevel(entry["root"]) for key, entry in by_root.items()}
    repository_docs = collections.defaultdict(lambda: collections.defaultdict(list))
    for key, (files, _) in read.items():
        for name, docs in type_docs_of(files).items():
            repository_docs[tops[key]][name] += docs
    before_copy_merge = []
    for key, entry in by_root.items():
        files, skipped = read[key]
        candidates, others = census(files, repository_docs[tops[key]])
        top = tops[key]
        report["subjects"].append({
            "group": entry["group"], "name": entry["name"], "also": entry["also"], "root": key, "toplevel": top,
            "revision": revision(entry["root"]), "dirty": bool(git(entry["root"], "status", "--porcelain")),
            "files": len(files), "skipped": skipped, "candidates": len(candidates)})
        candidate_paths = {row["path"] for row in candidates}
        for row in candidates + others:
            row["path"] = os.path.relpath(row["path"], key)
            row.update(group=entry["group"], repo=entry["name"], root=key, toplevel=top)
            row["id"] = f"{entry['name']}:{row['path']}:{row['line']}"
        before_copy_merge += candidates
        report["probes"]["R5"] += role_types(files, candidates, others, key, entry["name"])
        for row in others:
            if os.path.join(key, row["path"]) in candidate_paths:
                report["probes"]["R2"].append(row["id"])
            if entry["group"] == "decision" and row["cues"]["SHAPE"] and row["cues"]["GRAPH"]:
                report["probes"]["R4"].append(row)
    report["candidates_before_copy_merge"] = len(before_copy_merge)
    report["candidates"] = merge_copies(before_copy_merge)
    for row in report["candidates"]:
        if row["group"] == "decision" and not row["cues"]["NAME"] and (row["cues"]["DOC-OWN"] or row["cues"]["DOC-OWNER"]):
            report["probes"]["R3"].append(row["id"])
    choose(report, DECISION_CAP if groups is None else None)
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=1, sort_keys=True)
    for group in ("decision", "unmet", "wide"):
        rows = [row for row in report["candidates"] if row["group"] == group]
        repos = collections.Counter(row["repo"] for row in rows)
        print(f"  {group}: {len(rows)} candidates over {len(repos)} subjects, {sum(r['judged'] for r in rows)} judged"
              f"  {dict(repos.most_common(6))}")
    print(f"  R4: {len(report['probes']['R4'])} rows, {sum(r['judged'] for r in report['probes']['R4'])} judged;"
          f" R3: {len(report['probes']['R3'])}; before the copy merge {report['candidates_before_copy_merge']}")
    print(f"  R5: {len(report['probes']['R5'])} role-named declarations (a list to read, not a figure)")


def packets(census_path, out_dir):
    """§4: blind packets, seeded order, at most eight rows each. A packet holds the function's text, its docs,
    its owner, its location and its same-file one-hop callers and callees; never its cues, GATED, group,
    stratum, the predictions, the decision rule or any count."""
    report = json.load(open(census_path, encoding="utf-8"))
    rows = [row for row in report["candidates"] + report["probes"]["R4"] if row.get("judged")]
    rows.sort(key=lambda row: row["id"])
    random.Random(SEED).shuffle(rows)
    os.makedirs(out_dir, exist_ok=True)
    index = []
    for number in range(0, len(rows), PACKET_SIZE):
        chunk = rows[number:number + PACKET_SIZE]
        name = f"packet-{number // PACKET_SIZE + 1:02d}"
        parts = [f"# {name}\n"]
        for position, row in enumerate(chunk, 1):
            label = f"{name}/{position}"
            index.append({"label": label, "id": row["id"]})
            parts.append(
                f"## {label}\n\n- repository: `{row['repo']}`, at `{row['root']}`\n- file: `{row['path']}`, line {row['line']}\n"
                f"- owner: `{row['owner'] or '(top level)'}`\n"
                f"- owner's doc comment: {row['owner_doc'] or '(none)'}\n"
                f"- the function's doc comment: {row['doc'] or '(none)'}\n"
                f"- same-file functions it calls: {', '.join(row['callees']) or '(none)'}\n"
                f"- same-file functions that call it: {', '.join(row['callers']) or '(none)'}\n\n"
                f"```swift\n{row['text']}\n```\n")
        with open(os.path.join(out_dir, f"{name}.md"), "w", encoding="utf-8") as handle:
            handle.write("\n".join(parts))
    with open(os.path.join(out_dir, "index.json"), "w", encoding="utf-8") as handle:
        json.dump(index, handle, indent=1)
    print(f"{len(rows)} rows in {(len(rows) + PACKET_SIZE - 1) // PACKET_SIZE} packets → {out_dir}")


# ── The judgements and the decision (§4.3, §4.5, §8) ──────────────────────────────────────────────
BAR_COUNT, BAR_REPOSITORIES, GATE_PRECISION_BAR = 5, 2, 0.70


def join(index, workflow):
    """§4.3: the judge workflow's labelled records, joined to row ids through `packets`' index. Refuses a failed
    calibration, and any unknown, duplicated or missing label."""
    if not (workflow.get("calibration") or {}).get("passed"):
        raise SystemExit("the calibration did not pass (§4.2): no judgements are joined")
    ids = {entry["label"]: entry["id"] for entry in index}
    if len(ids) != len(index):
        raise SystemExit("the packet index repeats a label")
    labels = [entry["label"] for entry in workflow["judgements"]]
    unknown, repeated = set(labels) - set(ids), {label for label in labels if labels.count(label) > 1}
    missing = set(ids) - set(labels)
    if unknown or repeated or missing:
        raise SystemExit(f"labels: unknown {sorted(unknown)}, repeated {sorted(repeated)}, missing {sorted(missing)}")
    return [dict(entry, id=ids[entry["label"]]) for entry in workflow["judgements"]]


def _usable(record):
    """A judge's record, with a LAYERING verdict that does not say whether it is EXPRESSIBLE read as no answer."""
    if not record or (record["verdict"] == "LAYERING" and not isinstance(record.get("expressible"), bool)):
        return None
    return record


def final_record(entry):
    """§4.3: the two judges' record where they agree on the verdict and on EXPRESSIBLE; else the third's. A
    record left without a usable verdict is UNDETERMINED."""
    first, second, third = (_usable(entry.get(judge)) for judge in ("A", "B", "C"))
    if first and second and first["verdict"] == second["verdict"] and (
            first["verdict"] != "LAYERING" or first["expressible"] == second["expressible"]):
        return first
    return third or {"verdict": "UNDETERMINED", "reason": "no usable third verdict"}


def layering_groups(rows):
    """§4.5: LAYERING rows merged with same-file LAYERING rows they call or that call them, transitively.
    Returns groups as lists of rows, each sorted, the first row being the group's first copy."""
    parent = {row["id"]: row["id"] for row in rows}

    def find(item):
        while parent[item] != item:
            parent[item] = parent[parent[item]]
            item = parent[item]
        return item

    by_place = collections.defaultdict(list)
    for row in rows:
        by_place[(row["repo"], row["path"])].append(row)
    for siblings in by_place.values():
        names = {row["name"]: row for row in siblings}
        for row in siblings:
            for other in row.get("callees", []) + row.get("callers", []):
                if other in names:
                    parent[find(row["id"])] = find(names[other]["id"])
    groups = collections.defaultdict(list)
    for row in rows:
        groups[find(row["id"])].append(row)
    order = lambda row: (GROUP_ORDER.get(row["group"], 0), row["toplevel"], row["repo"], row["path"], row["line"])  # noqa: E731
    return sorted((sorted(members, key=order) for members in groups.values()), key=lambda g: order(g[0]))


def tally(rows, verdicts):
    """`(groups, expressible_groups)` among `rows` judged LAYERING."""
    layering = [dict(row, record=verdicts[row["id"]]) for row in rows
                if verdicts.get(row["id"], {}).get("verdict") == "LAYERING"]
    groups = layering_groups(layering)
    return groups, [group for group in groups if any(row["record"].get("expressible") for row in group)]


def toplevels(groups):
    return {group[0]["toplevel"] for group in groups}


def decide(report, judgements, kills):
    """§8, from the census report, the joined judgements (`[{id, A, B, C}]`) and the kill arm's report. Refuses
    unless every judged row (candidates and R4) has exactly one judgement."""
    judged_ids = sorted(row["id"] for row in report["candidates"] + report["probes"]["R4"] if row.get("judged"))
    judgement_ids = sorted(entry["id"] for entry in judgements)
    if judged_ids != judgement_ids:
        raise SystemExit(f"judgements do not match the judged rows: missing "
                         f"{sorted(set(judged_ids) - set(judgement_ids))[:5]}, extra "
                         f"{sorted(set(judgement_ids) - set(judged_ids))[:5]}")
    verdicts = {entry["id"]: final_record(entry) for entry in judgements}
    verdict = lambda row: verdicts.get(row["id"], {}).get("verdict")  # noqa: E731
    judged = [row for row in report["candidates"] if row.get("judged")]
    decision = [row for row in judged if row["group"] == "decision"]
    groups_any, groups = tally(decision, verdicts)
    gated_groups = [group for group in groups if any(row["gated"] for row in group)]
    gated = [row for row in decision if row["gated"]]
    precision = sum(verdict(row) == "LAYERING" for row in gated) / len(gated) if gated else None
    undetermined = [row for row in decision if verdict(row) == "UNDETERMINED"]
    unmet = tally([row for row in judged if row["group"] == "unmet"], verdicts)[1]
    wide = tally([row for row in judged if row["group"] == "wide"], verdicts)[1]
    wide_total = sum(row["group"] == "wide" for row in report["candidates"])
    wide_judged = sum(row["group"] == "wide" for row in judged)
    r4_groups = tally([row for row in report["probes"]["R4"] if row.get("judged")], verdicts)[1]
    # The NAME ∧ GRAPH-only stratum, when sampled: its unjudged rows, at the judged rows' LAYERING ∧ EXPRESSIBLE rate.
    stratum = [row for row in report["candidates"] if row["group"] == "decision" and row["stratum"] == "name-graph"]
    stratum_judged = [row for row in stratum if row.get("judged")]
    unjudged = [row for row in stratum if not row.get("judged")]
    extrapolated = None
    if unjudged and stratum_judged:
        hits = sum(verdict(row) == "LAYERING" and verdicts[row["id"]].get("expressible") for row in stratum_judged)
        extrapolated = round(hits / len(stratum_judged) * len(unjudged), 1)
    summary = (kills or {}).get("summary")
    controls_ok = bool(kills) and all((kills.get("controls_passed") or {"none": False}).values())
    expressible_rows = [row for group in groups for row in group if row["record"].get("expressible")]
    figures = {
        "N": len(groups), "repositories": len(toplevels(groups)),
        "unmerged": sum(1 + len(row.get("copies", [])) for row in expressible_rows),
        "N_without_expressible": len(groups_any), "N_gated": len(gated_groups),
        "gated_repositories": len(toplevels(gated_groups)), "gated_rows": len(gated),
        "gate_precision": None if precision is None else round(precision, 3),
        "gated_not_layering": sorted(row["id"] for row in gated if verdict(row) != "LAYERING"),
        "N_undetermined": len(undetermined), "undetermined_gated": sum(row["gated"] for row in undetermined),
        "N_unmet": len(unmet), "N_wide": len(wide), "wide_judged": wide_judged, "wide_candidates": wide_total,
        "N_wide_estimate": round(len(wide) * wide_total / wide_judged, 1) if wide_judged and wide_judged < wide_total
        else None,
        "R4_layering": len(r4_groups), "stratum_extrapolated": extrapolated,
        "decisive": summary["decisive_law_only_assertion_kills"] if summary else None,
        "groups": [[row["id"] for row in group] for group in groups],
        "body_disagrees": sorted(row_id for row_id, record in verdicts.items() if record.get("body_disagrees")),
    }
    if figures["N"] < BAR_COUNT or figures["repositories"] < BAR_REPOSITORIES:
        outcome = "DECLINE (population)"
    elif figures["N_gated"] < BAR_COUNT or figures["gated_repositories"] < BAR_REPOSITORIES:
        outcome = "DECLINE (signal)"
    elif precision is None or precision < GATE_PRECISION_BAR:
        outcome = "DECLINE (gate precision)"
    elif not summary or not controls_ok:
        outcome = "UNMEASURED (kills)"
    elif figures["decisive"] == 0:
        outcome = "DECLINE (kills)"
    else:
        outcome = "BUILD"

    def clears(count, repos):
        return count >= BAR_COUNT and len(repos) >= BAR_REPOSITORIES

    sensitivity = []
    if outcome == "DECLINE (population)":
        base = toplevels(groups)
        wide_count = figures["N_wide_estimate"] if figures["N_wide_estimate"] is not None else len(wide)
        if clears(len(groups) + len(unmet) + wide_count, base | toplevels(unmet) | toplevels(wide)):
            sensitivity.append("the universe's boundary: N + N_unmet + N_wide clears the bar")
        if clears(len(groups) + len(undetermined), base | {row["toplevel"] for row in undetermined}):
            sensitivity.append("unsettled verdicts: N + N_undetermined clears the bar")
        if clears(len(groups) + len(r4_groups), base | toplevels(r4_groups)):
            sensitivity.append("the cues: N + R4's LAYERING groups clears the bar")
        # An upper bound on the repositories: any unjudged row's might hold a layering.
        if extrapolated is not None and clears(len(groups) + extrapolated, base | {row["toplevel"] for row in unjudged}):
            sensitivity.append("the sample: the NAME ∧ GRAPH-only stratum, extrapolated, clears the bar")
    if outcome == "DECLINE (signal)":
        undetermined_gated = [row for row in undetermined if row["gated"]]
        if clears(len(gated_groups) + len(undetermined_gated),
                  toplevels(gated_groups) | {row["toplevel"] for row in undetermined_gated}):
            sensitivity.append("unsettled verdicts: N_gated + undetermined GATED rows clears the bar")
    return outcome, figures, sensitivity


def decision_line(outcome, figures, kills):
    summary = (kills or {}).get("summary") or {}
    decisive = summary.get("law_only_vs_reduced", [])
    assertion = [row for row in decisive if row["mechanism"] == "ASSERTION"]
    precision = "n/a" if figures["gate_precision"] is None else f"{figures['gate_precision']:.0%}"
    wide = str(figures["N_wide"])
    if figures["N_wide_estimate"] is not None:
        wide += (f" ({figures['wide_judged']} of {figures['wide_candidates']} judged;"
                 f" est. {figures['N_wide_estimate']})")
    return (f"DECISION: {outcome}  N = {figures['N']} over {figures['repositories']} local repositories "
            f"(bar: ≥ 5 across ≥ 2)  N_gated = {figures['N_gated']}  gate precision {precision}\n"
            f"law-only (reduced suite): {len(assertion)} by assertion "
            f"({sum(r['class'] == 'layering' for r in assertion)} layering, "
            f"{sum(r['class'] == 'placement' for r in assertion)} placement), "
            f"{len(decisive) - len(assertion)} by crash/timeout/memory\n"
            f"law-only (full suite): {len(summary.get('law_only_vs_suite', []))}   law {summary.get('law')}, "
            f"suite {summary.get('suite')}, reduced {summary.get('reduced')}, viable {summary.get('viable')}   "
            f"N_unmet {figures['N_unmet']}  N_wide {wide}  N_undetermined {figures['N_undetermined']}")


# ── Controls (§3) ─────────────────────────────────────────────────────────────────────────────────
def _one(source, name=None, others=None):
    """The census of `source` (plus `others`, more files of the same repository), as `{name: row}`."""
    files = {"/repo/A.swift": source}
    files.update(others or {})
    candidates, _ = census(files)
    rows = {row["name"]: row for row in candidates}
    return rows if name is None else rows.get(name)


# The controls' own copies of §1.2's frozen lists, so that dropping a word from the pass's constants fails a
# control instead of silently dropping the control with it.
FROZEN_NAME_WORDS = ("layer", "rank", "tier", "stratify", "topo", "sugiyama", "coffman", "row", "rows", "level",
                     "levels", "depth", "depths", "stratum", "strata")
FROZEN_GRAPH_WORDS = (
    "graph", "graphs", "digraph", "dag", "edge", "edges", "node", "nodes", "vertex", "vertices", "dependency",
    "dependencies", "adjacency", "successor", "successors", "predecessor", "predecessors", "arc", "arcs",
    "parent", "parents", "dependent", "dependents", "deps", "prerequisite", "prerequisites")
FROZEN_DOC_PHRASES = ("longest path", "longest-path", "layering", "layered", "layer assignment", "rank assignment",
                      "sugiyama", "topological", "coffman", "network simplex", "kahn", "critical path")
FROZEN_GATE_PHRASES = ("longest path", "longest-path", "layering", "layered")
FROZEN_SKIPPED = ("Tests", "tests", "test", "validation-test", "FooTests", "FooUITests", ".build", "build",
                  "DerivedData", "checkouts", ".hidden", "Pods", "Carthage", "carthage")


def control_rows():
    """`[(label, passed)]` for C1-C55."""
    checks = []
    row = _one("struct R {\n    static func computeRows(graph: ActivityGraph) -> [Int: Int] { [:] }\n}\n", "computeRows")
    checks.append(("C1 computeRows: NAME, SHAPE, GRAPH", bool(row) and row["cues"]["NAME"] == ["rows"]
                   and row["cues"]["SHAPE"] == "[K: I]" and "graph" in row["cues"]["GRAPH"]))
    row = _one("enum C {\n    static func dependencyLevels(for model: ComponentModel) -> [[String]] { [] }\n}\n",
               "dependencyLevels")
    checks.append(("C2 dependencyLevels: candidate, SHAPE [[T]], not GATED",
                   bool(row) and row["cues"]["SHAPE"] == "[[T]]" and not row["gated"]))
    row = _one("func assignLayers(_ g: Graph) -> [String: Int] { [:] }\n", "assignLayers")
    checks.append(("C3 assignLayers: candidate, GATED", bool(row) and row["gated"]))
    row = _one("func rank(of node: Node, in dag: DAG) -> Int { 0 }\n", "rank")
    checks.append(("C4 rank(of:in:): NAME ∧ GRAPH, GATED",
                   bool(row) and not row["cues"]["SHAPE"] and row["cues"]["GRAPH"] and row["gated"]))
    row = _one("func topologicalSort(_ nodes: [Item]) -> [Item] { nodes }\n", "topologicalSort")
    checks.append(("C5 topologicalSort: NAME ∧ GRAPH", bool(row) and row["cues"]["GRAPH"] == ["nodes"]))
    row = _one("func depthFirstSearch(from start: Int) -> [Int] { [] }\n", "depthFirstSearch")
    checks.append(("C6 depthFirstSearch: NAME ∧ SHAPE [I], not GATED",
                   bool(row) and row["cues"]["SHAPE"] == "[I]" and not row["gated"]))
    checks.append(("C7 indentationLevel(for:) -> Int: not a candidate",
                   _one("func indentationLevel(for line: String) -> Int { 0 }\n", "indentationLevel") is None))
    checks.append(("C8 rows(in:) -> [Row]: not a candidate",
                   _one("func rows(in table: Table) -> [Row] { [] }\n", "rows") is None))
    checks.append(("C9 strategy(for:): not a candidate",
                   _one("func strategy(for edges: [Edge]) -> Plan { Plan() }\n", "strategy") is None))
    doc_type = "/// Uses a simple longest-path layering: each node gets a row.\nstruct R {\n"
    row = _one(doc_type + "    static func place(_ g: G) -> [Int: Int] { [:] }\n}\n", "place")
    checks.append(("C10 type doc + SHAPE: DOC-OWNER candidate, GATED (the computeColumns look-alike)",
                   bool(row) and row["cues"]["DOC-OWNER"] and row["gated"] and not row["cues"]["NAME"]))
    row = _one("extension R {\n    static func place(_ g: G) -> [Int: Int] { [:] }\n}\n", "place",
               {"/repo/B.swift": doc_type + "    let x = 1\n}\n"})
    checks.append(("C11 extension reaches the same-name type's doc", bool(row) and row["gated"]))
    row = _one("/// Returns modules in topological order.\nfunc ordered(_ m: [M]) -> [M] { m }\n", "ordered")
    checks.append(("C12 own doc 'topological': DOC-OWN candidate", bool(row) and row["cues"]["DOC-OWN"]))
    checks.append(("C13 type doc + plain member: not a candidate",
                   _one(doc_type + "    func title() -> String { \"\" }\n}\n", "title") is None))
    body = "struct R {\n    static func computeRows(graph: ActivityGraph) -> [Int: Int] { [:] }\n}\n"
    candidates, _ = census({"/repo/A.swift": body, "/repo/vendor/A.swift": body})
    merged = merge_copies(candidates)
    checks.append(("C14 copies in one repository merge, both listed",
                   len(merged) == 1 and merged[0]["copies"] == ["/repo/vendor/A.swift:2"]))
    with tempfile.TemporaryDirectory() as tree:
        # Each skipped name gets its own parent: `tests` and `Tests` are one folder on a case-insensitive disk.
        folders = [f"part{index}/{folder}" for index, folder in enumerate(FROZEN_SKIPPED)]
        for folder in folders + ["Sources", "Sources/Testing"]:
            os.makedirs(os.path.join(tree, folder), exist_ok=True)
            with open(os.path.join(tree, folder, "R.swift"), "w", encoding="utf-8") as handle:
                handle.write(body)
        files, skipped = subject_files(tree, [tree])
        kept = sorted(os.path.relpath(os.path.dirname(path), os.path.realpath(tree)) for path in files)
    checks.append(("C15 every §2 skip name is skipped; Sources/ and Sources/Testing/ are read",
                   kept == ["Sources", "Sources/Testing"] and sum(skipped.values()) == len(FROZEN_SKIPPED)))
    checks.append(("C16 a declaration in a comment or a string is not a candidate",
                   _one("// func computeRows(graph: G) -> [Int: Int] { }\n"
                        "let s = \"func computeRows(graph: G) -> [Int: Int] { }\"\n") == {}))
    row = _one("func layerOf(_ n: Node) -> CALayer { CALayer() }\n", "layerOf")
    checks.append(("C17 layerOf(_ n: Node) -> CALayer: candidate, GATED", bool(row) and row["gated"]))
    checks.append(("C17b layerOf(_ n: N) -> CALayer: not a candidate",
                   _one("func layerOf(_ n: N) -> CALayer { CALayer() }\n", "layerOf") is None))
    row = _one("/** Ranks nodes by a longest-path layering. */\nfunc place(_ g: G) -> Plan { Plan() }\n", "place")
    checks.append(("C18 a /** */ own doc counts", bool(row) and row["cues"]["DOC-OWN"] and row["gated"]))
    row = _one("func levels(of graph: Graph) throws -> Swift.Dictionary<Node, Swift.Int>? { nil }\n", "levels")
    checks.append(("C19 throws + Optional + Dictionary<K, Swift.Int> is SHAPE",
                   bool(row) and row["cues"]["SHAPE"] == "[K: I]"))
    # C20: every NAME word and prefix makes a candidate with GRAPH; near misses do not.
    for word in FROZEN_NAME_WORDS:
        checks.append((f"C20 NAME '{word}'", _one(f"func {word}Of(graph: Graph) -> Plan {{ Plan() }}\n") != {}))
    for word in ("layout", "rowan", "strategy", "deep", "leveler", "longest"):
        checks.append((f"C20 not NAME '{word}'", _one(f"func {word}Of(graph: Graph) -> Plan {{ Plan() }}\n") == {}))
    row = _one("func longestPathLengths(in graph: Graph) -> [Node: Int] { [:] }\n", "longestPathLengths")
    checks.append(("C20 NAME pair 'longest path'", bool(row) and "longest path" in row["cues"]["NAME"]))
    checks.append(("C20 not NAME 'path longest'",
                   _one("func pathLongestOf(graph: Graph) -> Plan { Plan() }\n") == {}))
    # C21: every GRAPH word, in a parameter label, makes a NAME function a candidate; the owner's name and the
    # result's text count too.
    for word in FROZEN_GRAPH_WORDS:
        checks.append((f"C21 GRAPH '{word}'", _one(f"func rowsOf({word} value: Int) -> Plan {{ Plan() }}\n") != {}))
    checks.append(("C21 not GRAPH 'table'", _one("func rowsOf(table value: Int) -> Plan { Plan() }\n") == {}))
    checks.append(("C21 GRAPH through the owner's name",
                   _one("struct DependencyGraph {\n    func levels() -> Plan { Plan() }\n}\n") != {}))
    checks.append(("C21 GRAPH through the result's text", _one("func levels() -> [Vertex] { [] }\n") != {}))
    # C22: every DOC phrase makes DOC-OWN; a near miss does not.
    for phrase in FROZEN_DOC_PHRASES:
        checks.append((f"C22 DOC '{phrase}'",
                       _one(f"/// Built by {phrase.upper()} here.\nfunc place() -> Plan {{ Plan() }}\n") != {}))
    checks.append(("C22 not DOC 'longest'", _one("/// The longest one.\nfunc place() -> Plan { Plan() }\n") == {}))
    # C23: GATED is #667's evidence only.
    for word, gated in (("layer", True), ("rank", True), ("tier", False), ("topo", False), ("row", False),
                        ("level", False), ("depth", False), ("sugiyama", False)):
        row = _one(f"func {word}Of(graph: Graph) -> Plan {{ Plan() }}\n", f"{word}Of")
        checks.append((f"C23 '{word}' {'gates' if gated else 'does not gate'}", bool(row) and row["gated"] == gated))
    for phrase in FROZEN_DOC_PHRASES:
        row = _one(f"/// Built by {phrase} here.\nfunc place() -> Plan {{ Plan() }}\n", "place")
        gates = phrase in FROZEN_GATE_PHRASES
        checks.append((f"C23 doc '{phrase}' {'gates' if gates else 'does not gate'}",
                       bool(row) and row["gated"] == gates))
    # C24: SHAPE, spelling by spelling.
    for result, expected in (
            ("[Int: Int]", "[K: I]"), ("[String: UInt8]", "[K: I]"), ("Dictionary<Node, Int>", "[K: I]"),
            ("[Int: [Node]]", "[I: [T]]"), ("[Int: Set<Node>]", "[I: [T]]"), ("Dictionary<Int, [Node]>", "[I: [T]]"),
            ("[String: [Node]]", None),
            ("[[Node]]", "[[T]]"), ("Array<Array<Node>>", "[[T]]"), ("[Array<Node>]", "[[T]]"),
            ("Array<[Node]>", "[[T]]"), ("[Set<Node>]", "[[T]]"), ("[OrderedSet<Node>]", "[[T]]"),
            ("Array<Set<Node>>", "[[T]]"), ("[Int]", "[I]"), ("Array<Int>", "[I]"), ("[Int]?", "[I]"),
            ("(rows: [Int: Int], width: Int)", "[K: I]"), ("[String: String]", None), ("[[Int: Int]]", None),
            ("[Node]", None), ("Int", None), ("Set<Int>", None)):
        checks.append((f"C24 SHAPE {result} → {expected}", shape(result) == expected))
    # C25: DOC-OWNER with NAME alone; C26: an attribute line between a doc and its declaration.
    row = _one(doc_type + "    func rowFor(_ item: Item) -> Int { 0 }\n}\n", "rowFor")
    checks.append(("C25 DOC-OWNER ∧ NAME, no SHAPE or GRAPH", bool(row) and row["cues"]["DOC-OWNER"]))
    row = _one("/// A longest-path layering.\n@inlinable\nfunc place(_ g: G) -> Plan { Plan() }\n", "place")
    checks.append(("C26 an attribute line between doc and declaration", bool(row) and row["cues"]["DOC-OWN"]))
    # C27: `class func` keeps its real owner.
    row = _one(doc_type.replace("struct R", "class R") + "    class func place(_ g: G) -> [Int: Int] { [:] }\n}\n",
               "place")
    checks.append(("C27 class func: owner R, DOC-OWNER, GATED", bool(row) and row["owner"] == "R" and row["gated"]))
    # C28-C30: copies merge across repositories and groups, first in group order; a same body under another
    # name or other labels does not merge.
    # Repository names sort against group order, so a merge by name alone would pick the wide copy.
    rows = [dict(row, group=group, repo=repo) for group, repo in (("wide", "A"), ("decision", "Z"), ("unmet", "M"))
            for row in census({"/x/A.swift": body})[0]]
    merged = merge_copies(rows)
    checks.append(("C28 a copy across groups counts once, at the decision copy",
                   len(merged) == 1 and merged[0]["repo"] == "Z" and len(merged[0]["copies"]) == 2))
    other = body.replace("computeRows(graph:", "computeLanes(graph:").replace("Lanes", "Rows2")
    renamed = census({"/x/A.swift": body, "/x/B.swift": other})[0]
    checks.append(("C29 the same body under another name does not merge", len(merge_copies(renamed)) == 2))
    relabelled = census({"/x/A.swift": body, "/x/B.swift": body.replace("(graph:", "(of graph:")})[0]
    checks.append(("C30 the same body with other labels does not merge", len(merge_copies(relabelled)) == 2))
    # C31: acronyms, underscores and digits split as `words()` splits them.
    row = _one("func depthOf(_ n: DAGNode) -> Plan { Plan() }\n", "depthOf")
    checks.append(("C31 DAGNode → dag, node", bool(row) and row["cues"]["GRAPH"] == ["dag", "node"]))
    checks.append(("C31 layer_2Of: NAME through an underscore and a digit",
                   _one("func layer_2Of(graph: Graph) -> Plan { Plan() }\n") != {}))
    # C32: one-hop same-file callers and callees.
    hop = _one("enum C {\n    static func levels(graph: G) -> [[N]] { depths(graph) }\n"
               "    static func depths(_ g: G) -> [N: Int] { [:] }\n    func draw() { _ = levels(graph: g) }\n}\n")
    checks.append(("C32 callees and callers, same file",
                   hop.get("levels", {}).get("callees") == ["depths"] and hop["levels"]["callers"] == ["draw"]
                   and hop["depths"]["callers"] == ["levels"]))
    # C33: R4's row, SHAPE ∧ GRAPH with no NAME and no DOC, is not a candidate but is kept.
    candidates, others = census({"/x/A.swift": "func generations(of graph: Graph) -> [[Node]] { [] }\n"})
    checks.append(("C33 SHAPE ∧ GRAPH without NAME: not a candidate, an R4 row",
                   not candidates and others[0]["cues"]["SHAPE"] == "[[T]]" and others[0]["cues"]["GRAPH"]))
    # C34-C35: choose() judges what §4.1 says, sampling only above its caps.
    def fake(group, index, stratum, gated=False):
        cues_ = {"SHAPE": None, "DOC-OWN": [], "DOC-OWNER": [], "NAME": ["rows"], "GRAPH": ["graph"]}
        if stratum == "full":
            cues_["SHAPE"] = "[K: I]"
        return {"id": f"{group}-{index:04d}", "group": group, "cues": cues_, "gated": gated}
    small = {"candidates": [fake("decision", i, "name-graph") for i in range(60)] + [fake("wide", i, "full") for i in range(70)],
             "probes": {"R4": [fake("decision", i, "full") for i in range(5)]}}
    choose(small)
    checks.append(("C34 under the decision cap every decision row is judged; wide over its cap is sampled to 60;"
                   " R4 under its cap in full",
                   all(r["judged"] for r in small["candidates"] if r["group"] == "decision")
                   and sum(r["judged"] for r in small["candidates"] if r["group"] == "wide") == 60
                   and all(r["judged"] for r in small["probes"]["R4"])))
    under = {"candidates": [fake("wide", i, "full") for i in range(50)], "probes": {"R4": [fake("decision", i, "full")
                                                                                         for i in range(45)]}}
    choose(under)
    checks.append(("C34 wide under its cap in full; R4 over its cap sampled to 40",
                   all(r["judged"] for r in under["candidates"])
                   and sum(r["judged"] for r in under["probes"]["R4"]) == 40))
    big = {"candidates": [fake("decision", i, "full") for i in range(200)]
           + [fake("decision", 1000 + i, "name-graph") for i in range(200)]
           + [fake("decision", 2000 + i, "name-graph", gated=True) for i in range(10)],
           "probes": {"R4": []}}
    choose(big)
    checks.append(("C35 over the decision cap: SHAPE/DOC/GATED rows in full, 40 NAME ∧ GRAPH-only rows sampled",
                   sum(r["judged"] for r in big["candidates"] if r["stratum"] == "full") == 210
                   and all(r["judged"] for r in big["candidates"] if r["gated"])
                   and sum(r["judged"] for r in big["candidates"] if r["stratum"] == "name-graph") == 40))
    # C36: the wide list is the frozen one.
    checks.append(("C36 the wide list hashes to §2's WIDE_SHA256", wide_hash() == WIDE_SHA256 and len(WIDE) == 67))
    # C37: GATED reads a type doc's phrase on a SHAPE member that the NAME rule would not admit — the
    # computeColumns case, reported for gate precision (§8), not filtered.
    row = _one(doc_type + "    static func computeColumns(graph: G, rows: [Int: Int]) -> [Int: Int] { [:] }\n}\n",
               "computeColumns")
    checks.append(("C37 computeColumns under a layering doc: candidate, GATED", bool(row) and row["gated"]))
    # C46: `class` before each modifier is not a type, so a function inside that declaration keeps its owner.
    for modifier in ("func", "var", "let", "subscript", "init", "override", "final", "static", "private",
                     "fileprivate", "internal", "public", "open", "package", "convenience", "required", "deinit"):
        snippet = (f"class R {{\n    class {modifier} thing {{\n        func layerOf(graph: Graph) -> Plan {{ Plan() }}\n"
                   f"    }}\n}}\n")
        row = _one(snippet, "layerOf")
        checks.append((f"C46 `class {modifier}` is a modifier: the owner stays R", bool(row) and row["owner"] == "R"))
    # C47: an extension reaches the doc of a same-name class, enum and actor too.
    for kind in ("class", "enum", "actor"):
        row = _one("extension R {\n    static func place(_ g: G) -> [Int: Int] { [:] }\n}\n", "place",
                   {"/repo/B.swift": doc_type.replace("struct R", f"{kind} R") + "    let x = 1\n}\n"})
        checks.append((f"C47 an extension reaches a same-name {kind}'s doc", bool(row) and row["gated"]))
    # C48: every integer spelling, bare and `Swift.`-qualified.
    for integer in ("Int", "UInt", "Int8", "Int16", "Int32", "Int64", "UInt8", "UInt16", "UInt32", "UInt64"):
        checks.append((f"C48 SHAPE [Node: {integer}]", shape(f"[Node: {integer}]") == "[K: I]"
                       and shape(f"[Swift.{integer}]") == "[I]"))
    # C49: a blank line between a doc and its declaration; a phrase split by two spaces.
    row = _one("/// A longest-path layering.\n\nfunc place(_ g: G) -> Plan { Plan() }\n", "place")
    checks.append(("C49 a blank line between doc and declaration", bool(row) and row["cues"]["DOC-OWN"]))
    row = _one("/// A longest  path walk.\nfunc place(_ g: G) -> Plan { Plan() }\n", "place")
    checks.append(("C49 a phrase split by a run of spaces", bool(row) and row["cues"]["DOC-OWN"] == ["longest path"]))
    # C50: a plain `/* */` comment is not a doc, even below an earlier `/** */`.
    checks.append(("C50 a plain /* */ comment holding a phrase is not a doc",
                   _one("/* A longest-path layering, scratch. */\nfunc place(_ g: G) -> Plan { Plan() }\n", "place") is None))
    checks.append(("C50 a plain /* */ comment after an earlier /** */ block is not a doc",
                   _one("/** A longest-path layering of the module. */\nstruct Other {}\n"
                        "/* scratch note */\nfunc place(_ g: G) -> Plan { Plan() }\n", "place") is None))
    # C51: a copy in unmet and in wide counts at the unmet copy, whatever the repositories' order.
    rows = [dict(row, group=group, repo=repo, toplevel=f"/{repo}") for group, repo in (("wide", "A"), ("unmet", "Z"))
            for row in census({"/x/A.swift": body})[0]]
    merged = merge_copies(rows)
    checks.append(("C51 a copy in unmet and wide counts at the unmet copy", len(merged) == 1 and merged[0]["repo"] == "Z"))
    checks += decision_controls()
    return checks


def decision_controls():
    """C38-C45 and C52-C55: §4.3's join and final record, §4.5's merge, §8's outcomes and sensitivity lines, on
    synthetic census rows, judgements and kill reports."""
    def row(repo, name, gated=True, group="decision", path="A.swift", callees=(), callers=(), stratum="full",
            judged=True):
        return {"id": f"{repo}:{path}:{name}", "repo": repo, "toplevel": f"/{repo}", "path": path, "line": len(name),
                "name": name, "group": group, "gated": gated, "judged": judged, "stratum": stratum,
                "callees": list(callees), "callers": list(callers)}

    def votes(verdict, expressible=True, third=None):
        first = {"verdict": verdict, "expressible": expressible}
        if third is None:
            return {"A": first, "B": dict(first), "C": None}
        return {"A": first, "B": {"verdict": "NOT-LAYERING"}, "C": third or None}

    def judge(rows, verdict="LAYERING", **extra):
        return [dict(votes(verdict, **extra), id=r["id"]) for r in rows]

    kills_build = {"controls_passed": {f"RC{n}": True for n in range(1, 8)},
                   "summary": {"decisive_law_only_assertion_kills": 1}}
    kills_none = dict(kills_build, summary={"decisive_law_only_assertion_kills": 0})
    rows = [row(f"R{n % 2}", f"layers{n}", path=f"F{n}.swift") for n in range(5)]
    checks = []

    def outcome(candidates, judgements, kills, r4=()):
        return decide({"candidates": candidates, "probes": {"R4": list(r4)}}, judgements, kills)

    def refuses(call):
        try:
            call()
        except SystemExit:
            return True
        return False

    checks.append(("C38 five LAYERING groups over two repositories, gated, precise, a decisive kill: BUILD",
                   outcome(rows, judge(rows), kills_build)[0] == "BUILD"))
    checks.append(("C38 four groups: DECLINE (population)",
                   outcome(rows[:4], judge(rows[:4]), kills_build)[0] == "DECLINE (population)"))
    one_repo = [dict(r, toplevel="/R0") for r in rows]
    decided, _, sensitivity = outcome(one_repo, judge(one_repo), kills_build)
    checks.append(("C38 five groups in one repository: DECLINE (population), and no sensitivity line",
                   decided == "DECLINE (population)" and sensitivity == []))
    ungated = [dict(r, gated=n < 4) for n, r in enumerate(rows)]
    checks.append(("C39 four gated groups: DECLINE (signal)",
                   outcome(ungated, judge(ungated), kills_build)[0] == "DECLINE (signal)"))
    lookalikes = [row("R0", f"columns{n}", path=f"G{n}.swift") for n in range(3)]
    checks.append(("C40 gate precision 5/8 < 70%: DECLINE (gate precision)",
                   outcome(rows + lookalikes, judge(rows) + judge(lookalikes, "NOT-LAYERING"), kills_build)[0]
                   == "DECLINE (gate precision)"))
    seven = rows + [row(f"R{n % 2}", f"more{n}", path=f"M{n}.swift") for n in range(2)]
    checks.append(("C40 gate precision 7/10 = 70%: passes the gate",
                   outcome(seven + lookalikes, judge(seven) + judge(lookalikes, "NOT-LAYERING"), kills_build)[0]
                   == "BUILD"))
    many = [row(f"R{n % 2}", f"lay{n}", path=f"L{n}.swift") for n in range(69)]
    misses = [row("R0", f"col{n}", path=f"C{n}.swift") for n in range(31)]
    checks.append(("C40 gate precision 69/100 < 70%: DECLINE (gate precision)",
                   outcome(many + misses, judge(many) + judge(misses, "NOT-LAYERING"), kills_build)[0]
                   == "DECLINE (gate precision)"))
    failed_control = dict(kills_build, controls_passed=dict(kills_build["controls_passed"], RC7=False))
    checks.append(("C41 a failed runner control, or no summary: UNMEASURED (kills), never DECLINE (kills)",
                   outcome(rows, judge(rows), failed_control)[0] == "UNMEASURED (kills)"
                   and outcome(rows, judge(rows), dict(kills_build, summary=None))[0] == "UNMEASURED (kills)"
                   and outcome(rows, judge(rows), None)[0] == "UNMEASURED (kills)"))
    checks.append(("C42 no decisive kill: DECLINE (kills)", outcome(rows, judge(rows), kills_none)[0] == "DECLINE (kills)"))
    helper = [row("R0", "levels", path="H.swift", callees=["depth"]), row("R0", "depth", path="H.swift", callers=["levels"]),
              row("R0", "other", path="I.swift", callees=["depth"])]
    _, figures, _ = outcome(helper, judge(helper), kills_build)
    checks.append(("C43 a helper merges with its same-file caller; a namesake in another file does not",
                   figures["N"] == 2 and figures["unmerged"] == 3))
    _, figures, _ = outcome(helper, judge(helper[:1]) + judge(helper[1:2], expressible=False) + judge(helper[2:]),
                            kills_build)
    checks.append(("C43 the unmerged count is the EXPRESSIBLE functions", figures["N"] == 2 and figures["unmerged"] == 2))
    resolved = judge(rows[:4]) + [dict(votes("LAYERING", third={"verdict": "LAYERING", "expressible": True}),
                                       id=rows[4]["id"])]
    checks.append(("C44 the third judge decides a split", outcome(rows, resolved, kills_build)[1]["N"] == 5))
    expressible_split = judge(rows[:4]) + [{"id": rows[4]["id"], "A": {"verdict": "LAYERING", "expressible": True},
                                           "B": {"verdict": "LAYERING", "expressible": False},
                                           "C": {"verdict": "LAYERING", "expressible": False}}]
    checks.append(("C44 an EXPRESSIBLE split goes to the third judge",
                   outcome(rows, expressible_split, kills_build)[1]["N"] == 4))
    split = judge(rows[:4]) + [dict(votes("LAYERING", third={}), id=rows[4]["id"])]
    decided, figures, sensitivity = outcome(rows, split, kills_build)
    checks.append(("C44 a split with no third verdict is UNDETERMINED; N + N_undetermined clearing the bar is flagged",
                   decided == "DECLINE (population)" and figures["N_undetermined"] == 1
                   and any("unsettled" in line for line in sensitivity)))
    unexpressible = judge(rows[:4]) + judge(rows[4:], expressible=False)
    checks.append(("C45 N counts EXPRESSIBLE groups; N without it is reported",
                   outcome(rows, unexpressible, kills_build)[1]["N"] == 4
                   and outcome(rows, unexpressible, kills_build)[1]["N_without_expressible"] == 5))
    silent = judge(rows[:4]) + [{"id": rows[4]["id"], "A": {"verdict": "LAYERING"}, "B": {"verdict": "LAYERING"},
                                 "C": {"verdict": "LAYERING", "expressible": True}}]
    checks.append(("C45 LAYERING without an EXPRESSIBLE answer goes to the third judge",
                   outcome(rows, silent, kills_build)[1]["N"] == 5))
    # C52: decide refuses unless every judged row has exactly one judgement.
    checks.append(("C52 a judged row with no judgement: decide refuses",
                   refuses(lambda: outcome(rows, judge(rows[:4]), kills_build))))
    checks.append(("C52 a judgement for no judged row: decide refuses",
                   refuses(lambda: outcome(rows[:4], judge(rows), kills_build))))
    # C53: the join refuses a failed calibration and any unknown, repeated or missing label.
    index = [{"label": "packet-01/1", "id": "a"}, {"label": "packet-01/2", "id": "b"}]
    good = {"calibration": {"passed": True}, "judgements": [{"label": "packet-01/1"}, {"label": "packet-01/2"}]}
    checks.append(("C53 the join attaches each label's id", [e["id"] for e in join(index, good)] == ["a", "b"]))
    for label, workflow in (
            ("a failed calibration", dict(good, calibration={"passed": False})),
            ("a missing label", dict(good, judgements=good["judgements"][:1])),
            ("a repeated label", dict(good, judgements=good["judgements"] + good["judgements"][:1])),
            ("an unknown label", dict(good, judgements=good["judgements"] + [{"label": "packet-09/1"}]))):
        checks.append((f"C53 the join refuses {label}", refuses(lambda w=workflow: join(index, w))))
    # C54: each sensitivity line fires when its alternative clears both halves of the bar, and only then.
    three = [row(f"R{n % 2}", f"base{n}", path=f"B{n}.swift") for n in range(3)]
    wide = [row(f"W{n}", f"far{n}", group="wide", path=f"W{n}.swift") for n in range(2)]
    _, _, lines = outcome(three + wide, judge(three + wide), kills_build)
    checks.append(("C54 the universe's boundary", any("boundary" in line for line in lines)))
    r4 = [row("R4", f"gen{n}", path=f"R{n}.swift") for n in range(2)]
    _, _, lines = outcome(three, judge(three) + judge(r4), kills_build, r4=r4)
    checks.append(("C54 the cues (R4)", any("the cues" in line for line in lines)))
    sampled = ([row("S", f"s{n}", path=f"S{n}.swift", stratum="name-graph") for n in range(2)]
               + [row(f"T{n}", f"t{n}", path=f"T{n}.swift", stratum="name-graph", judged=False) for n in range(4)])
    _, figures, lines = outcome(three + sampled, judge(three) + judge(sampled[:1]) + judge(sampled[1:2], expressible=False),
                                kills_build)
    checks.append(("C54 the sample: N + the unjudged rows at the judged rate", figures["stratum_extrapolated"] == 2.0
                   and any("the sample" in line for line in lines)))
    _, _, lines = outcome(three, judge(three), kills_build)
    checks.append(("C54 nothing to add: no line", lines == []))
    for gated_count, expect_line in ((3, False), (4, True)):
        signal = [dict(r, gated=n < gated_count) for n, r in enumerate(rows)] + [row("R1", "maybe", path="Q.swift")]
        decided, _, lines = outcome(signal, judge(rows) + [dict(votes("LAYERING", third={}), id="R1:Q.swift:maybe")],
                                    kills_build)
        checks.append((f"C54 signal: {gated_count} GATED groups + 1 undetermined GATED row "
                       f"{'clears' if expect_line else 'does not clear'}",
                       decided == "DECLINE (signal)" and bool(lines) == expect_line))
    # C55: N_wide is an estimate when wide was sampled.
    wide_rows = ([row(f"W{n}", f"w{n}", group="wide", path=f"W{n}.swift") for n in range(2)]
                 + [row(f"V{n}", f"v{n}", group="wide", path=f"V{n}.swift", judged=False) for n in range(2)])
    _, figures, _ = outcome(rows + wide_rows, judge(rows) + judge(wide_rows[:2]), kills_build)
    checks.append(("C55 N_wide from 2 of 4 judged is estimated as 4", figures["N_wide"] == 2
                   and figures["N_wide_estimate"] == 4.0))
    # C56: the corpus list is the frozen one: each directory its origin's owner__repo, each revision a full SHA,
    # ten layout packages, six dependency tools and two commit-graph drawers.
    kinds = collections.Counter(kind for _, _, _, kind in CORPUS)
    checks.append(("C56 the corpus list hashes to CORPUS_SHA256: 18 entries, owner__repo, full SHAs, kinds 10/6/2",
                   corpus_hash() == CORPUS_SHA256 and len(CORPUS) == 18
                   and all(directory.lower() == "__".join(url.split("/")[-2:]) and re.fullmatch(r"[0-9a-f]{40}", sha)
                           for directory, url, sha, _ in CORPUS)
                   and kinds == {"layout": 10, "dependency": 6, "commit": 2}))
    # C57: the corpus alone decides; the witness, the layout-only line, the kinds and the owners are beside it.
    corpus_report = {"universe": "graph-layout corpus", "corpus_sha256": CORPUS_SHA256, "probes": {"R4": []}}

    def corpus(rows, judgements=None, witness_rows=(), kills=kills_build, frozen=False, report=None):
        return decide_corpus(dict(report or corpus_report, candidates=rows),
                             judge(rows) if judgements is None else judgements, kills, list(witness_rows), frozen)

    dagre = [row("lukilabs__dagre-swift", f"layers{n}", path=f"D{n}.swift") for n in range(3)]
    witness = [[row(WITNESS, f"layers{n}", path=f"W{n}.swift")] for n in range(2)]
    decided, figures, _, beside = corpus(dagre, witness_rows=witness)
    checks.append(("C57 three corpus groups and the witness's two: DECLINE (population); with the witness, 5 over 2",
                   decided == "DECLINE (population)" and figures["N"] == 3
                   and beside["with_witness"] == {"N": 5, "repositories": 2}))
    elk = [row("lukilabs__elk-swift", f"layers{n}", path=f"E{n}.swift") for n in range(2)]
    decided, figures, _, beside = corpus(dagre + elk)
    checks.append(("C57 five groups in two lukilabs repositories: the bar clears, and they are one owner",
                   decided == "BUILD" and figures["repositories"] == 2 and beside["owners"] == 1
                   and beside["layout_only"] == {"N": 5, "repositories": 2}))
    spm = [row("getyourguide__spmgraph", f"layers{n}", path=f"S{n}.swift") for n in range(2)]
    decided, figures, _, beside = corpus(dagre + spm)
    checks.append(("C57 three layout and two dependency groups: the bar clears; layout only, 3 over 1",
                   decided == "BUILD" and beside["layout_only"] == {"N": 3, "repositories": 1} and beside["owners"] == 2
                   and beside["by_kind"] == {"layout": 3, "dependency": 2, "commit": 0}
                   and beside["verdicts"] == {"LAYERING": 5}))
    # A group whose first copy is a dependency tool's, with a copy in a layout package, is in the layout line.
    shared = [dict(row("GlitchLoom__SwiftDependencyGraphExplorer", "layersShared", path="G.swift"),
                   copies=["lukilabs__elk-swift:Shared.swift:3"])]
    decided, figures, _, beside = corpus(shared + elk)
    checks.append(("C57 a layout copy puts a dependency tool's first copy in the layout line, at the layout repository",
                   beside["layout_only"] == {"N": 3, "repositories": 1} and beside["by_kind"]["dependency"] == 1))
    # Same-owner groups that share a name count once in the owner-merged line.
    lineage = [row(repo, "longestPath", path=f"{repo}.swift") for repo in
               ("lukilabs__dagre-swift", "lukilabs__elk-swift", "lukilabs__beautiful-mermaid-swift")]
    mermaid = [row("2389-research__MermaidKit", f"layers{n}", path=f"M{n}.swift") for n in range(2)]
    decided, figures, _, beside = corpus(lineage + mermaid)
    checks.append(("C57 three same-name lukilabs groups and two MermaidKit groups: N 5 over 4, owner-merged 3 over 2",
                   figures["N"] == 5 and figures["repositories"] == 4
                   and beside["owner_merged"] == {"N": 3, "owners": 2}))
    checks.append(("C57 decide-corpus refuses a census with neither label nor hash",
                   refuses(lambda: corpus(dagre, report={"probes": {"R4": []}}))))
    checks.append(("C57 decide-corpus refuses the right label with another corpus hash",
                   refuses(lambda: corpus(dagre, report=dict(corpus_report, corpus_sha256="0" * 64)))))
    checks.append(("C57 decide-corpus refuses the right hash under another label",
                   refuses(lambda: corpus(dagre, report=dict(corpus_report, universe="frozen")))))
    checks.append(("C57 decide-corpus refuses a missing kill report", refuses(lambda: corpus(dagre, kills=None))))
    checks.append(("C57 decide-corpus refuses a kill report other than the 2026-10-28 one",
                   refuses(lambda: corpus(dagre, frozen=True))))
    here = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fixtures", "layering-law")
    frozen_kills = json.load(open(os.path.join(here, "kill-arm-2026-10-28.json"), encoding="utf-8"))
    checks.append(("C57 decide-corpus reads the 2026-10-28 kill report: decisive 4, every runner control passed",
                   content_hash(frozen_kills) == KILL_ARM_SHA256
                   and corpus(dagre + elk, kills=frozen_kills, frozen=True)[0] == "BUILD"))
    # body_flags: a flag from either agreeing judge counts; a flag on a row whose final verdict is not LAYERING, or
    # from a judge the third overruled, does not.
    agreed = dict(votes("LAYERING"), id="a")
    agreed["B"] = dict(agreed["B"], body_disagrees=True)
    overruled = {"id": "b", "A": {"verdict": "LAYERING", "expressible": True, "body_disagrees": True},
                 "B": {"verdict": "NOT-LAYERING"}, "C": {"verdict": "LAYERING", "expressible": True}}
    not_layering = {"id": "c", "A": {"verdict": "NOT-LAYERING", "body_disagrees": True},
                    "B": {"verdict": "NOT-LAYERING", "body_disagrees": True}, "C": None}
    checks.append(("C57 body disagrees: B's flag on an agreed LAYERING row counts; an overruled or non-LAYERING flag does not",
                   body_flags([{"id": "a"}, {"id": "b"}, {"id": "c"}], [agreed, overruled, not_layering]) == ["a"]))
    # C58: a role name, by its last words: a layerer or a ranking is one; a strategy, a placer or a view is not.
    for name in ("LongestPathLayerer", "NetworkSimplexLayerer", "CoffmanGrahamLayerer", "MinWidthLayerer", "Layering",
                 "NodeRanker", "GraphRanking", "LongestPath", "LayerAssigner", "LayerAssignment", "RankAssigner",
                 "RankAssignment", "Rankers", "Layerers", "Layerings", "NodeRankings"):
        checks.append((f"C58 {name} is a role name", is_role(name)))
    for name in ("LayeringStrategy", "NetworkSimplexPlacer", "NetworkSimplex", "SimplexNoise", "RankingService",
                 "LongestPathFinder", "PathLongest", "LongestSimplePath", "LayerView", "CALayer", "RankedList",
                 "SugiyamaLayout", "Assignment", "Path", ""):
        checks.append((f"C58 {name or '(top level)'} is not a role name", not is_role(name)))
    # C59: R5 lists every role-named declaration: a class, a protocol, a type with no function, an extension, two
    # namesakes. A function nested in a method or in a nested type is not the type's own; an init is not a function.
    layered = {"/repo/A.swift": ("/** The most basic layering algorithm: layers by longest paths. */\n"
                                  "final class LongestPathLayerer {\n    init(graph: LGraph) { }\n"
                                  "    private struct Frame {\n        func walk(_ node: LNode) { }\n    }\n"
                                  "    func process(_ graph: LGraph) {\n        func visit(_ node: LNode) -> Int { 0 }\n    }\n}\n"
                                  "protocol NodeRanker {\n    func rank(_ graph: Graph) -> [Node: Int]\n}\n"
                                  "final class LayerView {\n    func depth(of node: Node) -> Int { 0 }\n}\n"
                                  "final class Layering {\n    var layers: [[Node]] { [] }\n}\n"
                                  "final class GraphRanking {\n    func process(_ g: G) { }\n}\n"),
               "/repo/B.swift": ("extension LongestPathLayerer {\n    func layers(of graph: Graph) -> [[Node]] { [] }\n}\n"
                                 "final class GraphRanking {\n    func rank(_ graph: Graph) -> [Node: Int] { [:] }\n}\n")}
    roles = role_types(layered, *census(layered), "/repo", "X")
    checks.append(("C59 R5: six role declarations, each with its own functions and candidates",
                   [(entry["repo"], entry["path"], entry["kind"], entry["name"], entry["functions"], entry["candidates"])
                    for entry in roles]
                   == [("X", "A.swift", "class", "LongestPathLayerer", ["process"], []),
                       ("X", "A.swift", "protocol", "NodeRanker", [], []),
                       ("X", "A.swift", "class", "Layering", [], []),
                       ("X", "A.swift", "class", "GraphRanking", ["process"], []),
                       ("X", "B.swift", "extension", "LongestPathLayerer", ["layers"], ["layers"]),
                       ("X", "B.swift", "class", "GraphRanking", ["rank"], ["rank"])]))
    # C60: the corpus judges every decision candidate; §4.1's cap still samples the first scope's universe.
    many = {"candidates": [{"id": f"r{n:03d}", "group": "decision", "gated": False,
                            "cues": {"SHAPE": "", "DOC-OWN": [], "DOC-OWNER": []}} for n in range(400)],
            "probes": {"R4": []}}
    choose(many, None)
    uncapped = sum(r["judged"] for r in many["candidates"])
    choose(many)
    checks.append(("C60 with no cap all 400 decision candidates are judged; with §4.1's cap, 40",
                   uncapped == 400 and sum(r["judged"] for r in many["candidates"]) == 40))
    # C61: the witness line reads the first run's own verdicts: two groups, in one repository.
    witnessed = witness_groups()
    checks.append(("C61 the witness's first-run groups: computeRows, and dependencyLevels with chainDepth",
                   len(witnessed) == 2 and len(toplevels(witnessed)) == 1
                   and sorted(group[0]["name"] for group in witnessed) == ["computeRows", "dependencyLevels"]))
    return checks


def self_test():
    checks = control_rows()
    failed = [label for label, passed in checks if not passed]
    for label in failed:
        print(f"  FAIL {label}")
    print(f"layering census controls: {len(checks) - len(failed)}/{len(checks)} pass")
    return not failed


def main(argv):
    if argv[1:] == ["--self-test"]:
        return 0 if self_test() else 1
    if len(argv) == 3 and argv[1] == "run":
        run(argv[2])
        return 0
    if len(argv) == 4 and argv[1] == "packets":
        packets(argv[2], argv[3])
        return 0
    if len(argv) == 5 and argv[1] == "join":
        joined = join(json.load(open(argv[2], encoding="utf-8")), json.load(open(argv[3], encoding="utf-8")))
        with open(argv[4], "w", encoding="utf-8") as handle:
            json.dump(joined, handle, indent=1)
        print(f"{len(joined)} judgements joined → {argv[4]}")
        return 0
    if len(argv) == 3 and argv[1] == "run-corpus":
        run(argv[2], corpus_universe())
        return 0
    if len(argv) == 5 and argv[1] == "decide":
        report = json.load(open(argv[2], encoding="utf-8"))
        judgements = json.load(open(argv[3], encoding="utf-8"))
        kills = json.load(open(argv[4], encoding="utf-8")) if os.path.exists(argv[4]) else None
        outcome, figures, sensitivity = decide(report, judgements, kills)
        print(decision_line(outcome, figures, kills))
        for line in sensitivity:
            print(f"  sensitivity: the decline rests on {line}")
        print(json.dumps(figures, indent=1))
        return 0
    if len(argv) == 5 and argv[1] == "decide-corpus":
        report = json.load(open(argv[2], encoding="utf-8"))
        judgements = json.load(open(argv[3], encoding="utf-8"))
        kills = json.load(open(argv[4], encoding="utf-8")) if os.path.exists(argv[4]) else None
        outcome, figures, sensitivity, beside = decide_corpus(report, judgements, kills)
        print(decision_line(outcome, figures, kills))
        for line in sensitivity:
            print(f"  sensitivity: the decline rests on {line}")
        print(f"beside: with the witness's first-run groups, N = {beside['with_witness']['N']} over "
              f"{beside['with_witness']['repositories']} repositories; layout packages only, N = "
              f"{beside['layout_only']['N']} over {beside['layout_only']['repositories']}; groups by kind "
              f"{beside['by_kind']}; repositories counted by owner {beside['owners']}; same-owner same-name groups "
              f"merged, N = {beside['owner_merged']['N']} over {beside['owner_merged']['owners']} owners")
        print(f"beside: final verdicts on judged decision candidates {beside['verdicts']}; body disagrees "
              f"{beside['body_disagrees']}")
        for entry in report["probes"].get("R5", []):
            print(f"R5 {entry['repo']}:{entry['path']}:{entry['line']} {entry['kind']} {entry['name']}: functions "
                  f"{entry['functions']}, candidates {entry['candidates']}")
        print(json.dumps(dict(figures, beside=beside), indent=1))
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
