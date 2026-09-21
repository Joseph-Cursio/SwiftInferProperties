#!/usr/bin/env python3
"""Size the THROWING-CODEC shape over named subjects, not over the manifest.

`throwing-codec-census.md` measured this across the 20-corpus manifest and found Shape A once in
172 hand-written encoders — then recorded that **the corpus could not answer the question**,
because none of the four subjects that ever produced a `codable-round-trip` finding is in it. Its
§4 says what would: run the same census over those exhibit subjects, and do **not** add them to
the manifest, because the corpus universe is every other census's denominator.

So this is a SHAPE census over named directories. It shares `measurement.py`'s file walk — and
therefore `EXCLUDED_DIRS`, which drops `Tests` — but takes its subjects as arguments.

## The two shapes, and why they are asymmetric

**Shape A — an encoder that can `throw`.** A *decoder* throwing on malformed input is ordinary
validation and is NOT counted; an *encoder* receives a value that already exists, so an encoder
that can throw is a type admitting values it cannot serialise. That is `UserDetectionStatus`.

**Shape B — `encodeIfPresent` on a key `decode` requires.** The encoder may omit the key and the
decoder demands it.

⚠ **Shape B is REFUTED as a detector on the exhibit subjects: 0 real of 6 hand-checked.** Two of
its false-positive modes are beyond a call-name proxy and are NOT fixed here — a discriminated
union whose arms each pair consistently but share a coding key, and `encodeIfPresent` applied to a
NON-OPTIONAL value, which always writes because Swift promotes `T` to `T?` at the call site.
Its count is kept because the hit list is what a future arm-aware version would be checked
against; **do not read it as a population.**

⚠ **Both are FLOORS, as the original census recorded.** Neither reaches a codec that throws
through a helper, and Shape B's proxy misses the `encode`-writes-null form that its own exhibit
(`CatalogFeatureFlags`) actually uses — catching that needs the property's optionality, not the
call name.

## The control runs first, and the run aborts if it fails

Shape B came back **0** on the manifest, and a detector that finds nothing prints the same figure
as a population that holds nothing — the mistake `module-state-base-rate.md` shipped once. So both
shapes are asserted detectable on synthetic sources before any subject is read.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import measurement  # noqa: E402

ENCODER = re.compile(r"func\s+encode\s*\(\s*to\s+encoder\s*:")
DECODER = re.compile(r"init\s*\(\s*from\s+decoder\s*:")
# `throws`, `throws(E)` or `rethrows` before the body or the return arrow.
THROWING_ENCODER = re.compile(
    r"func\s+encode\s*\(\s*to\s+encoder\s*:[^{]*?\b(?:re)?throws\b")


def _bodies(text, pattern):
    """Each brace-matched body whose declaration `pattern` matches, with its header and position."""
    for match in pattern.finditer(text):
        start = text.find("{", match.end())
        if start < 0:
            continue
        depth, index = 0, start
        while index < len(text):
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
                if depth == 0:
                    break
            index += 1
        yield text[match.start():start], text[start:index + 1], match.start()


def _explicit_throw(body):
    """A `throw` statement the encoder itself makes, not a `try` it propagates.

    ⚠ **`try` is deliberately not counted.** Every container call is `try`, so counting it would
    match every hand-written encoder in existence and report the population as the denominator.
    """
    return re.search(r"\bthrow\s+\w", body) is not None


DECLARATION = re.compile(
    r"\b(?:struct|enum|final class|class|actor|extension)\s+([A-Z_][\w.]*)")


def _type_spans(text):
    """`(name, open_brace, close_brace)` for every type declaration, innermost last."""
    spans = []
    for match in DECLARATION.finditer(text):
        start = text.find("{", match.end())
        if start < 0:
            continue
        depth, index = 0, start
        while index < len(text):
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
                if depth == 0:
                    break
            index += 1
        spans.append((match.group(1), start, index))
    return spans


def _owner(spans, position):
    """The innermost type whose body contains `position`, or `None` at file scope."""
    best = None
    for name, start, end in spans:
        if start < position < end and (best is None or start > best[1]):
            best = (name, start)
    return best[0] if best else None


ENCODE_IF_PRESENT = re.compile(r"encodeIfPresent\s*\(\s*([^,()]+?)\s*,\s*forKey:\s*\.(\w+)")
DECODE_REQUIRED = re.compile(r"(?<!IfPresent)\bdecode\s*\([^,()]+,\s*forKey:\s*\.(\w+)")
# The literal an encoder arm writes to its discriminator key, e.g. `encode("image", forKey: .type)`.
DISCRIMINATOR_WRITE = re.compile(r'\bencode\s*\(\s*"([^"]+)"\s*,\s*forKey:')
CASE_LABEL = re.compile(r"^\s*case\s+(.+?):\s*$", re.M)


def _arms(body):
    """`(label, text)` per `case` arm of a `switch`, or `[(None, body)]` when there is none.

    Split on `case` labels at the arm's own brace depth, so a nested `switch` inside one arm does
    not start a new arm.
    """
    arms, depth, current, label = [], 0, [], None
    started = False
    for line in body.splitlines():
        opens, closes = line.count("{"), line.count("}")
        match = CASE_LABEL.match(line)
        if match and depth <= 2:
            if started:
                arms.append((label, "\n".join(current)))
            label, current, started = match.group(1).strip(), [], True
        elif started:
            current.append(line)
        depth += opens - closes
    if started:
        arms.append((label, "\n".join(current)))
    return arms or [(None, body)]


def _discriminator(arm_text, label):
    """What an arm is keyed by: the literal its encoder writes, or a decoder's `case "x"` label."""
    write = DISCRIMINATOR_WRITE.search(arm_text)
    if write:
        return write.group(1)
    if label:
        quoted = re.match(r'^"([^"]+)"$', label.strip())
        if quoted:
            return quoted.group(1)
    return None


def _optional_names(block):
    """Names declared optional in `block`: stored properties and enum-case payload labels."""
    names = set()
    for match in re.finditer(r"\b(?:let|var)\s+(\w+)\s*:\s*([^\n=]+)", block):
        if match.group(2).strip().rstrip("{").rstrip().endswith("?"):
            names.add(match.group(1))
    for match in re.finditer(r"^\s*case\s+`?(\w+)`?\s*\(([^)]*)\)", block, re.M):
        for part in match.group(2).split(","):
            if ":" not in part:
                continue
            label, kind = part.split(":", 1)
            if kind.strip().split("=")[0].strip().endswith("?"):
                names.add(label.strip())
    return names


def _bound_optional(expression, arm_label, optional_names):
    """Is the encoded expression optional?

    Resolved by NAME — its last path component against the type's optional declarations, plus the
    payload bindings of the arm's own pattern (`case .resourceLink(let uri, …, let mimeType, …)`
    binds positionally to the case's declared labels, which `_optional_names` already holds).
    """
    name = expression.strip().split(".")[-1].strip("?!")
    return name in optional_names


def shapes(text):
    """`(encoders, decoders, shape_a, shape_b)` for one file's text.

    ⚠ **Shape B pairs an encoder with a decoder ON THE SAME TYPE AND THE SAME ARM**, and only
    where the encoded value is actually OPTIONAL. All three qualifiers were added after a
    hand-check found 0 real of 6:

    - **Same type**, because `DocumentInfo.swift` declares `Contact`, `License` and `Info`
      together and their keys were cross-paired.
    - **Same arm**, because a discriminated union encodes `mimeType` required in `.image` and
      `encodeIfPresent` in `.resourceLink`, decoding each to match — every arm consistent, and
      the keys paired across them.
    - **Actually optional**, because Swift promotes `T` to `T?` at the call site, so
      `encodeIfPresent` on a non-optional property always writes and can never be an asymmetry.

    Arms are paired by the discriminator an encoder arm WRITES against the literal a decoder arm
    is labelled with. ⚠ **An arm whose discriminator cannot be read is skipped**, so the count is
    a FLOOR: this shape's measured failure mode is overcounting, and the conservative direction is
    the one that keeps a reported site worth reading.
    """
    encoders = len(ENCODER.findall(text))
    decoders = len(DECODER.findall(text))
    spans = _type_spans(text)
    shape_a = sum(1 for header, body, _ in _bodies(text, ENCODER)
                  if THROWING_ENCODER.search(header) and _explicit_throw(body))

    required = {}
    for _, decoded, position in _bodies(text, DECODER):
        owner = _owner(spans, position)
        for label, arm in _arms(decoded):
            key = (owner, _discriminator(arm, label))
            required.setdefault(key, set()).update(DECODE_REQUIRED.findall(arm))

    shape_b = 0
    for _, body, position in _bodies(text, ENCODER):
        owner = _owner(spans, position)
        block = next((text[start:end] for name, start, end in spans
                      if name == owner and start < position < end), text)
        optional_names = _optional_names(block)
        for label, arm in _arms(body):
            discriminator = _discriminator(arm, label)
            demanded = required.get((owner, discriminator), set())
            if not demanded:
                continue
            for expression, key in ENCODE_IF_PRESENT.findall(arm):
                if key in demanded and _bound_optional(expression, label, optional_names):
                    shape_b += 1
    return encoders, decoders, shape_a, shape_b


CONTROL_A = """
struct Refuses: Codable {
    var mode: String?
    func encode(to encoder: Encoder) throws {
        guard let mode else { throw EncodingError.invalidValue(self, .init(codingPath: [], debugDescription: "")) }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
    }
}
"""

CONTROL_B = """
struct Omits: Codable {
    var flag: Bool?
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(flag, forKey: .flag)
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        flag = try container.decode(Bool.self, forKey: .flag)
    }
}
"""

# ⚠ Two types in ONE file: one omits `.name`, the other requires it. Neither has an asymmetry,
# and a file-scoped pairing reports one. This is the error the first run of this census made.
CONTROL_TWO_TYPES = """
struct Omitter: Codable {
    var name: String?
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
    }
}

struct Requirer: Codable {
    var name: String
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
    }
}
"""

# ⚠ A key-matching regex whose argument span crosses a PARENTHESIS can start in one call and
# finish in a later one. Here `decode(SourceLanguage.self)` and a following `decodeIfPresent(…,
# forKey: .platforms)` were read as one required decode of `.platforms`, in swift-docc.
CONTROL_SPAN = """
struct Spanning: Codable {
    var platforms: [String]?
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(platforms, forKey: .platforms)
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var nested = try container.nestedUnkeyedContainer(forKey: .languages)
        _ = try nested.decode(String.self)
        platforms = try container.decodeIfPresent([String].self, forKey: .platforms)
    }
}
"""

# ⚠ The arm-aware TRUE positive. One arm omits a key its OWN decoder arm requires, so the
# detector must still fire once arms are paired — otherwise a corpus-wide zero is indistinguishable
# from a detector that skips every switch.
CONTROL_ARM_TRUE = """
enum Tagged: Codable {
    case link(uri: String, mimeType: String?)
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .link(let uri, let mimeType):
            try container.encode("link", forKey: .type)
            try container.encode(uri, forKey: .uri)
            try container.encodeIfPresent(mimeType, forKey: .mimeType)
        }
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "link":
            let uri = try container.decode(String.self, forKey: .uri)
            let mimeType = try container.decode(String.self, forKey: .mimeType)
            self = .link(uri: uri, mimeType: mimeType)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "")
        }
    }
}
"""

# ⚠ The mcp-swift-sdk shape, reduced: `mimeType` is required in one arm and optional in another,
# and each arm pairs consistently. Every arm is correct and the keys must NOT be paired across.
CONTROL_CROSS_ARM = """
enum Content: Codable {
    case image(data: String, mimeType: String)
    case resourceLink(uri: String, mimeType: String?)
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .image(let data, let mimeType):
            try container.encode("image", forKey: .type)
            try container.encode(data, forKey: .data)
            try container.encode(mimeType, forKey: .mimeType)
        case .resourceLink(let uri, let mimeType):
            try container.encode("resource_link", forKey: .type)
            try container.encode(uri, forKey: .uri)
            try container.encodeIfPresent(mimeType, forKey: .mimeType)
        }
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "image":
            let data = try container.decode(String.self, forKey: .data)
            let mimeType = try container.decode(String.self, forKey: .mimeType)
            self = .image(data: data, mimeType: mimeType)
        case "resource_link":
            let uri = try container.decode(String.self, forKey: .uri)
            let mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
            self = .resourceLink(uri: uri, mimeType: mimeType)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "")
        }
    }
}
"""

# ⚠ `encodeIfPresent` on a NON-OPTIONAL value always writes — Swift promotes `T` to `T?` at the
# call site — so this is not an asymmetry however the decoder reads it.
CONTROL_NON_OPTIONAL = """
struct Required: Codable {
    var schema: Schema
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(schema, forKey: .schema)
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(Schema.self, forKey: .schema)
    }
}
"""

CONTROL_NEITHER = """
struct Ordinary: Codable {
    var name: String
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
    }
}
"""


def control():
    """Assert both shapes are detectable, and that an ordinary codec is neither."""
    checks = [
        ("Shape A detected", shapes(CONTROL_A)[2] == 1),
        ("Shape A does not fire on an ordinary encoder", shapes(CONTROL_NEITHER)[2] == 0),
        ("Shape B detected", shapes(CONTROL_B)[3] == 1),
        ("Shape B does not fire on an ordinary codec", shapes(CONTROL_NEITHER)[3] == 0),
        ("Shape B does not pair ACROSS types in one file", shapes(CONTROL_TWO_TYPES)[3] == 0),
        ("Shape B does not span a parenthesis into a later call", shapes(CONTROL_SPAN)[3] == 0),
        ("Shape B STILL fires when the arms are paired", shapes(CONTROL_ARM_TRUE)[3] == 1),
        ("Shape B does not pair ACROSS arms of one union", shapes(CONTROL_CROSS_ARM)[3] == 0),
        ("Shape B ignores encodeIfPresent on a NON-OPTIONAL", shapes(CONTROL_NON_OPTIONAL)[3] == 0),
        # The denominator has to be right too, or a zero is unreadable either way.
        ("an encoder is counted", shapes(CONTROL_NEITHER)[0] == 1),
        ("a decoder is counted", shapes(CONTROL_NEITHER)[1] == 1),
    ]
    for label, held in checks:
        print(f"  {'ok  ' if held else 'FAIL'}  {label}")
    return all(held for _, held in checks)


def census(root):
    files = encoders = decoders = shape_a = shape_b = 0
    hits = []
    for path in measurement.swift_files(root):
        try:
            text = open(path, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        files += 1
        counts = shapes(text)
        encoders += counts[0]
        decoders += counts[1]
        shape_a += counts[2]
        shape_b += counts[3]
        if counts[2] or counts[3]:
            hits.append((os.path.relpath(path, root), counts[2], counts[3]))
    return files, encoders, decoders, shape_a, shape_b, hits


def main(argv):
    print("Control — both shapes detectable on synthetic sources:")
    if not control():
        print("\nCONTROL FAILED — no subject figure is readable, so none is printed.")
        return 1
    print()
    header = f"{'subject':22s}{'files':>7}{'encode':>8}{'init':>7}{'ShapeA':>8}{'ShapeB':>8}"
    print(header)
    total = [0, 0, 0, 0, 0]
    every_hit = []
    for root in argv[1:]:
        name = os.path.basename(os.path.normpath(root))
        files, encoders, decoders, a, b, hits = census(root)
        print(f"{name:22s}{files:7d}{encoders:8d}{decoders:7d}{a:8d}{b:8d}")
        for index, value in enumerate((files, encoders, decoders, a, b)):
            total[index] += value
        every_hit += [(name,) + hit for hit in hits]
    print(f"{'TOTAL':22s}{total[0]:7d}{total[1]:8d}{total[2]:7d}{total[3]:8d}{total[4]:8d}")
    if every_hit:
        print("\nHits:")
        for name, path, a, b in every_hit:
            print(f"  {name}/{path}  ShapeA={a} ShapeB={b}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
