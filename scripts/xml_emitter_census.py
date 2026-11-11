#!/usr/bin/env python3
"""Which functions build an XML document as text? — `docs/plans/xml-emitter-census-scope.md`.

#668's two laws, gated separately. Law 1: the document a text-built XML emitter returns parses
(`XMLParser(data:).parse()`), apart from a guard's sentinel. Law 2, for SVG: every same-document reference in it
(`url(#X)`, `href="#X"`) names an `id="X"` it defines. This pass finds the units that might owe either, by cues read
off their literals (§1.2), and hands each candidate to a blind hand-check (§4). It never decides that a unit IS a
document emitter; the judges do.

Section numbers below are the scope's.

  --self-test                  the scope's pass and decision controls (no siblings; joins `make measurement-selftest`)
  universe                     §2's asserts only: resolve the frozen universe and print it, reading no source
  run <out.json>               census the frozen universe (§2), and choose what §4 judges
  packets <census.json> <dir>  write §4's blind judging packets, at most eight rows each, in seeded order
  render <path> <name> <repo> [<label>]   one unit in a packet's format, for the calibration file (§4.2)
  calibrate <judge.json>       §4.2: one judge's calibration records against the expected answers
  verdicts <workflow.json> <verdicts-dir>                  §4.3: A.json, B.json, C.json from the judge workflow's raw records
  join <index.json> <verdicts-dir> <judgements.json>       §4.3: the judges' records joined to row ids
  search <out.json>            §6's R5: GitHub code search, each frozen query once
  decide <census.json> <judgements.json> <kill-arm.json>   §8's outcomes, figures and sensitivity lines
"""
import collections
import contextlib
import hashlib
import io
import json
import os
import random
import re
import signal
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from budgeted_truncation_census import DECL, base_name, brace_pairs, parameters, revision, subjects  # noqa: E402
from layering_census import (  # noqa: E402
    HOME, corpus_universe, declarations, doc_block, git, origin, subject_files, toplevel,
)
from mutation_check import mask  # noqa: E402
from regex_acceptor_census import FROZEN_UNIVERSE, mask_code  # noqa: E402
import layering_census  # noqa: E402
import uniquifier_census  # noqa: E402
from uniquifier_census import member_lines, owner_entries, without_fixtures  # noqa: E402


def _unit_mask(text):
    """§1.1: units are bounded on `mask_code`'s view. `mutation_check.mask`, which #669's scanner uses, ends a
    one-line literal at the first `"` even inside an interpolation, so a nested `"<a href=\\"\\($0)\\"/>"` leaked a
    brace and cut the unit short."""
    return mask_code(text), []


layering_census.mask = _unit_mask
uniquifier_census.mask = _unit_mask

SEED = 20261030
PACKET_SIZE = 8
# §4.1: what is judged. Decision, unmet and layout candidates in full up to the cap; wide up to its own.
JUDGED_CAP, WIDE_CAP = 300, 60
GROUP_ORDER = {"decision": 0, "unmet": 1, "layout": 2, "wide": 3}
HOP_TEXT_CAP = 120

# §2: the witness and the subject #668 names, each at its frozen revision.
SWIFTUMLSTUDIO = "9ad7631"
SWIFTLINT = ("github_projects/SwiftLint", "https://github.com/realm/swiftlint", "ec4691d9e")

# ── The literal view (§1.1) ───────────────────────────────────────────────────────────────────────
PLACEHOLDER = "\x01"
ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", "\\": "\\", '"': '"', "'": "'"}


def literal_view(text):
    """`[(offset, end, content)]` for every string literal in `text`, in source order, nested ones (inside an
    interpolation) included. Comments are skipped. `content` has escapes resolved, each interpolation replaced by
    PLACEHOLDER, and a multi-line literal's line-ending backslash removed with its line break. A literal starts only
    where `mask_code` keeps its opening quote, so a quote inside a regex literal (`/"/`) never opens one."""
    code_only = mask_code(text, literals=False)
    full = mask_code(text)
    found = []

    def string(index):
        start, hashes = index, 0
        while code_only[index] == "#":
            hashes += 1
            index += 1
        multi = text.startswith('"""', index)
        quote = '"""' if multi else '"'
        closer, escape = quote + "#" * hashes, "\\" + "#" * hashes
        index += len(quote)
        entry = [start, len(text), ""]
        found.append(entry)
        parts = []
        while index < len(text):
            if text.startswith(closer, index):
                entry[1], entry[2] = index + len(closer), "".join(parts)
                return index + len(closer)
            if not multi and text[index] == "\n":
                entry[1], entry[2] = index, "".join(parts)
                return index
            if text.startswith(escape, index):
                after = index + len(escape)
                following = text[after:after + 1]
                if following == "(":
                    parts.append(PLACEHOLDER)
                    index = code(after + 1, inside=True)
                    continue
                if multi and re.match(r"[ \t]*\n", text[after:]):
                    index = text.index("\n", after) + 1
                    continue
                if following == "u" and text[after + 1:after + 2] == "{":
                    close = text.find("}", after)
                    if close < 0:
                        parts.append(text[index:])
                        index = len(text)
                        continue
                    try:
                        parts.append(chr(int(text[after + 2:close], 16)))
                    except ValueError:
                        parts.append("\ufffd")
                    index = close + 1
                    continue
                parts.append(ESCAPES.get(following, following))
                index = after + 1
                continue
            parts.append(text[index])
            index += 1
        entry[2] = "".join(parts)
        return len(text)

    def code(index, inside=False):
        depth = 0
        while index < len(text):
            character = code_only[index]
            if (character == '"' and full[index] == '"') or (
                    character == "#" and re.match(r'#+"', code_only[index:index + 8]) and full[index] == "#"):
                index = string(index)
                continue
            if inside:
                if character == "(":
                    depth += 1
                elif character == ")":
                    if depth == 0:
                        return index + 1
                    depth -= 1
            index += 1
        return index

    code(0)
    found.sort(key=lambda entry: entry[0])
    return [tuple(entry) for entry in found]


class _Slow(Exception):
    pass


def parsable(text, seconds=10.0, views=None):
    """§2: whether the views this pass runs over a file (the code view and the literal view) finish on `text` within
    `seconds`. A file that does not is dropped and listed as `unparsable`."""
    def stop(*_):
        raise _Slow()

    previous = signal.signal(signal.SIGALRM, stop)
    signal.setitimer(signal.ITIMER_REAL, seconds)
    try:
        for view in views or (mask_code, literal_view):
            view(text)
        return True
    except (_Slow, RecursionError):
        return False
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)


# ── Cues on literal content (§1.2) ────────────────────────────────────────────────────────────────
NAME = r"[A-Za-z_:][A-Za-z0-9_.:-]*"
START_TAG = re.compile(r"<(" + NAME + r")")
XMLNS_ATTRIBUTE = re.compile(r"\sxmlns(?::[A-Za-z_][\w.-]*)?\s*=")
GREP_MARKERS = ("<?xml", "xmlns", "<svg", "</svg>", "<plist", "</plist>")
ANY_END_TAG = re.compile(r"</" + NAME)
HTML = re.compile(r"<html\b|<!doctype\s+html\b", re.I)
IDDEF = re.compile(r"(?:(?<=\s)|^)id=[\"']")
REF = re.compile(r"url\(#|href=[\"']#")
COMMENT_OR_CDATA = re.compile(r"<!--.*?(?:-->|\Z)|<!\[CDATA\[.*?(?:\]\]>|\Z)", re.S)


def markup(content):
    """`content` with each XML comment and CDATA section blanked, its length kept: a tag named inside one is text, so
    it opens, roots and closes nothing (§1.2, X34). One left open runs to the literal's end."""
    return COMMENT_OR_CDATA.sub(lambda match: " " * len(match.group(0)), content)


def xmlns_tag(content, match):
    """Whether the start tag `match` carries `xmlns` or `xmlns:PREFIX` before its next `>`, or before the literal's
    end when it has none."""
    end = content.find(">", match.end())
    return bool(XMLNS_ATTRIBUTE.search(content[match.end():end if end >= 0 else len(content)]))


def open_marker(content):
    """`(position, kind, root)` of the opening marker in `content`, or None: XMLDECL at `<?xml`, or XMLNS when the
    literal's FIRST start tag carries `xmlns`, whichever comes first. `root` is the XMLNS tag's name, or None for
    XMLDECL (§1.2's ROOT resolves it from the stream). An `xmlns` tag after another start tag is not an opener: it is
    an element inside some other root (`<div><svg xmlns=…>`)."""
    content = markup(content)
    declaration = content.find("<?xml")
    first = START_TAG.search(content)
    if first and xmlns_tag(content, first) and (declaration < 0 or first.start() < declaration):
        return first.start(), "XMLNS", first.group(1)
    return (declaration, "XMLDECL", None) if declaration >= 0 else None


def end_tag(root):
    return re.compile(r"</" + re.escape(root) + r"\s*>")


# ── Search keys (§1.2) ────────────────────────────────────────────────────────────────────────────
SEARCH_CALLS = {"hasPrefix", "hasSuffix", "contains", "starts", "range", "ranges", "firstRange", "firstIndex",
                "lastIndex", "components", "split", "trimmingPrefix", "trimPrefix", "matches", "wholeMatch",
                "prefixMatch", "firstMatch", "memcmp", "strcmp", "strncmp", "replacing", "replace"}
# A replacing call's `with:` argument is what it writes, so it flows.
REPLACING = {"replacing", "replace"}
OPENERS, CLOSERS = "([{", ")]}"


def brackets(code, floor, stop):
    """`inner[i - floor]`: the index of the innermost unclosed bracket in `code[floor:i]`, or -1, for each `i` from
    `floor` to `stop`, in one pass. The outward walk reads it rather than scanning back from every literal, which cost
    the square of a body's length (a generated icon catalog's `switch`)."""
    inner, stack = [], []
    for index in range(floor, stop):
        inner.append(stack[-1] if stack else -1)
        character = code[index]
        if character in OPENERS:
            stack.append(index)
        elif character in CLOSERS and stack:
            stack.pop()
    inner.append(stack[-1] if stack else -1)
    return inner


def _opener(code, start, floor):
    """The index of the innermost unclosed bracket before `start`, or -1."""
    depth, cursor = 0, start - 1
    while cursor >= floor:
        character = code[cursor]
        if character in CLOSERS:
            depth += 1
        elif character in OPENERS:
            if depth == 0:
                return cursor
            depth -= 1
        cursor -= 1
    return -1


def _label(code, opener, start):
    """The label of the argument that holds `start`, inside the call whose `(` is at `opener`, or ""."""
    segment, inner, cut = code[opener + 1:start], 0, 0
    for index, character in enumerate(segment):
        if character in OPENERS:
            inner += 1
        elif character in CLOSERS:
            inner -= 1
        elif character == "," and inner == 0:
            cut = index + 1
    found = re.match(r"\s*([A-Za-z_]\w*)\s*:(?!:)", segment[cut:])
    return found.group(1) if found else ""


def _last_token(code, floor, end):
    """The index just past the last non-blank character of `code[floor:end]`, or `floor`."""
    while end > floor and code[end - 1].isspace():
        end -= 1
    return end


def _callee(code, floor, opener):
    """The identifier written straight before the bracket at `opener` (blanks allowed), or ""."""
    cursor = end = _last_token(code, floor, opener)
    while cursor > floor and (code[cursor - 1].isalnum() or code[cursor - 1] == "_"):
        cursor -= 1
    return code[cursor:end].lstrip("0123456789")


COMPARISON_AFTER = re.compile(r"\s*(?:==|!=|~=)")


def search_key(code, start, end, floor=0, inner=None):
    """§1.2: whether the literal or reference spanning `[start, end)` of a code view sits in a search-key position.
    It is one when it is an operand of `==`, `!=` or `~=`, or a `case` label; or when, walking outward through the
    brackets that enclose it up to the nearest `{`, some call it is an argument of is named in SEARCH_CALLS (but not
    a `replacing` call's `with:` argument, which it writes), or some argument it sits in is labelled `of:`. `floor` bounds the scan
    (the body's start); `inner`, when given, is `brackets(code, floor, …)` over the same body."""
    last = _last_token(code, floor, start)
    if code[max(floor, last - 2):last] in ("==", "!=", "~=") or COMPARISON_AFTER.match(code, end):
        return True
    line = code[code.rfind("\n", floor, start) + 1:start]
    if re.match(r"\s*case\b", line) and ":" not in line:
        return True
    position = start
    while True:
        opener = inner[position - floor] if inner is not None else _opener(code, position, floor)
        if opener < 0 or code[opener] == "{":
            return False
        if code[opener] == "(":
            label = _label(code, opener, position)
            name = _callee(code, floor, opener)
            if label == "of" or (name in SEARCH_CALLS and not (name in REPLACING and label == "with")):
                return True
        position = opener


# ── Units (§1.1) ──────────────────────────────────────────────────────────────────────────────────
PROPERTY = re.compile(r"\bvar\s+([A-Za-z_]\w*|`[^`]+`)\s*:\s*([^={\n]+?)\s*\{")
STORED = re.compile(r"\b(?:let|var)\s+([A-Za-z_]\w*)\s*(?::\s*([^=\n{]+?))?\s*=(?!=)")


def _types(masked, pairs):
    """`[(start, body_open, body_close, name, kind)]` of every type declaration in a masked file."""
    found = []
    for match in DECL.finditer(masked):
        if match.group(1) == "class" and match.group(2) in ("func", "var", "let"):
            continue
        # `import struct Foundation.Date` declares nothing; its next `{` is the following type's (X36).
        if re.search(r"\bimport\s+$", masked[masked.rfind("\n", 0, match.start()) + 1:match.start()]):
            continue
        brace = masked.find("{", match.end())
        if brace < 0 or masked[match.end():brace].count("\n") > 3:
            continue
        found.append((match.start(), brace, pairs.get(brace, len(masked) - 1), base_name(match.group(2)),
                      match.group(1)))
    return found


def _innermost_braces(masked, positions):
    """`{position: open brace index or -1}`: the innermost `{` enclosing each position, in one pass."""
    wanted, result, stack = sorted(set(positions)), {}, []
    cursor = 0
    for index, character in enumerate(masked):
        while cursor < len(wanted) and wanted[cursor] == index:
            result[wanted[cursor]] = stack[-1] if stack else -1
            cursor += 1
        if character == "{":
            stack.append(index)
        elif character == "}" and stack:
            stack.pop()
    while cursor < len(wanted):
        result[wanted[cursor]] = stack[-1] if stack else -1
        cursor += 1
    return result


def _owner_at(types, position):
    owners = [entry for entry in types if entry[1] < position < entry[2]]
    return min(owners, key=lambda entry: entry[2] - entry[1]) if owners else None


def _doc(text, offset):
    return doc_block(text, offset)


def properties_of(text, masked=None):
    """Computed and stored properties directly in a type body or at file scope. Computed: `(kind "property", …)`
    with a getter body; stored: `(kind "stored", …)` with an initialiser span."""
    masked = masked if masked is not None else mask_code(text)
    pairs = brace_pairs(masked)
    types = _types(masked, pairs)
    bodies = {entry[1] for entry in types}
    computed = list(PROPERTY.finditer(masked))
    stored = list(STORED.finditer(masked))
    enclosing = _innermost_braces(masked, [m.start() for m in computed + stored])
    found = []
    for match in computed:
        holder = enclosing[match.start()]
        if holder != -1 and holder not in bodies:
            continue
        brace = match.end() - 1
        close = pairs.get(brace, len(masked) - 1)
        block = masked[brace + 1:close]
        head = block.lstrip()
        if re.match(r"(willSet|didSet|set)\b", head):
            continue
        getter = re.match(r"((?:mutating|nonmutating)\s+)?get\b([^{]*)\{", head)
        effects = ""
        if getter:
            inner = brace + 1 + (len(block) - len(head)) + getter.end() - 1
            effects = (getter.group(1) or "") + getter.group(2)
            body_open, body_close = inner, pairs.get(inner, close)
        elif re.match(r"get\s*(set\s*)?$", head.strip()):
            continue
        else:
            body_open, body_close = brace, close
        line_start = masked.rfind("\n", 0, match.start()) + 1
        owner = _owner_at(types, match.start())
        found.append({"kind": "property", "name": match.group(1).strip("`"), "type": match.group(2).strip(),
                      "effects": effects, "prefix": masked[line_start:match.start()], "start": match.start(),
                      "line_start": line_start, "body_open": body_open, "body_close": body_close,
                      "end": close, "owner": owner})
    for match in stored:
        holder = enclosing[match.start()]
        if holder != -1 and holder not in bodies:
            continue
        line_start = masked.rfind("\n", 0, match.start()) + 1
        if re.search(r"\b(if|guard|while|case|for)\b", masked[line_start:match.start()]):
            continue
        start = match.end()
        depth, cursor = 0, start
        while cursor < len(masked):
            character = masked[cursor]
            if character in OPENERS:
                depth += 1
            elif character in CLOSERS:
                if depth == 0:
                    break
                depth -= 1
            elif character == "\n" and depth == 0:
                rest = masked[cursor + 1:].lstrip(" \t")
                line = masked[masked.rfind("\n", 0, cursor) + 1:cursor].rstrip()
                if not (line.endswith(("+", "=", ",", "(")) or rest.startswith((".", "+"))):
                    break
            cursor += 1
        found.append({"kind": "stored", "name": match.group(1), "type": (match.group(2) or "").strip(),
                      "prefix": masked[line_start:match.start()], "start": match.start(), "line_start": line_start,
                      "body_open": start - 1, "body_close": cursor, "end": cursor,
                      "owner": _owner_at(types, match.start())})
    return found


def _func_parts(unit_text):
    """`(prefix, tail, body_open, body_close)` of one func's text from its line start: `tail` is what lies between
    the parameter list and the body (effects and result)."""
    code = mask_code(unit_text)
    found = re.search(r"\bfunc\b", code)
    if not found:
        return "", "", -1, -1
    paren = code.find("(", found.end())
    depth, index = 0, paren
    while 0 <= index < len(code):
        if code[index] == "(":
            depth += 1
        elif code[index] == ")":
            depth -= 1
            if depth == 0:
                break
        index += 1
    brace = code.find("{", index)
    return code[:found.start()], code[index + 1:brace], brace, code.rfind("}")


def units_of(path, text):
    """§1.1: every func with a body and every computed property, each with its owner, signature cues and body span
    (offsets into `unit["text"]`). Stored properties are returned apart, for hops only."""
    _, functions = declarations(text)
    masked = mask_code(text)
    units, stored = [], []
    for function in functions:
        unit_text = function["text"]
        prefix, tail, body_open, body_close = _func_parts(unit_text)
        if body_open < 0:
            continue
        units.append({
            "kind": "func", "path": path, "name": function["name"], "labels": function["labels"],
            "parameters": function["parameters"], "result": function["result"], "owner": function["owner"],
            "owner_kind": function["owner_kind"], "owner_doc": function["owner_doc"], "doc": function["doc"],
            "visibility": function["visibility"], "line": function["line"], "text": unit_text,
            "body": (body_open + 1, body_close), "key": function["key"],
            "throws": bool(re.search(r"\b(throws|rethrows)\b", tail)), "async": bool(re.search(r"\basync\b", tail)),
            "mutating": bool(re.search(r"\bmutating\b", prefix)), "static": bool(re.search(r"\b(static|class)\b", prefix))})
    for entry in properties_of(text, masked):
        owner = entry["owner"]
        unit_text = text[entry["line_start"]:entry["end"] + 1]
        offset = entry["line_start"]
        common = {"path": path, "name": entry["name"], "labels": [], "parameters": "", "result": entry["type"],
                  "owner": owner[3] if owner else "", "owner_kind": owner[4] if owner else "",
                  "owner_doc": _doc(text, owner[0]) if owner else "", "doc": _doc(text, entry["start"]),
                  "visibility": (re.findall(r"\b(public|open|package|internal|fileprivate|private)\b",
                                            entry["prefix"]) or [""])[-1],
                  "line": text.count("\n", 0, entry["start"]) + 1, "text": unit_text,
                  "body": (entry["body_open"] + 1 - offset, entry["body_close"] - offset),
                  "static": bool(re.search(r"\b(static|class)\b", entry["prefix"]))}
        if entry["kind"] == "stored":
            stored.append(dict(common, kind="stored"))
            continue
        body = " ".join(masked[entry["body_open"] + 1:entry["body_close"]].split())
        units.append(dict(common, kind="property", throws=bool(re.search(r"\bthrows\b", entry["effects"])),
                          **{"async": bool(re.search(r"\basync\b", entry["effects"]))},
                          mutating=bool(re.search(r"\bmutating\b", entry["effects"])),
                          key=hashlib.sha256("\x00".join([entry["name"], "", body]).encode()).hexdigest()[:16]))
    return units, stored


# ── One unit's literals, references and cues ──────────────────────────────────────────────────────
KEYWORDS = {"if", "for", "while", "switch", "guard", "return", "init", "super", "self", "Self", "case", "let", "var",
            "in", "try", "await", "throw", "repeat", "else", "where", "is", "as", "do", "catch", "defer", "func",
            "true", "false", "nil", "some", "any", "inout", "static", "class", "struct", "enum"}
IMPURITY = [r"\bFileManager\b", r"\bProcessInfo\b", r"\bBundle\s*\.\s*main\b", r"\bUserDefaults\b",
            r"\bURLSession\b", r"\bFileHandle\b", r"\bProcess\s*\(", r"\bDate\s*\(\s*\)", r"\bDate\s*\.\s*now\b",
            r"\.now\s*\(\s*\)", r"\bUUID\s*\(\s*\)", r"\.random\s*\(", r"\barc4random", r"\bCFAbsoluteTimeGetCurrent\b",
            r"\bDispatchTime\s*\.\s*now\b", r"\bgetenv\s*\(", r"\bfopen\s*\(", r"\bprint\s*\(", r"\bNSLog\s*\(",
            r"\bcurrentDirectoryPath\b"]


# A closure's head: a capture list and attributes allowed, then its parameters, bare or in parentheses (typed or not,
# a type holding parentheses itself), then `async`, `throws` and a result type, then `in` (§1.2, X9).
CLOSURE_HEAD = re.compile(r"\{\s*(?:\[[^\]]*\]\s*)?(?:@\w+\s*)*"
                          r"(\((?:[^()]|\([^()]*\))*\)|[A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)"
                          r"\s*(?:async\s*)?(?:throws\s*)?(?:->[^{}]*?)?\s+in\b")


def closure_names(group):
    """The parameter names of a closure head's group: each depth-0 part's leading identifier."""
    inner = group[1:-1] if group.startswith("(") else group
    names, depth, part = set(), 0, []
    for index, character in enumerate(inner + ","):
        if character in "([{<":
            depth += 1
        elif character in ")]}" or (character == ">" and inner[index - 1:index] != "-"):
            depth -= 1
        elif character == "," and depth == 0:
            found = re.match(r"\s*([A-Za-z_]\w*)", "".join(part))
            if found:
                names.add(found.group(1))
            part = []
            continue
        part.append(character)
    return names


def analysed(unit):
    """`unit`, given its body's literals (`[(offset, end, content, flows)]`), its code view and its locals, once."""
    if "literals" in unit:
        return unit
    code = mask_code(unit["text"])
    start, stop = unit["body"]
    spans = [(offset, end, content) for offset, end, content in literal_view(unit["text"]) if start <= offset < stop]
    inner = brackets(code, start, stop) if spans else None
    literals = [(offset, end, content, not search_key(code, offset, end, start, inner))
                for offset, end, content in spans]
    body = code[start:stop]
    local = set(re.findall(r"\b(?:let|var)\s+([A-Za-z_]\w*)", body))
    for group in re.findall(r"\b(?:let|var)\s*\(([^)]*)\)", body):
        local |= set(re.findall(r"[A-Za-z_]\w*", group))
    local |= set(re.findall(r"\bfor\s+(?:case\s+)?(?:let\s+)?\(?\s*([A-Za-z_]\w*)", body))
    for group in re.findall(r"\bfor\s+(?:case\s+)?(?:let\s+)?\(([^)]*)\)", body):
        local |= set(re.findall(r"[A-Za-z_]\w*", group))
    for group in CLOSURE_HEAD.findall(body):
        local |= closure_names(group)
    local |= {name for _, name, _ in parameters(unit.get("parameters", ""))}
    unit.update(literals=literals, code=code, locals=local, inner=inner)
    return unit


CALL_OPEN, LABEL_COLON = re.compile(r"\s*\("), re.compile(r"\s*:(?!:)")


def references(unit, member_names, owner):
    """§1.2's hop references: `[(name, offset, end)]` for each call or read in the body that names a same-type
    member, bare or after `self.`, `Self.` or the owner's own name. A bare read is not a reference when a local or a
    parameter of that name shadows it, or when it is an argument label (`wrap(title: x)`); an explicit receiver
    cannot be shadowed."""
    unit = analysed(unit)
    code, (start, stop) = unit["code"], unit["body"]
    found = []
    for match in re.finditer(r"\b([A-Za-z_]\w*)\b", code[start:stop]):
        name = match.group(1)
        if name not in member_names or name in KEYWORDS:
            continue
        begin, end = start + match.start(), start + match.end()
        last = _last_token(code, start, begin)
        explicit = last > start and code[last - 1] == "."
        if explicit:
            # The receiver is the identifier before the dot, blanks between: `self`, `Self` or the owner's name.
            receiver_end = receiver_start = _last_token(code, start, last - 1)
            while receiver_start > start and (code[receiver_start - 1].isalnum() or code[receiver_start - 1] == "_"):
                receiver_start -= 1
            while receiver_start < receiver_end and code[receiver_start].isdigit():
                receiver_start += 1
            if code[receiver_start:receiver_end] not in ("self", "Self", owner or "\x00"):
                continue
            begin = receiver_start
        call = CALL_OPEN.match(code, end, stop)
        if not call and not explicit and (name in unit["locals"] or (
                LABEL_COLON.match(code, end, stop) and last > start and code[last - 1] in "(,[")):
            continue
        if call:
            depth, cursor = 0, call.end() - 1
            while cursor < stop:
                if code[cursor] == "(":
                    depth += 1
                elif code[cursor] == ")":
                    depth -= 1
                    if depth == 0:
                        break
                cursor += 1
            end = cursor + 1
        found.append((name, begin, end))
    return found


STRINGS = {"String", "Swift.String"}
STRING_ARRAYS = {"[String]", "[Swift.String]", "Array<String>", "Array<Swift.String>"}


def is_string(type_text):
    return type_text.strip() in STRINGS


def literal_only(member):
    """A stored property's initialiser is one literal, or literals joined by `+`, and nothing else. The gaps are read
    off the code view, so a trailing comment (`= "<svg …>" // opener`) is not code (§1.2, X7)."""
    start, stop = member["body"]
    text, cursor, rest = member["code"], start, []
    for offset, end, _, _ in member["literals"]:
        if offset < cursor:
            continue
        rest.append(text[cursor:offset])
        cursor = end
    rest.append(text[cursor:stop])
    return bool(member["literals"]) and not re.sub(r"[\s+]", "", "".join(rest))


def hop_string(member):
    """§1.2: a hop's result reaches the unit's text: a func or computed property written `String` or `[String]`, or a
    stored property typed so, or untyped and initialised by literals alone."""
    if member["kind"] == "stored" and not member["result"]:
        return literal_only(member)
    return member["result"].strip() in STRINGS | STRING_ARRAYS


def _without_print_to(view):
    """The code view with the `print` of each `print(…, to: …)` call blanked: printing into a local `String` builds
    text. The call is one only when `to:` labels one of print's own arguments, not an argument nested inside one
    (`print(a.distance(to: b))`), and the arguments' tokens still count (§1.2, X28)."""
    for match in reversed(list(re.finditer(r"\bprint\s*\(", view))):
        depth, cursor, own = 0, match.end() - 1, []
        while cursor < len(view):
            character = view[cursor]
            if character in OPENERS:
                depth += 1
                if depth == 1:
                    cursor += 1
                    continue
            elif character in CLOSERS:
                depth -= 1
                if depth == 0:
                    break
            if depth == 1:
                own.append(character)
            cursor += 1
        if re.search(r"(?:^|[(,\s])to\s*:(?!:)", "".join(own)):
            view = view[:match.start()] + " " * 5 + view[match.start() + 5:]
    return view


def _interpolations(code, offset, end):
    """Source spans `[open, close)` of a literal's own interpolations, read off the code view, where the literal's
    text is blank and each interpolation's code is kept: every bracket left at depth 0 opens one."""
    spans, depth, begin = [], 0, None
    for index in range(offset + 1, end):
        character = code[index]
        if character in OPENERS:
            if depth == 0:
                begin = index
            depth += 1
        elif character in CLOSERS and depth:
            depth -= 1
            if depth == 0 and code[begin] == "(":
                spans.append((begin, index + 1))
    return spans


def stream_of(code, flowing, string_hops):
    """§1.2's stream: the body's flowing literals (`[(offset, end, content)]`) and its flowing String hops
    (`[(begin, member)]`), in source order, as `[("literal", piece, content, at, offset) | ("hop", member)]`. A literal
    nested in another's interpolation, and a hop read there, sit at that interpolation's placeholder, in every flowing
    literal that holds them, outermost first; each such literal is cut there, and `piece` is
    `content[at:at + len(piece)]`. So `"\\(header)<root>"` reads the hop before `<root>`, and
    `"\\(flag ? "<?xml…?>" : "")<root>"` the declaration before it (X35)."""
    spans_of = {}
    for offset, end, content in flowing:
        spans = _interpolations(code, offset, end)
        places = [index for index, character in enumerate(content) if character == PLACEHOLDER]
        if len(spans) == len(places):
            spans_of[offset] = list(zip(spans, places))

    def chain(position):
        return tuple((offset, place, -1) for offset, _, _ in flowing
                     for (left, right), place in spans_of.get(offset, ()) if left < position < right)

    chains = {("literal", offset): chain(offset) for offset, _, _ in flowing}
    chains.update({("hop", begin): chain(begin) for begin, _ in string_hops})
    cuts = collections.defaultdict(set)
    for found in chains.values():
        for offset, place, _ in found:
            cuts[offset].add(place)
    items = []
    for offset, _, content in flowing:
        bounds = [0] + sorted(cuts[offset]) + [len(content)]
        for left, right in zip(bounds, bounds[1:]):
            items.append((chains[("literal", offset)] + ((offset, left, 0),),
                          ("literal", content[left:right], content, left, offset)))
    for begin, member in string_hops:
        items.append((chains[("hop", begin)] + ((begin, -1, 0),), ("hop", member)))
    return [item for _, item in sorted(items, key=lambda pair: pair[0])]


def _root(open_event, stream, closes):
    """§1.2's ROOT. For XMLNS, the tag that carries it. For XMLDECL, the first start tag in the rest of the opening
    literal, up to the first cut the stream makes after the declaration; else the first later start tag in the stream
    that carries `xmlns`; else the first whose end tag some flowing literal holds; else the first. Tags inside an XML
    comment or CDATA section are text (X34)."""
    index, _, (position, kind, root), content, hop = open_event
    if kind == "XMLNS":
        return root
    stop = len(content)
    if hop is None:
        # Step 1 reads the opening literal up to the first cut after the declaration: what the stream places there
        # comes before the rest of the literal (X35).
        declared = content.find("?>", position)
        after = declared + 2 if declared >= 0 else len(content)
        later = [event[3] for event in stream[index + 1:]
                 if event[0] == "literal" and event[4] == stream[index][4] and event[3] >= after]
        stop = later[0] if later else len(content)
    first = START_TAG.search(markup(content), position, stop)
    if first:
        return first.group(1)
    rest = []
    if hop:
        member, at = hop
        rest += [c for _, _, c, f in member["literals"][at + 1:] if f]
    for event in stream[index + 1:]:
        rest += [event[1]] if event[0] == "literal" else [c for _, _, c, f in event[1]["literals"] if f]
    tags = [(piece, match) for piece in map(markup, rest) for match in START_TAG.finditer(piece)]
    for piece, match in tags:
        if xmlns_tag(piece, match):
            return match.group(1)
    for _, match in tags:
        if any(end_tag(match.group(1)).search(content) for content in closes):
            return match.group(1)
    return tags[0][1].group(1) if tags else None


def cues(unit, members):
    """§1.2's cues for one unit. `members` maps a same-type member's name to its units (funcs, computed and stored
    properties), each with its own literal view. Every same-type member of a referenced name is a hop, overloads
    included, except the unit itself."""
    unit = analysed(unit)
    owner = unit["owner"]
    hops = []
    found_references = references(unit, set(members), owner)
    if found_references and unit["inner"] is None:
        unit["inner"] = brackets(unit["code"], *unit["body"])
    for name, begin, end in found_references:
        flows = not search_key(unit["code"], begin, end, unit["body"][0], unit["inner"])
        for member in members[name]:
            if member is not unit:
                hops.append((begin, name, flows, analysed(member)))
    literals = unit["literals"]
    contents = [content for _, _, content, _ in literals]
    hop_contents = [content for _, _, _, member in hops for _, _, content, _ in member["literals"]]
    flowing_spans = [(offset, end, content) for offset, end, content, flows in literals if flows]
    string_hops = [(begin, member) for begin, _, flows, member in hops if flows and hop_string(member)]
    stream = stream_of(unit["code"], flowing_spans, string_hops)
    open_event = None
    for index, event in enumerate(stream):
        if event[0] == "literal":
            _, piece, content, at, _ = event
            marker = open_marker(content)
            if marker and at <= marker[0] < at + len(piece):
                open_event = (index, "body", marker, content, None)
                break
        else:
            for position, (_, _, content, flows) in enumerate(event[1]["literals"]):
                marker = open_marker(content) if flows else None
                if marker:
                    open_event = (index, "hop", marker, content, (event[1], position))
                    break
            if open_event:
                break
    flowing = [markup(content) for _, _, content in flowing_spans]
    hop_flowing = [markup(content) for _, member in string_hops for _, _, content, f in member["literals"] if f]
    stream_contents = [content for _, _, content in flowing_spans] + [
        content for _, member in string_hops for _, _, content, f in member["literals"] if f]
    structure = list(map(markup, stream_contents))
    root = _root(open_event, stream, flowing + hop_flowing) if open_event else None
    closing = end_tag(root) if root else None
    close = bool(closing and any(closing.search(content) for content in flowing))
    found = {
        "XMLDECL": any("<?xml" in content for content in structure),
        "XMLNS": any(START_TAG.search(content) and xmlns_tag(content, START_TAG.search(content))
                     for content in structure),
        "OPEN_BODY": bool(open_event and open_event[1] == "body"),
        "OPEN_HOP": bool(open_event and open_event[1] == "hop"),
        "ROOT": root,
        "CLOSE": close,
        "CLOSE_HOP": bool(closing and not close and any(closing.search(content) for content in hop_flowing)),
        "HTML": any(HTML.search(content) for content in stream_contents),
        "IDDEF": any(IDDEF.search(content) for content in contents + hop_contents),
        "REF": any(REF.search(content) for content in contents + hop_contents),
        "COMMENT": any("<!--" in content for content in contents + hop_contents),
        "STRING": is_string(unit["result"]),
        "NOTHROW": not unit["throws"],
        "SYNC": not unit["async"],
        "NONMUTATING": not unit["mutating"],
        "hops": sorted({name for _, name, _, _ in hops}),
    }
    views = [unit["code"][unit["body"][0]:unit["body"][1]]] + [
        member["code"][member["body"][0]:member["body"][1]] for _, _, _, member in hops]
    impure = sorted({pattern for pattern in IMPURITY for view in map(_without_print_to, views)
                     if re.search(pattern, view)})
    found["PURE"] = not impure
    found["impure"] = impure
    found["OPEN"] = found["OPEN_BODY"] or found["OPEN_HOP"]
    candidate = any(marker in content for content in contents for marker in GREP_MARKERS) or (
        found["OPEN_HOP"] and any(ANY_END_TAG.search(content) for content in contents))
    return found, candidate, hops


def copy_key(unit):
    """§1.3's copy key: name, labels, the code view of the body (interpolations kept) and the literal view's contents,
    whitespace collapsed. #669's key blanked literal text, and here the literals are the signal."""
    unit = analysed(unit)
    start, stop = unit["body"]
    parts = [unit["name"], ",".join(unit["labels"]), " ".join(unit["code"][start:stop].split()),
             "\x01".join(" ".join(content.split()) for _, _, content, _ in unit["literals"])]
    return hashlib.sha256("\x00".join(parts).encode()).hexdigest()[:16]


def is_gated(found):
    """§1.4: #668's signal, mechanically."""
    return all(found[cue] for cue in ("STRING", "NOTHROW", "SYNC", "NONMUTATING", "PURE", "OPEN", "CLOSE")) \
        and not found["HTML"]


def is_gated2(found):
    return is_gated(found) and found["ROOT"] == "svg" and found["IDDEF"]


def is_gated_without_pure(found):
    return all(found[cue] for cue in ("STRING", "NOTHROW", "SYNC", "NONMUTATING", "OPEN", "CLOSE")) \
        and not found["HTML"]


# ── The same-type index (§1.2) ────────────────────────────────────────────────────────────────────
class Repository:
    """Every unit and stored property of one repository, parsed lazily, indexed by owner for hops."""

    def __init__(self, files):
        self.files = files
        self.parsed = {}
        self.owners = {}

    def units(self, path):
        if path not in self.parsed:
            self.parsed[path] = units_of(path, self.files[path])
        return self.parsed[path]

    def members(self, owner, path):
        """`{name: [unit]}` of the same type: every declaration of `owner` in the repository, or, for a top-level
        unit, the same file's top-level units."""
        if not owner:
            units, stored = self.units(path)
            found = collections.defaultdict(list)
            for unit in units + stored:
                if not unit["owner"]:
                    found[unit["name"]].append(unit)
            return found
        if owner not in self.owners:
            pattern = re.compile(r"\b(?:struct|class|enum|actor|extension|protocol)\s+(?:[\w.]+\.)?"
                                 + re.escape(owner) + r"\b")
            found = collections.defaultdict(list)
            for other in sorted(self.files):
                if not pattern.search(self.files[other]):
                    continue
                units, stored = self.units(other)
                for unit in units + stored:
                    if unit["owner"] == owner:
                        found[unit["name"]].append(unit)
            self.owners[owner] = found
        return self.owners[owner]


UNICODE_ESCAPE = re.compile(r"\\#*u\{")


def census(files, repository_files=None, probes=None, prefilter=True, probe_names=()):
    """`candidates` over one subject's `{path: text}`. `repository_files` (default `files`) is every file of the
    subject's repository, for hops (§1.2). A unit named in `probe_names` (§6's R3) is appended to `probes` whether or
    not it is a candidate. With `prefilter`, a file or unit whose text holds no grep marker and no `</` is passed
    over without its cues: no literal of it can make it a candidate (§1.3). A `\\u{…}` or `\\#u{…}` escape, or a
    multi-line literal (whose line-ending `\\` joins two lines), can spell a marker the raw text does not hold, so
    any of them keeps it (X37)."""
    repository = Repository(repository_files if repository_files is not None else files)
    candidates = []

    def promising(text):
        return any(marker in text for marker in GREP_MARKERS + ("</", '"""')) or bool(UNICODE_ESCAPE.search(text))

    for path in sorted(files):
        text = files[path]
        if prefilter and not (promising(text) or any(name in text for name in probe_names)):
            continue
        units, _ = repository.units(path)
        for unit in units:
            probed = probes is not None and unit["name"] in probe_names
            if prefilter and not probed and not promising(unit["text"]):
                continue
            members = repository.members(unit["owner"], path)
            found, candidate, hops = cues(unit, members)
            row = make_row(unit, found, candidate, hops, members) if candidate or probed else None
            if probed:
                probes.append(dict(row, candidate=candidate))
            if candidate:
                candidates.append(row)
    return candidates


def make_row(unit, found, candidate, hops, members):
    referenced_by = sorted({name for name, others in members.items() for other in others
                            if other is not unit and other["kind"] != "stored"
                            and any(ref[0] == unit["name"] for ref in references(other, {unit["name"]},
                                                                                     unit["owner"]))})
    hop_texts = []
    for name in found["hops"]:
        for member in members.get(name, []):
            if member is unit:
                continue
            lines = member["text"].split("\n")
            shown = lines if len(lines) <= HOP_TEXT_CAP else lines[:HOP_TEXT_CAP] + [
                f"// … {len(lines) - HOP_TEXT_CAP} more lines left out"]
            hop_texts.append(f"// {os.path.basename(member['path'])}, line {member['line']}\n" + "\n".join(shown))
    return {"path": unit["path"], "line": unit["line"], "kind": unit["kind"], "owner": unit["owner"],
            "owner_kind": unit["owner_kind"], "name": unit["name"], "labels": unit["labels"],
            "visibility": unit["visibility"], "result": unit["result"], "cues": found,
            "gated": is_gated(found), "gated2": is_gated2(found), "gated_without_pure": is_gated_without_pure(found),
            "doc": unit["doc"], "owner_doc": unit["owner_doc"], "text": unit["text"], "key": copy_key(unit),
            "referenced_by": referenced_by, "hop_texts": hop_texts}


def merge_copies(rows):
    """§1.3: copies (same name, labels and masked body) count once, at the first in group order (decision,
    unmet, layout, wide), then repository (git toplevel), subject, path and line."""
    first = collections.OrderedDict()
    order = sorted(rows, key=lambda row: (GROUP_ORDER[row["group"]], row["toplevel"], row["repo"], row["path"],
                                          row["line"]))
    for row in order:
        where = f"{row['repo']}:{row['path']}:{row['line']}"
        if row["key"] in first:
            first[row["key"]]["copies"].append(where)
            first[row["key"]]["copy_groups"].append(row["group"])
            first[row["key"]]["copy_repos"].append(row["repo"])
        else:
            first[row["key"]] = dict(row, copies=[], copy_groups=[], copy_repos=[])
    return list(first.values())


# ── The universe (§2) and the run ─────────────────────────────────────────────────────────────────
# §6's R3: #668's named sites, by repository, owner (None for any) and name.
R3_SITES = [("SwiftUMLStudio", "ComponentSVGRenderer", "renderSVG"), ("SwiftUMLStudio", "SVGRenderer", "render"),
            ("SwiftUMLStudio", "ActivitySVGRenderer", "renderFromLayout"),
            ("SwiftUMLStudio", "ActivitySVGRenderer", "render"),
            ("SwiftUMLStudio", "SequenceSVGRenderer", "renderFromLayout"),
            ("SwiftUMLStudio", "SequenceSVGRenderer", "render"), ("SwiftLint", None, "generateReport"),
            ("swift-package-manager", None, "generate"), ("swift-package-manager", None, "generateResourceInfoPlist"),
            ("SwiftFormat", "XMLReporter", "write")]
R3_NAMES = {name for _, _, name in R3_SITES}


def r3_match(repo, row):
    """Whether a probed row is one of R3_SITES; SwiftPM's `generate` must carry `at:` and
    `detailedFailureMessage:`, and SwiftLint's `generateReport` must be a reporter's."""
    for site_repo, owner, name in R3_SITES:
        if repo != site_repo or row["name"] != name or (owner and row["owner"] != owner):
            continue
        if name == "generate" and row["labels"][:2] != ["at", "detailedFailureMessage"]:
            continue
        if name == "generateReport" and not row["owner"].endswith("Reporter"):
            continue
        return True
    return False


# §2: the decision and unmet lists. #669's, with the eight unmet subjects #666's census could not find, which now
# resolve under `~/github_projects`.
FROZEN = {
    "manifest": list(FROZEN_UNIVERSE["manifest"]),
    "funnel": list(FROZEN_UNIVERSE["funnel"]),
    "unmet": list(FROZEN_UNIVERSE["unmet"]) + ["Harbeth", "JiraKit", "nocturne-swift", "Open-Jellycore",
                                               "scale-codec-swift", "sora-ios-sdk", "StripeKit", "swift-codex"],
}

# §2: the wide group, re-taken on 2026-10-30 by #667's definition: every directory with Swift sources directly under
# `~/xcode_projects` and `~/github_projects` that no other group holds, with its `origin`. #667's 67 less SwiftLint
# (now a decision subject) and the two with no remote that live on another machine, plus three clones made since.
WIDE668 = [
    ("xcode_projects/SwiftCompilerFlagStudio", "https://github.com/joseph-cursio/swiftcompilerflagstudio"),
    ("xcode_projects/SwiftMutator", "https://github.com/joseph-cursio/swiftmutator"),
    ("github_projects/Alamofire", "https://github.com/alamofire/alamofire"),
    ("github_projects/AnyCodable", "https://github.com/flight-school/anycodable"),
    ("github_projects/BigInt", "https://github.com/attaswift/bigint"),
    ("github_projects/Checkout", "https://github.com/joseph-cursio/checkout"),
    ("github_projects/CombineExt", "https://github.com/combinecommunity/combineext"),
    ("github_projects/FHIRModels", "https://github.com/apple/fhirmodels"),
    ("github_projects/Hummingbird", "https://github.com/hummingbird-project/hummingbird"),
    ("github_projects/IceCubesApp", "https://github.com/dimillian/icecubesapp"),
    ("github_projects/KeychainAccess", "https://github.com/kishikawakatsumi/keychainaccess"),
    ("github_projects/Kingfisher", "https://github.com/onevcat/kingfisher"),
    ("github_projects/Mastermind", "https://github.com/jonreid/mastermind"),
    ("github_projects/Moya", "https://github.com/moya/moya"),
    ("github_projects/Nimble", "https://github.com/quick/nimble"),
    ("github_projects/OpenAI", "https://github.com/macpaw/openai"),
    ("github_projects/Quick", "https://github.com/quick/quick"),
    ("github_projects/RxSwift", "https://github.com/reactivex/rxswift"),
    ("github_projects/Sitrep", "https://github.com/joseph-cursio/sitrep"),
    ("github_projects/SnapKit", "https://github.com/snapkit/snapkit"),
    ("github_projects/SwaggerParser", "https://github.com/attilathefun/swaggerparser"),
    ("github_projects/SwiftPackageIndex-Server", "https://github.com/swiftpackageindex/swiftpackageindex-server"),
    ("github_projects/SwiftPlantUML", "https://github.com/marcoeidinger/swiftplantuml"),
    ("github_projects/SwiftyJSON", "https://github.com/swiftyjson/swiftyjson"),
    ("github_projects/TestableView", "https://github.com/jonreid/testableview"),
    ("github_projects/ViewInspector", "https://github.com/nalexn/viewinspector"),
    ("github_projects/XcodeGen", "https://github.com/yonaskolb/xcodegen"),
    ("github_projects/XcodeProj", "https://github.com/tuist/xcodeproj"),
    ("github_projects/Yams", "https://github.com/jpsim/yams"),
    ("github_projects/aider", "https://github.com/aider-ai/aider"),
    ("github_projects/algoliasearch-client-swift", "https://github.com/algolia/algoliasearch-client-swift"),
    ("github_projects/apollo-ios", "https://github.com/apollographql/apollo-ios"),
    ("github_projects/async-http-client", "https://github.com/swift-server/async-http-client"),
    ("github_projects/exhaust", "https://github.com/nesevis/exhaust"),
    ("github_projects/fluent-kit", "https://github.com/vapor/fluent-kit"),
    ("github_projects/indexstore-db", "https://github.com/swiftlang/indexstore-db"),
    ("github_projects/lottie-ios", "https://github.com/airbnb/lottie-ios"),
    ("github_projects/muter", "https://github.com/muter-mutation-testing/muter"),
    ("github_projects/muter-upstream", "https://github.com/joseph-cursio/muter"),
    ("github_projects/opentelemetry-swift", "https://github.com/open-telemetry/opentelemetry-swift"),
    ("github_projects/pkl-swift", "https://github.com/apple/pkl-swift"),
    ("github_projects/postgres-nio", "https://github.com/vapor/postgres-nio"),
    ("github_projects/scip-swift", "https://github.com/alex2481kobe/scip-swift"),
    ("github_projects/soto-core", "https://github.com/soto-project/soto-core"),
    ("github_projects/sourcekit-lsp", "https://github.com/swiftlang/sourcekit-lsp"),
    ("github_projects/supabase-swift", "https://github.com/supabase/supabase-swift"),
    ("github_projects/swift-asn1", "https://github.com/apple/swift-asn1"),
    ("github_projects/swift-async-algorithms", "https://github.com/apple/swift-async-algorithms"),
    ("github_projects/swift-atomics", "https://github.com/apple/swift-atomics"),
    ("github_projects/swift-aws-lambda-events", "https://github.com/swift-server/swift-aws-lambda-events"),
    ("github_projects/swift-aws-lambda-runtime", "https://github.com/swift-server/swift-aws-lambda-runtime"),
    ("github_projects/swift-certificates", "https://github.com/apple/swift-certificates"),
    ("github_projects/swift-composable-architecture", "https://github.com/pointfreeco/swift-composable-architecture"),
    ("github_projects/swift-configuration", "https://github.com/apple/swift-configuration"),
    ("github_projects/swift-crypto", "https://github.com/apple/swift-crypto"),
    ("github_projects/swift-docc-symbolkit", "https://github.com/swiftlang/swift-docc-symbolkit"),
    ("github_projects/swift-http-types", "https://github.com/apple/swift-http-types"),
    ("github_projects/swift-markdown", "https://github.com/swiftlang/swift-markdown"),
    ("github_projects/swift-mutation-testing", "https://github.com/ericodx/swift-mutation-testing"),
    ("github_projects/swift-openapi-generator", "https://github.com/apple/swift-openapi-generator"),
    ("github_projects/swift-openapi-runtime", "https://github.com/apple/swift-openapi-runtime"),
    ("github_projects/swift-property-based", "https://github.com/x-sheep/swift-property-based"),
    ("github_projects/swift-protobuf", "https://github.com/apple/swift-protobuf"),
    ("github_projects/swift-sdk", "https://github.com/modelcontextprotocol/swift-sdk"),
    ("github_projects/swift-service-lifecycle", "https://github.com/swift-server/swift-service-lifecycle"),
    ("github_projects/swift-testing", "https://github.com/swiftlang/swift-testing"),
    ("github_projects/vapor", "https://github.com/vapor/vapor"),
]
WIDE668_SHA256 = "5ce9dbf95b1ae4697c63e757328658e3d50bee6dfa33a80931b2a5d4948a52d0"


def wide668_hash():
    text = "\n".join(f"{relative} {url}" for relative, url in sorted(WIDE668, key=lambda entry: entry[0].lower()))
    return hashlib.sha256(text.encode()).hexdigest()


def groups():
    """§2, asserted: the decision group (the manifest and funnel subjects read from their roots, plus SwiftLint),
    unmet, layout (#667's graph-layout corpus at its frozen revisions) and wide (§2's list)."""
    found, _ = subjects()
    resolved = {group: [name for g, name, _, _ in found if g == group] for group in FROZEN}
    if resolved != FROZEN:
        raise SystemExit(f"the universe is not §2's frozen list:\n  resolved {resolved}\n  frozen   {FROZEN}")
    uml = [root for _, name, root, _ in found if name == "SwiftUMLStudio"]
    if not uml or not (revision(uml[0]) or "").startswith(SWIFTUMLSTUDIO) or git(uml[0], "status", "--porcelain"):
        raise SystemExit(f"§2 reads SwiftUMLStudio at {SWIFTUMLSTUDIO}, with a clean working tree")
    relative, url, sha = SWIFTLINT
    lint = os.path.join(HOME, relative)
    if (not os.path.isdir(lint) or origin(lint) != url or not (revision(lint) or "").startswith(sha)
            or git(lint, "status", "--porcelain")):
        raise SystemExit(f"§2 reads SwiftLint at {lint}, {url} at {sha}, with a clean working tree")
    if wide668_hash() != WIDE668_SHA256:
        raise SystemExit(f"§2's wide list hashes to {wide668_hash()}, not the frozen {WIDE668_SHA256}")
    result = [("decision" if g in ("manifest", "funnel") else g, name, root, [root])
              for g, name, root, _ in found]
    result.append(("decision", "SwiftLint", lint, [lint]))
    for wide_relative, wide_url in WIDE668:
        root = os.path.join(HOME, wide_relative)
        if not os.path.isdir(root) or origin(root) != wide_url:
            raise SystemExit(f"§2's wide member {wide_relative} is missing or has origin {origin(root)}, not {wide_url}")
        result.append(("wide", os.path.basename(wide_relative), root, [root]))
    result += [("layout", name, root, roots) for _, name, root, roots in corpus_universe()]
    return result


def choose(report):
    """§4.1: decision, unmet and layout candidates in full up to JUDGED_CAP; wide up to WIDE_CAP, sampled above."""
    def sample(rows, size):
        rows = sorted(rows, key=lambda row: row["id"])
        return rows if len(rows) <= size else random.Random(SEED).sample(rows, size)

    rows = report["candidates"]
    full = [row for row in rows if row["group"] != "wide"]
    if len(full) > JUDGED_CAP:
        raise SystemExit(f"{len(full)} non-wide candidates exceed §4.1's cap of {JUDGED_CAP}; the scope says what then")
    judged = {row["id"] for row in full} | {row["id"] for row in sample([r for r in rows if r["group"] == "wide"],
                                                                         WIDE_CAP)}
    for row in rows:
        row["judged"] = row["id"] in judged


R4_MARKERS = ("<?xml", "<svg", "</svg>", "<plist", "</plist>")


def r4_files(files):
    """§6's R4: the files whose literals hold one of #668's grep markers."""
    hits = []
    for path, text in files.items():
        if any(marker in text for marker in R4_MARKERS):
            if any(marker in content for _, _, content in literal_view(text) for marker in R4_MARKERS):
                hits.append(path)
    return sorted(hits)


def run(out_path):
    if not self_test():
        raise SystemExit("a control failed — not reporting candidates")
    by_root = collections.OrderedDict()
    for group, name, root, roots in groups():
        key = os.path.realpath(root)
        entry = by_root.setdefault(key, {"group": group, "name": name, "root": root, "roots": [], "also": []})
        if entry["name"] != name:
            entry["also"].append(name)
        entry["roots"].extend(roots)
    read = {}
    for key, entry in by_root.items():
        files, skipped = subject_files(entry["root"], sorted(set(entry["roots"])))
        files, dropped = without_fixtures(files, entry["root"])
        skipped = dict(skipped, fixtures=dropped) if dropped else dict(skipped)
        unparsable = sorted(path for path, text in files.items() if not parsable(text))
        for path in unparsable:
            del files[path]
        if unparsable:
            skipped["unparsable"] = [os.path.relpath(path, key) for path in unparsable]
        read[key] = (files, skipped)
    tops = {key: toplevel(entry["root"]) for key, entry in by_root.items()}
    repository_files = collections.defaultdict(dict)
    for key, (files, _) in read.items():
        repository_files[tops[key]].update(files)
    report = {"subjects": [], "candidates": [], "probes": {"R3": [], "R4": {}}}
    rows, members = [], {}
    for key, entry in by_root.items():
        files, skipped = read[key]
        probes = []
        names = {name for repo, _, name in R3_SITES if repo == entry["name"]}
        candidates = census(files, repository_files[tops[key]], probes, probe_names=names)
        report["subjects"].append({
            "group": entry["group"], "name": entry["name"], "also": entry["also"], "root": key,
            "toplevel": tops[key], "revision": revision(entry["root"]),
            "dirty": bool(git(entry["root"], "status", "--porcelain")), "files": len(files), "skipped": skipped,
            "candidates": len(candidates)})
        hits = r4_files(files)
        if hits:
            report["probes"]["R4"][entry["name"]] = [os.path.relpath(path, key) for path in hits]
        for row in candidates + probes:
            absolute = row["path"]
            row["path"] = os.path.relpath(absolute, key)
            row.update(group=entry["group"], repo=entry["name"], root=key, toplevel=tops[key])
            row["id"] = f"{entry['name']}:{row['path']}:{row['line']}"
            if row in candidates and row["owner"]:
                cache = (tops[key], row["owner"])
                if cache not in members:
                    members[cache] = owner_entries(repository_files[tops[key]], row["owner"])
                row["members"] = member_lines(members[cache], first=absolute, skip=(absolute, row["line"]))
        rows += candidates
        report["probes"]["R3"] += [dict(row, site=True) for row in probes if r3_match(entry["name"], row)]
    seen = {(row["repo"], row["owner"], row["name"]) for row in report["probes"]["R3"]}
    for repo, owner, name in R3_SITES:
        if not any(r == repo and n == name and (owner is None or o == owner) for r, o, n in seen):
            report["probes"]["R3"].append({"site": [repo, owner, name], "status": "not read",
                                           "why": "no unit of that name in the files §2 reads"
                                           if repo in {entry["name"] for entry in by_root.values()}
                                           else "outside §2's universe"})
    report["candidates_before_copy_merge"] = len(rows)
    report["candidates"] = merge_copies(rows)
    choose(report)
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=1, sort_keys=True)
    for group in GROUP_ORDER:
        found = [row for row in report["candidates"] if row["group"] == group]
        repos = collections.Counter(row["repo"] for row in found)
        print(f"  {group}: {len(found)} candidates ({sum(r['gated'] for r in found)} GATED,"
              f" {sum(r['gated2'] for r in found)} GATED2) over {len(repos)} subjects,"
              f" {sum(r['judged'] for r in found)} judged  {dict(repos.most_common(6))}")
    print(f"  before the copy merge {report['candidates_before_copy_merge']}; R3 sites {len(report['probes']['R3'])};"
          f" R4 files {sum(len(v) for v in report['probes']['R4'].values())}")


def render(label, row):
    """One row as a packet shows it (§4.3): never its cues, GATED, GATED2 or group."""
    members = "\n".join(row.get("members") or ["(none found)"])
    hops = "\n\n".join(row.get("hop_texts") or []) or "(none)"
    return (f"## {label}\n\n- repository: `{row['repo']}`, at `{row['root']}`\n"
            f"- file: `{row['path']}`, line {row['line']}\n"
            f"- unit: a {'function' if row['kind'] == 'func' else 'computed property'}\n"
            f"- owner: `{row['owner'] or '(top level)'}` ({row['owner_kind'] or 'none'})\n"
            f"- owner's doc comment: {row['owner_doc'] or '(none)'}\n"
            f"- the unit's doc comment: {row['doc'] or '(none)'}\n"
            f"- same-type members that reference it: {', '.join(row['referenced_by']) or '(none)'}\n"
            f"- the owner's other members in this repository (bodies left out):\n\n```swift\n{members}\n```\n\n"
            f"- the same-type members it references, in full:\n\n```swift\n{hops}\n```\n\n"
            f"The unit:\n\n```swift\n{row['text']}\n```\n")


def packets(census_path, out_dir):
    """§4.3: blind packets, seeded order, at most eight rows each. The label index is written beside the packet
    directory, never in it."""
    report = json.load(open(census_path, encoding="utf-8"))
    rows = sorted((row for row in report["candidates"] if row["judged"]), key=lambda row: row["id"])
    random.Random(SEED).shuffle(rows)
    if os.path.isdir(out_dir) and os.listdir(out_dir):
        raise SystemExit(f"{out_dir} is not empty: packets go in a directory that holds nothing else")
    os.makedirs(out_dir, exist_ok=True)
    index = []
    for number in range(0, len(rows), PACKET_SIZE):
        chunk = rows[number:number + PACKET_SIZE]
        name = f"packet-{number // PACKET_SIZE + 1:02d}"
        parts = [f"# {name}\n"]
        for position, row in enumerate(chunk, 1):
            label = f"{name}/{position}"
            index.append({"label": label, "id": row["id"]})
            parts.append(render(label, row))
        with open(os.path.join(out_dir, f"{name}.md"), "w", encoding="utf-8") as handle:
            handle.write("\n".join(parts))
    beside = os.path.dirname(os.path.abspath(out_dir))
    with open(os.path.join(beside, "index.json"), "w", encoding="utf-8") as handle:
        json.dump(index, handle, indent=1)
    # The judge workflow's `args.sizes` (§4.3): each packet's row count, in order.
    sizes = [len(rows[number:number + PACKET_SIZE]) for number in range(0, len(rows), PACKET_SIZE)]
    with open(os.path.join(beside, "sizes.json"), "w", encoding="utf-8") as handle:
        json.dump(sizes, handle)
    print(f"{len(rows)} rows in {len(sizes)} packets → {out_dir}; sizes {json.dumps(sizes)}")


def render_one(path, name, repo_root, label="calibration/N"):
    """§4.2: one unit of a real file, in a packet's format, with its repository's members."""
    root = os.path.realpath(repo_root)
    files, _ = subject_files(root, [root])
    absolute = os.path.realpath(path)
    rows = [row for row in census({absolute: files[absolute]}, files, probes=None, prefilter=False)
            if row["name"] == name]
    if not rows:
        units, _ = units_of(absolute, files[absolute])
        unit = next(u for u in units if u["name"] == name)
        members = Repository(files).members(unit["owner"], absolute)
        found, candidate, hops = cues(unit, members)
        rows = [make_row(unit, found, candidate, hops, members)]
    row = rows[0]
    row.update(repo=os.path.basename(root), root=root, path=os.path.relpath(absolute, root))
    row["members"] = member_lines(owner_entries(files, row["owner"]), first=absolute, skip=(absolute, row["line"])) \
        if row["owner"] else []
    print(render(label, row))


# ── The judgements (§4.3–§4.4) ────────────────────────────────────────────────────────────────────
VERDICTS = {"DOCUMENT", "FRAGMENT", "HTML", "NOT-EMITTER", "UNDETERMINED"}
LAW2 = {"OWES", "VACUOUS", "EXTERNAL", "NOT-SVG"}
BOOLEAN_FIELDS = ("expressible", "ambient", "body_disagrees", "refs_dangle")
FLAGS = ("ambient", "body_disagrees", "refs_dangle")


def usable(record):
    """A judge's record is usable when its verdict is known and, for DOCUMENT, each flag is answered."""
    if not isinstance(record, dict) or record.get("verdict") not in VERDICTS:
        return False
    return record["verdict"] != "DOCUMENT" or (all(isinstance(record.get(f), bool) for f in BOOLEAN_FIELDS)
                                               and record.get("law2") in LAW2)


def _agree(first, second):
    return (usable(first) and usable(second) and first["verdict"] == second["verdict"]
            and (first["verdict"] != "DOCUMENT"
                 or (first["expressible"] == second["expressible"] and first["law2"] == second["law2"])))


def records_by_label(judge, records):
    """One judge's records keyed by label; a judge that repeats a label is refused (§4.3), never last-wins."""
    counts = collections.Counter(record.get("label") for record in records)
    repeated = sorted(label for label, count in counts.items() if count > 1)
    if repeated:
        raise SystemExit(f"judge {judge} repeats labels: {repeated[:5]}")
    return {record["label"]: record for record in records}


def _union(record, others):
    """A DOCUMENT record with each flag raised when any of `others` (the usable DOCUMENT records beside it) raises
    it, and every witness kept."""
    record = dict(record)
    peers = [other for other in others if usable(other) and other["verdict"] == "DOCUMENT"]
    for flag in FLAGS:
        record[flag] = any(other[flag] for other in [record] + peers)
    record["witness"] = " | ".join(w for w in dict.fromkeys(other.get("witness") for other in [record] + peers) if w)
    return record


def join(index, verdicts):
    """§4.3: each label's final record. `verdicts` maps a judge (`A`, `B`, `C`) to that judge's list of records. A
    and B decide when they agree on the verdict and, for DOCUMENT, on EXPRESSIBLE and law2. Otherwise C decides. On
    a DOCUMENT row the flags (*ambient*, *body disagrees*, *refs dangle*) are raised when any judge whose record
    is a usable DOCUMENT raises them, with every witness kept. Unknown, repeated or missing labels are refused, and
    so is a disagreement C has not judged."""
    labels = [entry["label"] for entry in index]
    if len(set(labels)) != len(labels):
        raise SystemExit("the index repeats a label")
    by_judge = {judge: records_by_label(judge, records) for judge, records in verdicts.items()}
    for judge, records in by_judge.items():
        unknown = set(records) - set(labels)
        if unknown:
            raise SystemExit(f"judge {judge} labelled rows the index does not hold: {sorted(unknown)[:5]}")
    final = {}
    for entry in index:
        label = entry["label"]
        first, second = by_judge.get("A", {}).get(label), by_judge.get("B", {}).get(label)
        if first is None or second is None:
            raise SystemExit(f"{label} lacks a judge A or B record")
        if _agree(first, second):
            # A record C gave for a row A and B agreed on decides nothing, but its flags are kept (§4.3).
            peers = [second] + ([by_judge["C"][label]] if label in by_judge.get("C", {}) else [])
            record = dict(_union(first, peers) if first["verdict"] == "DOCUMENT" else first, decided_by="A+B")
        elif label in by_judge.get("C", {}):
            third = by_judge["C"][label]
            if not usable(third):
                record = {"verdict": "UNDETERMINED", "decided_by": "C"}
            elif third["verdict"] == "DOCUMENT":
                record = dict(_union(third, [first, second]), decided_by="C")
            else:
                record = dict(third, decided_by="C")
        else:
            raise SystemExit(f"{label}: A and B disagree and no judge C record exists")
        final[entry["id"]] = record
    return final


# §4.2: the calibration items' expected answers. Only this file, the scope and the judge workflow hold them, and the
# judges may read none of the three. Each judge's record must match on every field named here.
CALIBRATION = {
    "calibration/1": {"verdict": "DOCUMENT", "expressible": True, "law2": "OWES", "body_disagrees": False,
                      "refs_dangle": False},
    "calibration/2": {"verdict": "FRAGMENT"},
    "calibration/3": {"verdict": "DOCUMENT", "expressible": True, "body_disagrees": True},
    "calibration/4": {"verdict": "HTML"},
    "calibration/5": {"verdict": "NOT-EMITTER"},
    "calibration/6": {"verdict": "DOCUMENT", "expressible": True, "law2": "NOT-SVG", "body_disagrees": False},
    "calibration/7": {"verdict": "DOCUMENT", "expressible": False},
    "calibration/8": {"verdict": "DOCUMENT", "law2": "EXTERNAL"},
    "calibration/9": {"verdict": "DOCUMENT", "law2": "VACUOUS"},
    "calibration/10": {"verdict": "DOCUMENT", "expressible": True, "body_disagrees": True},
}


def calibrate(records):
    """§4.2: the labels whose record misses an expected answer, is missing, is repeated, or is not `usable` (a
    DOCUMENT record that leaves a flag unanswered). An empty list passes."""
    counts = collections.Counter(record.get("label") for record in records)
    by_label = {record.get("label"): record for record in records}
    return [label for label, expected in CALIBRATION.items()
            if counts[label] != 1 or not usable(by_label[label])
            or any(by_label[label].get(field) != value for field, value in expected.items())]


def judge_files(result):
    """§4.3: `{judge: records}` from the judge workflow's output, each judge's raw records concatenated over the
    packets in order, never a label map, so that `join` sees a repeat. Refuses a stopped run, a packet that returned
    nothing, and a calibration record `calibrate` misses."""
    if result.get("stopped"):
        raise SystemExit(f"the judge workflow stopped at {result['stopped']}")
    for judge, entry in zip("AB", result["calibration"]):
        missed = calibrate((entry or {}).get("records") or [])
        if missed:
            raise SystemExit(f"calibration judge {judge} missed {missed}")
    files = {"A": [], "B": [], "C": []}
    for packet in result["judged"]:
        if not packet:
            raise SystemExit("a packet's judging returned nothing")
        for judge in files:
            files[judge] += packet["records"][judge]
    return files


# ── The decision (§4.5, §8) ───────────────────────────────────────────────────────────────────────
BAR_COUNT, BAR_REPOSITORIES, GATE_PRECISION_BAR = 5, 2, 0.70
# §8's sensitivity: the subject #668 named, which #667's and #669's universes held in the wide group.
NAMED = "SwiftLint"
LAW1_CUES = ("STRING", "NOTHROW", "SYNC", "NONMUTATING", "PURE", "OPEN", "CLOSE")


def owes(verdict, law, need_expressible=True):
    if verdict.get("verdict") != "DOCUMENT":
        return False
    if need_expressible and verdict.get("expressible") is not True:
        return False
    return law == 1 or verdict.get("law2") == "OWES"


def owing_groups(rows, verdicts, law, need_expressible=True, group="decision"):
    """§4.5: owing rows of one group, merged: a row also merges with an owing row of the same type (same
    repository and owner, or the same file for top-level units) that it references or that references it."""
    members = [row for row in rows if row["group"] == group and row.get("judged")
               and owes(verdicts.get(row["id"], {}), law, need_expressible)]
    parent = {row["id"]: row["id"] for row in members}

    def find(identifier):
        while parent[identifier] != identifier:
            parent[identifier] = parent[parent[identifier]]
            identifier = parent[identifier]
        return identifier

    by_type = collections.defaultdict(list)
    for row in members:
        by_type[(row["toplevel"], row["owner"] or row["path"])].append(row)
    for same in by_type.values():
        for row in same:
            for other in same:
                if other is not row and (other["name"] in row["cues"]["hops"] or other["name"] in row["referenced_by"]):
                    parent[find(row["id"])] = find(other["id"])
    merged = collections.OrderedDict()
    for row in members:
        merged.setdefault(find(row["id"]), []).append(row)
    return list(merged.values())


def repositories(groups_):
    """A repository counts when it holds a merged group's first row (§4.5)."""
    return {group_[0]["toplevel"] for group_ in groups_}


def clears(count, repos):
    return count >= BAR_COUNT and repos >= BAR_REPOSITORIES


def missed(row, law):
    """§6's R2: the gate cues a row lacks. CLOSE-HOP is named when the close is only in a hop."""
    cues = row["cues"]
    found = {cue for cue in LAW1_CUES if not cues[cue]} | ({"HTML"} if cues["HTML"] else set())
    if not cues["CLOSE"] and cues.get("CLOSE_HOP"):
        found.add("CLOSE-HOP")
    if law == 2:
        found |= ({"ROOT≠svg"} if cues["ROOT"] != "svg" else set()) | ({"¬IDDEF"} if not cues["IDDEF"] else set())
    return sorted(found)


def law_figures(rows, judged, verdicts, law):
    gate = "gated" if law == 1 else "gated2"
    population = owing_groups(rows, verdicts, law)
    gated_groups = [group_ for group_ in population if any(row[gate] for row in group_)]
    decision_gated = [row for row in judged if row["group"] == "decision" and row[gate]]
    true_gated = [row for row in decision_gated if owes(verdicts[row["id"]], law, need_expressible=False)]
    loose = owing_groups(rows, verdicts, law, need_expressible=False)
    outside = {group: owing_groups(rows, verdicts, law, group=group) for group in ("unmet", "layout", "wide")}
    wide_total = len([row for row in rows if row["group"] == "wide"])
    wide_judged = len([row for row in judged if row["group"] == "wide"])
    wide_estimate = len(outside["wide"]) * wide_total / wide_judged if wide_judged else 0.0
    undetermined = [[row] for row in judged if row["group"] == "decision"
                    and verdicts[row["id"]]["verdict"] == "UNDETERMINED"]
    owing_rows = [row for row in judged if row["group"] == "decision" and owes(verdicts[row["id"]], law)]
    without_pure = [row for row in judged if row["group"] == "decision" and row["gated_without_pure"]
                    and (law == 1 or (row["cues"]["ROOT"] == "svg" and row["cues"]["IDDEF"]))]
    without_named = owing_groups([row for row in rows if row["repo"] != NAMED], verdicts, law)
    unambient = [group_ for group_ in population
                 if any(row[gate] and verdicts[row["id"]].get("ambient") is False for row in group_)]
    anywhere = sorted({repo for row in judged
                       if verdicts[row["id"]].get("verdict") == "DOCUMENT" and verdicts[row["id"]].get("law2") == "OWES"
                       for repo in [row["repo"]] + row.get("copy_repos", [])})
    figures = {
        "N": len(population), "repositories": len(repositories(population)),
        "N_gated": len(gated_groups), "gated_repositories": len(repositories(gated_groups)),
        "gated": len(decision_gated), "gated_owing": len(true_gated),
        "precision": len(true_gated) / len(decision_gated) if decision_gated else 0.0,
        "gated_not_owing": [row["id"] for row in decision_gated
                            if not owes(verdicts[row["id"]], law, need_expressible=False)],
        "precision_without_pure": (sum(owes(verdicts[row["id"]], law, need_expressible=False) for row in without_pure),
                                   len(without_pure)),
        "N_without_expressible": len(loose), "N_without_expressible_repositories": len(repositories(loose)),
        "N_unmet": len(outside["unmet"]), "N_layout": len(outside["layout"]), "N_wide": len(outside["wide"]),
        "wide_candidates": wide_total, "wide_judged": wide_judged, "N_wide_estimate": round(wide_estimate, 1),
        "N_undetermined": len(undetermined),
        "ungated_owing": [{"id": group_[0]["id"], "expressible": verdicts[group_[0]["id"]].get("expressible"),
                           "missed": missed(group_[0], law)}
                          for group_ in loose if not any(row[gate] for row in group_)],
        "outside_without_expressible": {group: len(owing_groups(rows, verdicts, law, need_expressible=False,
                                                                group=group)) for group in ("unmet", "layout", "wide")},
        "N_wide_estimate_without_expressible": round(
            len(owing_groups(rows, verdicts, law, need_expressible=False, group="wide")) * wide_total / wide_judged
            if wide_judged else 0.0, 1),
        "unmerged": len(owing_rows) + sum(group == "decision" for row in owing_rows
                                          for group in row.get("copy_groups", [])),
        "owing_anywhere": anywhere,
        "N_gated_unambient": (len(unambient), len(repositories(unambient))),
    }
    base = repositories(population)
    figures["sensitivity"] = {
        "N + N_unmet + N_layout + N_wide": (
            len(population) + len(outside["unmet"]) + len(outside["layout"]) + round(wide_estimate),
            len(base | repositories(outside["unmet"]) | repositories(outside["layout"])
                | repositories(outside["wide"]))),
        "N + N_undetermined": (len(population) + len(undetermined), len(base | repositories(undetermined))),
        "N without EXPRESSIBLE": (len(loose), len(repositories(loose))),
        f"N without {NAMED}": (len(without_named), len(repositories(without_named))),
    }
    return figures


def law_outcome(law, figures, summary):
    """§8: the first outcome that applies, for one law."""
    if law == 2 and figures["repositories"] == 1:
        return "DECLINE (population: a single subject)"
    if not clears(figures["N"], figures["repositories"]):
        return "DECLINE (population)"
    if not clears(figures["N_gated"], figures["gated_repositories"]):
        return "DECLINE (signal)"
    if figures["precision"] < GATE_PRECISION_BAR:
        return "DECLINE (gate precision)"
    law_summary = (summary or {}).get(f"law{law}") if summary else None
    if (not summary or not summary.get("controls_passed") or not summary.get("complete") or not law_summary
            or law_summary.get("decisive") is None):
        return "UNMEASURED (kills)"
    if law_summary["decisive"] == 0:
        return "DECLINE (kills)"
    return "BUILD"


def decide(report, judgements, kills):
    """§8: `({law: outcome}, {law: figures}, lines)`. Refuses unless every judged row has exactly one judgement, so
    a dropped packet can never read as rows that do not owe a law."""
    rows = report["candidates"]
    judged = [row for row in rows if row["judged"]]
    missing = [row["id"] for row in judged if row["id"] not in judgements]
    if missing:
        raise SystemExit(f"{len(missing)} judged rows have no judgement, e.g. {missing[:3]}")
    extra = set(judgements) - {row["id"] for row in judged}
    if extra:
        raise SystemExit(f"judgements for rows that were not judged: {sorted(extra)[:3]}")
    verdicts = {identifier: (record if usable(record) else {"verdict": "UNDETERMINED"})
                for identifier, record in judgements.items()}
    summary = (kills or {}).get("summary")
    outcomes, all_figures, lines = {}, {}, []
    for law in (1, 2):
        figures = law_figures(rows, judged, verdicts, law)
        law_summary = (summary or {}).get(f"law{law}") or {}
        figures["decisive"] = law_summary.get("decisive")
        figures["decisive_with_hand"] = law_summary.get("decisive_with_hand")
        outcomes[law] = law_outcome(law, figures, summary)
        all_figures[law] = figures
        lines += decision_lines(law, outcomes[law], figures, law_summary, (summary or {}).get("hand"))
    lines.append("body disagrees: " + (", ".join(row["id"] for row in judged
                                                  if verdicts[row["id"]].get("body_disagrees") is True) or "none")
                 + "   refs dangle: " + (", ".join(row["id"] for row in judged
                                                   if verdicts[row["id"]].get("refs_dangle") is True) or "none")
                 + f"   unparsable files dropped "
                   f"{sum(len(s['skipped'].get('unparsable', [])) for s in report.get('subjects', []))}")
    return outcomes, all_figures, lines


def decision_lines(law, outcome, figures, summary, hand=None):
    gate = "GATED" if law == 1 else "GATED2"
    kept, total = figures["precision_without_pure"]
    unambient, unambient_repos = figures["N_gated_unambient"]
    lines = [
        f"LAW {law} DECISION: {outcome}  N{law} = {figures['N']} over {figures['repositories']} local repositories"
        f" (bar: ≥ {BAR_COUNT} across ≥ {BAR_REPOSITORIES})  N_gated = {figures['N_gated']}"
        f"  {gate} precision {figures['gated_owing']}/{figures['gated']} ({figures['precision']:.0%})",
        f"law {law}-only (reduced suite): {summary.get('decisive', '—')} by assertion,"
        f" {summary.get('law_only_reduced_other', '—')} by crash/timeout/memory"
        f"   law-only (full suite): {summary.get('law_only_full', '—')}"
        f"   law {summary.get('law', '—')}, suite {summary.get('suite', '—')}, reduced {summary.get('reduced', '—')},"
        f" viable {summary.get('viable', '—')}",
        f"law {law} beside: unmerged {figures['unmerged']}  N_unmet {figures['N_unmet']}  N_layout {figures['N_layout']}"
        f"  N_wide {figures['N_wide']} ({figures['wide_judged']} of {figures['wide_candidates']} judged, estimate"
        f" {figures['N_wide_estimate']})  N_undetermined {figures['N_undetermined']}"
        f"  {gate} precision without PURE {kept}/{total}",
        f"law {law} without EXPRESSIBLE: N {figures['N_without_expressible']}"
        + "".join(f"  N_{group} {count}" for group, count in figures["outside_without_expressible"].items())
        + f" (estimate {figures['N_wide_estimate_without_expressible']})",
        f"law {law} {gate} not owing: {', '.join(figures['gated_not_owing']) or 'none'}",
        f"law {law} R2 (owing, no {gate} member): "
        + ("; ".join(f"{entry['id']} (EXPRESSIBLE {entry['expressible']}, missed {', '.join(entry['missed'])})"
                     for entry in figures["ungated_owing"]) or "none"),
    ]
    if law == 2:
        lines.append(f"law 2 repositories with an owing SVG emitter in any group: "
                     f"{', '.join(figures['owing_anywhere']) or 'none'}")
    for name, (count, repos) in figures["sensitivity"].items():
        lines.append(f"SENSITIVITY law {law} {name}: {count} over {repos} repositories"
                     f" — {'clears' if clears(count, repos) else 'does not clear'} the population bar")
    lines.append(f"SENSITIVITY law {law} N_gated without rows judged ambient: {unambient} over {unambient_repos}"
                 f" repositories — {'clears' if clears(unambient, unambient_repos) else 'does not clear'} the signal bar")
    with_hand = summary.get("decisive_with_hand")
    lines.append(f"SENSITIVITY law {law} decisive count with H1–H6 counted: "
                 + ("—" if with_hand is None else f"{with_hand} — {'clears' if with_hand > 0 else 'does not clear'}"
                                                  " the kills bar (more than 0)"))
    lines.append(f"law {law} hand mutants: " + ("; ".join(
        f"{entry['id']} law {entry[f'law{law}'] or 'SURVIVED'}, reduced {entry['reduced'] or 'SURVIVED'},"
        f" full {entry['suite'] or 'SURVIVED'}" for entry in hand) if hand else "—"))
    return lines


# ── R5: GitHub code search (§6) ───────────────────────────────────────────────────────────────────
QUERIES = [("Q1", '"<?xml version" language:Swift'), ("Q2", '"xmlns=" "</svg>" language:Swift'),
           ("Q3", '"url(#" language:Swift'), ("Q4", '"<!DOCTYPE html" language:Swift'),
           ("Q5", '"</checkstyle>" language:Swift'), ("Q6", '"</testsuites>" language:Swift')]


def search(out_path):
    """§6's R5: each frozen query once, its `total_count`, and the ten repositories with the most matching files
    among the first 100 results. GitHub counts files, test files included."""
    results = {}
    for label, query in QUERIES:
        out = subprocess.run(["gh", "api", "-X", "GET", "search/code", "-f", f"q={query}", "-f", "per_page=100"],
                             capture_output=True, text=True)
        if out.returncode != 0:
            results[label] = {"query": query, "error": out.stderr.strip()[:500]}
            continue
        data = json.loads(out.stdout)
        repos = collections.Counter(item["repository"]["full_name"] for item in data.get("items", []))
        results[label] = {"query": query, "total_count": data.get("total_count"),
                          "incomplete_results": data.get("incomplete_results"),
                          "top_repositories": repos.most_common(10)}
        print(f"{label} {query}: {data.get('total_count')} files; top {repos.most_common(3)}")
    date = subprocess.run(["date", "-u", "+%Y-%m-%dT%H:%M:%SZ"], capture_output=True, text=True).stdout.strip()
    json.dump({"date": date, "results": results}, open(out_path, "w", encoding="utf-8"), indent=1)


# ── Controls (§3) ─────────────────────────────────────────────────────────────────────────────────
# C1, C2: SwiftUMLStudio `9ad7631`, `Model/ComponentSVGRenderer+SVG.swift`, verbatim (lines 1-67 and 197-203).
COMPONENT_SVG = r'''import Foundation

// MARK: - SVG output

extension ComponentSVGRenderer {

    /// Shared font-family attribute for every text element.
    private static var textFontFamily: String { "system-ui, -apple-system, sans-serif" }

    /// Render a positioned `ComponentLayout` as a standalone SVG document.
    /// Kept lightweight — Studio uses the native renderer; this SVG is the
    /// WebView fallback when the user picks .svg without launching Studio.
    public static func renderSVG(_ layout: ComponentLayout) -> String {
        guard !layout.components.isEmpty else { return "" }

        var lines: [String] = []
        lines.append(svgHeader(width: layout.totalWidth, height: layout.totalHeight))
        lines.append(arrowMarkerDefs)

        // Edges first so boxes paint over them at their borders.
        for dependency in layout.dependencies {
            if let edgeLine = edgeSVGLine(for: dependency, in: layout) {
                lines.append(edgeLine)
            }
        }

        for component in layout.components {
            lines.append(contentsOf: componentSVGLines(for: component))
        }

        lines.append("</svg>")
        return lines.joined(separator: "\n")
    }

    // MARK: - SVG fragments

    static func svgHeader(width: Double, height: Double) -> String {
        let widthInt = Int(width.rounded(.up))
        let heightInt = Int(height.rounded(.up))
        return "<svg xmlns=\"http://www.w3.org/2000/svg\""
            + " width=\"\(widthInt)\" height=\"\(heightInt)\""
            + " viewBox=\"0 0 \(widthInt) \(heightInt)\">"
    }

    static var arrowMarkerDefs: String {
        """
        <defs>
          <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5"\
         markerWidth="6" markerHeight="6" orient="auto-start-reverse">
            <path d="M 0 0 L 10 5 L 0 10 z" fill="#444"/>
          </marker>
        </defs>
        """
    }

    static func edgeSVGLine(
        for dependency: ComponentDependency,
        in layout: ComponentLayout
    ) -> String? {
        guard
            let source = layout.component(named: dependency.from),
            let target = layout.component(named: dependency.to)
        else { return nil }
        let (startX, startY) = edgePoint(from: source, towards: target)
        let (endX, endY) = edgePoint(from: target, towards: source)
        return "<line"
            + " x1=\"\(format(startX))\" y1=\"\(format(startY))\""
            + " x2=\"\(format(endX))\" y2=\"\(format(endY))\""
            + " stroke=\"#444\" stroke-width=\"1.2\""
            + " stroke-dasharray=\"5 4\" marker-end=\"url(#arrow)\"/>"
    }

    static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

}
'''

# C3: SwiftUMLStudio `9ad7631`, `Emitters/SVGRenderer.swift`: `render`, one of `arrowMarkers`' four markers, and
# `renderNode`'s and `renderEdge`'s opening lines and markers, each line verbatim. §10 records that the real files give
# the cues C1-C5 expect.
SVG_RENDERER = r'''import Foundation

/// Renders a positioned `LayoutGraph` as an SVG XML string.
public struct SVGRenderer: Sendable {

    private static let strokeColor = "#333333"

    /// Render the positioned layout graph to an SVG string.
    public static func render(_ graph: LayoutGraph) -> String {
        let margin: Double = 20
        let svgWidth = graph.width + margin * 2
        let svgHeight = graph.height + margin * 2

        var svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(svgWidth))" height="\(Int(svgHeight))" \
        viewBox="0 0 \(Int(svgWidth)) \(Int(svgHeight))" \
        style="font-family: -apple-system, 'SF Pro Text', 'Helvetica Neue', sans-serif;">
        <defs>
            \(arrowMarkers())
        </defs>
        """

        // Render module cluster boxes first (behind everything)
        for cluster in graph.clusters {
            svg += renderCluster(cluster)
        }

        // Render edges (behind nodes)
        for edge in graph.edges {
            svg += renderEdge(edge)
        }

        // Render nodes
        for node in graph.nodes {
            svg += renderNode(node)
        }

        svg += "\n</svg>"
        return svg
    }

    // MARK: - Arrow Markers

    private static func arrowMarkers() -> String {
        """
        <marker id="arrow-inheritance" viewBox="0 0 12 12" refX="12" refY="6" \
        markerWidth="12" markerHeight="12" orient="auto-start-reverse">
            <path d="M 0 0 L 12 6 L 0 12 Z" fill="white" stroke="\(strokeColor)" stroke-width="1"/>
        </marker>
        """
    }

    private static func renderNode(_ node: LayoutNode) -> String {
        let leftX = node.posX - node.width / 2
        let topY = node.posY - node.height / 2
        let stereotype = node.stereotype ?? "class"
        let fill = headerFill[stereotype] ?? headerFill["class"]!

        // The label appears only in the <text> elements. It is not copied into an XML comment,
        // because a comment cannot contain `--` and no escaping makes it legal there (#56).
        var svg = "\n<g>\n"

        // Name label
        let nameY = topY + 28
        svg += "  <text x=\"\(fmt(node.posX))\" y=\"\(fmt(nameY))\" "
        svg += "text-anchor=\"middle\" fill=\"\(textColor)\" "
        svg += "font-size=\"\(headerFontSize)\" font-weight=\"bold\">"
        svg += "\(node.label.xmlEscaped)</text>\n"

        svg += "</g>\n"
        return svg
    }

    static func renderEdge(_ edge: LayoutEdge) -> String {
        guard edge.points.count >= 2 else { return "" }

        let markerId: String
        let dashArray: String
        switch edge.style {
        case .inheritance:
            markerId = "arrow-inheritance"
            dashArray = ""
        case .association:
            markerId = ""
            dashArray = ""
        }

        var svg = ""
        svg += "stroke-width=\"1.2\"\(dashArray)"
        if !markerId.isEmpty {
            svg += " marker-end=\"url(#\(markerId))\""
        }
        svg += "/>\n"
        return svg
    }
}
'''

# C4: SwiftUMLStudio `9ad7631`, `Emitters/ActivitySVGRenderer.swift` (`renderFromLayout`, `render(graph:)`) and
# `+Shapes.swift`'s `renderEdge` and `renderForwardEdge`, verbatim.
ACTIVITY = r'''import Foundation

public struct ActivitySVGRenderer: Sendable {

    static let strokeColor = "#333333"
    static let bodyTextColor = "#333333"

    /// Render an SVG diagram from a pre-computed layout.
    public static func renderFromLayout(_ layout: ActivityLayout) -> String {
        var svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(layout.totalWidth))" \
        height="\(Int(layout.totalHeight))" \
        viewBox="0 0 \(Int(layout.totalWidth)) \(Int(layout.totalHeight))" \
        style="font-family: -apple-system, 'SF Pro Text', 'Helvetica Neue', sans-serif;">
        <defs>
            <marker id="act-arrow" viewBox="0 0 10 10" refX="9" refY="5" \
            markerWidth="8" markerHeight="8" orient="auto-start-reverse">
                <path d="M 0 0 L 10 5 L 0 10 Z" fill="\(strokeColor)"/>
            </marker>
        </defs>

        """

        if !layout.title.isEmpty {
            svg += "<text x=\"\(Int(layout.totalWidth / 2))\" y=\"18\" text-anchor=\"middle\" "
            svg += "font-size=\"14\" font-weight=\"bold\" fill=\"\(bodyTextColor)\">"
            svg += "\(layout.title.xmlEscaped)</text>\n"
        }

        for edge in layout.edges {
            svg += renderEdge(edge: edge, layout: layout)
        }

        for node in layout.nodes {
            svg += renderNode(node)
        }

        svg += "\n</svg>"
        return svg
    }

    /// Convenience — compute layout and render in one call.
    public static func render(graph: ActivityGraph) -> String {
        renderFromLayout(computeLayout(from: graph))
    }
}

extension ActivitySVGRenderer {
    static func renderEdge(edge: ActivityEdge, layout: ActivityLayout) -> String {
        guard let source = layout.node(withId: edge.fromId),
              let target = layout.node(withId: edge.toId) else { return "" }

        if target.centerY <= source.centerY {
            return renderBackEdge(from: source, to: target, label: edge.label)
        }
        return renderForwardEdge(from: source, to: target, label: edge.label)
    }

    static func renderForwardEdge(
        from source: PositionedActivityNode,
        to target: PositionedActivityNode,
        label: String?
    ) -> String {
        let startY = source.centerY + source.height / 2
        var svg = "<line x1=\"\(fmt(startX))\" y1=\"\(fmt(startY))\" " +
                  "stroke=\"\(strokeColor)\" stroke-width=\"1.2\" marker-end=\"url(#act-arrow)\"/>\n"
        return svg
    }
}
'''

# C5: SwiftUMLStudio `9ad7631`, `Emitters/SequenceSVGRenderer.swift`: `renderFromLayout` and `renderMessage`,
# verbatim apart from lines elided inside them.
SEQUENCE = r'''import Foundation

public struct SequenceSVGRenderer: Sendable {

    private static let strokeColor = "#333333"

    /// Render SVG from a pre-computed sequence layout.
    public static func renderFromLayout(_ layout: SequenceLayout) -> String {
        var svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(layout.totalWidth))" height="\(Int(layout.totalHeight))" \
        viewBox="0 0 \(Int(layout.totalWidth)) \(Int(layout.totalHeight))" \
        style="font-family: -apple-system, 'SF Pro Text', 'Helvetica Neue', sans-serif;">
        <defs>
            <marker id="seq-arrow" viewBox="0 0 10 10" refX="10" refY="5" \
            markerWidth="8" markerHeight="8" orient="auto-start-reverse">
                <path d="M 0 0 L 10 5 L 0 10 Z" fill="\(strokeColor)"/>
            </marker>
        </defs>

        """

        // Messages
        for message in layout.messages {
            if message.isUnresolved, let noteText = message.noteText {
                svg += renderNote(text: noteText, centerX: message.toX, posY: message.posY)
            } else {
                svg += renderMessage(
                    label: message.label, fromX: message.fromX, toX: message.toX,
                    posY: message.posY, isAsync: message.isAsync
                )
            }
        }

        svg += "\n</svg>"
        return svg
    }

    private static func renderMessage(
        label: String,
        fromX: Double,
        toX: Double,
        posY: Double,
        isAsync: Bool
    ) -> String {
        let markerId = isAsync ? "seq-arrow-open" : "seq-arrow"
        var svg = ""
        svg += "<line x1=\"\(fmt(fromX))\" y1=\"\(fmt(posY))\" "
        svg += "marker-end=\"url(#\(markerId))\"/>\n"
        return svg
    }
}
'''

# C6: SwiftUMLStudio `e36da59`, `Emitters/SVGRenderer.swift`: `render` and the head of `renderNode`, verbatim.
SVG_RENDERER_E36 = r'''import Foundation

public struct SVGRenderer: Sendable {

    public static func render(_ graph: LayoutGraph) -> String {
        let margin: Double = 20
        let svgWidth = graph.width + margin * 2
        let svgHeight = graph.height + margin * 2

        var svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(svgWidth))" height="\(Int(svgHeight))" \
        viewBox="0 0 \(Int(svgWidth)) \(Int(svgHeight))" \
        style="font-family: -apple-system, 'SF Pro Text', 'Helvetica Neue', sans-serif;">
        <defs>
            \(arrowMarkers())
        </defs>
        """

        // Render nodes
        for node in graph.nodes {
            svg += renderNode(node)
        }

        svg += "\n</svg>"
        return svg
    }

    private static func renderNode(_ node: LayoutNode) -> String {
        let leftX = node.posX - node.width / 2
        let topY = node.posY - node.height / 2

        var svg = "\n<!-- \(node.label.xmlEscaped) -->\n"
        svg += "<g>\n"
        svg += "</g>\n"
        return svg
    }
}
'''


def _rows(files, repository_files=None):
    return {row["name"]: row for row in census(files, repository_files, prefilter=False)}


def _one(source, path="/r/A.swift", others=None):
    files = {path: source}
    repository = dict(files, **(others or {}))
    return _rows(files, repository)


def _unit(source, name, path="/r/A.swift", others=None):
    """Cues for a named unit, candidate or not."""
    repository = Repository(dict({path: source}, **(others or {})))
    units, _ = repository.units(path)
    unit = next(u for u in units if u["name"] == name)
    found, candidate, _ = cues(unit, repository.members(unit["owner"], path))
    return found, candidate


def _wrap(body, signature="static func make(_ items: [String]) -> String", owner="enum Emitter"):
    return f"{owner} {{\n    {signature} {{\n{body}\n    }}\n}}\n"


def control_rows():
    """§3: `[(label, passed)]`."""
    checks = []

    def check(label, condition):
        checks.append((label, bool(condition)))

    component = _rows({"/r/ComponentSVGRenderer+SVG.swift": COMPONENT_SVG})
    c1 = component.get("renderSVG")
    check("C1 renderSVG: candidate, OPEN-HOP via svgHeader, ROOT svg, CLOSE, GATED",
          c1 and c1["cues"]["OPEN_HOP"] and not c1["cues"]["OPEN_BODY"] and c1["cues"]["ROOT"] == "svg"
          and c1["cues"]["CLOSE"] and c1["gated"])
    check("C1 renderSVG: IDDEF through the computed property arrowMarkerDefs, GATED2, REF through edgeSVGLine",
          c1 and c1["cues"]["IDDEF"] and c1["gated2"] and c1["cues"]["REF"]
          and {"svgHeader", "arrowMarkerDefs", "edgeSVGLine"} <= set(c1["cues"]["hops"]))
    without = _rows({"/r/ComponentSVGRenderer+SVG.swift": COMPONENT_SVG.replace("lines.append(arrowMarkerDefs)\n",
                                                                                "")}).get("renderSVG")
    check("C1 renderSVG without the arrowMarkerDefs read: no IDDEF, GATED, not GATED2",
          without and not without["cues"]["IDDEF"] and without["cues"]["REF"] and without["gated"]
          and not without["gated2"])
    c2 = component.get("svgHeader")
    check("C2 svgHeader: candidate, OPEN-BODY, no CLOSE, not GATED",
          c2 and c2["cues"]["OPEN_BODY"] and not c2["cues"]["CLOSE"] and not c2["gated"])
    check("C1 arrowMarkerDefs (a computed property) is a unit and no candidate",
          "arrowMarkerDefs" not in component and _unit(COMPONENT_SVG, "arrowMarkerDefs")[1] is False)
    c3 = _rows({"/r/SVGRenderer.swift": SVG_RENDERER}).get("render")
    check("C3 SVGRenderer.render: OPEN-BODY, CLOSE in `svg +=`, GATED, IDDEF via arrowMarkers(), GATED2, REF via"
          " renderEdge", c3 and c3["cues"]["OPEN_BODY"] and c3["cues"]["CLOSE"] and c3["gated"]
          and c3["cues"]["IDDEF"] and c3["gated2"] and c3["cues"]["REF"] and "arrowMarkers" in c3["cues"]["hops"])
    activity = _rows({"/r/ActivitySVGRenderer.swift": ACTIVITY})
    c4 = activity.get("renderFromLayout")
    check("C4 Activity renderFromLayout: GATED, GATED2, IDDEF in its own body, no REF (two hops away)",
          c4 and c4["gated"] and c4["gated2"] and not c4["cues"]["REF"])
    check("C4 render(graph:): no candidate", "render" not in activity)
    c5 = _rows({"/r/SequenceSVGRenderer.swift": SEQUENCE}).get("renderFromLayout")
    check("C5 Sequence renderFromLayout: GATED, GATED2, REF via renderMessage",
          c5 and c5["gated"] and c5["gated2"] and c5["cues"]["REF"] and "renderMessage" in c5["cues"]["hops"])
    c6 = _rows({"/r/SVGRenderer.swift": SVG_RENDERER_E36}).get("render")
    check("C6 SVGRenderer.render at e36da59: GATED, COMMENT through renderNode",
          c6 and c6["gated"] and c6["cues"]["COMMENT"])
    check("C6 at 9ad7631, whose renderNode no longer writes the label comment: no COMMENT",
          c3 and "renderNode" in c3["cues"]["hops"] and not c3["cues"]["COMMENT"])
    report = _wrap('        ["<?xml version=\\"1.0\\" encoding=\\"utf-8\\"?>", "<checkstyle version=\\"4.3\\">",\n'
                   '         items.map { "<file name=\\"\\($0)\\"/>" }.joined(), "</checkstyle>"].joined()',
                   "static func generateReport(_ items: [String]) -> String", "struct CheckstyleReporter")
    c7 = _one(report).get("generateReport")
    check("C7 a joined report: XMLDECL, ROOT checkstyle from the next literal, CLOSE, GATED, not GATED2",
          c7 and c7["cues"]["XMLDECL"] and c7["cues"]["ROOT"] == "checkstyle" and c7["gated"] and not c7["gated2"])
    c8 = _one(_wrap('        if items[0].hasPrefix("<?xml") { return "xml" }\n'
                    '        if Data().starts(with: "<?xml".utf8) { return "data" }\n        return ""')).get("make")
    check("C8 `<?xml` as a hasPrefix and a starts(with:) key: candidate, no OPEN, not GATED",
          c8 and not c8["cues"]["OPEN"] and not c8["gated"])
    c9 = _one(_wrap('        let svg = items[0]\n        let head = "<svg xmlns=\\"http://www.w3.org/2000/svg\\">"\n'
                    '        return head + svg.replacingOccurrences(of: "</svg>", with: items[1])')).get("make")
    check("C9 the `of:` literal is a search key: no CLOSE", c9 and c9["cues"]["OPEN"] and not c9["cues"]["CLOSE"])
    c10 = _one(_wrap('        return "<!DOCTYPE html><html><body><svg xmlns=\\"http://www.w3.org/2000/svg\\">'
                     '</svg></body></html>"')).get("make")
    check("C10 an HTML page with inline svg: HTML, not GATED", c10 and c10["cues"]["HTML"] and not c10["gated"])
    base = '        return "<svg xmlns=\\"http://www.w3.org/2000/svg\\">" + items.joined() + "</svg>"'
    check("C11 the base shape is GATED", _one(_wrap(base))["make"]["gated"])
    for label, signature, cue in (
            ("throws", "static func make(_ items: [String]) throws -> String", "NOTHROW"),
            ("async", "static func make(_ items: [String]) async -> String", "SYNC"),
            ("mutating", "mutating func make(_ items: [String]) -> String", "NONMUTATING"),
            ("String?", "static func make(_ items: [String]) -> String?", "STRING"),
            ("Data", "static func make(_ items: [String]) -> Data", "STRING")):
        row = _one(_wrap(base, signature)).get("make")
        check(f"C11 {label}: {cue} false, not GATED", row and not row["cues"][cue] and not row["gated"])
    c12 = _one(_wrap('        let here = FileManager.default.currentDirectoryPath\n' + base.replace("items.joined()",
                                                                                                "here"))).get("make")
    check("C12 FileManager in the body: PURE false, not GATED", c12 and not c12["cues"]["PURE"] and not c12["gated"])
    c12b = _one('enum Emitter {\n    static func make(_ items: [String]) -> String {\n'
                '        "<svg xmlns=\\"http://www.w3.org/2000/svg\\">" + stamp() + "</svg>"\n    }\n'
                '    static func stamp() -> String { "\\(Date())" }\n}\n').get("make")
    check("C12 an impure hop: PURE false", c12b and not c12b["cues"]["PURE"])
    computed = ('struct Icon {\n    var body: String\n'
                '    var svg: String { "<svg xmlns=\\"http://www.w3.org/2000/svg\\">" + body + "</svg>" }\n'
                '    var xml: String {\n        get {\n            "<svg xmlns=\\"http://www.w3.org/2000/svg\\">'
                '</svg>"\n        }\n    }\n}\n')
    rows = _one(computed)
    check("C13 two computed properties, one with `get { }`: units, GATED",
          rows.get("svg", {}).get("gated") and rows.get("xml", {}).get("gated") and rows["svg"]["kind"] == "property")
    observers = ('struct Icon {\n    var svg: String = "" {\n        didSet { log("<svg xmlns=\\"a\\">") }\n    }\n'
                 '    var other: String {\n        set { store("<svg xmlns=\\"a\\"></svg>") }\n'
                 '        get { "" }\n    }\n}\n')
    check("C14 a didSet observer and a set block: no unit", not _one(observers))
    commented = _wrap('        // xmlns and </svg> appear here only\n        return items.joined()',
                      "/// Builds <svg xmlns=…></svg>.\n    static func make(_ items: [String]) -> String")
    check("C15 markers only in comments: no candidate", not _one(commented))
    raw = _one(_wrap('        return #"<svg xmlns="http://www.w3.org/2000/svg">"# + "</svg>"')).get("make")
    check("C16 a raw string: XMLNS, GATED", raw and raw["cues"]["XMLNS"] and raw["gated"])
    multi = _one(_wrap('        return """\n        <svg \\\n        xmlns="http://www.w3.org/2000/svg">\n'
                       '        </svg>\n        """')).get("make")
    check("C17 a multi-line literal joined by a trailing backslash: XMLNS, GATED",
          multi and multi["cues"]["XMLNS"] and multi["gated"])
    c18 = _one(_wrap('        return "<svg xmlns=\\"http://www.w3.org/2000/svg\\">" + "</g>"')).get("make")
    check("C18 OPEN with only </g>: no CLOSE", c18 and c18["cues"]["OPEN"] and not c18["cues"]["CLOSE"])
    c19 = _one(_wrap('        return "<?xml version=\\"1.0\\"?><rss version=\\"2.0\\">" + items.joined()'
                     ' + "</rss>"')).get("make")
    check("C19 <?xml and <rss> in one literal: ROOT rss, CLOSE", c19 and c19["cues"]["ROOT"] == "rss"
          and c19["cues"]["CLOSE"])
    other = ('enum Emitter {\n    static func make(_ items: [String]) -> String {\n'
             '        Other.header() + items.joined() + "</svg>"\n    }\n}\n'
             'enum Other {\n    static func header() -> String { "<svg xmlns=\\"http://www.w3.org/2000/svg\\">" }\n}\n')
    c20 = _one(other).get("make")
    check("C20 a hop through another type: no OPEN-HOP", c20 and not c20["cues"]["OPEN"])
    two = ('enum Emitter {\n    static func make(_ items: [String]) -> String {\n        a() + "</svg>"\n    }\n'
           '    static func a() -> String { b() }\n'
           '    static func b() -> String { "<svg xmlns=\\"http://www.w3.org/2000/svg\\">" }\n}\n')
    c21 = _one(two).get("make")
    check("C21 body → a() → b(): no OPEN-HOP", c21 and not c21["cues"]["OPEN"])
    stored = ('enum Emitter {\n    static let defs = "<marker id=\\"m\\"/>"\n'
              '    static func make(_ items: [String]) -> String {\n'
              '        "<svg xmlns=\\"http://www.w3.org/2000/svg\\">" + Self.defs + "</svg>"\n    }\n}\n')
    c22 = _one(stored).get("make")
    check("C22 IDDEF through a stored property read as Self.defs: GATED2", c22 and c22["cues"]["IDDEF"]
          and c22["gated2"])
    for label, literal in (("data-id", 'data-id=\\"x\\"'), ("gid", 'gid=\\"x\\"')):
        row = _one(_wrap(f'        return "<svg xmlns=\\"http://www.w3.org/2000/svg\\"><g {literal}/></svg>"')).get("make")
        check(f"C23 {label}: no IDDEF", row and not row["cues"]["IDDEF"])
    code_id = _one(_wrap('        let id = "x"\n        return "<svg xmlns=\\"http://www.w3.org/2000/svg\\">'
                         '\\(id)</svg>"')).get("make")
    check("C23 `id = \"x\"` in Swift code: no IDDEF", code_id and not code_id["cues"]["IDDEF"])
    for label, literal in (("href", 'href=\\"#a\\"'), ("xlink:href", "xlink:href='#a'"), ("url", "fill=\\\"url(#a)\\\"")):
        row = _one(_wrap(f'        return "<svg xmlns=\\"http://www.w3.org/2000/svg\\"><use {literal}/></svg>"')).get("make")
        check(f"C24 {label}: REF", row and row["cues"]["REF"])
    extension = {"/r/B.swift": 'extension Emitter {\n    static func header() -> String {\n'
                               '        "<svg xmlns=\\"http://www.w3.org/2000/svg\\">"\n    }\n}\n'}
    c25 = _one('enum Emitter {\n    static func make(_ items: [String]) -> String {\n'
               '        header() + items.joined() + "</svg>"\n    }\n}\n', others=extension).get("make")
    check("C25 the opening literal in an extension in another file: OPEN-HOP", c25 and c25["cues"]["OPEN_HOP"]
          and c25["gated"])
    top = ('func make(_ items: [String]) -> String {\n    header() + items.joined() + "</svg>"\n}\n')
    header = 'func header() -> String {\n    "<svg xmlns=\\"http://www.w3.org/2000/svg\\">"\n}\n'
    c26a = _one(top + header).get("make")
    c26b = _one(top, others={"/r/B.swift": header}).get("make")
    check("C26 top-level hop in the same file: OPEN-HOP; in another file: none",
          c26a and c26a["cues"]["OPEN_HOP"] and c26b and not c26b["cues"]["OPEN"])
    plist = _one(_wrap('        return "<?xml version=\\"1.0\\"?><plist version=\\"1.0\\">" + items.joined()'
                       ' + "</plist>"')).get("make")
    check("C27 a plist: ROOT plist, GATED", plist and plist["cues"]["ROOT"] == "plist" and plist["gated"])
    comment = _one(_wrap('        return "<svg xmlns=\\"http://www.w3.org/2000/svg\\"><!-- \\(items[0]) --></svg>"'))
    check("C28 a comment literal: COMMENT", comment.get("make", {}).get("cues", {}).get("COMMENT"))
    keys = _one(_wrap('        switch items[0] {\n        case "<?xml": return ""\n        default: break\n'
                      '        }\n        if items[1] == "</svg>" { return "" }\n'
                      '        return items.contains("xmlns") ? "a" : "b"')).get("make")
    check("C30 case label, ==, contains(): search keys; no OPEN or CLOSE",
          keys and not keys["cues"]["OPEN"] and not keys["cues"]["CLOSE"])
    interpolated = _one(_wrap('        let tag = "svg"\n        return "<\\(tag) xmlns=\\"a\\">" + "</svg>"')).get("make")
    check("C31 an interpolated root name: no XMLNS", interpolated and not interpolated["cues"]["XMLNS"])
    inline = _one(_wrap('        return "<svg width=\\"1\\">" + items.joined() + "</svg>"')).get("make")
    check("C32 `<svg` with no xmlns: candidate, no OPEN, not GATED", inline and not inline["cues"]["OPEN"]
          and not inline["gated"])
    tried = _one(_wrap('        let first = try? items.first.map { $0 }\n' + base)).get("make")
    check("C33 `try?` inside a non-throwing function: NOTHROW, GATED", tried and tried["cues"]["NOTHROW"]
          and tried["gated"])
    decl_hop = ('enum Emitter {\n    static func make(_ items: [String]) -> String {\n'
                '        "<?xml version=\\"1.0\\"?>" + root() + items.joined() + "</feed>"\n    }\n'
                '    static func root() -> String { "<feed xmlns=\\"http://www.w3.org/2005/Atom\\">" }\n}\n')
    c34 = _one(decl_hop).get("make")
    check("C34 <?xml in the body, the root start tag in a later hop: ROOT feed from the hop's stream, CLOSE",
          c34 and c34["cues"]["ROOT"] == "feed" and c34["cues"]["CLOSE"] and c34["gated"])
    check("C35 a view that does not finish in time makes the file unparsable; both views finish on the witness, on a"
          " comment that never closes and on an unterminated `\\u{`",
          not parsable("x", seconds=0.2, views=(lambda _: time.sleep(1),)) and parsable(COMPONENT_SVG, seconds=2)
          and parsable("func f() {}\n/* never closed\n", seconds=2) and parsable('let s = "\\u{41', seconds=2))
    counted = ('enum Emitter {\n    static func make(_ items: [String]) -> String {\n'
               '        let n = headerLength()\n        return items.joined() + "\\(n)</svg>"\n    }\n'
               '    static func headerLength() -> Int { "<svg xmlns=\\"http://www.w3.org/2000/svg\\">".count }\n}\n')
    c37 = _one(counted).get("make")
    check("C37 a hop whose result is an Int: no OPEN-HOP", c37 and not c37["cues"]["OPEN"])
    closure = _one(_wrap(base, "static func make(_ items: [String], _ visit: () throws -> Void) -> String")).get("make")
    check("C38 `throws` inside a parameter's closure type: NOTHROW, GATED", closure and closure["cues"]["NOTHROW"]
          and closure["gated"])
    shadow = ('enum Emitter {\n    static func make(_ items: [String]) -> String {\n'
              '        let header = items.joined()\n        return header + "</svg>"\n    }\n'
              '    static var header: String { "<svg xmlns=\\"http://www.w3.org/2000/svg\\">" }\n}\n')
    c39 = _one(shadow).get("make")
    check("C39 a local that shadows a member is not a hop: no OPEN", c39 and not c39["cues"]["OPEN"])
    doc_func = _wrap(base, "/// func fake() -> String { \"<svg\" }\n    static func make(_ items: [String]) -> String")
    c36 = _one(doc_func).get("make")
    check("C36 a func in a doc comment above the signature: the body is the real one", c36 and c36["gated"])
    copies = [dict(row, group=group, toplevel=f"/{group}", repo=group, path="A.swift", line=1, key="k", copies=[])
              for group, row in (("wide", {}), ("layout", {}), ("decision", {}))]
    merged = merge_copies(copies)
    check("C29 a copy in the decision, layout and wide groups: one row, at the decision copy",
          len(merged) == 1 and merged[0]["group"] == "decision" and len(merged[0]["copies"]) == 2)
    views = literal_view('let a = "x\\(f("<y>"))z" + #"q"r"# + """\n  m \\\n  n\n  """')
    check("§1.1 the literal view: interpolation placeholder, nested literal, raw string, continuation",
          [content for _, _, content in views] == ["x\x01z", "<y>", 'q"r', "\n  m   n\n  "])
    return checks


SVG_OPEN = '<svg xmlns=\\"http://www.w3.org/2000/svg\\">'
XML_DECL = '<?xml version=\\"1.0\\"?>'


def more_controls():
    """§3's controls added after the review's parser attack and rule-break audit: one or more per rule the first 83
    controls did not catch. `[(label, passed)]`."""
    checks = []

    def check(label, condition):
        checks.append((label, bool(condition)))

    def make(body, **kwargs):
        return _one(_wrap(body, **kwargs)).get("make")

    def cue(row, name):
        return bool(row) and row["cues"][name]

    def gated(row):
        return bool(row) and row["gated"]

    # Search keys (§1.2).
    row = make('        if Data().starts(with: Array("<?xml".utf8)) { return "XML" }\n        return "x"')
    check("X1 `starts(with: Array(\"<?xml\".utf8))`: a nested argument is still a search key; no OPEN",
          row and not cue(row, "OPEN"))
    for label, body in (
            ("`s == \"</svg>\"`", f'        let s = "{SVG_OPEN}" + items.joined()\n        return s == "</svg>" ? s : s + "x"'),
            ("`\"</svg>\" == s`", f'        let s = "{SVG_OPEN}" + items.joined()\n        return "</svg>" == s ? s : s + "x"'),
            ("`s != \"</svg>\"`", f'        let s = "{SVG_OPEN}" + items.joined()\n        return s != "</svg>" ? s : s + "x"'),
            ("`\"</svg>\" ~= s`", f'        let s = "{SVG_OPEN}" + items.joined()\n        return "</svg>" ~= s ? s : s + "x"')):
        row = make(body)
        check(f"X2 {label} beside an opener: an operand is a search key; OPEN, no CLOSE",
              cue(row, "OPEN") and not cue(row, "CLOSE"))
    row = make(f'        if items.contains("{SVG_OPEN}") {{ return "" }}\n        return items.joined() + "</svg>"')
    check("X2 `.contains(<svg xmlns…>)` beside a flowing close: no OPEN", row and not cue(row, "OPEN"))
    row = make(f'        switch items[0] {{\n        case "{SVG_OPEN}": return ""\n        default: break\n        }}\n'
               '        return items.joined() + "</svg>"')
    check("X2 a `case` label holding the opener: no OPEN", row and not cue(row, "OPEN"))
    row = make(f'        let s = "{SVG_OPEN}" + items.joined()\n        return s.replacing("</svg>", with: "")')
    check("X2 `replacing(\"</svg>\", with:)`: the searched literal is a key; no CLOSE", not cue(row, "CLOSE"))
    row = make(f'        "{SVG_OPEN}" + items[0].replacing("<g>", with: "</svg>")')
    check("X2 `replacing(_:with: \"</svg>\")`: what it writes flows; CLOSE", cue(row, "CLOSE"))
    header = f'    static func header() -> String {{ "{SVG_OPEN}" }}\n'
    row = _one('enum Emitter {\n    static func make(_ items: [String]) -> String {\n'
               '        if items[0].hasPrefix(header()) { return items[0] + "</svg>" }\n        return ""\n    }\n'
               + header + '}\n').get("make")
    check("X3 a hop reference used as a search key: no OPEN", row and not cue(row, "OPEN"))
    row = _one('enum Emitter {\n    static func make(_ items: [String]) -> String {\n'
               '        header(items[0]) + "</svg>"\n    }\n'
               f'    static func header(_ s: String) -> String {{ s.hasPrefix("{SVG_OPEN}") ? s : "" }}\n}}\n').get("make")
    check("X4 a hop whose opener literal is a search key inside it: no OPEN", row and not cue(row, "OPEN"))
    row = make(f'        // lines.append("</svg>")\n        /* "{SVG_OPEN}" */\n        return "{SVG_OPEN}" + items.joined()')
    check("X5 quoted markers in a line comment and a block comment: no CLOSE", row and not cue(row, "CLOSE"))
    check("X5 a quoted opener only in a comment: no candidate",
          not _one(_wrap(f'        // was: return "{SVG_OPEN}" + x\n        return items.joined()')))

    # Stored properties as hops (§1.2).
    row = _one(f'enum Emitter {{\n    static let header =\n        "{SVG_OPEN}"\n'
               '    static func make(_ items: [String]) -> String {\n        header + items.joined() + "</svg>"\n'
               '    }\n}\n').get("make")
    check("X6 a stored header wrapped after `=`: OPEN-HOP, GATED", cue(row, "OPEN_HOP") and gated(row))
    row = _one(f'enum Emitter {{\n    static let header = "{XML_DECL}" +\n        "<checkstyle version=\\"4.3\\">"\n'
               '    static func make(_ items: [String]) -> String {\n'
               '        header + items.joined() + "</checkstyle>"\n    }\n}\n').get("make")
    check("X6 a stored header wrapped after `+`: ROOT checkstyle, GATED",
          row and row["cues"]["ROOT"] == "checkstyle" and gated(row))
    row = _one(f'enum Emitter {{\n    static let header = "{SVG_OPEN}"\n'
               '    static func make(_ items: [String]) -> String {\n        header + items.joined() + "</svg>"\n'
               '    }\n}\n').get("make")
    check("X7 an untyped stored header initialised by a literal: OPEN-HOP, GATED", cue(row, "OPEN_HOP") and gated(row))
    row = _one(f'enum Emitter {{\n    static let n = "{SVG_OPEN}".count\n'
               '    static func make(_ items: [String]) -> String {\n        "\\(Self.n)" + items.joined() + "</svg>"\n'
               '    }\n}\n').get("make")
    check("X7 a stored property built from a literal but not a String (`.count`): no OPEN",
          row and not cue(row, "OPEN"))

    # The same type, receivers, locals and labels (§1.2).
    for label, read in (("self.header", "self.header"), ("Emitter.header", "Emitter.header"),
                        ("Self.header", "Self.header")):
        row = _one('struct Emitter {\n    func make(_ items: [String]) -> String {\n'
                   f'        {read} + items.joined() + "</svg>"\n    }}\n'
                   f'    static var header: String {{ "{SVG_OPEN}" }}\n    var header: String {{ "{SVG_OPEN}" }}\n}}\n').get("make")
        check(f"X8 `{label}`: OPEN-HOP, GATED", cue(row, "OPEN_HOP") and gated(row))
    member = f'    static var header: String {{ "{SVG_OPEN}" }}\n'
    for label, body, signature in (
            ("a parameter", '        header + "</svg>"', "static func make(header: String) -> String"),
            ("a for variable", '        var s = ""\n        for header in ["a"] { s += header }\n'
                               '        return s + "</svg>"', "static func make(_ items: [String]) -> String"),
            ("a closure parameter", '        items.map { header in header }.joined() + "</svg>"',
             "static func make(_ items: [String]) -> String"),
            ("a tuple binding", '        let (header, rest) = (items[0], items[1])\n        return header + rest + "</svg>"',
             "static func make(_ items: [String]) -> String")):
        row = _one(f'enum Emitter {{\n    {signature} {{\n{body}\n    }}\n{member}}}\n').get("make")
        check(f"X9 a bare read shadowed by {label}: no OPEN", row and not cue(row, "OPEN"))
    row = _one('enum Emitter {\n    static func make(_ items: [String]) -> String {\n'
               '        let header = Self.header\n        return header + items.joined() + "</svg>"\n    }\n'
               + member + '}\n').get("make")
    check("X9 `let header = Self.header`: an explicit receiver is never shadowed; OPEN-HOP, GATED",
          cue(row, "OPEN_HOP") and gated(row))
    row = _one('enum Emitter {\n    static func make(_ items: [String], flag: Bool) -> String {\n'
               '        (flag ? declaration : "<plist version=\\"1.0\\">") + "<dict>" + items.joined()'
               ' + "</dict></plist>"\n    }\n'
               f'    static var declaration: String {{ "{XML_DECL}<plist version=\\"1.0\\">" }}\n}}\n').get("make")
    check("X9 a ternary's first branch is a read, not a label: OPEN-HOP, ROOT plist, GATED",
          cue(row, "OPEN_HOP") and row["cues"]["ROOT"] == "plist" and gated(row))
    row = _one('enum Emitter {\n    static func make(_ items: [String]) -> String {\n'
               '        wrap(title: items[0]) + "</svg>"\n    }\n'
               f'    static let title = "{SVG_OPEN}"\n    static func wrap(title: String) -> String {{ title }}\n}}\n').get("make")
    check("X10 an argument label named like a member is not a hop: no OPEN", row and not cue(row, "OPEN"))
    rows = census({"/r/A.swift": 'enum Emitter {\n    static func render(_ items: [String]) -> String {\n'
                                 '        render(items, header: true) + "</svg>"\n    }\n'
                                 '    static func render(_ items: [String], header: Bool) -> String {\n'
                                 f'        "{SVG_OPEN}" + items.joined()\n    }}\n}}\n'}, prefilter=False)
    short = [r for r in rows if r["labels"] == ["_"]]
    check("X11 an overload with the unit's own name is a hop; the unit itself is not: OPEN-HOP, GATED",
          len(short) == 1 and short[0]["cues"]["OPEN_HOP"] and short[0]["gated"] and short[0]["cues"]["hops"] == ["render"])
    row = _one('enum Emitter {\n    static func make(_ items: [String]) -> String {\n'
               '        header(1) + items.joined() + "</svg>"\n    }\n    static func header() -> String { "" }\n'
               f'    static func header(_ n: Int) -> String {{ "{SVG_OPEN}" }}\n}}\n').get("make")
    check("X12 every overload of a referenced name is a hop: OPEN-HOP, GATED", cue(row, "OPEN_HOP") and gated(row))
    row = _one('enum Emitter {\n    static func make(_ items: [String]) -> String {\n'
               '        if items[0] == Self.header { return "" }\n        return items.joined() + "</svg>"\n    }\n'
               + member + '}\n').get("make")
    check("X13 `== Self.header` is a search key over the whole receiver chain: no OPEN", row and not cue(row, "OPEN"))

    # Start tags, XMLNS, the opener and ROOT (§1.2).
    row = make('        return "<?xml version=\\"1.0\\"?>\\n<!DOCTYPE plist PUBLIC \\"-//Apple//DTD PLIST 1.0//EN\\"'
               ' \\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\\">\\n<plist version=\\"1.0\\">"'
               ' + items.joined() + "</plist>"')
    check("X14 Apple's plist doctype before the root: ROOT plist, GATED",
          row and row["cues"]["ROOT"] == "plist" and gated(row))
    row = make(f'        return "{XML_DECL}\\n</x>\\n<root>" + items.joined() + "</root>"')
    check("X14 an end tag before the root in the opening literal: ROOT root", row and row["cues"]["ROOT"] == "root")
    for label, literal, expect in (
            ("a placeholder before xmlns", '<svg width=\\"\\(items.count)\\" xmlns=\\"http://www.w3.org/2000/svg\\">',
             True),
            ("xmlns:atom on rss", '<rss version=\\"2.0\\" xmlns:atom=\\"http://www.w3.org/2005/Atom\\">', True),
            ("data-xmlns", '<svg data-xmlns=\\"x\\">', False), ("xmlnsx", '<svg xmlnsx=\\"x\\">', False)):
        close = "</rss>" if "rss" in literal else "</svg>"
        row = make(f'        return "{literal}" + items.joined() + "{close}"')
        check(f"X15 {label}: {'GATED' if expect else 'no XMLNS'}", (gated(row) if expect
                                                                      else row and not cue(row, "XMLNS")))
    row = make(f'        return "<div>{SVG_OPEN}" + items.joined() + "</svg></div>"')
    check("X15 an xmlns tag after another start tag is not an opener: no OPEN", row and not cue(row, "OPEN"))
    row = make(f'        return "{XML_DECL}<rss version=\\"2.0\\"><channel xmlns:atom=\\"a\\">"'
               ' + items.joined() + "</channel></rss>"')
    check("X16 a later xmlns tag in the opening literal does not move ROOT: ROOT rss",
          row and row["cues"]["ROOT"] == "rss")
    row = make(f'        return "{SVG_OPEN}<?xml-stylesheet href=\\"a\\"?>" + items.joined() + "</svg>"')
    check("X16 an xmlns tag before `<?xml…`: XMLNS decides, ROOT svg, GATED",
          row and row["cues"]["ROOT"] == "svg" and gated(row))
    row = _one('enum Emitter {\n    static func make(_ items: [String]) -> String {\n'
               f'        "{XML_DECL}" + root() + "<title/>" + items.joined() + "</feed>"\n    }}\n'
               '    static func root() -> String { "<feed xmlns=\\"http://www.w3.org/2005/Atom\\">" }\n}\n').get("make")
    check("X16 C34 with a later body start tag: ROOT feed, GATED", row and row["cues"]["ROOT"] == "feed" and gated(row))
    row = make(f'        return "{SVG_OPEN}" + "<div xmlns=\\"http://www.w3.org/1999/xhtml\\">" + items.joined()'
               ' + "</div></svg>"')
    check("X16 two opening literals: the first in the stream decides, ROOT svg", row and row["cues"]["ROOT"] == "svg")
    row = _one('enum Emitter {\n    static func make(_ items: [String]) -> String {\n'
               '        header() + items.joined() + "</checkstyle>"\n    }\n'
               f'    static func header() -> String {{ "{XML_DECL}\\n" + "<checkstyle version=\\"4.3\\">" }}\n}}\n').get("make")
    check("X17 `<?xml` in a hop, the root in the hop's next literal: ROOT checkstyle, GATED; a candidate by its end tag",
          row and row["cues"]["ROOT"] == "checkstyle" and gated(row) and cue(row, "OPEN_HOP"))
    row = _one('enum Emitter {\n    static func make(_ items: [String]) -> String {\n'
               f'        "{XML_DECL}" + body(items) + "</root>"\n    }}\n'
               '    static func body(_ s: [String]) -> String {\n'
               '        if s.first?.hasPrefix("<foo xmlns=\\"x\\">") == true { return "" }\n'
               '        return "<root>"\n    }\n}\n').get("make")
    check("X17 a search-key start tag in a later hop is not the root: ROOT root", row and row["cues"]["ROOT"] == "root")
    row = make(f'        let header = "{XML_DECL}\\n"\n'
               '        let body = Dictionary(grouping: items) { $0.isEmpty ? "<nopath>" : $0 }.keys.joined()\n'
               '        return header + "<checkstyle version=\\"4.3\\">\\n" + body + "\\n</checkstyle>"')
    check("X18 a `<nopath>` placeholder before the root: ROOT checkstyle (the tag whose end tag is written), GATED",
          row and row["cues"]["ROOT"] == "checkstyle" and gated(row))
    row = _one('enum Emitter {\n    static func make(_ items: [String]) -> String {\n'
               f'        "{SVG_OPEN}" + items.joined() + footer()\n    }}\n'
               '    static func footer() -> String { "</svg>" }\n}\n').get("make")
    check("X19 the close only in a footer hop: no CLOSE, CLOSE-HOP, not GATED",
          row and not cue(row, "CLOSE") and cue(row, "CLOSE_HOP") and not gated(row))
    check("X19 `</svg >` closes; `</svgs>` does not",
          gated(make(f'        return "{SVG_OPEN}" + items.joined() + "</svg >"'))
          and not cue(make(f'        return "{SVG_OPEN}" + items.joined() + "</svgs>"'), "CLOSE"))

    # HTML, IDDEF, the candidate rule and GATED2 (§1.2–§1.4).
    for label, body in (
            ("a doctype alone", f'        return "<!DOCTYPE html>\\n{SVG_OPEN}" + items.joined() + "</svg>"'),
            ("upper case", f'        return "{SVG_OPEN}<HTML>" + items.joined() + "</HTML></svg>"'),
            ("XHTML", '        return "<html xmlns=\\"http://www.w3.org/1999/xhtml\\">" + items.joined() + "</html>"')):
        row = make(body)
        check(f"X20 HTML by {label}: HTML, not GATED", cue(row, "HTML") and not gated(row))
    row = _one('enum Emitter {\n    static func make(_ items: [String]) -> String {\n'
               f'        page() + "{SVG_OPEN}" + items.joined() + "</svg></body></html>"\n    }}\n'
               '    static func page() -> String { "<!DOCTYPE html><html><body>" }\n}\n').get("make")
    check("X20 the HTML opener in a hop: HTML, not GATED", cue(row, "HTML") and not gated(row))
    row = make(f'        precondition(!items[0].contains("<html"))\n        return "{SVG_OPEN}" + items[0] + "</svg>"')
    check("X20 `<html` only as a search key: no HTML, GATED", row and not cue(row, "HTML") and gated(row))
    for label, literal, expect in (("single quotes", "<marker id='m'/>", True),
                                   ("an unquoted value", '<marker id=\\(items[0])/>', False)):
        row = make(f'        return "{SVG_OPEN}{literal}" + items.joined() + "</svg>"')
        check(f"X21 IDDEF with {label}: {expect}", row and row["cues"]["IDDEF"] is expect)
    row = make(f'        return ["{SVG_OPEN}<defs><path ", "id=\\"glyph\\" d=\\"", items[0], "\\"/></defs>",'
               ' "<use href=\\"#glyph\\"/></svg>"].joined()')
    check("X21 `id=` at a literal's start: IDDEF, GATED2", cue(row, "IDDEF") and row["gated2"])
    row = make(f'        return "{SVG_OPEN}<marker id=\\"m\\"/>"')
    check("X23 an svg opener with an id and no close: not GATED2", row and not row["gated2"])
    row = make(f'        return "{XML_DECL}<feed xmlns=\\"http://www.w3.org/2005/Atom\\"><entry id=\\"x\\"/>"'
               ' + items.joined() + "</feed>"')
    check("X23 an id in a non-SVG document: GATED, not GATED2", gated(row) and not row["gated2"])

    # Units (§1.1) and the signature (§1.2).
    check("X24 an observer block `var svg: String { didSet { … } }`: no unit",
          not _one(f'struct Icon {{\n    var title: String {{\n        didSet {{ svg = "{SVG_OPEN}\\(title)</svg>" }}\n'
                   '    }\n    var svg = ""\n}\n'))
    check("X24 a computed property local to a function: no unit",
          "svg" not in _one(f'func outer() -> Int {{\n    var svg: String {{ "{SVG_OPEN}</svg>" }}\n    return svg.count\n}}\n'))
    check("X24 a file-scope computed property: a unit, GATED",
          gated(_one(f'var svg: String {{ "{SVG_OPEN}</svg>" }}\n').get("svg")))
    row = _one('enum Emitter {\n    static func make(_ items: [String]) -> String {\n        header + "</svg>"\n    }\n'
               f'    static func other() -> String {{\n        let header = "{SVG_OPEN}"\n        return header\n    }}\n'
               '    static let header = "<g/>"\n}\n').get("make")
    check("X24 a function-local `let` named like a member is not the member: no OPEN", row and not cue(row, "OPEN"))
    for label, block, field in (("get throws", "get throws", "NOTHROW"), ("get async", "get async", "SYNC"),
                                ("mutating get", "mutating get", "NONMUTATING")):
        row = _one(f'struct Icon {{\n    var xml: String {{\n        {block} {{ "{SVG_OPEN}</svg>" }}\n    }}\n}}\n').get("xml")
        check(f"X25 a computed property with `{label}`: {field} false, not GATED",
              row and not row["cues"][field] and not gated(row))
    base = f'        return "{SVG_OPEN}" + items.joined() + "</svg>"'
    check("X26 `-> Swift.String`: STRING, GATED",
          gated(make(base, signature="static func make(_ items: [String]) -> Swift.String")))
    row = make(base, signature="static func make(_ items: [String], _ f: () throws -> Void) rethrows -> String")
    check("X26 `rethrows`: NOTHROW false", row and not cue(row, "NOTHROW"))
    check("X26 `async` inside a parameter's closure type: SYNC, GATED",
          gated(make(base, signature="static func make(_ items: [String], _ done: () async -> Void) -> String")))
    row = make(f'        var out = ""\n        print("{XML_DECL}", to: &out)\n        print("<checkstyle>", to: &out)\n'
               '        print("</checkstyle>", to: &out)\n        return out')
    check("X28 `print(…, to: &out)` builds text: PURE", cue(row, "PURE"))
    row = make('        print("x")\n' + base)
    check("X28 a plain `print(…)`: PURE false", row and not cue(row, "PURE"))
    row = _one('enum Emitter {\n    static func make(_ items: [String]) -> String {\n'
               '        var lines = headerLines()\n        lines.append("</svg>")\n'
               '        return lines.joined(separator: "\\n")\n    }\n'
               f'    static func headerLines() -> [String] {{ ["{SVG_OPEN}", "<defs><marker id=\\"m\\"/></defs>"] }}\n}}\n'
               ).get("make")
    check("X29 a hop returning [String]: OPEN-HOP, GATED, GATED2",
          cue(row, "OPEN_HOP") and gated(row) and row["gated2"])
    row = make('        return "<?xml version=\\"1.0\\"?><links>\\(items.map { "<link href=\\"\\($0)\\"/>" }.joined())'
               '</links>"')
    check("X31 a nested literal holding `\\\"` inside an interpolation's closure: the unit is whole; CLOSE, GATED",
          cue(row, "CLOSE") and gated(row))
    source = ('enum Emitter {\n    static func make(_ items: [String]) -> String {\n'
              '        "<?xml version=\\"1.0\\"?><a xmlns=\\"http://x.org/ns\\">\\(items.map { "<b c=\\"\\($0)\\"/>" }'
              '.joined())</a>"\n    }\n    static func other() -> String { "</a>" }\n}\n')
    units, _ = units_of("/r/A.swift", source)
    check("X31 a namespace URL (`//`) in a nested literal: the unit is whole and the next member keeps its owner",
          gated(_one(source).get("make")) and [(u["name"], u["owner"]) for u in units]
          == [("make", "Emitter"), ("other", "Emitter")])
    check("X31 gated_without_pure: C12's impure emitter yes, C2's header no",
          _one(_wrap('        let here = FileManager.default.currentDirectoryPath\n'
                     f'        return "{SVG_OPEN}" + here + "</svg>"')).get("make", {}).get("gated_without_pure")
          and not _rows({"/r/ComponentSVGRenderer+SVG.swift": COMPONENT_SVG})["svgHeader"]["gated_without_pure"])

    # The literal view (§1.1).
    view = [content for _, _, content in literal_view('let a = "a\\nb\\tc\\u{41}"')]
    check("X27 escapes: \\n, \\t and \\u{41} resolve", view == ["a\nb\tcA"])
    view = [content for _, _, content in literal_view('let a = #"C:\\"# + "x"')]
    check("X27 a raw string ending in a backslash, then a literal on the same line", view == ["C:\\", "x"])
    view = [content for _, _, content in literal_view('let a = #"\\(x)\\#(y)"#')]
    check("X27 in a raw string, `\\(x)` is text and `\\#(y)` an interpolation", view == ["\\(x)\x01"])
    view = [content for _, _, content in literal_view('let r = /"/\nlet s = "<svg>"')]
    check("X27 a regex literal holding a quote opens no literal", view == ["<svg>"])

    # Copies (§1.3).
    def keys(*sources):
        rows = []
        for index, source in enumerate(sources):
            for found in census({f"/r{index}/A.swift": source}, prefilter=False):
                rows.append(dict(found, group="decision", toplevel=f"/r{index}", repo=f"r{index}"))
        return merge_copies(rows)

    differ = keys(_wrap(base, owner="enum A"),
                  _wrap(f'        return "{XML_DECL}<feed xmlns=\\"a\\">" + items.joined() + "</feed>"', owner="enum B"))
    check("X32 two units that differ only in their literals are not copies", len(differ) == 2)
    differ = keys(_wrap(f'        return "{SVG_OPEN}\\(items[0].lowercased())</svg>"', owner="enum A"),
                  _wrap(f'        return "{SVG_OPEN}\\(items[1])</svg>"', owner="enum B"))
    check("X32 two units that differ only in interpolation code are not copies", len(differ) == 2)
    page = f'struct Page {{\n    var r = ""\n    var svg: String {{ "<!doctype html><html><body>{SVG_OPEN}\\(r)</svg></body></html>" }}\n}}\n'
    circle = f'struct Circle {{\n    var r = ""\n    var svg: String {{ "{SVG_OPEN}<circle r=\\"\\(r)\\"/></svg>" }}\n}}\n'
    both = keys(page, circle)
    check("X32 an HTML page and a GATED emitter with one name and shape stay two rows; the GATED one is kept",
          len(both) == 2 and any(row["gated"] for row in both))
    same = keys(circle, circle)
    check("X32 a verbatim copy of a computed property in two repositories is one row", len(same) == 1
          and len(same[0]["copies"]) == 1)
    real = [dict(group=group, toplevel=top, repo=repo, path="A.swift", line=1, key="k")
            for group, top, repo in (("wide", "/Users/j/github_projects/Sitrep", "Sitrep"),
                                     ("decision", "/Users/j/xcode_projects/SwiftUMLStudio", "SwiftUMLStudio"),
                                     ("decision", "/b", "b"), ("decision", "/a", "a"))]
    merged = merge_copies(real)
    check("X33 copies keep the decision group's first repository by path, over a wide copy that sorts first",
          len(merged) == 1 and merged[0]["toplevel"] == "/Users/j/xcode_projects/SwiftUMLStudio"
          and merged[0]["copy_groups"].count("wide") == 1)
    merged = merge_copies(real[3:] + real[2:3])
    check("X33 of two decision copies, /a's is kept over /b's", len(merged) == 1 and merged[0]["toplevel"] == "/a")
    return checks


def round_two_controls():
    """§3's controls added after the second review round: one or more per rule its rule-break audit found no control
    caught, per shape its parser attack found misread, and per decision line no control read. `[(label, passed)]`."""
    checks = []

    def check(label, condition):
        checks.append((label, bool(condition)))

    def make(body, **kwargs):
        return _one(_wrap(body, **kwargs)).get("make")

    def cue(row, name):
        return bool(row) and row["cues"][name]

    def gated(row):
        return bool(row) and row["gated"]

    base = f'        return "{SVG_OPEN}" + items.joined() + "</svg>"'

    # The stream: a hop interpolated into a literal (§1.2).
    head = '    static var xmlHeader: String { "<?xml version=\\"1.0\\" encoding=\\"UTF-8\\"?>" }\n'
    for label, body in (("called before the body's literal that holds the root",
                         '        xmlHeader + "\\n<testsuites>\\n" + names.joined() + "</testsuites>"'),
                        ("interpolated into the literal that holds the root",
                         '        "\\(xmlHeader)\\n<testsuites>\\n" + names.joined() + "</testsuites>"')):
        row = _one('struct JUnitReporter {\n' + head + '    static func generateReport(_ names: [String]) -> String {\n'
                   + body + '\n    }\n}\n').get("generateReport")
        check(f"X35 the declaration in a hop {label}: OPEN-HOP, ROOT testsuites, CLOSE, GATED",
              cue(row, "OPEN_HOP") and row["cues"]["ROOT"] == "testsuites" and gated(row))
    row = _one('enum Emitter {\n    static var size: String { "24" }\n    static func make(_ items: [String]) -> String {\n'
               '        "<svg width=\\"\\(size)\\" xmlns=\\"http://www.w3.org/2000/svg\\">" + items.joined() + "</svg>"\n'
               '    }\n}\n').get("make")
    check("X35 a String hop interpolated inside the opening tag, before its xmlns: the body's tag still opens; ROOT svg,"
          " GATED", cue(row, "OPEN_BODY") and row["cues"]["ROOT"] == "svg" and gated(row))
    row = _one('enum Emitter {\n    static var prolog: String { "<?xml version=\\"1.0\\"?>" }\n'
               '    static func make(_ items: [String]) -> String {\n'
               f'        "\\(prolog){SVG_OPEN}" + items.joined() + "</svg>"\n    }}\n}}\n').get("make")
    check("X35 a declaration hop interpolated before the body's svg tag opens first: OPEN-HOP, ROOT svg, GATED",
          cue(row, "OPEN_HOP") and row["cues"]["ROOT"] == "svg" and gated(row))

    # Receivers (§1.2): the owner's own member holds the opener, so the receiver rule alone decides.
    two = ('enum Emitter {\n    static func make(_ items: [String]) -> String {\n        let o = Other()\n'
           '        return o.header() + Other.header() + items.joined() + "</svg>"\n    }\n'
           f'    static func header() -> String {{ "{SVG_OPEN}" }}\n}}\n'
           'struct Other {\n    func header() -> String { "" }\n    static func header() -> String { "" }\n}\n')
    row = _one(two).get("make")
    check("X8 `o.header()` and `Other.header()` beside an own `header()` that holds the opener: no OPEN",
          row and not cue(row, "OPEN"))
    row = _one('struct Document {\n    var header: String\n}\n'
               f'enum SVGRenderer {{\n    static var header: String {{ "{SVG_OPEN}" }}\n'
               '    static func render(_ doc: Document) -> String {\n        doc.header + "</svg>"\n    }\n}\n').get("render")
    check("X8 `doc.header`, a same-named member read on a model value: no OPEN, not GATED",
          row and not cue(row, "OPEN") and not gated(row))

    # Stored properties as hops (§1.2).
    for label, declaration, body, root in (
            ("continued on a line that starts with `+`",
             f'    static let header = "{XML_DECL}\\n"\n        + "<checkstyle version=\\"4.3\\">"\n',
             '        header + items.joined() + "</checkstyle>"', "checkstyle"),
            ("typed `String` and continued on a line that starts with `.`",
             f'    static let header: String = "{XML_DECL}"\n        .appending("<checkstyle version=\\"4.3\\">")\n',
             '        header + items.joined() + "</checkstyle>"', "checkstyle"),
            ("typed `[String]` over several bracketed lines",
             f'    static let header: [String] = [\n        "{XML_DECL}",\n        "<checkstyle version=\\"4.3\\">"\n'
             '    ]\n', '        (header + items + ["</checkstyle>"]).joined()', "checkstyle"),
            ("private and typed `String`",
             f'    private static let header: String = "{XML_DECL}\\n<checkstyle version=\\"4.3\\">"\n',
             '        header + items.joined() + "</checkstyle>"', "checkstyle"),
            ("untyped, with a trailing line comment", f'    static let header = "{SVG_OPEN}" // the opener\n',
             '        header + items.joined() + "</svg>"', "svg"),
            ("untyped, with a trailing block comment", f'    static let header = "{SVG_OPEN}" /* opener */\n',
             '        header + items.joined() + "</svg>"', "svg"),
            ("untyped, a declaration and a root, commented, the body's only marker an end tag",
             f'    static let header = "{XML_DECL}<checkstyle version=\\"4.3\\">" // prolog\n',
             '        header + items.joined() + "</checkstyle>"', "checkstyle")):
        row = _one('enum Emitter {\n' + declaration + '    static func make(_ items: [String]) -> String {\n'
                   + body + '\n    }\n}\n').get("make")
        check(f"X6–X7 a stored header {label}: OPEN-HOP, ROOT {root}, GATED",
              cue(row, "OPEN_HOP") and row["cues"]["ROOT"] == root and gated(row))
    row = _one('enum Emitter {\n    static let doctype = "<!DOCTYPE html>" // HTML5\n'
               f'    static func make(_ items: [String]) -> String {{\n        doctype + "{SVG_OPEN}" + items.joined() + "</svg>"\n'
               '    }\n}\n').get("make")
    check("X7 an untyped doctype with a trailing comment still reaches the text: HTML, not GATED",
          cue(row, "HTML") and not gated(row))
    row = _one(f'let svgHeader = "{SVG_OPEN}"\nfunc renderIcon(_ items: [String]) -> String {{\n'
               '    svgHeader + items.joined() + "</svg>"\n}\n').get("renderIcon")
    check("X7 a file-scope stored header read by a top-level emitter: OPEN-HOP, GATED", cue(row, "OPEN_HOP") and gated(row))
    for spelling in ("[Swift.String]", "Array<String>", "Array<Swift.String>", "Swift.String"):
        value = f'["{SVG_OPEN}"]' if spelling != "Swift.String" else f'"{SVG_OPEN}"'
        joined = ".joined()" if spelling != "Swift.String" else ""
        row = _one('enum Emitter {\n    static func make(_ items: [String]) -> String {\n'
                   f'        header(){joined} + items.joined() + "</svg>"\n    }}\n'
                   f'    static func header() -> {spelling} {{ {value} }}\n}}\n').get("make")
        check(f"X29 a hop written `-> {spelling}`: OPEN-HOP", cue(row, "OPEN_HOP"))

    # Locals and labels (§1.2).
    member = f'    static let line = "{SVG_OPEN}"\n'
    for label, body in (("an untyped two-parameter closure", '        items.enumerated().map { index, line in line }'
                                                              '.joined() + "</svg>"'),
                        ("a parenthesised two-parameter closure", '        items.enumerated().map { (index, line) in line }'
                                                                 '.joined() + "</svg>"'),
                        ("a typed closure parameter list", '        items.enumerated().map { (index: Int, line: String)'
                                                           ' -> String in line }.joined() + "</svg>"'),
                        ("a `for` tuple's second name", '        var s = ""\n        for (index, line) in items.enumerated()'
                                                        ' { s += line }\n        return s + "</svg>"')):
        row = _one('enum Emitter {\n    static func make(_ items: [String]) -> String {\n' + body + '\n    }\n'
                   + member + '}\n').get("make")
        check(f"X9 a bare read shadowed by {label}: no OPEN", row and not cue(row, "OPEN"))
    row = _one('enum Emitter {\n    static func make(_ items: [String]) -> String {\n        var out = line\n'
               '        for item in items {\n            let line = "<g>"\n            out += line + item\n        }\n'
               '        return out + "</svg>"\n    }\n' + member + '}\n').get("make")
    check("X9 a local declared anywhere in the body shadows the name everywhere in it (disclosed): no OPEN",
          row and not cue(row, "OPEN"))
    row = _one('enum Emitter {\n    static func make(_ items: [String]) -> String {\n'
               '        wrap(items.joined(), header: false) + "</svg>"\n    }\n'
               f'    static let header = "{SVG_OPEN}"\n'
               '    static func wrap(_ x: String, header: Bool) -> String { x }\n}\n').get("make")
    check("X10 an argument label after `,` named like a member is not a hop: no OPEN", row and not cue(row, "OPEN"))
    row = _one('enum Emitter {\n    static func make(_ s: Box) -> String {\n        s[header: "x"] + "</svg>"\n    }\n'
               f'    static let header = "{SVG_OPEN}"\n}}\n').get("make")
    check("X10 a subscript label after `[` named like a member is not a hop: no OPEN", row and not cue(row, "OPEN"))

    # Owners (§1.1–§1.2).
    row = _one('enum Reporters {\n    struct Checkstyle {\n        static func make(_ items: [String]) -> String {\n'
               '            header() + items.joined() + "</svg>"\n        }\n    }\n}\n',
               others={"/r/B.swift": 'extension Reporters.Checkstyle {\n    static func header() -> String {\n'
                                     f'        "{SVG_OPEN}"\n    }}\n}}\n'}).get("make")
    check("C25 the opening literal in `extension Outer.Inner` in another file: OPEN-HOP, GATED",
          cue(row, "OPEN_HOP") and gated(row))
    row = _one('import struct Foundation.Date\nenum Renderer {\n'
               '    static var markerDefs: String { "<defs><marker id=\\"arrow\\"/></defs>" }\n'
               f'    static func render(_ items: [String]) -> String {{\n        "{SVG_OPEN}" + markerDefs + items.joined()'
               ' + "</svg>"\n    }\n}\n').get("render")
    check("X36 `import struct M.T` above a type declares nothing: the type's computed property keeps its owner;"
          " IDDEF through it, GATED2", row and row["cues"]["hops"] == ["markerDefs"] and row["gated2"])

    # Search keys (§1.2).
    row = make(f'        switch items.count {{\n        case 0: return "{SVG_OPEN}</svg>"\n        default: return ""\n'
               '        }')
    check("X2 a literal after a `case` pattern's colon on its line flows: OPEN, CLOSE, GATED",
          cue(row, "OPEN") and cue(row, "CLOSE") and gated(row))
    missed = [name for name in sorted(SEARCH_CALLS)
              if cue(make(f'        _ = items[0].{name}("</svg>")\n        return "{SVG_OPEN}" + items.joined()'), "CLOSE")
              or not cue(make(f'        _ = items[0].{name}("</svg>")\n        return "{SVG_OPEN}" + items.joined()'),
                         "OPEN")]
    check(f"X38 each of the {len(SEARCH_CALLS)} search calls by its name alone, unlabelled: OPEN, no CLOSE", not missed)
    check("X38 the search calls are §1.2's 22", SEARCH_CALLS == {
        "hasPrefix", "hasSuffix", "contains", "starts", "range", "ranges", "firstRange", "firstIndex", "lastIndex",
        "components", "split", "trimmingPrefix", "trimPrefix", "matches", "wholeMatch", "prefixMatch", "firstMatch",
        "memcmp", "strcmp", "strncmp", "replacing", "replace"})

    # Comments and CDATA inside a literal (§1.2).
    for label, literal, root in (
            ("a bracketed URL in a leading comment", f'<!-- Generated by tool <https://example.com> -->{SVG_OPEN}', "svg"),
            ("a tag named in a comment after the declaration",
             f'{XML_DECL}<!-- by <tool> --><checkstyle version=\\"4.3\\">', "checkstyle"),
            ("a CDATA section holding a tag", f'{XML_DECL}<![CDATA[<b>]]><checkstyle version=\\"4.3\\">', "checkstyle")):
        close = "</svg>" if root == "svg" else "</checkstyle>"
        row = make(f'        return "{literal}" + items.joined() + "{close}"')
        check(f"X34 {label} is text: ROOT {root}, GATED", row and row["cues"]["ROOT"] == root and gated(row))
    row = make(f'        return "{SVG_OPEN}" + items.joined() + "<!-- </svg> -->"')
    check("X34 an end tag only inside a comment closes nothing: no CLOSE", row and not cue(row, "CLOSE"))

    # Known false-positive classes of the gate, pinned as they stand (§1.2, §9).
    row = make(f'        "{XML_DECL}\\n" + "<rss version=\\"2.0\\">\\n<channel>\\n" + "<title>\\(items[0])</title>\\n"')
    check("X39 a split-literal declaration header that never closes its root takes a closed child as ROOT: ROOT title,"
          " GATED (a known false-positive class; the judges read FRAGMENT)",
          row and row["cues"]["ROOT"] == "title" and gated(row))
    row = make('        var html = "<div class=\\"card\\">"\n'
               f'        html += "{SVG_OPEN}<path d=\\"\\(items[0])\\"/></svg>"\n'
               '        html += "<p>\\(items[1])</p>"\n        html += "</div>"\n        return html')
    check("X39 an xmlns tag after another start tag in an earlier literal still opens: ROOT svg, GATED (a known"
          " false-positive class; the judges read FRAGMENT or HTML)", row and row["cues"]["ROOT"] == "svg" and gated(row))
    row = make('        var bars = "<g class=\\"bars\\">"\n        bars += items.joined()\n        bars += "</g>"\n'
               f'        return "{SVG_OPEN}" + bars + "</svg>"')
    check("X39 a chart that builds its body before the opener: ROOT svg, GATED (what a cross-literal rule would lose)",
          row and row["cues"]["ROOT"] == "svg" and gated(row))

    # PURE and `print(…, to:)` (§1.2).
    spellings = {
        r"\bFileManager\b": "FileManager.default.homeDirectoryForCurrentUser.path",
        r"\bProcessInfo\b": "ProcessInfo.processInfo.hostName", r"\bBundle\s*\.\s*main\b": "Bundle.main.bundlePath",
        r"\bUserDefaults\b": 'UserDefaults.standard.string(forKey: "k") ?? ""',
        r"\bURLSession\b": "URLSession.shared", r"\bFileHandle\b": "FileHandle.standardInput",
        r"\bProcess\s*\(": "Process()", r"\bDate\s*\(\s*\)": "Date()", r"\bDate\s*\.\s*now\b": "Date.now",
        r"\.now\s*\(\s*\)": "clock.now()", r"\bUUID\s*\(\s*\)": "UUID().uuidString",
        r"\.random\s*\(": "Int.random(in: 0...9)", r"\barc4random": "arc4random()",
        r"\bCFAbsoluteTimeGetCurrent\b": "CFAbsoluteTimeGetCurrent()", r"\bDispatchTime\s*\.\s*now\b": "DispatchTime.now",
        r"\bgetenv\s*\(": 'getenv("HOME")', r"\bfopen\s*\(": 'fopen("a", "r")', r"\bprint\s*\(": 'print("x")',
        r"\bNSLog\s*\(": 'NSLog("x")', r"\bcurrentDirectoryPath\b": "fm.currentDirectoryPath"}
    wrong = [pattern for pattern, use in spellings.items()
             if (lambda row: not row or row["cues"]["PURE"] or row["gated"] or row["cues"]["impure"] != [pattern])(
                 make(f'        let n = {use}\n        return "{SVG_OPEN}\\(n)" + items.joined() + "</svg>"'))]
    check("C12 each of the 20 impurity tokens alone: PURE false, that token only, not GATED",
          sorted(spellings) == sorted(IMPURITY) and not wrong)
    row = make('        var out = ""\n        print("<?xml version=\\"1.0\\"?>", to: &out)\n'
               '        print("<testsuites timestamp=\\"\\(Date())\\">", to: &out)\n        print("</testsuites>", to: &out)\n'
               '        return out')
    check("X28 a clock read inside a `print(…, to:)` argument still counts: PURE false, not GATED",
          row and not cue(row, "PURE") and not gated(row))
    row = make('        print(items[0].distance(to: items[1]))\n' + base)
    check("X28 a `to:` label nested inside a plain print's argument: not print(to:); PURE false",
          row and not cue(row, "PURE"))
    row = make('        print("rendering")\n        for i in stride(from: 0, to: 3, by: 1) { _ = i }\n' + base)
    check("X28 a plain print followed by a later `to:` label: PURE false", row and not cue(row, "PURE"))
    row = _one('enum Emitter {\n    static func make(_ items: [String]) -> String {\n        var out = ""\n'
               '        print(header(), to: &out)\n        return out + items.joined() + "</svg>"\n    }\n'
               f'    static func header() -> String {{ "{SVG_OPEN}" }}\n}}\n').get("make")
    check("X28 `print(header(), to: &out)`, a call inside the print's own argument: PURE, GATED",
          cue(row, "PURE") and gated(row))

    # The signature and units (§1.1–§1.2).
    row = make(base, signature="static func make(_ items: [String]) -> [String]")
    check("C11 `-> [String]` is a hop's shape, not a unit's: STRING false, not GATED",
          row and not cue(row, "STRING") and not gated(row))
    check("X24 a `willSet` observer block: no unit",
          "t" not in _one(f'struct Icon {{\n    var t: String {{\n        willSet {{ log("{SVG_OPEN}</svg>") }}\n    }}\n}}\n'))
    for marker in ("<svg", "<plist", "</plist>"):
        check(f"§1.3 `{marker}` alone in a body literal makes a candidate",
              make(f'        return items.joined() + "{marker}"') is not None)
    row = make('        return "<html xmlns=\\"http://www.w3.org/1999/xhtml\\">" + items.joined() + "</html>"')
    check("X20 an XHTML page is not gated_without_pure", row and not row["gated_without_pure"])

    # IDDEF (§1.2).
    row = make(f'        return "{SVG_OPEN}<marker\\n\\tid=\\"m\\"/>" + items.joined() + "</svg>"')
    check("X21 a line break and a tab before `id=`: IDDEF, GATED2", cue(row, "IDDEF") and row["gated2"])

    # The prefilter (§1.3).
    source = ('enum Emitter {\n    static func make(_ items: [String]) -> String {\n'
              '        header() + items.joined() + "</checkstyle>"\n    }\n'
              f'    static func header() -> String {{ "{XML_DECL}\\n" + "<checkstyle version=\\"4.3\\">" }}\n}}\n'
              'enum Plain {\n    static func f() -> Int { 1 }\n}\n')
    filtered = [(row["name"], row["cues"]["ROOT"], row["gated"]) for row in census({"/r/A.swift": source})]
    unfiltered = [(row["name"], row["cues"]["ROOT"], row["gated"]) for row in census({"/r/A.swift": source},
                                                                                      prefilter=False)]
    check("X37 the prefilter `run` uses changes no row: X17's candidate by its end tag is kept",
          filtered == unfiltered and ("make", "checkstyle", True) in filtered)
    escaped = _wrap('        return "\\u{3C}?xml version=\\"1.0\\"?>\\u{3C}root>" + items.joined() + "\\u{3C}/root>"')
    row = {r["name"]: r for r in census({"/r/A.swift": escaped})}.get("make")
    check("X37 markers spelled with `\\u{…}` escapes pass the prefilter: a candidate, ROOT root, GATED",
          row and row["cues"]["ROOT"] == "root" and gated(row))
    cases = "\n".join(f'        case .i{i}: return "{SVG_OPEN}<path d=\\"M{i}\\"/></svg>"' for i in range(4000))
    catalog = ("enum Icon {\n" + "\n".join(f"    case i{i}" for i in range(4000))
               + "\n    var svg: String {\n        switch self {\n" + cases + "\n        }\n    }\n}\n")
    started = time.monotonic()
    row = _one(catalog).get("svg")
    check("X37 a 4,000-case icon catalog's `switch` is read in linear time: under 10 s, GATED",
          gated(row) and time.monotonic() - started < 10)

    # Copies (§1.3).
    def keys(*sources):
        rows = []
        for index, text in enumerate(sources):
            for found in census({f"/r{index}/A.swift": text}, prefilter=False):
                rows.append(dict(found, group="decision", toplevel=f"/r{index}", repo=f"r{index}"))
        return merge_copies(rows)

    one_line = _wrap(base, owner="enum A")
    nested = ('enum Outer {\n    enum A {\n        static func make(_ items: [String]) -> String {\n'
              f'            return "{SVG_OPEN}" +\n                items.joined() + "</svg>"\n        }}\n    }}\n}}\n')
    multi = ('enum A {\n    static func make(_ items: [String]) -> String {\n        """\n'
             '        <svg xmlns="http://www.w3.org/2000/svg">\n        """ + items.joined() + "</svg>"\n    }\n}\n')
    deeper = ('enum Outer {\n    enum A {\n        static func make(_ items: [String]) -> String {\n            """\n'
              '            <svg xmlns="http://www.w3.org/2000/svg">\n            """ + items.joined() + "</svg>"\n'
              '        }\n    }\n}\n')
    for label, first, second in (
            ("a copy re-indented and nested one level deeper", one_line, nested),
            ("a multi-line literal re-indented one level", multi, deeper),
            ("one body under `enum A` and under `enum B`", one_line, _wrap(base, owner="enum B")),
            ("one body over `[String]` and over `ArraySlice<String>`", one_line,
             _wrap(base, "static func make(_ items: ArraySlice<String>) -> String", owner="enum A"))):
        merged = keys(first, second)
        check(f"X32 {label} is one row: whitespace collapsed, owner and parameter types not compared",
              len(merged) == 1 and len(merged[0]["copies"]) == 1)
    split = [dict(group="decision", toplevel=top, repo=repo, path="A.swift", line=1, key="k")
             for top, repo in (("/Users/j/xcode_projects/Alpha", "Alpha"), ("/Users/j/github_projects/Zeta", "Zeta"))]
    merged = merge_copies(split)
    check("X33 the repository (toplevel) orders before the subject name: Zeta's copy is kept",
          len(merged) == 1 and merged[0]["repo"] == "Zeta" and merged[0]["copy_repos"] == ["Alpha"])

    # What a judge sees (§4.3).
    source = ('struct LinkRenderer {\n    static func links(_ xs: [String]) -> String {\n'
              '        "<?xml version=\\"1.0\\"?><links>\\(xs.map { "<a href=\\"\\($0)\\"/>" }.joined())</links>"\n'
              '    }\n    static func title() -> String { "t" }\n    static let version = 2\n}\n')
    files = {"/r/A.swift": source}
    row = census(files, prefilter=False)[0]
    row.update(repo="r", root="/r", path="A.swift", group="decision", toplevel="/r", id="r:A.swift:2", judged=True)
    row["members"] = member_lines(owner_entries(files, "LinkRenderer"), first="/r/A.swift", skip=("/r/A.swift", row["line"]))
    text = render("p/1", row)
    shown = text.replace(row["text"], "")
    check("X40 a packet row: the owner's other members whole past a nested literal, and no cue, gate or group shown",
          "static func title() -> String" in row["members"] and "static let version = 2" in row["members"]
          and not any(word in shown for word in ["GATED", "gated", "decision", "ROOT", "OPEN", "CLOSE", "PURE",
                                                 "IDDEF", "XMLNS", "XMLDECL"]))
    rows = [dict(row, id=f"r:A.swift:{i}", judged=i != 17) for i in range(18)]
    with tempfile.TemporaryDirectory() as scratch:
        path = os.path.join(scratch, "census.json")
        json.dump({"candidates": rows}, open(path, "w", encoding="utf-8"))
        with contextlib.redirect_stdout(io.StringIO()):
            packets(path, os.path.join(scratch, "packets"))
        written = sorted(os.listdir(os.path.join(scratch, "packets")))
        index = json.load(open(os.path.join(scratch, "index.json"), encoding="utf-8"))
        first = open(os.path.join(scratch, "packets", "packet-01.md"), encoding="utf-8").read()
    check("X40 packets: 17 judged rows in packets of eight, the index beside them, the unjudged row left out, no cue"
          " in a packet", written == ["packet-01.md", "packet-02.md", "packet-03.md"] and len(index) == 17
          and "r:A.swift:17" not in {entry["id"] for entry in index} and "GATED" not in first)
    return checks


def round_two_decisions():
    """§3's decision controls added after the second review round. `[(label, passed)]`."""
    checks = []

    def check(label, condition):
        checks.append((label, bool(condition)))

    def refuses(call):
        try:
            call()
        except SystemExit:
            return True
        return False

    def decided(rows, verdicts, kills=KILLS):
        return decide({"candidates": rows}, verdicts, kills)

    def documents(rows, **kwargs):
        return {row["id"]: _doc_verdict(**kwargs) for row in rows}

    five = [_row(f"r{i}", top=f"/r{i % 2}") for i in range(5)]
    verdicts = documents(five)
    svg = [_row(f"g{i}", top=f"/g{i % 2}", gated2=True) for i in range(5)]
    owing_svg = documents(svg, law2="OWES")

    # Law 2's later outcomes, and each law reading its own kill summary (§8).
    check("D8 law 2 reads its own decisive count: law 1 BUILD, law 2 DECLINE (kills)",
          decided(svg, owing_svg, _kills(law1=3, law2=0))[0] == {1: "BUILD", 2: "DECLINE (kills)"})
    check("D8 law 1 reads its own: law 1 DECLINE (kills), law 2 BUILD",
          decided(svg, owing_svg, _kills(law1=0, law2=2))[0] == {1: "DECLINE (kills)", 2: "BUILD"})
    check("D7 law 2's decisive count None: law 2 UNMEASURED (kills), law 1 BUILD",
          decided(svg, owing_svg, _kills(law2=None))[0] == {1: "BUILD", 2: "UNMEASURED (kills)"})
    fewer = [dict(row, gated2=(i < 4)) for i, row in enumerate(svg)]
    check("D30 five OWES groups over two repositories, four GATED2: law 2 DECLINE (signal)",
          decided(fewer, owing_svg)[0][2] == "DECLINE (signal)")
    for count, expect in ((7, "BUILD"), (6, "DECLINE (gate precision)")):
        rows = [_row(f"p{i}", top=f"/p{i % 2}", gated2=True) for i in range(count)]
        rows += [_row(f"q{i}", top="/p0", gated2=True) for i in range(3)]
        judged = dict(documents(rows[:count], law2="OWES"), **{f"q{i}": _doc_verdict(law2="VACUOUS") for i in range(3)})
        outcomes, figures, _ = decided(rows, judged)
        check(f"D30 GATED2 precision {count}/{count + 3}: law 2 {expect}, law 1 BUILD",
              outcomes == {1: "BUILD", 2: expect} and figures[2]["gated_not_owing"] == ["q0", "q1", "q2"])

    # The signal bar's repository half, and its unambient sensitivity (§8).
    confined = [_row(f"c{i}", top="/r0") for i in range(5)] + [_row("c9", top="/r1", gated=False)]
    outcomes, figures, _ = decided(confined, documents(confined))
    check("D5 five gated groups in one repository of a two-repository population: DECLINE (signal)",
          outcomes[1] == "DECLINE (signal)" and figures[1]["N"] == 6 and figures[1]["repositories"] == 2
          and figures[1]["N_gated"] == 5 and figures[1]["gated_repositories"] == 1)
    bridged = ([_row("render", top="/r9", owner="E", name="render", hops=("body",)),
                _row("body", top="/r9", owner="E", name="body", gated=False)]
               + [_row(f"g{i}", top=f"/r{i % 2}", owner=f"T{i}") for i in range(4)])
    _, figures, _ = decided(bridged, dict(documents(bridged), render=_doc_verdict(ambient=True)))
    check("D22 a group whose only GATED row is ambient is out of N_gated without ambient, though an ungated member is"
          " not ambient: 4 over 2", figures[1]["N_gated"] == 5 and figures[1]["N_gated_unambient"] == (4, 2))
    _, _, lines = decided(five, verdicts)
    check("D22 five unambient gated groups over two repositories: the ambient line says clears",
          "SENSITIVITY law 1 N_gated without rows judged ambient: 5 over 2 repositories — clears the signal bar" in lines)

    # Beside figures (§8).
    rows = five + [dict(_row("p1", top="/p", gated=False, cues={"PURE": False, "ROOT": "svg", "IDDEF": True}),
                        gated_without_pure=True), _row("n1", top="/n"), _row("w1", group="wide", top="/w")]
    _, figures, _ = decided(rows, dict(verdicts, p1=_doc_verdict(law2="OWES"), n1=_doc_verdict(expressible=False),
                                       w1={"verdict": "FRAGMENT"}))
    check("D21 precision without PURE: an impure SVG emitter counts for law 2, non-SVG rows do not; a wide row is"
          " outside; a DOCUMENT row need not be EXPRESSIBLE",
          figures[1]["precision_without_pure"] == (7, 7) and figures[2]["precision_without_pure"] == (1, 1))
    _, figures, _ = decided(five + [_row("n1", top="/n")], dict(verdicts, n1=_doc_verdict(expressible=False)))
    check("D21 the unmerged count needs EXPRESSIBLE", figures[1]["unmerged"] == 5)
    for total, owing, expect, label in ((120, 3, (11, 5), "estimate 6.0"), (94, 3, (10, 5), "estimate 4.7, rounded"),
                                         (150, 1, (7, 3), "estimate 2.5, rounded half to even")):
        wide = [_row(f"w{i}", group="wide", top=f"/w{i}", gated=False) for i in range(total)]
        judged = dict(verdicts)
        for i, row in enumerate(wide):
            row["judged"] = i < 60
            if i < 60:
                judged[row["id"]] = _doc_verdict() if i < owing else {"verdict": "HTML"}
        _, figures, lines = decided(five + wide, judged)
        check(f"D21 the sum's wide term is N_wide's estimate ({label}): {expect}",
              figures[1]["sensitivity"]["N + N_unmet + N_layout + N_wide"] == expect)
    check("D21 N_wide's estimate without EXPRESSIBLE is printed", any(
        line.startswith("law 1 without EXPRESSIBLE:") and line.endswith("(estimate 2.5)") for line in lines))
    spread = [_row("w1", group="wide", top="/w", gated2=True), dict(_row("e1", top="/e", gated2=True), copy_repos=["/c"])]
    _, figures, lines = decided(spread, {"w1": _doc_verdict(law2="OWES"),
                                         "e1": _doc_verdict(law2="OWES", expressible=False)})
    check("D27 an owing SVG emitter in the wide group, one not EXPRESSIBLE, and a copy's repository are all listed",
          figures[2]["owing_anywhere"] == ["/c", "/e", "/w"] and any(l.endswith("in any group: /c, /e, /w") for l in lines))
    cue_rows = [_row(f"m{cue}", top=f"/m{i}", gated=False, cues={cue: False})
                for i, cue in enumerate(("STRING", "NOTHROW", "SYNC", "NONMUTATING", "PURE", "OPEN"))]
    cue_rows += [_row("mHTML", top="/mh", gated=False, cues={"HTML": True}),
                 _row("mX", top="/mx", gated=False, cues={"OPEN": False}), _row("mG", top="/mg")]
    _, figures, _ = decided(cue_rows, dict(documents(cue_rows, law2="OWES"), mX=_doc_verdict(law2="OWES",
                                                                                            expressible=False)))
    found = {entry["id"]: (entry["expressible"], entry["missed"]) for entry in figures[1]["ungated_owing"]}
    law2 = {entry["id"]: entry["missed"] for entry in figures[2]["ungated_owing"]}
    check("D27 R2 names each missed cue alone, HTML, and an owing group that is not EXPRESSIBLE; a gated group is not"
          " listed", found == dict({f"m{cue}": (True, [cue]) for cue in
                                    ("STRING", "NOTHROW", "SYNC", "NONMUTATING", "PURE", "OPEN")},
                                   mHTML=(True, ["HTML"]), mX=(False, ["OPEN"]))
          and law2["mPURE"] == ["PURE", "ROOT≠svg", "¬IDDEF"] and "mG" in law2)
    check("D28 the flag line lists every judged row in any group under its own flag",
          decided([_row("r1", top="/r1", gated2=True), _row("w1", group="wide", top="/w1")],
                  {"r1": _doc_verdict(law2="OWES", dangle=True), "w1": _doc_verdict(body=True)})[2][-1]
          .startswith("body disagrees: w1   refs dangle: r1   "))
    hand = _kills(law1=0, law2=3, hand=[{"id": "H1", "law1": "ASSERTION", "law2": None, "suite": "ASSERTION",
                                         "reduced": None, "suite_failed": []}])
    hand["summary"]["law1"]["decisive_with_hand"] = 1
    hand["summary"]["law2"]["decisive_with_hand"] = 3
    outcomes, _, lines = decided(five, verdicts, hand)
    check("D24 decisive 0 with H-mutants 1: DECLINE (kills); law 1's H line says 1 and that it clears the kills bar,"
          " and each hand mutant's outcome is printed",
          outcomes[1] == "DECLINE (kills)"
          and "SENSITIVITY law 1 decisive count with H1–H6 counted: 1 — clears the kills bar (more than 0)" in lines
          and "law 1 hand mutants: H1 law ASSERTION, reduced SURVIVED, full ASSERTION" in lines)
    hand["summary"]["law1"]["decisive_with_hand"] = 0
    _, _, lines = decided(five, verdicts, hand)
    check("D24 an H count of 0 does not clear the kills bar",
          "SENSITIVITY law 1 decisive count with H1–H6 counted: 0 — does not clear the kills bar (more than 0)" in lines)

    # The join (§4.3).
    index = [{"label": "p/1", "id": "r0"}]

    def labelled(record):
        return dict(record, label="p/1")

    kept = join(index, {"A": [labelled(_doc_verdict(law2="OWES"))], "B": [labelled(_doc_verdict(law2="VACUOUS", body=True))],
                        "C": [labelled(_doc_verdict(law2="VACUOUS"))]})
    check("D19 join: with C deciding, B's flag is kept", kept["r0"]["decided_by"] == "C" and kept["r0"]["body_disagrees"])
    unusable = dict(_doc_verdict(body=True), law2=None)
    kept = join(index, {"A": [labelled(unusable)], "B": [labelled(_doc_verdict(law2="VACUOUS"))],
                        "C": [labelled(_doc_verdict(law2="VACUOUS"))]})
    check("D19 join: a flag on an unusable DOCUMENT record is not raised", not kept["r0"]["body_disagrees"])
    check("D19 join: a DOCUMENT record whose flag is not a bool is unusable, so A and B go to C",
          refuses(lambda: join(index, {"A": [labelled(dict(_doc_verdict(), body_disagrees="false"))],
                                       "B": [labelled(_doc_verdict())]})))
    check("D16 law2's four values, each usable, and the same four the brief and the workflow name",
          LAW2 == {"OWES", "VACUOUS", "EXTERNAL", "NOT-SVG"} and all(usable(_doc_verdict(law2=value)) for value in LAW2))
    good = _calibration_records()
    record = {"label": "packet-01/1", "verdict": "HTML"}
    workflow = {"calibration": [{"records": good}, {"records": good}],
                "judged": [{"packet": "packet-01", "records": {"A": [record], "B": [record], "C": []}},
                           {"packet": "packet-02", "records": {"A": [dict(record, label="packet-02/1")] * 2,
                                                               "B": [dict(record, label="packet-02/1")], "C": []}}]}
    files = judge_files(workflow)
    two = [{"label": "packet-01/1", "id": "a"}, {"label": "packet-02/1", "id": "b"}]
    check("D29 the judge files concatenate each judge's raw records over the packets in order, so `join` refuses a"
          " label one judge repeated in a later packet",
          [r["label"] for r in files["A"]] == ["packet-01/1", "packet-02/1", "packet-02/1"]
          and refuses(lambda: join(two, files)))
    check("D29 the judge files refuse a stopped run, and a calibration record `calibrate` misses",
          refuses(lambda: judge_files({"stopped": "calibration"}))
          and refuses(lambda: judge_files(dict(workflow, calibration=[{"records": good + [good[1]]}, {"records": good}]))))

    # Frozen names (§2, §4.2).
    check("§8 the named subject is §2's SwiftLint", NAMED == "SwiftLint" and SWIFTLINT[0].endswith("/" + NAMED))
    check("D23 the calibration answers are §4.2's table", CALIBRATION == {
        "calibration/1": {"verdict": "DOCUMENT", "expressible": True, "law2": "OWES", "body_disagrees": False,
                          "refs_dangle": False},
        "calibration/2": {"verdict": "FRAGMENT"},
        "calibration/3": {"verdict": "DOCUMENT", "expressible": True, "body_disagrees": True},
        "calibration/4": {"verdict": "HTML"}, "calibration/5": {"verdict": "NOT-EMITTER"},
        "calibration/6": {"verdict": "DOCUMENT", "expressible": True, "law2": "NOT-SVG", "body_disagrees": False},
        "calibration/7": {"verdict": "DOCUMENT", "expressible": False},
        "calibration/8": {"verdict": "DOCUMENT", "law2": "EXTERNAL"},
        "calibration/9": {"verdict": "DOCUMENT", "law2": "VACUOUS"},
        "calibration/10": {"verdict": "DOCUMENT", "expressible": True, "body_disagrees": True}})

    # What is judged (§4.1).
    wide = [dict(_row(f"w{i:02d}", group="wide"), judged=False) for i in range(75)] + [_row("u1", group="unmet")]
    layout = [dict(_row(f"l{i:02d}", group="layout"), judged=False) for i in range(61)]
    report = {"candidates": [dict(r) for r in wide + layout]}
    choose(report)
    picked = sorted(r["id"] for r in report["candidates"] if r["judged"] and r["group"] == "wide")
    check("D26 61 layout candidates, more than the wide cap, are judged in full; the wide sample is unchanged",
          all(r["judged"] for r in report["candidates"] if r["group"] == "layout")
          and hashlib.sha256(",".join(picked).encode()).hexdigest()[:16] == "048c987a23e61ba2")
    return checks


def round_three_controls():
    """§3's controls added after the third review round: the ROOT bound and the nested stream it found, and one or more
    per rule its rule-break audit found no control caught. `[(label, passed)]`."""
    checks = []

    def check(label, condition):
        checks.append((label, bool(condition)))

    def make(body, **kwargs):
        return _one(_wrap(body, **kwargs)).get("make")

    def cue(row, name):
        return bool(row) and row["cues"][name]

    def gated(row):
        return bool(row) and row["gated"]

    def emitter(members, body, signature="static func make(_ items: [String]) -> String", name="make"):
        return _one(f'enum Emitter {{\n{members}    {signature} {{\n{body}\n    }}\n}}\n').get(name)

    svg_open = ('    static func svgOpen(_ w: Int) -> String {'
                ' "<svg xmlns=\\"http://www.w3.org/2000/svg\\" width=\\"\\(w)\\">" }\n')
    # ROOT's step 1 stops at the first cut after the declaration (§1.2).
    row = emitter(svg_open, f'        "{XML_DECL}\\n\\(svgOpen(10))\\n<rect width=\\"1\\"/>" + items.joined() + "</svg>"')
    check("X35 a declaration in the body, the root's tag in an interpolated hop, a child after it: ROOT svg, CLOSE, GATED",
          row and row["cues"]["ROOT"] == "svg" and cue(row, "CLOSE") and gated(row))
    row = emitter(svg_open, f'        "{XML_DECL}\\n\\(svgOpen(10))<g id=\\"a\\"></g>" + items.joined() + "</svg>"')
    check("X35 the same with an id-carrying child: GATED2", row and row["gated2"])
    row = emitter('    static var rootOpen: String { "<root>" }\n    static var rootClose: String { "</root>" }\n',
                  f'        "{XML_DECL}\\n\\(rootOpen)<item>x</item>" + items.joined() + rootClose')
    check("X35 the root's start tag in a hop and its close only in another: ROOT root, CLOSE-HOP, not GATED",
          row and row["cues"]["ROOT"] == "root" and cue(row, "CLOSE_HOP") and not gated(row))
    row = emitter('    static var version: String { "1.0" }\n',
                  '        "<?xml version=\\"\\(version)\\"?><feed>" + "<entry xmlns=\\"x\\"/>" + items.joined()'
                  ' + "</feed>"')
    check("X35 a hop inside the declaration does not end step 1: ROOT feed, not the later xmlns child; GATED",
          row and row["cues"]["ROOT"] == "feed" and gated(row))
    head = '    static var xmlHeader: String { "<?xml version=\\"1.0\\" encoding=\\"UTF-8\\"?>" }\n'
    for label, body, root in (
            ("a header hop inside a ternary's nested literal",
             '        "\\(flag ? "\\(xmlHeader)\\n" : "")<testsuites>" + items.joined() + "</testsuites>"', "testsuites"),
            ("a declaration written as a ternary's nested literal",
             f'        "\\(flag ? "{XML_DECL}\\n" : "")<plist version=\\"1.0\\">" + items.joined() + "</plist>"', "plist"),
            ("a function hop interpolated into the root's literal",
             '        "\\(header())\\n<testsuites>\\n" + items.joined() + "</testsuites>"', "testsuites"),
            ("a header hop after other text in a multi-line literal",
             '        """\n        \\(xmlHeader)\n        <checkstyle version="4.3">\n        \\(items.joined())\n'
             '        </checkstyle>\n        """', "checkstyle")):
        members = head + ('    static func header() -> String { "<?xml version=\\"1.0\\"?>" }\n' if "header()" in body else "")
        row = emitter(members, body, signature="static func make(_ items: [String], flag: Bool) -> String")
        check(f"X35 {label}: the stream reads it at its placeholder; ROOT {root}, GATED",
              row and row["cues"]["ROOT"] == root and gated(row))
    row = emitter(head, '        """\n        \\(xmlHeader)\n        <svg xmlns="http://www.w3.org/2000/svg">\n'
                        '        \\(items.joined())\n        </svg>\n        """')
    check("X35 a multi-line literal's svg tag after an interpolated header: OPEN-HOP, not OPEN-BODY, ROOT svg, GATED",
          cue(row, "OPEN_HOP") and not cue(row, "OPEN_BODY") and row["cues"]["ROOT"] == "svg" and gated(row))
    row = emitter('    static var head: String { "<?xml version=\\"1.0\\"?><report>" }\n',
                  f'        " \\(head){SVG_OPEN}" + items.joined() + "</svg></report>"')
    check("X35 a marker after the cut opens only from its own piece: the hop first, OPEN-HOP, ROOT report",
          cue(row, "OPEN_HOP") and row["cues"]["ROOT"] == "report")

    # Brackets closed inside a search call (§1.2).
    for label, test in (("a closed `{…}`", "items.contains(where: { $0.isEmpty })"),
                        ("a closed `[…]`", "items[0].hasPrefix(items[1])")):
        row = make(f'        let flag = {test}\n        var svg = "{SVG_OPEN}"\n'
                   '        svg += flag ? "" : items.joined()\n        svg += "</svg>"\n        return svg')
        check(f"X37 {label} inside a search call's arguments before the opener: OPEN, ROOT svg, CLOSE, GATED",
              cue(row, "OPEN") and row["cues"]["ROOT"] == "svg" and cue(row, "CLOSE") and gated(row))
    row = make('        var out = ""\n'
               f'        print("{SVG_OPEN}", to: &out)\n        print(items[0], to: &out)\n'
               '        print(items.map { "<g>\\($0)</g>" }.joined(), to: &out)\n        print("</svg>", to: &out)\n'
               '        return out')
    check("X28 a subscript and a closure inside print's own arguments still reach `to:`: PURE, GATED",
          cue(row, "PURE") and gated(row))

    # Comments and CDATA (§1.2).
    for label, body in (
            ("a comment spanning lines", '        return """\n        <?xml version="1.0"?>\n        <!--\n'
                                         '          by <https://example.com>\n        -->\n        <checkstyle version="4.3">\n'
                                         '        \\(items.joined())\n        </checkstyle>\n        """'),
            ("a comment left open to its literal's end", f'        return "{XML_DECL}<!-- by <https://example.com> on "'
                                                         ' + items[0] + " --><checkstyle version=\\"4.3\\">" + items.joined()'
                                                         ' + "</checkstyle>"'),
            ("a CDATA section left open to its literal's end", f'        return "{XML_DECL}<![CDATA[<b>" + items[0]'
                                                               ' + "]]><checkstyle version=\\"4.3\\">" + items.joined()'
                                                               ' + "</checkstyle>"')):
        row = make(body)
        check(f"X34 {label} is text: ROOT checkstyle, GATED", row and row["cues"]["ROOT"] == "checkstyle" and gated(row))

    # References: labels, receivers, closure heads (§1.2).
    row = _one('enum Emitter {\n    static func make(_ items: [String]) -> String {\n'
               '        wrap(\n            items.joined(),\n            header: false\n        ) + "</svg>"\n    }\n'
               f'    static let header = "{SVG_OPEN}"\n'
               '    static func wrap(_ x: String, header: Bool) -> String { x }\n}\n').get("make")
    check("X10 a label on its own line after `,` named like a member is not a hop: no OPEN, not GATED",
          row and not cue(row, "OPEN") and not gated(row))
    lines = "".join(f"        let w{n} = items.count * {n} + 1\n" for n in range(10))
    row = _one('struct Reporter {\n    static var rootOpen: String { "<checkstyle version=\\"4.3\\">" }\n'
               '    static func generateReport(_ items: [String]) -> String {\n' + lines
               + f'        var out = "{XML_DECL}\\n"\n        out += Self.rootOpen\n        out += items.joined()\n'
               '        out += "</checkstyle>"\n        return out\n    }\n}\n').get("generateReport")
    check("X8 a `Self.` read more than 256 characters into the body sits where it is read: ROOT checkstyle, GATED",
          row and row["cues"]["ROOT"] == "checkstyle" and gated(row))
    row = _one('enum Emitter {\n    static func make(_ items: [String]) -> String {\n        Self\n'
               + "".join(f"            // {'note ' * 12}\n" for _ in range(5))
               + f'            .header + items.joined() + "</svg>"\n    }}\n    static var header: String {{ "{SVG_OPEN}" }}\n}}\n'
               ).get("make")
    check("X8 a `Self` receiver more than 256 blank characters before its `.header`: OPEN-HOP, GATED",
          cue(row, "OPEN_HOP") and gated(row))
    member = f'    static let line = "{SVG_OPEN}"\n'
    for label, head_ in (("an untyped parameter with a result type", "line -> String in"),
                         ("a parenthesised one with a result type", "(line) -> String in"),
                         ("a capture list", "[weak self] line in"), ("an attribute", "@Sendable line in"),
                         ("a parameter whose type holds parentheses", "(line: (String, Int)) -> String in")):
        row = _one('enum Emitter {\n    static func make(_ items: [String]) -> String {\n'
                   f'        items.map {{ {head_} "<g/>" }}.joined() + line.count.description + "</svg>"\n    }}\n'
                   + member + '}\n').get("make")
        check(f"X9 a closure head with {label} shadows the name everywhere: no OPEN", row and not cue(row, "OPEN"))
    row = emitter('    static func header() -> String {\n        let d = "<?xml version=\\"1.0\\"?>"\n'
                  '        if d.hasSuffix("<foo xmlns=\\"x\\">") { return "" }\n        return d + "<root>"\n    }\n',
                  '        header() + items.joined() + "</root>"')
    check("X17 a search-key tag carrying xmlns among the opening hop's own later literals is not the root: ROOT root",
          row and row["cues"]["ROOT"] == "root" and gated(row))
    escaped = _wrap('        return #"\\#u{3C}?xml version="1.0"?>\\#u{3C}root>"# + items.joined() + #"\\#u{3C}/root>"#')
    row = {r["name"]: r for r in census({"/r/A.swift": escaped})}.get("make")
    check("X37 markers spelled with a raw string's `\\#u{…}` escapes pass the prefilter: a candidate, ROOT root, GATED",
          row and row["cues"]["ROOT"] == "root" and gated(row))
    return checks


def round_three_decisions():
    """§3's decision and judge-path controls added after the third review round. `[(label, passed)]`."""
    checks = []

    def check(label, condition):
        checks.append((label, bool(condition)))

    def refuses(call):
        try:
            call()
        except SystemExit:
            return True
        return False

    def decided(rows, verdicts, kills=KILLS):
        return decide({"candidates": rows}, verdicts, kills)

    five = [_row(f"r{i}", top=f"/r{i % 2}") for i in range(5)]
    verdicts = {row["id"]: _doc_verdict() for row in five}
    spread = [dict(_row("w1", group="wide", top="/w", gated2=True), repo="WideSVG"),
              dict(_row("e1", top="/e", gated2=True), repo="Deci", copy_repos=["Copied"]),
              dict(_row("n1", top="/n", gated2=True), repo="Checkstyle")]
    _, figures, _ = decided(spread, {"w1": _doc_verdict(law2="OWES"), "e1": _doc_verdict(law2="OWES", expressible=False),
                                     "n1": _doc_verdict(law2="NOT-SVG")})
    check("D27 Law 2's list names subjects, a copy's included, and leaves out a DOCUMENT row that is NOT-SVG",
          figures[2]["owing_anywhere"] == ["Copied", "Deci", "WideSVG"])
    hand = _kills(law1=0, law2=3, hand=[{"id": "H1", "law1": "ASSERTION", "law2": None, "suite": "ASSERTION",
                                         "reduced": None, "suite_failed": []}])
    _, _, lines = decided(five, verdicts, hand)
    check("D24 each law's hand line reads its own law: H1 found by law 1 and not by law 2",
          "law 1 hand mutants: H1 law ASSERTION, reduced SURVIVED, full ASSERTION" in lines
          and "law 2 hand mutants: H1 law SURVIVED, reduced SURVIVED, full ASSERTION" in lines)
    _, _, lines = decided(five, verdicts, {})
    check("D24 with no kill summary, the H line prints no count and no bar verdict",
          "SENSITIVITY law 1 decisive count with H1–H6 counted: —" in lines)
    wide = [_row(f"w{i}", group="wide", top=f"/w{i}", gated=False) for i in range(120)]
    judged = dict(verdicts)
    for i, row in enumerate(wide):
        row["judged"] = i < 60
        if i < 60:
            judged[row["id"]] = _doc_verdict(expressible=False) if i < 2 else {"verdict": "HTML"}
    _, figures, lines = decided(five + wide, judged)
    check("D21 two wide DOCUMENT rows not EXPRESSIBLE, 60 judged of 120: estimate 0.0 with EXPRESSIBLE, 4.0 without",
          figures[1]["N_wide_estimate"] == 0.0 and figures[1]["N_wide_estimate_without_expressible"] == 4.0
          and any(line.startswith("law 1 without EXPRESSIBLE:") and line.endswith("N_wide 2 (estimate 4.0)")
                  for line in lines))

    # The judge path (§4.2–§4.3).
    good = _calibration_records()
    check("D23 a calibration DOCUMENT record that leaves a flag unanswered is a miss",
          calibrate([dict(good[0], ambient=None)] + good[1:]) == ["calibration/1"])
    workflow = {"calibration": [{"records": good}, {"records": good}], "judged": [None]}
    check("D29 the judge files refuse a packet whose judging returned nothing", refuses(lambda: judge_files(workflow)))
    index = [{"label": "p/1", "id": "r0"}]
    kept = join(index, {"A": [dict(_doc_verdict(), label="p/1")], "B": [dict(_doc_verdict(), label="p/1")],
                        "C": [dict(_doc_verdict(dangle=True), label="p/1")]})
    check("D19 join: a record C gave for a row A and B agreed on decides nothing, but its flag is kept",
          kept["r0"]["decided_by"] == "A+B" and kept["r0"]["refs_dangle"])
    text = open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "fixtures", "xml-emitter-law",
                             "judge-workflow.js"), encoding="utf-8").read()

    def array(name):
        found = re.search(r"const " + name + r" = \[([^\]]*)\]", text)
        return set(re.findall(r"'([^']*)'", found.group(1))) if found else None

    block = re.search(r"const EXPECTED = (\{.*?\n\})", text, re.S)
    expected = None
    if block:
        literal = re.sub(r"(?<=[{,\s])(\w+):", r'"\1":', block.group(1).replace("'", '"'))
        expected = json.loads(re.sub(r",(\s*})", r"\1", literal))
    check("D16, D23 the judge workflow's verdicts, law2 values and expected answers are the script's",
          array("VERDICTS") == VERDICTS and array("LAW2") == LAW2 and expected == CALIBRATION)
    row = _one(_wrap(f'        return "{SVG_OPEN}" + items.joined() + "</svg>"'))["make"]
    rows = [dict(row, id=f"r:A.swift:{i}", judged=True, repo="r", root="/r", path="A.swift", group="decision",
                 toplevel="/r") for i in range(17)]
    with tempfile.TemporaryDirectory() as scratch:
        path = os.path.join(scratch, "census.json")
        json.dump({"candidates": rows}, open(path, "w", encoding="utf-8"))
        with contextlib.redirect_stdout(io.StringIO()):
            packets(path, os.path.join(scratch, "packets"))
        sizes = json.load(open(os.path.join(scratch, "sizes.json"), encoding="utf-8"))
    check("X40 packets write the workflow's sizes beside the index: 8, 8, 1", sizes == [8, 8, 1])
    return checks


def _row(identifier, group="decision", top="/r1", gated=True, gated2=False, path="a.swift", name=None,
         owner="T", hops=(), referenced_by=(), repo=None, cues=None):
    found = {"hops": list(hops), "ROOT": "svg" if gated2 else "x", "IDDEF": gated2, "STRING": True, "NOTHROW": True,
             "SYNC": True, "NONMUTATING": True, "PURE": True, "OPEN": True, "CLOSE": True, "CLOSE_HOP": False,
             "HTML": False}
    found.update(cues or {})
    return {"id": identifier, "group": group, "toplevel": top, "repo": repo or top, "root": top, "judged": True,
            "gated": gated, "gated2": gated2, "gated_without_pure": gated, "path": path, "name": name or identifier,
            "owner": owner, "copies": [], "copy_groups": [], "referenced_by": list(referenced_by), "cues": found}


def _doc_verdict(expressible=True, law2="NOT-SVG", body=False, dangle=False, ambient=False):
    return {"verdict": "DOCUMENT", "expressible": expressible, "law2": law2, "body_disagrees": body,
            "refs_dangle": dangle, "ambient": ambient}


def _calibration_records():
    """§4.2's expected answers as complete, usable records: each DOCUMENT row's unlisted flags answered."""
    answered = {"expressible": True, "ambient": False, "law2": "NOT-SVG", "body_disagrees": False, "refs_dangle": False}
    return [dict(answered, label=label, **expected) if expected["verdict"] == "DOCUMENT" else dict(label=label, **expected)
            for label, expected in CALIBRATION.items()]


def _kills(law1=2, law2=1, **summary):
    return {"summary": dict({"controls_passed": True, "complete": True, "law1": {"decisive": law1},
                             "law2": {"decisive": law2}}, **summary)}


KILLS = _kills()


def decision_controls():
    checks = []

    def check(label, condition):
        checks.append((label, bool(condition)))

    def refuses(call):
        try:
            call()
        except SystemExit:
            return True
        return False

    def decided(rows, verdicts, kills=KILLS):
        return decide({"candidates": rows}, verdicts, kills)

    def documents(rows, **kwargs):
        return {row["id"]: _doc_verdict(**kwargs) for row in rows}

    five = [_row(f"r{i}", top=f"/r{i % 2}") for i in range(5)]
    verdicts = documents(five)
    outcomes, figures, lines = decided(five, verdicts)
    check("D1 five owing groups over two repositories, kills: law 1 BUILD", outcomes[1] == "BUILD")
    check("D2 no OWES group anywhere: law 2 DECLINE (population), not a single subject",
          outcomes[2] == "DECLINE (population)")
    one = [_row(f"o{i}", top="/one", gated2=True) for i in range(6)]
    outcomes, _, _ = decided(one, documents(one, law2="OWES"))
    check("D2 six OWES groups in one repository: law 2 DECLINE (population: a single subject)",
          outcomes[2] == "DECLINE (population: a single subject)")
    four = five[:4]
    check("D3 four groups: law 1 DECLINE (population)", decided(four, documents(four))[0][1] == "DECLINE (population)")
    same = [_row(f"s{i}", top="/one") for i in range(6)]
    check("D4 six groups in one repository: law 1 DECLINE (population)",
          decided(same, documents(same))[0][1] == "DECLINE (population)")
    ungated = [dict(row, gated=(i < 4)) for i, row in enumerate(five)]
    check("D5 four gated groups: law 1 DECLINE (signal)", decided(ungated, verdicts)[0][1] == "DECLINE (signal)")
    noisy = five + [_row(f"n{i}", top="/r0") for i in range(3)]
    outcomes, figures, _ = decided(noisy, dict(verdicts, **{f"n{i}": {"verdict": "FRAGMENT"} for i in range(3)}))
    check("D6 gate precision 5/8: law 1 DECLINE (gate precision), the three listed",
          outcomes[1] == "DECLINE (gate precision)" and figures[1]["gated_not_owing"] == ["n0", "n1", "n2"])
    seven = [_row(f"p{i}", top=f"/p{i % 2}") for i in range(7)] + [_row(f"q{i}", top="/p0") for i in range(3)]
    outcomes, figures, _ = decided(seven, dict(documents(seven[:7]), **{f"q{i}": {"verdict": "HTML"} for i in range(3)}))
    check("D6 gate precision exactly 7/10: BUILD", outcomes[1] == "BUILD" and figures[1]["precision"] == 0.7)
    six = [_row(f"p{i}", top=f"/p{i % 2}") for i in range(6)] + [_row(f"q{i}", top="/p0") for i in range(3)]
    outcomes, _, _ = decided(six, dict(documents(six[:6]), **{f"q{i}": {"verdict": "HTML"} for i in range(3)}))
    check("D6 gate precision 6/9: DECLINE (gate precision)", outcomes[1] == "DECLINE (gate precision)")
    both = [dict(row, gated=(i < 4)) for i, row in enumerate(five)] + [_row(f"z{i}", top="/r0") for i in range(4)]
    outcomes, _, _ = decided(both, dict(verdicts, **{f"z{i}": {"verdict": "FRAGMENT"} for i in range(4)}))
    check("D6 failing both signal and precision reads DECLINE (signal), the first that applies",
          outcomes[1] == "DECLINE (signal)")
    for label, kills in (("no summary", {}),
                         ("controls failed", _kills(controls_passed=False)),
                         ("incomplete", _kills(complete=False)),
                         ("a decisive count of None", _kills(law1=None))):
        check(f"D7 {label}: law 1 UNMEASURED (kills)", decided(five, verdicts, kills)[0][1] == "UNMEASURED (kills)")
    check("D8 decisive 0: law 1 DECLINE (kills)", decided(five, verdicts, _kills(law1=0))[0][1] == "DECLINE (kills)")
    check("D8 N = 4 with decisive 0: DECLINE (population), which comes first",
          decided(four, documents(four), _kills(law1=0))[0][1] == "DECLINE (population)")
    svg = [_row(f"g{i}", top=f"/g{i % 2}", gated2=True) for i in range(5)]
    check("D9 five OWES groups over two repositories: law 2 BUILD",
          decided(svg, documents(svg, law2="OWES"))[0][2] == "BUILD")
    two = [_row(f"t{i}", top=f"/t{i}", gated2=True) for i in range(2)]
    check("D10 two OWES groups over two repositories: law 2 DECLINE (population)",
          decided(two, documents(two, law2="OWES"))[0][2] == "DECLINE (population)")
    unexpressible = five + [_row("x9", top="/r1")]
    outcomes, figures, _ = decided(four + [_row("x9", top="/r1")],
                                   dict(documents(four), x9=_doc_verdict(expressible=False)))
    check("D11 a DOCUMENT row that is not EXPRESSIBLE is outside N, inside N without EXPRESSIBLE",
          figures[1]["N"] == 4 and outcomes[1] == "DECLINE (population)" and figures[1]["N_without_expressible"] == 5)
    outcomes, figures, _ = decided(unexpressible + [_row(f"y{i}", top="/r0") for i in range(3)],
                                   dict(documents(unexpressible),
                                        **{f"y{i}": _doc_verdict(expressible=False) for i in range(3)}))
    check("D11 gated DOCUMENT rows that are not EXPRESSIBLE count as owing in gate precision",
          figures[1]["precision"] == 1.0)
    wide_fragments = five + [_row(f"w{i}", group="wide", top="/w") for i in range(3)]
    outcomes, figures, _ = decided(wide_fragments, dict(verdicts, **{f"w{i}": {"verdict": "FRAGMENT"} for i in range(3)}))
    check("D11 gated wide FRAGMENT rows do not enter gate precision", figures[1]["precision"] == 1.0
          and outcomes[1] == "BUILD")
    mixed = [_row("m1", top="/m", owner="R", name="render", hops=("renderFromLayout",), gated=False),
             _row("m2", top="/m", owner="R", name="renderFromLayout", referenced_by=("render",))]
    mixed += [_row(f"k{i}", top=f"/k{i % 2}") for i in range(4)]
    check("D11 a merged group with one gated member counts as gated: BUILD",
          decided(mixed, documents(mixed))[0][1] == "BUILD")
    linked = [_row("m1", top="/m", owner="R", name="render", hops=("renderFromLayout",)),
              _row("m2", top="/m", owner="R", name="renderFromLayout", path="b.swift", referenced_by=("render",)),
              _row("m3", top="/m", owner="Q", name="render")]
    check("D12 a same-type reference across files merges; another type does not",
          sorted(len(g) for g in owing_groups(linked, documents(linked), 1)) == [1, 2])
    split = [_row("a1", top="/x", owner="R", name="render", hops=("renderFromLayout",)),
             _row("a2", top="/y", owner="R", name="renderFromLayout", referenced_by=("render",))]
    check("D12 the same owner and names in two repositories: two groups", len(owing_groups(split, documents(split), 1)) == 2)
    files = [_row("f1", top="/z", owner="", name="make", hops=("header",), path="a.swift"),
             _row("f2", top="/z", owner="", name="header", referenced_by=("make",), path="b.swift")]
    check("D12 top-level units in two files: two groups", len(owing_groups(files, documents(files), 1)) == 2)
    overloads = [_row("v1", top="/v", owner="R", name="render"), _row("v2", top="/v", owner="R", name="render",
                                                                       referenced_by=("render",))]
    check("D12 two same-name overloads linked only by referenced_by: one group",
          len(owing_groups(overloads, documents(overloads), 1)) == 1)
    check("D13 the merge is by reference, not by owner alone",
          len(owing_groups([_row("x1", top="/x", owner="R", name="a"), _row("x2", top="/x", owner="R", name="b")],
                           {"x1": _doc_verdict(), "x2": _doc_verdict()}, 1)) == 2)
    check("D14 a dropped judgement is refused", refuses(lambda: decided(five, {})))
    check("D15 an extra judgement is refused", refuses(lambda: decided(five, dict(verdicts, other=_doc_verdict()))))
    for label, record in (("law2", {k: v for k, v in _doc_verdict().items() if k != "law2"}),
                          ("expressible", {k: v for k, v in _doc_verdict().items() if k != "expressible"}),
                          ("ambient", {k: v for k, v in _doc_verdict().items() if k != "ambient"}),
                          ("body_disagrees", {k: v for k, v in _doc_verdict().items() if k != "body_disagrees"}),
                          ("refs_dangle", {k: v for k, v in _doc_verdict().items() if k != "refs_dangle"}),
                          ("an unknown verdict", {"verdict": "MAYBE"}),
                          ("an unknown law2", _doc_verdict(law2="OWE"))):
        _, figures, _ = decided(five, dict(verdicts, r0=record))
        check(f"D16 a record lacking {label} is UNDETERMINED", figures[1]["N_undetermined"] == 1 and figures[1]["N"] == 4)
    index = [{"label": "p/1", "id": "r0"}, {"label": "p/2", "id": "r1"}]

    def labelled(label, record):
        return dict(record, label=label)

    agreed = join(index, {"A": [labelled("p/1", _doc_verdict(body=True)), labelled("p/2", {"verdict": "FRAGMENT"})],
                          "B": [labelled("p/1", _doc_verdict(dangle=True, ambient=True)),
                                labelled("p/2", {"verdict": "FRAGMENT"})]})
    check("D17 join: agreement unions body disagrees, refs dangle and ambient",
          agreed["r0"]["body_disagrees"] and agreed["r0"]["refs_dangle"] and agreed["r0"]["ambient"]
          and agreed["r1"]["verdict"] == "FRAGMENT")
    mirrored = join(index[:1], {"A": [labelled("p/1", _doc_verdict())], "B": [labelled("p/1", _doc_verdict(body=True))]})
    check("D17 join: B's flag alone is kept", mirrored["r0"]["body_disagrees"])
    for label, a, b in (("law2", _doc_verdict(law2="OWES"), _doc_verdict(law2="VACUOUS")),
                        ("EXPRESSIBLE", _doc_verdict(expressible=True), _doc_verdict(expressible=False)),
                        ("the verdict", {"verdict": "FRAGMENT"}, _doc_verdict())):
        check(f"D18 join: a disagreement on {label} without C is refused",
              refuses(lambda a=a, b=b: join(index[:1], {"A": [labelled("p/1", a)], "B": [labelled("p/1", b)]})))
    third = join(index[:1], {"A": [labelled("p/1", _doc_verdict(law2="OWES", body=True))],
                             "B": [labelled("p/1", _doc_verdict(law2="VACUOUS"))],
                             "C": [labelled("p/1", _doc_verdict(law2="VACUOUS"))]})
    check("D19 join: C decides a disagreement, and A's flag on a DOCUMENT record is kept",
          third["r0"]["law2"] == "VACUOUS" and third["r0"]["decided_by"] == "C" and third["r0"]["body_disagrees"])
    incomplete = {"verdict": "DOCUMENT", "expressible": True}
    settled = join(index[:1], {"A": [labelled("p/1", incomplete)], "B": [labelled("p/1", incomplete)],
                               "C": [labelled("p/1", {"verdict": "FRAGMENT"})]})
    check("D19 join: two incomplete agreeing records go to C", settled["r0"]["decided_by"] == "C"
          and settled["r0"]["verdict"] == "FRAGMENT")
    check("D20 join: an unknown label is refused",
          refuses(lambda: join(index[:1], {"A": [labelled("p/1", {"verdict": "HTML"}), labelled("p/9", {"verdict": "HTML"})],
                                           "B": [labelled("p/1", {"verdict": "HTML"})]})))
    check("D20 join: a missing A record is refused even when C judged the row",
          refuses(lambda: join(index[:1], {"B": [labelled("p/1", {"verdict": "HTML"})],
                                           "C": [labelled("p/1", {"verdict": "HTML"})]})))
    check("D20 join: a judge that repeats a label is refused, never last-wins",
          refuses(lambda: join(index[:1], {"A": [labelled("p/1", {"verdict": "FRAGMENT"}), labelled("p/1", _doc_verdict())],
                                           "B": [labelled("p/1", _doc_verdict())]})))
    check("D20 join: an index that repeats a label is refused",
          refuses(lambda: join(index[:1] * 2, {"A": [labelled("p/1", {"verdict": "HTML"})],
                                               "B": [labelled("p/1", {"verdict": "HTML"})]})))
    partly = five + [_row(f"w{i}", group="wide", top=f"/w{i}", gated=False) for i in range(120)]
    partly_verdicts = dict(verdicts)
    for i, row in enumerate(partly[5:]):
        row["judged"] = i < 60
        if i < 60:
            partly_verdicts[row["id"]] = _doc_verdict() if i < 3 else {"verdict": "HTML"}
    partly_verdicts["w3"] = {"verdict": "UNDETERMINED"}
    _, figures, _ = decided(partly, partly_verdicts)
    check("D21 N_wide over 60 judged of 120: 3 owing, estimate 6.0; an UNDETERMINED wide row is not in N_undetermined",
          figures[1]["N"] == 5 and figures[1]["N_wide"] == 3 and figures[1]["N_wide_estimate"] == 6.0
          and figures[1]["N_undetermined"] == 0)
    copied = dict(five[0], copies=["x", "y", "z"], copy_groups=["decision", "wide", "unmet"])
    _, figures, _ = decided([copied] + five[1:], verdicts)
    check("D21 unmerged counts decision copies only", figures[1]["unmerged"] == 6)
    unmet = five + [_row("u1", group="unmet", top="/u")]
    _, figures, _ = decided(unmet, dict(verdicts, u1=_doc_verdict(expressible=False)))
    check("D21 N_unmet needs EXPRESSIBLE", figures[1]["N_unmet"] == 0 and figures[1]["outside_without_expressible"]["unmet"] == 1)
    rows = ([_row(f"d{i}", top="/r0") for i in range(3)] + [_row("u1", group="unmet", top="/u")]
            + [_row("l1", group="layout", top="/l")]
            + [_row("w1", group="wide", top="/w")] + [_row("e1", top="/e")] + [_row("n1", top="/n")]
            + [_row(f"s{i}", top="/r0", repo=NAMED) for i in range(2)])
    sensitivity_verdicts = dict(documents(rows), e1={"verdict": "UNDETERMINED"}, n1=_doc_verdict(expressible=False))
    _, figures, lines = decided(rows, sensitivity_verdicts)
    found = figures[1]["sensitivity"]
    check("D22 each sensitivity sum: unmet, layout and wide added, UNDETERMINED a group of its own, without EXPRESSIBLE,"
          " and without the named subject",
          figures[1]["N"] == 5 and found["N + N_unmet + N_layout + N_wide"] == (8, 4)
          and found["N + N_undetermined"] == (6, 2)
          and found["N without EXPRESSIBLE"] == (6, 2) and found[f"N without {NAMED}"] == (3, 1))
    check("D22 the decision lines name each law first, and the clears word follows the bar",
          lines[0].startswith("LAW 1 DECISION:") and any(l.startswith("LAW 2 DECISION:") for l in lines)
          and any("N + N_unmet + N_layout + N_wide: 8 over 4 repositories — clears" in l for l in lines)
          and any("N + N_undetermined: 6 over 2 repositories — clears" in l for l in lines)
          and any(f"N without {NAMED}: 3 over 1 repositories — does not clear" in l for l in lines))
    ambient = five + [_row("a1", top="/r1")]
    _, figures, lines = decided(ambient, dict(documents(five, ambient=True), a1=_doc_verdict()))
    check("D22 N_gated without rows judged ambient: 1 over 1, which does not clear the signal bar",
          figures[1]["N_gated_unambient"] == (1, 1)
          and any("without rows judged ambient: 1 over 1 repositories — does not clear" in l for l in lines))
    good = _calibration_records()
    check("D23 calibration: the expected answers pass, one miss is named, a repeated label is a miss",
          calibrate(good) == [] and calibrate([dict(good[0], verdict="FRAGMENT")] + good[1:]) == ["calibration/1"]
          and calibrate(good + [good[0]]) == ["calibration/1"])
    exact = {"candidates": [dict(_row(f"d{i:03d}"), judged=False) for i in range(300)]}
    choose(exact)
    many = {"candidates": [dict(_row(f"d{i:03d}"), judged=False) for i in range(301)]}
    check("D25 exactly 300 non-wide candidates are all judged; 301 stop the pass",
          all(row["judged"] for row in exact["candidates"]) and refuses(lambda: choose(many)))
    wide = [dict(_row(f"w{i:02d}", group="wide"), judged=False) for i in range(75)] + [_row("u1", group="unmet")]
    first, second = {"candidates": [dict(r) for r in wide]}, {"candidates": [dict(r) for r in reversed(wide)]}
    choose(first)
    choose(second)
    picked = sorted(r["id"] for r in first["candidates"] if r["judged"] and r["group"] == "wide")
    check("D26 75 wide candidates: the seed's 60, the same set in either order; the unmet row judged",
          hashlib.sha256(",".join(picked).encode()).hexdigest()[:16] == "048c987a23e61ba2"
          and "u1" in {r["id"] for r in first["candidates"] if r["judged"]}
          and picked == sorted(r["id"] for r in second["candidates"] if r["judged"] and r["group"] == "wide"))
    r2 = [_row("h1", top="/h", gated=False, gated2=False, cues={"CLOSE": False, "CLOSE_HOP": True})]
    _, figures, lines = decided(r2, documents(r2, law2="OWES"))
    check("D27 R2 names CLOSE-HOP, and for law 2 ROOT≠svg and ¬IDDEF; every owing SVG repository is listed",
          figures[1]["ungated_owing"][0]["missed"] == ["CLOSE", "CLOSE-HOP"]
          and figures[2]["ungated_owing"][0]["missed"] == ["CLOSE", "CLOSE-HOP", "ROOT≠svg", "¬IDDEF"]
          and any(l.endswith("in any group: /h") for l in lines))
    return checks


def self_test():
    checks = (control_rows() + more_controls() + round_two_controls() + round_three_controls() + decision_controls()
              + round_two_decisions() + round_three_decisions())
    failed = [label for label, passed in checks if not passed]
    for label in failed:
        print(f"  FAIL {label}")
    print(f"xml emitter census controls: {len(checks) - len(failed)}/{len(checks)} pass")
    return not failed


def main(argv):
    if argv[1:] == ["--self-test"]:
        return 0 if self_test() else 1
    if argv[1:] == ["universe"]:
        for group, name, root, _ in groups():
            print(f"{group:<9} {name:<40} {revision(root) or '-'}  {root}")
        return 0
    if len(argv) == 3 and argv[1] == "run":
        run(argv[2])
        return 0
    if len(argv) == 4 and argv[1] == "packets":
        packets(argv[2], argv[3])
        return 0
    if len(argv) in (5, 6) and argv[1] == "render":
        render_one(argv[2], argv[3], argv[4], *(argv[5:] or ["calibration/N"]))
        return 0
    if len(argv) == 3 and argv[1] == "calibrate":
        misses = calibrate(json.load(open(argv[2], encoding="utf-8")))
        print("calibration:", "pass" if not misses else f"misses {misses}")
        return 0 if not misses else 1
    if len(argv) == 4 and argv[1] == "verdicts":
        os.makedirs(argv[3], exist_ok=True)
        for judge, records in judge_files(json.load(open(argv[2], encoding="utf-8"))).items():
            json.dump(records, open(os.path.join(argv[3], f"{judge}.json"), "w", encoding="utf-8"), indent=1)
        return 0
    if len(argv) == 5 and argv[1] == "join":
        index = json.load(open(argv[2], encoding="utf-8"))
        verdicts = {judge: json.load(open(os.path.join(argv[3], f"{judge}.json"), encoding="utf-8"))
                    for judge in ("A", "B", "C") if os.path.exists(os.path.join(argv[3], f"{judge}.json"))}
        json.dump(join(index, verdicts), open(argv[4], "w", encoding="utf-8"), indent=1, sort_keys=True)
        return 0
    if len(argv) == 3 and argv[1] == "search":
        search(argv[2])
        return 0
    if len(argv) == 5 and argv[1] == "decide":
        report = json.load(open(argv[2], encoding="utf-8"))
        judgements = json.load(open(argv[3], encoding="utf-8"))
        kills = json.load(open(argv[4], encoding="utf-8")) if os.path.exists(argv[4]) else {}
        _, _, lines = decide(report, judgements, kills)
        print("\n".join(lines))
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
