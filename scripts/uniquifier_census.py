#!/usr/bin/env python3
"""Which functions hand out names they promise never to repeat? — `docs/plans/uniquifier-law-census-scope.md`.

#669's law: take a fresh receiver (or fresh `inout` state) and drawn inputs `x1 … xn`; the results
`r.f(x1) … r.f(xn)` are pairwise distinct, apart from the guard's sentinel. A memoizing uniquifier owes
*equal keys give equal results, and distinct keys distinct ones*. This pass finds the functions that might owe
either, by cues read off the body (§1.2), and hands each candidate to a blind hand-check (§4). It never decides
that a function IS a uniquifier; the judges do.

Section numbers below are the scope's.

  --self-test                  the scope's pass and decision controls (no siblings; joins `make measurement-selftest`)
  run <out.json>               census the frozen universe (§2), and choose what §4 judges
  packets <census.json> <dir>  write §4's blind judging packets, at most eight rows each, in seeded order
  render <path> <name> <repo>  one function in a packet's format, for the calibration file (§4.2)
  calibrate <judge.json>       §4.2: one judge's calibration records against the expected answers
  join <index.json> <verdicts-dir> <judgements.json>       §4.3: the judges' records joined to row ids
  decide <census.json> <judgements.json> <kill-arm.json>   §8's outcome, figures and sensitivity lines
"""
import collections
import json
import os
import random
import re
import signal
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from budgeted_truncation_census import DECL, base_name, revision, split_top, words  # noqa: E402
from layering_census import (  # noqa: E402
    corpus_universe, declarations, git, subject_files, toplevel, universe,
)
from mutation_check import mask  # noqa: E402
from regex_acceptor_census import mask_code  # noqa: E402

SEED = 20261028
PACKET_SIZE = 8
# §4.1: what is judged. Decision, unmet and layout candidates in full up to the cap; wide up to its own.
JUDGED_CAP, WIDE_CAP = 300, 60
GROUP_ORDER = {"decision": 0, "unmet": 1, "layout": 2, "wide": 3}
# §2: a directory component skipped on top of #667's rule, ignoring case: test data, not product code.
SKIP_FIXTURES = "fixtures"
# §6's R3: #669's grep sites, looked up by name whether or not they are candidates.
R3_NAMES = {"makeUniqueName", "uniqueCaseName", "resolvedNames", "unique"}
MEMBERS_CAP = 200

# ── Cues (§1.2) ───────────────────────────────────────────────────────────────────────────────────
NAME_PREFIXES = ("uniq", "fresh", "disambig")
CHAIN = r"([A-Za-z_][\w.?!]*)"
SUBSCRIPT = r"\[([^\[\]\n]*)\]"
# TEST: something tested against a collection. Group 1 is the tested collection's chain; the argument is read
# from the bracket or parenthesis that follows (`_argument`).
TESTS = (
    ("contains", re.compile(CHAIN + r"\s*\.\s*contains\s*\(")),
    ("nil-compare", re.compile(CHAIN + r"\s*" + SUBSCRIPT + r"\s*(?:!=|==)\s*nil\b")),
    ("default-subscript", re.compile(CHAIN + r"\s*\[[^\[\]\n]*,\s*default\s*:")),
    ("coalesce", re.compile(CHAIN + r"\s*" + SUBSCRIPT + r"\s*\?\?")),
    ("binding", re.compile(r"(?:\b(?:if|guard|while)|,)\s*(?:let|var)\s+[A-Za-z_]\w*\s*=\s*" + CHAIN + r"\s*\[")),
    ("index-for-key", re.compile(CHAIN + r"\s*\.\s*index\s*\(\s*forKey\s*:")),
    ("inserted", re.compile(CHAIN + r"\s*\.\s*insert\s*\([^\n]*?\)\s*\.\s*inserted\b")),
)
COUNTER_CHAIN = r"((?:self\s*\.\s*)?[A-Za-z_]\w*(?:\s*\.\s*[A-Za-z_]\w*)*)"
INCREMENT = re.compile(COUNTER_CHAIN + r"\s*(?:\+=|&\+=)\s*1(?![\w.])(?![ \t]*[*/%])")
SELF_INCREMENT = re.compile(COUNTER_CHAIN + r"\s*=\s*(?:self\s*\.\s*)?\1\s*(?:\+|&\+)\s*1(?![\w.])")
# A counter bound from a subscript: `let i = t[k, default: 0]`, `let k = t[b] ?? 0`, `let n = (t[b] ?? 0) + 1`.
BOUND = re.compile(r"\b(?:let|var)\s+([A-Za-z_]\w*)\s*=\s*(\()?\s*" + CHAIN
                   + r"\s*\[[^\[\]\n]*(?:,\s*default\s*:\s*\d+\s*\]|\]\s*\?\?\s*\d+)"
                   + r"\s*(?(2)\))\s*(?:[+-]\s*\d+)?\s*(?=$|[;}])", re.M)
# A local copied from a counter (`let id = next`), and from a subscript (`let n = t[k]!`, `if let n = t[k]`).
ALIAS = re.compile(r"\b(?:let|var)\s+([A-Za-z_]\w*)\s*=\s*" + COUNTER_CHAIN + r"\s*(?=$|[;}])", re.M)
TABLE_READ = re.compile(r"\b(?:let|var)\s+([A-Za-z_]\w*)\s*=\s*" + CHAIN + r"\s*\[[^\[\]\n]*\]\s*!?\s*"
                        r"(?=$|[;}{,]|else\b)", re.M)
RANGE_LOOP = re.compile(r"\bfor\s+([A-Za-z_]\w*)\s+in\s+[^{\n]*(?:\.\.\.|\.\.<)")
# A counter table: a subscript incremented in place (`t[k, default: 0] += 1`, `t[k] = (t[k] ?? 0) + 1`).
TABLE_INCREMENT = re.compile(CHAIN + r"\s*\[[^\[\]\n]*\]\s*(?:\+=|&\+=)\s*1(?![\w.])")
TABLE_ASSIGN = re.compile(CHAIN + r"\s*\[[^\[\]\n]*\]\s*=\s*\(?\s*\1\s*\[[^\n]*\+\s*1(?![\w.])")
STRINGIFIED = re.compile(r"\bString\s*\(\s*(?:describing\s*:\s*)?" + COUNTER_CHAIN + r"\s*\)"
                         r"|" + COUNTER_CHAIN + r"\s*\.\s*description\b")
WRITE_CALLS = ("append", "insert", "formUnion", "updateValue", "merge", "add", "unionInPlace")
COLLECTIONS = {"Array", "Set", "Dictionary", "OrderedSet", "OrderedDictionary", "ContiguousArray"}
CLASS_LIKE = {"class", "actor"}


def _norm(chain):
    """`self.taken?` → `taken`; whitespace and optional marks removed."""
    return re.sub(r"^self\.", "", re.sub(r"[\s?!]", "", chain).strip("."))


def _base(chain):
    return _norm(chain).split(".")[0] if chain else ""


def _type_kinds(files):
    """`{type name: {kind, …}}` over `{path: text}`: how §1.2's STATE resolves an extension's owner."""
    kinds = collections.defaultdict(set)
    for text in files.values():
        for kind, name, _ in declarations(text)[0]:
            kinds[name].add(kind)
    return kinds


def _close(code, index):
    """The index of the bracket closing the one at `index` in a code view, or len(code)."""
    pairs = {"(": ")", "[": "]", "{": "}"}
    opener, closer, depth = code[index], pairs[code[index]], 0
    for cursor in range(index, len(code)):
        if code[cursor] == opener:
            depth += 1
        elif code[cursor] == closer:
            depth -= 1
            if depth == 0:
                return cursor
    return len(code)


def split_function(text):
    """`(modifiers, body_code, body_raw)` of one function's text from its line start through its closing brace.
    `body_code` is `mask_code`'s view: comments and literal text blanked, interpolation code kept."""
    code = mask_code(text)
    found = re.search(r"\bfunc\b", code)
    if not found:
        return "", "", ""
    paren = code.find("(", found.end())
    index = _close(code, paren) if paren >= 0 else -1
    brace = code.find("{", index) if index >= 0 else -1
    end = code.rfind("}")
    if paren < 0 or brace < 0 or end <= brace:
        return code[:found.start()], "", ""
    return code[:found.start()], code[brace + 1:end], text[brace + 1:end]


def interpolations(code, raw):
    """`[(position, code)]` for every interpolation in `raw`, found where `mask_code` kept a `(` whose `\\` it
    blanked."""
    found = []
    for index, character in enumerate(raw):
        if character != "\\":
            continue
        opener = index + 1
        while opener < len(raw) and raw[opener] == "#":
            opener += 1
        if opener >= len(code) or code[opener] != "(" or code[index] != " ":
            continue
        found.append((index, " ".join(code[opener + 1:_close(code, opener)].split())))
    return found


def _argument(code, end):
    """`(start, end)` of the bracket or call a TEST match ends in or just before: `contains(x)` → where `x` is."""
    index = end - 1 if end > 0 and code[end - 1] in "([" else end
    while index < len(code) and code[index] in " \t":
        index += 1
    if index < len(code) and code[index] in "([":
        return index + 1, _close(code, index)
    return end, end


def tests(code):
    """`[{kind, chain, argument, span, start}]` for every membership test in a body's code view. `start` is where
    the tested chain starts, so a binding's test sits inside its `if` or `guard` condition."""
    found = []
    for kind, pattern in TESTS:
        for match in pattern.finditer(code):
            if kind in ("nil-compare", "coalesce"):
                span = (match.start(2), match.end(2))
            elif kind in ("contains", "index-for-key", "inserted"):
                span = _argument(code, code.find("(", match.end(1)) + 1)
            else:
                span = _argument(code, code.find("[", match.end(1)) + 1)
            found.append({"kind": kind, "chain": _norm(match.group(1)), "span": span,
                          "argument": " ".join(code[span[0]:span[1]].split()), "start": match.start(1)})
    return found


def _opener(code, close):
    """The index of the `{` matching the `}` at `close`, or -1."""
    depth = 0
    for cursor in range(close, -1, -1):
        if code[cursor] == "}":
            depth += 1
        elif code[cursor] == "{":
            depth -= 1
            if depth == 0:
                return cursor
    return -1


def regions(code, found_tests):
    """`[(start, end, kind)]`: the spans a TEST decides. The body of an `if` or `while` whose condition holds a
    TEST, and the `else` block straight after such an `if`; the `else` block of such a `guard`; the body of a
    `repeat` whose trailing `while` holds one; and a ternary's branches after a TEST on the same line. `#if` is
    not an `if`."""
    starts = [test["start"] for test in found_tests]
    spans = []
    for match in re.finditer(r"(?<!#)\b(if|while|guard)\b", code):
        keyword = match.group(1)
        before = code[:match.start()].rstrip()
        if keyword == "while" and before.endswith("}"):
            opener = _opener(code, len(before) - 1)
            if opener >= 0 and re.search(r"\brepeat\s*$", code[:opener]):
                stop = code.find("\n", match.end())
                stop = len(code) if stop < 0 else stop
                if any(match.end() <= start < stop for start in starts):
                    spans.append((opener, len(before) - 1, "repeat"))
                continue
        cursor, depth = match.end(), 0
        while cursor < len(code):
            if code[cursor] in "([":
                depth += 1
            elif code[cursor] in ")]":
                depth -= 1
            elif code[cursor] == "{" and depth == 0:
                break
            cursor += 1
        if cursor >= len(code) or not any(match.end() <= start < cursor for start in starts):
            continue
        close = _close(code, cursor)
        spans.append((cursor, close, keyword))
        after = re.match(r"\s*else\s*\{", code[close + 1:])
        if keyword == "if" and after:
            opener = close + 1 + after.end() - 1
            spans.append((opener, _close(code, opener), "else"))
    for test in found_tests:
        line_end = code.find("\n", test["start"])
        line_end = len(code) if line_end < 0 else line_end
        question = re.search(r"\s\?\s", code[test["start"]:line_end])
        if question:
            spans.append((test["start"] + question.start(), line_end, "ternary"))
    return spans


def counters(code, params, local):
    """`(counters, sources, stored_increments, tables, aliases)`.

    - counters: identifiers or chains that count — incremented, bound from a subscript, a range loop's variable,
      or a local copied from one of those;
    - sources: for a counter read from a subscript, the base of the collection it was read from;
    - stored_increments: the incremented chains whose base is stored (§1.2);
    - tables: bases of subscripts incremented in place;
    - aliases: a local copied from an incremented chain (`let id = next`), and that chain."""
    incremented = {_norm(match.group(1)) for pattern in (INCREMENT, SELF_INCREMENT) for match in pattern.finditer(code)}
    sources = {match.group(1): _base(match.group(3)) for match in BOUND.finditer(code)}
    loops = {match.group(1) for match in RANGE_LOOP.finditer(code)}
    tables = {_base(match.group(1)) for pattern in (TABLE_INCREMENT, TABLE_ASSIGN) for match in pattern.finditer(code)}
    aliases = {match.group(1): _norm(match.group(2)) for match in ALIAS.finditer(code)
               if _norm(match.group(2)) in incremented}
    for match in TABLE_READ.finditer(code):
        name, table = match.group(1), _base(match.group(2))
        written_back = re.search(rf"(?<![\w.]){re.escape(table)}\s*\[[^\n]*\]\s*=\s*{re.escape(name)}\s*[+-]\s*\d",
                                 code)
        if table in tables or written_back:
            sources[name] = table
    stored = {chain for chain in incremented if _stored(chain.split(".")[0], params, local)}
    return incremented | set(sources) | loops | set(aliases), sources, stored, tables, aliases


def _stored(name, params, local):
    """Stored state (§1.2): not declared in the body, and not a parameter unless an `inout` collection."""
    names, inout = params
    return name not in local and (name not in names or name in inout)


def decorations(code, raw, counted, tables):
    """`[(position, counter)]`: where the body decorates with a counter. An interpolated counter (`\\(index)`,
    `\\(n + 1)`, `\\(names.count)`), a counter table's entry (`\\(counts[b]!)`), or `String(n)` / `n.description`."""
    found = []
    for position, expression in interpolations(code, raw):
        expression = _norm(re.sub(r"\s*[+-]\s*\d+$", "", expression)) if "[" not in expression else expression
        table = re.match(r"^(?:self\s*\.\s*)?([A-Za-z_][\w.]*)\s*\[", expression)
        if expression in counted:
            found.append((position, expression))
        elif re.match(r"^[A-Za-z_][\w.]*\.count$", expression):
            found.append((position, expression))
        elif table and _base(table.group(1)) in tables:
            found.append((position, f"{_base(table.group(1))}[]"))
    for match in STRINGIFIED.finditer(code):
        name = _norm(match.group(1) or match.group(2))
        if name in counted:
            found.append((match.start(), name))
    return sorted(found)


CONTINUES_AFTER = ("+", "(", ",", "=", "[", "?", ":")
CONTINUES_BEFORE = (".", "+", ")", "]", "?", ":")


def _statement(code, position):
    """`(start, text)` of the statement around `position`: its lines, joined over lines that continue an
    expression (one ending in a binary operator, `(`, `,`, `=`, `[`, `?` or `:`, or the next starting with `.`,
    `+`, `)`, `]`, `?` or `:`), then narrowed to the `;`- or brace-separated part that holds `position`."""
    start = code.rfind("\n", 0, position) + 1
    end = code.find("\n", position)
    end = len(code) if end < 0 else end
    while start > 0:
        previous = code.rfind("\n", 0, start - 1) + 1
        if (code[previous:start - 1].rstrip().endswith(CONTINUES_AFTER)
                or code[start:end].lstrip().startswith(CONTINUES_BEFORE)):
            start = previous
        else:
            break
    while end < len(code):
        following = code.find("\n", end + 1)
        following = len(code) if following < 0 else following
        if (code[start:end].rstrip().endswith(CONTINUES_AFTER)
                or code[end + 1:following].lstrip().startswith(CONTINUES_BEFORE)):
            end = following
        else:
            break
    left, depth = start, 0
    for cursor in range(position - 1, start - 1, -1):
        character = code[cursor]
        if character in ")]}":
            depth += 1
        elif character in "([{":
            if depth == 0 and character == "{":
                left = cursor + 1
                break
            depth = max(depth - 1, 0)
        elif character == ";" and depth == 0:
            left = cursor + 1
            break
    right, depth = end, 0
    for cursor in range(position, end):
        character = code[cursor]
        if character in "([{":
            depth += 1
        elif character in ")]}":
            if depth == 0 and character == "}":
                right = cursor
                break
            depth = max(depth - 1, 0)
        elif character == ";" and depth == 0:
            right = cursor
            break
    return left, code[left:right]


def _assigned(code, position):
    """The variable the statement at `position` assigns or declares, or None: `let name = …`, `name += …`."""
    match = re.match(r"\s*(?:(?:let|var)\s+)?(?:self\s*\.\s*)?([A-Za-z_]\w*)\s*(?::[^=]*)?(?:=(?!=)|\+=)",
                     _statement(code, position)[1])
    return match.group(1) if match else None


def _returns(code, position):
    """Whether the statement at `position` is a `return`."""
    return bool(re.match(r"\s*return\b", _statement(code, position)[1]))


def reaches_return(code, position):
    """Whether the decoration at `position` is returned: its statement returns, or it builds a variable a `return`
    names."""
    if _returns(code, position):
        return True
    variable = _assigned(code, position)
    return bool(variable and re.search(rf"\breturn\b[^\n;]*(?<![\w.]){re.escape(variable)}(?!\w)", code))


def _write_arguments(code, tested_bases):
    """`[(start, end)]`: the argument of every write call on a tested base, and the right-hand side of every
    subscript or whole assignment to one."""
    calls = "|".join(WRITE_CALLS)
    spans = []
    for base in tested_bases:
        name = rf"(?<![\w.])(?:self\s*\.\s*)?{re.escape(base)}(?:\s*\.\s*[A-Za-z_]\w*)*"
        for match in re.finditer(name + rf"\s*\.\s*(?:{calls})\s*\(", code):
            spans.append((match.end(), _close(code, match.end() - 1)))
        for match in re.finditer(name + r"\s*(?:\[[^\n]*?\])?\s*(?:=(?!=)|\+=)", code):
            line_end = code.find("\n", match.end())
            spans.append((match.end(), len(code) if line_end < 0 else line_end))
    return spans


def tied(code, decoration, found_tests, spans, sources, tested_bases):
    """§1.2: a decoration is TIED to a test when its counter was read from a tested collection (a per-key counter);
    when it sits inside a test's argument, or inside what is written to a tested collection; when the variable
    its statement assigns is a test's argument or is written to a tested collection; or when it sits in a span a
    test decides and builds what is returned there."""
    position, counter = decoration
    if sources.get(counter) in tested_bases or (counter.endswith("[]") and counter[:-2] in tested_bases):
        return True
    writes = _write_arguments(code, tested_bases)
    if any(start <= position < end for start, end in [test["span"] for test in found_tests] + writes):
        return True
    variable = _assigned(code, position)
    if variable:
        word = re.compile(rf"(?<![\w.]){re.escape(variable)}(?!\w)")
        if any(word.search(test["argument"]) for test in found_tests):
            return True
        if any(word.search(code[start:end]) for start, end in writes):
            return True
    return any(start <= position <= end for start, end, _ in spans) and reaches_return(code, position)


def retests(code, found_tests):
    """RETEST: a `while` (or a `repeat`'s trailing `while`) whose condition tests an argument the loop body
    reassigns: any identifier in the argument, assigned, `+=`'d or appended to. Returns the tested chains."""
    found = []
    for start, end, kind in regions(code, found_tests):
        if kind not in ("while", "repeat"):
            continue
        body = code[start:end]
        condition_tests = [test for test in found_tests
                           if (kind == "while" and test["start"] < start and not code[test["start"]:start].count("{"))
                           or (kind == "repeat" and end < test["start"] <= end + 200
                               and "\n" not in code[end:test["start"]])]
        for test in condition_tests:
            names = set(re.findall(r"[A-Za-z_]\w*", test["argument"]))
            if any(re.search(rf"(?<![\w.]){re.escape(name)}\s*(?:=(?!=)|\+=|&\+=|\.\s*append\s*\()", body)
                   for name in names):
                found.append(test["chain"])
    return found


def locals_of(code):
    return ({match.group(1) for match in re.finditer(r"\b(?:var|let)\s+([A-Za-z_]\w*)", code)}
            | {match.group(1) for match in re.finditer(r"\bfor\s+(?:case\s+let\s+)?([A-Za-z_]\w*)\s+in\b", code)})


def written(code, base):
    """Whether a body writes `base`: a mutating call on it or below it, a subscript or whole assignment."""
    name = rf"(?<![\w.])(?:self\s*\.\s*)?{re.escape(base)}"
    calls = "|".join(WRITE_CALLS)
    return bool(re.search(name + rf"(?:\s*\.\s*[A-Za-z_]\w*)*\s*\.\s*(?:{calls})\s*\(", code)
                or re.search(name + r"(?:\s*\.\s*[A-Za-z_]\w*)*\s*\[[^\n]*?\]\s*(?:=(?!=)|\+=)", code)
                or re.search(name + r"\s*(?:=(?!=)|\+=)", code))


def parameter_list(text):
    """`[(name, raw type)]` for a parameter list's masked text, `inout` kept."""
    found = []
    for part in split_top(text):
        part = re.sub(r"@\w+(?:\([^)]*\))?\s*", "", part)
        head, _, kind = part.partition(":")
        names = head.split()
        if names and kind:
            found.append((names[-1], " ".join(kind.split("=")[0].split())))
    return found


def is_collection(kind):
    kind = re.sub(r"^inout\s+", "", kind).strip()
    if kind.startswith("[") and kind.endswith("]"):
        return True
    return re.split(r"[<\s]", kind, maxsplit=1)[0].split(".")[-1] in COLLECTIONS


def cues(function, kinds):
    """§1.2's cues for one function. `kinds` maps a type name to its declared kinds across the repository."""
    modifiers, code, raw = split_function(function["text"])
    found_tests = tests(code)
    params = parameter_list(function["parameters"])
    inout = {name for name, kind in params if kind.startswith("inout ") and is_collection(kind)}
    names = ({name for name, _ in params}, inout)
    local = locals_of(code)
    counted, sources, stored_increments, tables, aliases = counters(code, names, local)
    decorated = decorations(code, raw, counted, tables)
    tested_bases = {_base(test["chain"]) for test in found_tests} - {""}
    spans = regions(code, found_tests)
    tied_ = sorted({decoration[1] for decoration in decorated
                    if tied(code, decoration, found_tests, spans, sources, tested_bases)})
    loop = retests(code, found_tests)
    static = bool(re.search(r"\bstatic\b", modifiers) or re.search(r"\bclass\s+$", modifiers))
    owner_kinds = ({function["owner_kind"]} if function["owner_kind"] != "extension"
                   else kinds.get(function["owner"], set()))
    state = []
    if owner_kinds & CLASS_LIKE and not static:
        state.append("class")
    if re.search(r"\bmutating\b", modifiers):
        state.append("mutating")
    if inout:
        state.append("inout")
    result = " ".join(function["result"].split())
    stored_tested = sorted(base for base in tested_bases if _stored(base, names, local) and written(code, base))
    inserted = sorted(_base(test["chain"]) for test in found_tests
                      if test["kind"] == "inserted" and _stored(_base(test["chain"]), names, local))
    fresh = sorted({counter for position, counter in decorated
                    if (counter in stored_increments or aliases.get(counter) in stored_increments)
                    and reaches_return(code, position)})
    return {
        "NAME": [word for word in words(function["name"]) if word.startswith(NAME_PREFIXES)],
        "TEST": sorted({f"{test['kind']}:{test['chain']}" for test in found_tests}),
        "SUFFIX": sorted({counter for _, counter in decorated}),
        "TIED": tied_,
        "RETEST": sorted(set(loop)),
        "FRESH": fresh,
        "STATE": state,
        "RETURNS": result not in ("", "Void", "()", "Never"),
        "WRITE": sorted(set(stored_tested) | set(inserted)
                        | {f"counter:{chain}" for chain in stored_increments}),
    }


def is_candidate(found):
    """§1.3."""
    decorated = bool(found["TIED"] or found["RETEST"])
    return ((bool(found["TEST"]) and decorated) or bool(found["FRESH"])
            or (bool(found["NAME"]) and (bool(found["TEST"]) or bool(found["SUFFIX"]))))


def is_gated(found):
    """§1.4: #669's three criteria, mechanically."""
    return bool(found["STATE"] and found["RETURNS"] and found["TEST"] and (found["TIED"] or found["RETEST"])
                and found["WRITE"])


# ── The owner's members, for a packet (§4.3) ──────────────────────────────────────────────────────
MEMBER = re.compile(
    r"^(?:@\w+(?:\([^)]*\))?\s*)*(?:(?:public|private|fileprivate|internal|open|package|static|class|final|override"
    r"|mutating|nonmutating|lazy|weak|unowned|nonisolated|convenience|required|dynamic|indirect)(?:\([^)]*\))?\s+)*"
    r"(var|let|func|init|subscript|case|typealias)\b")


def owner_entries(files, owner):
    """`[(path, line, [lines])]`: every top-level declaration of every `struct`, `class`, `enum`, `actor`,
    `extension` or `protocol` named `owner` in `files`, in path order, each type's header first (line 0). A member
    carries its doc comment (a `///` run or a `/** … */` block) and the attribute lines between them, without its
    body."""
    entries = []
    for path in sorted(files):
        text = files[path]
        masked, _ = mask(text)
        raw_lines = text.split("\n")
        for match in DECL.finditer(masked):
            if base_name(match.group(2)) != owner or (match.group(1) == "class" and match.group(2) in ("func", "var")):
                continue
            brace = masked.find("{", match.end())
            if brace < 0 or masked[match.end():brace].count("\n") > 3:
                continue
            close = _close(masked, brace)
            header = raw_lines[text.count("\n", 0, match.start())].strip()
            entries.append((path, 0, [f"// {os.path.basename(path)}: {header.rstrip('{').strip()}"]))
            depth, cursor = 0, brace + 1
            while cursor < close:
                line_end = masked.find("\n", cursor)
                line_end = close if line_end < 0 or line_end > close else line_end
                line = masked[cursor:line_end]
                number = text.count("\n", 0, cursor)
                if depth == 0 and MEMBER.match(line.strip()):
                    entries.append((path, number + 1, _member_docs(raw_lines, number) + [
                        raw_lines[number].strip()[:raw_lines[number].strip().find("{")].rstrip()
                        if "{" in line and raw_lines[number].strip().find("{") > 0 else raw_lines[number].strip()]))
                depth += line.count("{") - line.count("}")
                cursor = line_end + 1
    return entries


def _member_docs(raw_lines, number):
    """The doc comment and attribute lines above line `number`: attributes first walked over, then a `///` run or a
    `/** … */` block."""
    above, attributes = number - 1, []
    while above >= 0 and raw_lines[above].strip().startswith("@"):
        attributes.insert(0, raw_lines[above].strip())
        above -= 1
    docs = []
    if above >= 0 and raw_lines[above].strip().endswith("*/"):
        top = above
        while top >= 0 and not raw_lines[top].strip().startswith("/*"):
            top -= 1
        if top >= 0 and raw_lines[top].strip().startswith("/**"):
            docs = [line.strip() for line in raw_lines[top:above + 1]]
    else:
        while above >= 0 and raw_lines[above].strip().startswith("///"):
            docs.insert(0, raw_lines[above].strip())
            above -= 1
    return docs + attributes


def member_lines(entries, first=None, skip=None):
    """The packet's member list: `first`'s declarations first, `skip` (the row's own `(path, line)`) left out, at
    most MEMBERS_CAP lines with the rest counted."""
    ordered = sorted(entries, key=lambda entry: entry[0] != first)
    lines = [line for path, number, block in ordered if (path, number) != skip for line in block]
    if len(lines) > MEMBERS_CAP:
        return lines[:MEMBERS_CAP] + [f"// … {len(lines) - MEMBERS_CAP} more lines left out"]
    return lines


def owner_members(files, owner, skip=None):
    """`member_lines` over `owner_entries`, with the row's own file first when `skip` names it."""
    return member_lines(owner_entries(files, owner), first=skip[0] if skip else None, skip=skip)


class _Slow(Exception):
    pass


def parsable(text, seconds=10.0):
    """§2: whether `mutation_check.mask`, which every pass over a file runs, finishes on `text` within `seconds`.
    It loops forever on a comment or a multi-line literal whose closer it cannot find, which valid Swift can
    reach (`\\\"\"\"` inside a multi-line literal)."""
    def stop(*_):
        raise _Slow()

    previous = signal.signal(signal.SIGALRM, stop)
    signal.setitimer(signal.ITIMER_REAL, seconds)
    try:
        mask(text)
        return True
    except _Slow:
        return False
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)


def census(files, kinds=None, probes=None):
    """`candidates` over one subject's `{path: text}`. `kinds` defaults to the subject's own; `run` passes its
    repository's. Every row carries its same-file one-hop callers and callees (§4). A function named in R3_NAMES
    is appended to `probes` whether or not it is a candidate (§6)."""
    parsed = {path: declarations(text)[1] for path, text in files.items()}
    if kinds is None:
        kinds = _type_kinds(files)
    candidates = []
    for path in sorted(parsed):
        functions = parsed[path]
        defined = {function["name"] for function in functions}
        for function in functions:
            found = cues(function, kinds)
            candidate = is_candidate(found)
            if probes is not None and function["name"] in R3_NAMES:
                probes.append({"path": path, "line": function["line"], "name": function["name"],
                               "owner": function["owner"], "cues": found, "candidate": candidate,
                               "gated": is_gated(found)})
            if not candidate:
                continue
            candidates.append({
                "path": path, "line": function["line"], "owner": function["owner"],
                "owner_kind": function["owner_kind"], "name": function["name"], "labels": function["labels"],
                "visibility": function["visibility"], "result": function["result"], "cues": found,
                "gated": is_gated(found), "doc": function["doc"], "owner_doc": function["owner_doc"],
                "text": function["text"], "key": function["key"],
                "callees": sorted((set(function["calls"]) & defined) - {function["name"]}),
                "callers": sorted({other["name"] for other in functions
                                   if other is not function and function["name"] in other["calls"]})})
    return candidates


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
        else:
            first[row["key"]] = dict(row, copies=[])
    return list(first.values())


# ── The universe (§2) and the run ─────────────────────────────────────────────────────────────────
def groups():
    """§2: #667's frozen universe (decision, unmet, wide), asserted by `layering_census.universe`, with every
    decision subject read from its root rather than its manifest source directories; plus the graph-layout corpus
    as the layout group, asserted by `layering_census.corpus_universe`."""
    found = [(group, name, root, [root] if group == "decision" else roots) for group, name, root, roots in universe()]
    return found + [("layout", name, root, roots) for _, name, root, roots in corpus_universe()]


def without_fixtures(files, root):
    """§2: drop a file with a `fixtures` directory component below the subject root, ignoring case."""
    kept, dropped = {}, 0
    real = os.path.realpath(root)
    for path, text in files.items():
        parts = os.path.relpath(path, real).split(os.sep)[:-1]
        if any(part.lower() == SKIP_FIXTURES for part in parts):
            dropped += 1
        else:
            kept[path] = text
    return kept, dropped


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
    repository_kinds = collections.defaultdict(lambda: collections.defaultdict(set))
    repository_files = collections.defaultdict(dict)
    for key, (files, _) in read.items():
        repository_files[tops[key]].update(files)
        for name, kinds in _type_kinds(files).items():
            repository_kinds[tops[key]][name] |= kinds
    report = {"subjects": [], "candidates": [], "probes": {"R3": []}}
    rows, members = [], {}
    for key, entry in by_root.items():
        files, skipped = read[key]
        probes = []
        candidates = census(files, repository_kinds[tops[key]], probes)
        report["subjects"].append({
            "group": entry["group"], "name": entry["name"], "also": entry["also"], "root": key,
            "toplevel": tops[key], "revision": revision(entry["root"]),
            "dirty": bool(git(entry["root"], "status", "--porcelain")), "files": len(files), "skipped": skipped,
            "candidates": len(candidates)})
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
        report["probes"]["R3"] += probes
    report["candidates_before_copy_merge"] = len(rows)
    report["candidates"] = merge_copies(rows)
    choose(report)
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=1, sort_keys=True)
    for group in GROUP_ORDER:
        found = [row for row in report["candidates"] if row["group"] == group]
        repos = collections.Counter(row["repo"] for row in found)
        print(f"  {group}: {len(found)} candidates ({sum(r['gated'] for r in found)} GATED) over {len(repos)} subjects,"
              f" {sum(r['judged'] for r in found)} judged  {dict(repos.most_common(6))}")
    print(f"  before the copy merge {report['candidates_before_copy_merge']}; R3 probes {len(report['probes']['R3'])}")


def render(label, row):
    """One row as a packet shows it (§4.3): never its cues, GATED or group."""
    members = "\n".join(row.get("members") or ["(none found)"])
    return (f"## {label}\n\n- repository: `{row['repo']}`, at `{row['root']}`\n"
            f"- file: `{row['path']}`, line {row['line']}\n"
            f"- owner: `{row['owner'] or '(top level)'}` ({row['owner_kind'] or 'none'})\n"
            f"- owner's doc comment: {row['owner_doc'] or '(none)'}\n"
            f"- the function's doc comment: {row['doc'] or '(none)'}\n"
            f"- same-file functions it calls: {', '.join(row['callees']) or '(none)'}\n"
            f"- same-file functions that call it: {', '.join(row['callers']) or '(none)'}\n"
            f"- the owner's other members in this repository (bodies left out):\n\n```swift\n{members}\n```\n\n"
            f"```swift\n{row['text']}\n```\n")


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
    with open(os.path.join(os.path.dirname(os.path.abspath(out_dir)), "index.json"), "w", encoding="utf-8") as handle:
        json.dump(index, handle, indent=1)
    print(f"{len(rows)} rows in {(len(rows) + PACKET_SIZE - 1) // PACKET_SIZE} packets → {out_dir}")


# ── The judgements (§4.3–§4.4) ────────────────────────────────────────────────────────────────────
VERDICTS = {"UNIQUIFIER", "MEMOIZING", "BATCH", "LOOKUP", "NOT-UNIQUIFIER", "UNDETERMINED"}
OWING = {"UNIQUIFIER", "MEMOIZING"}
BOOLEAN_FIELDS = ("expressible", "setup", "body_disagrees")


def usable(record):
    """A judge's record is usable when its verdict is known and, for an owing verdict, each flag is answered."""
    if not isinstance(record, dict) or record.get("verdict") not in VERDICTS:
        return False
    return record["verdict"] not in OWING or all(isinstance(record.get(field), bool) for field in BOOLEAN_FIELDS)


def _agree(first, second):
    return (usable(first) and usable(second) and first["verdict"] == second["verdict"]
            and (first["verdict"] not in OWING
                 or (first["expressible"] == second["expressible"] and first["setup"] == second["setup"])))


def join(index, verdicts):
    """§4.3: each label's final record. `verdicts` maps a judge (`A`, `B`, `C`) to `{label: record}`. A and B
    decide when they agree on the verdict and, for an owing verdict, on EXPRESSIBLE and SETUP; their record then
    flags *body disagrees* when either flags it, with both witnesses. Otherwise C decides, and a label C has not
    judged is refused. Unknown, repeated or missing labels are refused."""
    labels = [entry["label"] for entry in index]
    if len(set(labels)) != len(labels):
        raise SystemExit("the index repeats a label")
    for judge, records in verdicts.items():
        unknown = set(records) - set(labels)
        if unknown:
            raise SystemExit(f"judge {judge} labelled rows the index does not hold: {sorted(unknown)[:5]}")
    final = {}
    for entry in index:
        label = entry["label"]
        first, second = verdicts.get("A", {}).get(label), verdicts.get("B", {}).get(label)
        if first is None or second is None:
            raise SystemExit(f"{label} lacks a judge A or B record")
        if _agree(first, second):
            record = dict(first, decided_by="A+B")
            if first["verdict"] in OWING:
                record["body_disagrees"] = first["body_disagrees"] or second["body_disagrees"]
                record["witness"] = " | ".join(w for w in (first.get("witness"), second.get("witness")) if w)
            final[entry["id"]] = record
        elif label in verdicts.get("C", {}):
            third = verdicts["C"][label]
            final[entry["id"]] = dict(third if usable(third) else {"verdict": "UNDETERMINED"}, decided_by="C")
        else:
            raise SystemExit(f"{label}: A and B disagree and no judge C record exists")
    return final


# §4.2: the calibration items' expected answers, which only this file holds. Each judge's record must match on
# every field named here.
CALIBRATION = {
    "calibration/1": {"verdict": "UNIQUIFIER", "expressible": False, "setup": True},
    "calibration/2": {"verdict": "UNIQUIFIER", "expressible": True, "body_disagrees": True},
    "calibration/3": {"verdict": "MEMOIZING", "expressible": True, "setup": False, "body_disagrees": False},
    "calibration/4": {"verdict": "LOOKUP"},
    "calibration/5": {"verdict": "NOT-UNIQUIFIER"},
    "calibration/6": {"verdict": "BATCH"},
    "calibration/7": {"verdict": "NOT-UNIQUIFIER"},
    "calibration/8": {"verdict": "NOT-UNIQUIFIER"},
    "calibration/9": {"verdict": "UNIQUIFIER", "expressible": True, "body_disagrees": True},
}


def calibrate(records):
    """§4.2: the labels whose record misses an expected answer, or is missing. An empty list passes."""
    by_label = {record.get("label"): record for record in records}
    return [label for label, expected in CALIBRATION.items()
            if label not in by_label or any(by_label[label].get(field) != value for field, value in expected.items())]


# ── The decision (§4.5, §8) ───────────────────────────────────────────────────────────────────────
BAR_COUNT, BAR_REPOSITORIES, GATE_PRECISION_BAR = 5, 2, 0.70


def owing_groups(rows, verdicts, need_expressible=True, group="decision"):
    """§4.5: owing rows (UNIQUIFIER or MEMOIZING, EXPRESSIBLE unless told otherwise) of one group, merged: a row
    also merges with an owing row in the same file it calls or that calls it, transitively."""
    def owing(row):
        verdict = verdicts.get(row["id"], {})
        return verdict.get("verdict") in OWING and (not need_expressible or verdict.get("expressible") is True)

    members = [row for row in rows if row["group"] == group and row.get("judged") and owing(row)]
    parent = {row["id"]: row["id"] for row in members}

    def find(identifier):
        while parent[identifier] != identifier:
            parent[identifier] = parent[parent[identifier]]
            identifier = parent[identifier]
        return identifier

    by_file = collections.defaultdict(list)
    for row in members:
        by_file[(row["root"], row["path"])].append(row)
    for same in by_file.values():
        for row in same:
            for other in same:
                if other is not row and (other["name"] in row["callees"] or other["name"] in row["callers"]):
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


def decide(report, judgements, kills):
    """§8: `(outcome, figures, lines)`. Refuses unless every judged row has exactly one usable-or-UNDETERMINED
    judgement, so a dropped packet can never read as rows that are not uniquifiers."""
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
    population = owing_groups(rows, verdicts)
    gated_groups = [group_ for group_ in population if any(row["gated"] for row in group_)]
    decision_gated = [row for row in judged if row["group"] == "decision" and row["gated"]]
    true_gated = [row for row in decision_gated if verdicts[row["id"]]["verdict"] in OWING]
    precision = len(true_gated) / len(decision_gated) if decision_gated else 0.0
    loose = owing_groups(rows, verdicts, need_expressible=False)
    setup = [group_ for group_ in loose if all(verdicts[row["id"]].get("expressible") is False for row in group_)
             and any(verdicts[row["id"]].get("setup") is True for row in group_)]
    outside = {group: owing_groups(rows, verdicts, group=group) for group in ("unmet", "layout", "wide")}
    wide_total = len([row for row in rows if row["group"] == "wide"])
    wide_judged = len([row for row in judged if row["group"] == "wide"])
    wide_estimate = len(outside["wide"]) * wide_total / wide_judged if wide_judged else 0.0
    undetermined = [[row] for row in judged if row["group"] == "decision"
                    and verdicts[row["id"]]["verdict"] == "UNDETERMINED"]
    owing_expressible = [row for row in judged if row["group"] == "decision"
                         and verdicts[row["id"]]["verdict"] in OWING and verdicts[row["id"]].get("expressible")]
    figures = {
        "N": len(population), "repositories": len(repositories(population)),
        "N_gated": len(gated_groups), "gated_repositories": len(repositories(gated_groups)),
        "gated": len(decision_gated), "gated_owing": len(true_gated), "precision": precision,
        "gated_not_owing": [row["id"] for row in decision_gated if verdicts[row["id"]]["verdict"] not in OWING],
        "N_without_expressible": len(loose), "N_setup": len(setup),
        "N_unmet": len(outside["unmet"]), "N_layout": len(outside["layout"]), "N_wide": len(outside["wide"]),
        "wide_candidates": wide_total, "wide_judged": wide_judged, "N_wide_estimate": round(wide_estimate, 1),
        "N_undetermined": len(undetermined),
        "ungated_owing": [{"id": group_[0]["id"], "expressible": verdicts[group_[0]["id"]].get("expressible"),
                           "setup": verdicts[group_[0]["id"]].get("setup")}
                          for group_ in loose if not any(row["gated"] for row in group_)],
        "outside_without_expressible": {group: len(owing_groups(rows, verdicts, need_expressible=False, group=group))
                                        for group in ("unmet", "layout", "wide")},
        "body_disagrees": [row["id"] for row in judged if verdicts[row["id"]].get("body_disagrees") is True],
        "unmerged": len(owing_expressible) + sum(len(row["copies"]) for row in owing_expressible),
        "unparsable": sum(len(subject["skipped"].get("unparsable", [])) for subject in report.get("subjects", [])),
    }
    base = repositories(population)
    figures["sensitivity"] = {
        "N + N_setup": (len(population) + len(setup), len(base | repositories(setup))),
        "N + N_unmet + N_layout + N_wide": (
            len(population) + len(outside["unmet"]) + len(outside["layout"]) + round(wide_estimate),
            len(base | repositories(outside["unmet"]) | repositories(outside["layout"])
                | repositories(outside["wide"]))),
        "N + N_undetermined": (len(population) + len(undetermined), len(base | repositories(undetermined))),
    }
    summary = (kills or {}).get("summary")
    decisive = summary.get("decisive") if summary else None
    if not clears(figures["N"], figures["repositories"]):
        outcome = "DECLINE (population)"
    elif not clears(figures["N_gated"], figures["gated_repositories"]):
        outcome = "DECLINE (signal)"
    elif precision < GATE_PRECISION_BAR:
        outcome = "DECLINE (gate precision)"
    elif not summary or not summary.get("controls_passed") or not summary.get("complete") or decisive is None:
        outcome = "UNMEASURED (kills)"
    elif decisive == 0:
        outcome = "DECLINE (kills)"
    else:
        outcome = "BUILD"
    figures["decisive"] = decisive
    s0 = (((kills or {}).get("controls") or {}).get("S0") or {}).get("summary") or []
    return outcome, figures, decision_lines(outcome, figures, summary, s0)


def decision_lines(outcome, figures, summary, s0=()):
    summary = summary or {}
    lines = [
        f"DECISION: {outcome}  N = {figures['N']} over {figures['repositories']} local repositories"
        f" (bar: ≥ {BAR_COUNT} across ≥ {BAR_REPOSITORIES})  N_gated = {figures['N_gated']}"
        f"  gate precision {figures['gated_owing']}/{figures['gated']} ({figures['precision']:.0%})",
        f"law-only (reduced suite): {summary.get('decisive', '—')} by assertion,"
        f" {summary.get('law_only_reduced_other', '—')} by crash/timeout/memory"
        f"   law-only (full suite): {summary.get('law_only_full', '—')}",
        f"law {summary.get('law', '—')}, suite {summary.get('suite', '—')}, reduced {summary.get('reduced', '—')},"
        f" viable {summary.get('viable', '—')}   N_setup {figures['N_setup']}  N_unmet {figures['N_unmet']}"
        f"  N_layout {figures['N_layout']}  N_wide {figures['N_wide']} ({figures['wide_judged']} of"
        f" {figures['wide_candidates']} judged, estimate {figures['N_wide_estimate']})"
        f"  N_undetermined {figures['N_undetermined']}  unparsable files dropped {figures['unparsable']}",
        f"without EXPRESSIBLE: N {figures['N_without_expressible']}"
        + "".join(f"  N_{group} {count}" for group, count in figures["outside_without_expressible"].items()),
    ]
    for name, (count, repos) in figures["sensitivity"].items():
        lines.append(f"SENSITIVITY {name}: {count} over {repos} repositories"
                     f" — {'clears' if clears(count, repos) else 'does not clear'} the population bar")
    if "decisive_with_identifiers_kept" in summary:
        lines.append(f"SENSITIVITY decisive count with DiagramIdentifiersTests kept: "
                     f"{summary['decisive_with_identifiers_kept']} (resting on its exclusion:"
                     f" {', '.join(summary.get('decisive_resting_on_identifiers', [])) or 'none'})")
    lines += [f"S0 {line}" for line in s0]
    return lines


# ── Controls (§3) ─────────────────────────────────────────────────────────────────────────────────
def _one(source, kinds=None):
    """The cues of the last function in `source`, with the snippet's own types as `kinds`."""
    files = {"f.swift": source}
    functions = declarations(source)[1]
    found = cues(functions[-1], kinds if kinds is not None else _type_kinds(files))
    return found, is_candidate(found), is_gated(found)


UNIQ_E36 = '''class DiagramContext {
    var uniqElementNames: [String] = []
    var index = 0
    func uniqName(item: SyntaxStructure, relationship: String) -> String {
        guard let name = item.fullName else { return "" }
        var newName = name
        if uniqElementNames.contains(name) {
            newName += "\\(index)"
            index += 1
        } else {
            uniqElementNames.append(name)
        }
        return newName
    }
}'''
UNIQ_C6C = '''class DiagramContext {
    private(set) var takenIdentifiers: Set<String> = []
    var uniqElementNames: [String] = []
    var index = 0
    func uniqName(item: SyntaxStructure, relationship: String) -> String {
        guard let name = item.fullName else { return "" }
        var newName = name
        if uniqElementNames.contains(name) {
            repeat {
                newName = name + "\\(index)"
                index += 1
            } while takenIdentifiers.contains(newName)
        } else {
            uniqElementNames.append(name)
        }
        if declaresIdentifier(of: item) {
            takenIdentifiers.insert(newName)
        }
        return newName
    }
}'''
UNIQUE_ID = '''enum LayoutGraphBuilder {
    private static func uniqueId(for name: String, existing: inout [String: String]) -> String {
        if existing[name] == nil { return name }
        var counter = 1
        var candidate = "\\(name)_\\(counter)"
        while existing.values.contains(candidate) {
            counter += 1
            candidate = "\\(name)_\\(counter)"
        }
        return candidate
    }
}'''
MEMO = '''struct DiagramIdentifiers {
    private var byKey: [String: String] = [:]
    private var taken: Set<String> = []
    mutating func id(forKey key: String, sanitizing text: String) -> String {
        if let existing = byKey[key] {
            return existing
        }
        let base = sanitize(text)
        var candidate = base
        var suffix = 2
        while taken.contains(candidate) {
            candidate = "\\(base)_\\(suffix)"
            suffix += 1
        }
        byKey[key] = candidate
        taken.insert(candidate)
        return candidate
    }
}'''
MAKE_UNIQUE = '''public class BasicMacroExpansionContext {
    let sharedState: SharedState
    public func makeUniqueName(_ providedName: String) -> TokenSyntax {
        let name = providedName.isEmpty ? "__local" : providedName
        let uniqueIndex = sharedState.uniqueNames[name, default: 0]
        sharedState.uniqueNames[name] = uniqueIndex + 1
        let resultString = "$s\\(name.count)\\(name)fMu\\(uniqueIndex)_"
        return TokenSyntax(.identifier(resultString), presence: .present)
    }
}'''
CASE_NAME = '''enum ViewModelActionEnumEmitter {
    static func uniqueCaseName(for base: String, taken: inout Set<String>) -> String {
        var candidate = base
        var suffix = 2
        while taken.contains(candidate) {
            candidate = "\\(base)\\(suffix)"
            suffix += 1
        }
        taken.insert(candidate)
        return candidate
    }
}'''


def control_rows():
    """`[(id, description, ok)]` for §3's pass controls."""
    out = []

    def check(identifier, description, ok):
        out.append((identifier, description, bool(ok)))

    found, candidate, gated = _one(UNIQ_E36)
    check("C1", "e36da59 uniqName: GATED; STATE class; TIED `index` (in the contains branch); WRITE names + counter",
          candidate and gated and found["STATE"] == ["class"] and found["TIED"] == ["index"]
          and "uniqElementNames" in found["WRITE"] and "counter:index" in found["WRITE"])
    found, candidate, gated = _one(UNIQ_C6C)
    check("C2", "c6c82e3 uniqName: GATED; RETEST on takenIdentifiers through repeat-while; TIED in the repeat body",
          gated and found["RETEST"] == ["takenIdentifiers"] and found["TIED"] == ["index"])
    found, candidate, gated = _one(UNIQUE_ID)
    check("C3", "uniqueId: candidate, NOT GATED — writes neither `existing` nor a stored counter; STATE inout",
          candidate and not gated and found["WRITE"] == [] and found["STATE"] == ["inout"]
          and found["RETEST"] == ["existing.values"])
    found, candidate, gated = _one(MEMO)
    check("C4", "DiagramIdentifiers.id(forKey:): GATED, mutating, binding + contains tests",
          gated and found["STATE"] == ["mutating"] and "binding:byKey" in found["TEST"]
          and "contains:taken" in found["TEST"] and set(found["WRITE"]) == {"byKey", "taken"})
    found, candidate, gated = _one(MAKE_UNIQUE)
    check("C5", "makeUniqueName: GATED; its counter is read from the tested table, so it is TIED",
          gated and found["TEST"] == ["default-subscript:sharedState.uniqueNames"]
          and found["TIED"] == ["uniqueIndex"] and found["WRITE"] == ["sharedState"])
    found, candidate, gated = _one(CASE_NAME)
    check("C6", "uniqueCaseName: GATED through an inout Set, static allowed", gated and found["STATE"] == ["inout"])
    found, candidate, gated = _one('''extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}''')
    check("C7", "a dedup helper: NAME ∧ TEST makes a candidate; not GATED (local state, no decoration)",
          candidate and not gated and found["NAME"] == ["uniqued"] and found["WRITE"] == [])
    found, candidate, gated = _one('''class Logger {
    var count = 0
    func log(_ message: String) {
        count += 1
        print("\\(count): \\(message)")
    }
}''')
    check("C8", "a counting logger that returns nothing: no FRESH (the decoration is never returned), no candidate",
          not candidate and found["FRESH"] == [] and found["SUFFIX"] == ["count"])
    found, candidate, gated = _one('''class Names {
    private var counter = 0
    func nextName() -> String {
        counter += 1
        return "tmp\\(counter)"
    }
}''')
    check("C9", "a counter-only generator: FRESH candidate, not GATED, no NAME word",
          candidate and not gated and found["NAME"] == [] and found["FRESH"] == ["counter"])
    found, candidate, gated = _one('func f(x: [String]) -> Bool { x.contains("a") }')
    check("C10", "a lone membership test is no candidate", not candidate and found["TEST"] == ["contains:x"])
    found, candidate, gated = _one('''class C {
    var names: [String] = []
    var index = 0
    func g(_ name: String) -> String {
        // newName = "\\(name)\\(index)"
        if names.contains(name) { index += 1 }
        return name
    }
}''')
    check("C11", "an interpolation in a comment is no SUFFIX", found["SUFFIX"] == [] and not gated)
    found, candidate, gated = _one('''class C {
    var index = 0
    func g(_ name: String) -> String {
        let note = "names.contains(x)"
        index += 1
        return "\\(name)\\(index)"
    }
}''')
    check("C12", "literal text is no TEST", found["TEST"] == [] and found["FRESH"] == ["index"] and not gated)
    found, candidate, gated = _one('''class Renamer {
    func batch(_ names: [String]) -> [String] {
        var used = Set<String>()
        var out: [String] = []
        for name in names {
            var candidate = name
            var i = 1
            while used.contains(candidate) {
                candidate = "\\(name)\\(i)"
                i += 1
            }
            used.insert(candidate)
            out.append(candidate)
        }
        return out
    }
}''')
    check("C13", "a batch renamer's local set: candidate, WRITE empty, not GATED",
          candidate and found["WRITE"] == [] and not gated)
    found, candidate, gated = _one('''struct Table {
    var taken: [String] = []
    var n = 0
    mutating func claim(_ base: String) -> String {
        var name = base
        if taken.contains(name) {
            n += 1
            name = "\\(base)-\\(n)"
        }
        taken.append(name)
        return name
    }
}''')
    check("C14", "a mutating claim on a struct: GATED", gated and found["STATE"] == ["mutating"])
    found, candidate, gated = _one('''class Registry {
    static var used: Set<String> = []
    static var n = 0
    static func claim(_ base: String) -> String {
        var name = base
        while used.contains(name) {
            n += 1
            name = "\\(base)\\(n)"
        }
        used.insert(name)
        return name
    }
}''')
    check("C15", "a static func on a class without inout: STATE empty, not GATED (§9)",
          candidate and found["STATE"] == [] and not gated)
    found, candidate, gated = _one('''final class Pool {}
extension Pool {
    func claim(_ base: String) -> String {
        var name = base
        while used.contains(name) {
            n += 1
            name = "\\(base)\\(n)"
        }
        used.insert(name)
        return name
    }
}''')
    check("C16", "an extension of a class in the same repository: STATE class, GATED",
          found["STATE"] == ["class"] and gated)
    found, candidate, gated = _one('''class C {
    var used: Set<String> = []
    var n = 0
    func claim(_ base: String) -> String {
        var name = base
        while used.contains(name) {
            n += 1
            name = #"\\#(base)_\\#(n)"#
        }
        used.insert(name)
        return name
    }
}''')
    check("C17", "a raw string's interpolation is a SUFFIX", found["SUFFIX"] == ["n"] and gated)
    found, candidate, gated = _one('''class C {
    var used: Set<String> = []
    var n = 0
    func claim(_ base: String) -> String {
        var name = base
        if used.contains(name) {
            n += 1
            name = base + String(n)
        }
        used.insert(name)
        return name
    }
}''')
    check("C18", "`String(n)` is a SUFFIX", found["SUFFIX"] == ["n"] and gated)
    found, candidate, gated = _one('''class C {
    var names: [String] = []
    func claim(_ base: String) -> String {
        names.append(base)
        return names.contains(base) ? "\\(base)\\(names.count)" : base
    }
}''')
    check("C19", "an interpolated `.count` in a ternary's branch, tied by nothing else, is TIED",
          found["TIED"] == ["names.count"] and gated)
    found, candidate, gated = _one('''class C {
    var used: Set<String> = []
    func claim(_ base: String) -> String {
        for i in 1... {
            let name = "\\(base)\\(i)"
            if !used.contains(name) {
                used.insert(name)
                return name
            }
        }
        fatalError()
    }
}''')
    check("C20", "a range loop's variable is a counter, TIED because the value it builds is tested; GATED",
          found["TIED"] == ["i"] and gated)
    found, candidate, gated = _one('''enum E {
    static func claim(_ base: String, n: inout Int, used: Set<String>) -> String {
        var name = base
        while used.contains(name) {
            n += 1
            name = "\\(base)\\(n)"
        }
        return name
    }
}''')
    check("C21", "an inout Int is no STATE, and a counter that is a parameter is no stored counter",
          found["STATE"] == [] and not any(w.startswith("counter:") for w in found["WRITE"]) and not gated)
    found, candidate, gated = _one('''class C {
    var used: Set<String> = []
    var n = 0
    func claim(_ base: String) {
        var name = base
        while used.contains(name) {
            n += 1
            name = "\\(base)\\(n)"
        }
        used.insert(name)
    }
}''')
    check("C22", "a claim that returns nothing: RETURNS false, not GATED", not found["RETURNS"] and not gated)
    found, candidate, gated = _one('func makeUniqueName() -> String { "x" }\n')
    check("C23", "NAME words: make-unique-name", found["NAME"] == ["unique"] and not candidate)
    check("C24", "NAME words: freshVariable, disambiguated; nextName is none",
          [w for w in words("freshVariable") if w.startswith(NAME_PREFIXES)] == ["fresh"]
          and [w for w in words("disambiguated") if w.startswith(NAME_PREFIXES)] == ["disambiguated"]
          and [w for w in words("nextName") if w.startswith(NAME_PREFIXES)] == [])
    found, candidate, gated = _one('''class C {
    var names: [String: Int] = [:]
    func g(_ k: String) -> String {
        if names[k] == nil { names[k] = 0 }
        if let i = names.index(forKey: k) { _ = i }
        return k
    }
}''')
    check("C25", "nil-compare and index(forKey:) are TESTs", set(found["TEST"]) == {"nil-compare:names",
                                                                                   "index-for-key:names"})
    found, candidate, gated = _one('''class C {
    var used: Set<String> = []
    var i = 0
    func g(_ k: String) -> String {
        while i < 10 { i += 1 }
        if used.contains(k) { return "\\(k)\\(i)" }
        used.insert(k)
        return k
    }
}''')
    check("C26", "a while loop with no membership test is no RETEST", found["RETEST"] == [] and gated)
    found, candidate, gated = _one('''class C {
    var used: Set<String> = []
    var n = 0
    class func claim(_ base: String) -> String {
        var name = base
        while used.contains(name) { n += 1; name = "\\(base)\\(n)" }
        used.insert(name)
        return name
    }
}''')
    check("C27", "a `class func` is static: STATE empty", found["STATE"] == [] and not gated)
    found, candidate, gated = _one('''class C {
    var used: Set<String> = []
    func claim(_ base: String) -> String {
        var name = base
        var n = 0
        while used.contains(name) { n += 1; name = "\\(base)\\(n)" }
        if used.insert(name).inserted { return name }
        return name
    }
}''')
    check("C28", "`insert(…).inserted` is a TEST and a write; a local counter is no WRITE",
          "inserted:used" in found["TEST"] and found["WRITE"] == ["used"] and gated)
    copies = merge_copies([
        {"group": "wide", "toplevel": "/a", "repo": "a", "path": "x.swift", "line": 3, "key": "k"},
        {"group": "decision", "toplevel": "/b", "repo": "b", "path": "y.swift", "line": 9, "key": "k"},
        {"group": "layout", "toplevel": "/c", "repo": "c", "path": "z.swift", "line": 1, "key": "k"}])
    check("C29", "copies merge to the decision copy, the others listed",
          len(copies) == 1 and copies[0]["repo"] == "b" and copies[0]["copies"] == ["c:z.swift:1", "a:x.swift:3"])
    check("C30", "split_function ignores a `func` inside a comment before the signature",
          split_function('/// func not(this)\nfunc f(a: Int) -> Int {\n    a + 1\n}')[2].strip() == "a + 1")
    found, candidate, gated = _one('''class C {
    var used: [String] = []
    var n = 0
    func claim(_ base: String) -> String {
        var name = base
        if used.contains(name) {
            n = n + 1
            name = "\\(base)\\(n.description)"
        }
        used = used + [name]
        return name
    }
}''')
    check("C31", "`n = n + 1` counts; `n.description` is a SUFFIX; a whole assignment is a WRITE",
          found["TIED"] == ["n"] and "used" in found["WRITE"] and "counter:n" in found["WRITE"] and gated)
    found, candidate, gated = _one('''class C {
    var seen: [String: Int] = [:]
    func claim(_ base: String) -> String {
        let k = seen[base] ?? 0
        seen[base] = k + 1
        return k == 0 ? base : "\\(base)-\\(k + 1)"
    }
}''')
    check("C32", "a `?? 0` subscript binding is a per-key counter: TEST coalesce, TIED, GATED",
          found["TEST"] == ["coalesce:seen"] and found["TIED"] == ["k"] and gated)
    found, candidate, gated = _one('''class C {
    var names: [String] = []
    func uniqueLabel(_ base: String) -> String {
        "\\(base)\\(names.count)"
    }
}''')
    check("C33", "NAME ∧ SUFFIX with no TEST is a candidate", candidate and found["TEST"] == [] and not gated)
    found, candidate, gated = _one('''class C {
    var used: Set<String> = []
    func uniqueName(_ name: String) -> String {
        if used.contains(name) { return name }
        used.insert(name)
        return name
    }
}''')
    check("C34", "every conjunct but the decoration: a candidate by NAME, not GATED",
          candidate and found["STATE"] and found["RETURNS"] and found["TEST"] and found["WRITE"] and not gated)
    rows = [{"id": f"d{i:03d}", "group": "decision"} for i in range(301)]
    try:
        choose({"candidates": rows})
        check("C35", "more than 300 non-wide candidates stop the pass", False)
    except SystemExit:
        check("C35", "more than 300 non-wide candidates stop the pass", True)
    rows = [{"id": f"w{i:03d}", "group": "wide"} for i in range(75)] + [{"id": "u1", "group": "unmet"}]
    choose({"candidates": rows})
    picked = sorted(row["id"] for row in rows if row["judged"])
    again = [{"id": f"w{i:03d}", "group": "wide"} for i in reversed(range(75))]
    choose({"candidates": again})
    check("C36", "wide is sampled to 60 by the seed, the same set whatever the order; unmet is judged in full",
          len(picked) == 61 and "u1" in picked
          and sorted(row["id"] for row in again if row["judged"]) == [i for i in picked if i != "u1"])
    # The review's look-alikes: a count or a retry number in a message, not tied to the test.
    found, candidate, gated = _one('''final class SelectionModel {
    var selected: Set<String> = []
    func toggle(_ id: String) -> String {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        return "\\(selected.count) selected"
    }
}''')
    check("C37", "a count in a status message after a test: no TIED, no candidate", not candidate and not gated)
    found, candidate, gated = _one('''final class Cart {
    var items: [String] = []
    func add(_ item: String) -> String {
        if items.contains(item) { return "already there" }
        items.append(item)
        return "Added \\(item), \\(items.count) in cart"
    }
}''')
    check("C38", "a count in a message on the miss path: no TIED, no candidate", not candidate and not gated)
    found, candidate, gated = _one('''class C {
    var counts: [String: Int] = [:]
    func next(_ b: String) -> String {
        let n = (counts[b] ?? 0) + 1
        counts[b] = n
        return "\\(b)\\(n)"
    }
}''')
    check("C39", "`let n = (t[b] ?? 0) + 1`: a per-key counter, TIED, GATED", found["TIED"] == ["n"] and gated)
    found, candidate, gated = _one('''class C {
    var counts: [String: Int] = [:]
    func next(_ b: String) -> String {
        counts[b, default: 0] += 1
        return "\\(b)_\\(counts[b]!)"
    }
}''')
    check("C40", "a counter table incremented in place and read in the interpolation: TIED, GATED",
          found["TIED"] == ["counts[]"] and gated)
    found, candidate, gated = _one('''class C {
    var byKey: [String: String] = [:]
    var taken: Set<String> = []
    func id(_ k: String, flag: Bool) -> String {
        if flag, let e = byKey[k] { return e }
        var c = k
        var n = 2
        while taken
            .contains(c) {
            c = "\\(k)_\\(n)"
            n += 1
        }
        taken.insert(c)
        byKey[k] = c
        return c
    }
}''')
    check("C41", "a binding in a later clause is a TEST; a multi-line while condition is a RETEST",
          "binding:byKey" in found["TEST"] and found["RETEST"] == ["taken"] and gated)
    found, candidate, gated = _one('''class C {
    var queue: [String] = []
    var n = 0
    func drain(_ x: String) -> String {
        while queue.contains(x) { queue.removeFirst() }
        n += 1
        print("\\(n)")
        return x
    }
}''')
    check("C42", "a while loop that never reassigns what it tests is no RETEST", found["RETEST"] == [])
    found, candidate, gated = _one('''class C {
    var used: Set<String> = []
    func claim(_ base: String) -> String {
        var stats = Stats()
        stats.count += 1
        var name = base
        if used.contains(name) { name = "\\(base)\\(stats.count)" }
        used.insert(name)
        return name
    }
}''')
    check("C43", "a local's member incremented is no stored counter", "counter:stats.count" not in found["WRITE"]
          and found["WRITE"] == ["used"])
    found, candidate, gated = _one('''actor Namer {
    var used: Set<String> = []
    var n = 0
    func claim(_ base: String) -> String {
        var name = base
        while used.contains(name) { n &+= 1; name = "\\(base)\\(n)" }
        used.formUnion([name])
        return name
    }
}''')
    check("C44", "an actor is STATE class; `&+=` counts; `formUnion` is a WRITE",
          found["STATE"] == ["class"] and "used" in found["WRITE"] and "counter:n" in found["WRITE"] and gated)
    members = owner_members({"/r/b.swift": "extension Ctx {\n    var count: Int { taken.count }\n}\nstruct Other { var x = 1 }\n",
                             "/r/a.swift": '''/// The context.
class Ctx {
    /// Every id issued.
    var taken: Set<String> = []
    init(format: Int = 0) {
        self.format = format
    }
    /// Call before the first alias.
    @discardableResult
    func reserve(_ items: [String]) -> Int {
        taken.formUnion(items)
        return 0
    }
    /**
     Issues one alias.
     */
    func claim(_ base: String) -> String {
        return base
    }
    /* not a doc */
    func other() {}
}'''}, "Ctx", skip=("/r/a.swift", 5))
    check("C45", "owner members: the row's file first; properties, signatures, `///` docs above an attribute and "
          "`/** */` docs; bodies and the row left out; a plain comment is no doc",
          members == ["// a.swift: class Ctx", "/// Every id issued.", "var taken: Set<String> = []",
                      "/// Call before the first alias.", "@discardableResult",
                      "func reserve(_ items: [String]) -> Int", "/**", "Issues one alias.", "*/",
                      "func claim(_ base: String) -> String", "func other()", "// b.swift: extension Ctx",
                      "var count: Int"])
    for label, body in (("guard-else", '''guard !used.contains(name) else {
            n += 1
            return "\\(name)\\(n)"
        }
        used.insert(name)
        return name'''), ("else-after-if", '''if !used.contains(name) {
            used.insert(name)
            return name
        } else {
            n += 1
            return "\\(name)\\(n)"
        }'''), ("if-let binding", '''if let e = byKey[name] {
            return e
        } else {
            n += 1
            byKey[name] = name
            return "\\(name)\\(n)"
        }''')):
        found, candidate, gated = _one("class C {\n    var used: Set<String> = []\n    var byKey: [String: String] = [:]\n"
                                       "    var n = 0\n    func claim(_ name: String) -> String {\n        " + body
                                       + "\n    }\n}")
        check(f"C49 {label}", f"a decoration returned in the {label} span a test decides is TIED, GATED",
              found["TIED"] == ["n"] and gated)
    found, candidate, gated = _one('''class C {
    var n = 0
    func next() -> String {
        n += 1
        let label = "t\\(n)"
        return label
    }
}''')
    check("C50", "FRESH through a returned variable", found["FRESH"] == ["n"])
    found, candidate, gated = _one('''class C {
    var names: [String] = []
    var n = 0
    var hits = 0
    func claim(_ base: String) -> String {
        if names.contains(base) { hits += 1 }
        n += 1
        let c = "\\(base)\\(n)"
        names.append(c)
        return base
    }
}''')
    check("C51", "TIED only because the value it builds is written to the tested collection",
          found["TIED"] == ["n"] and found["FRESH"] == [])
    found, candidate, gated = _one('''class C {
    var names: [String] = []
    var n = 0
    func claim(_ base: String) -> String {
        if names.contains(base) { n += 1 }
        names.append("\\(base)\\(n)")
        return base
    }
}''')
    check("C52", "TIED by sitting inside what is written to the tested collection", found["TIED"] == ["n"])
    found, candidate, gated = _one('''class C {
    var names: Set<String> = []
    var n = 0
    func claim(_ base: String) -> Int {
        while names.contains("\\(base)\\(n)") { n += 1 }
        return n
    }
}''')
    check("C53", "TIED by sitting inside a test's argument", found["TIED"] == ["n"])
    writes = []
    for call in WRITE_CALLS:
        found, _, _ = _one("class C {\n    var used: Set<String> = []\n    func f(_ x: String) -> String {\n"
                           f"        if used.contains(x) {{ return x }}\n        used.{call}(x)\n        return x\n    }}\n}}")
        writes.append(found["WRITE"] == ["used"])
    check("C54", "each write call on a tested base is a WRITE", all(writes))
    kinds_ok = []
    for kind, expected in (("Array<String>", True), ("[String: Int]", True), ("OrderedSet<String>", True),
                           ("ContiguousArray<String>", True), ("Dictionary<String, Int>", True), ("Set<String>", True),
                           ("String", False)):
        found, _, _ = _one(f"func f(_ x: String, taken: inout {kind}) -> String {{ x }}\\n")
        kinds_ok.append((found["STATE"] == ["inout"]) == expected)
    check("C55", "each inout collection type is STATE inout, and an inout String is not", all(kinds_ok))
    found, candidate, gated = _one('''class C {
    var used: Set<String> = []
    var n = 0
    func claim(_ x: String) -> String {
        if used.contains(x) {
            n += 1
            print("duplicate \\(x), \\(n) so far")
        }
        used.insert(x)
        return x
    }
}''')
    check("C56", "a log line in the hit branch: no TIED, no FRESH, no candidate", not candidate and found["TIED"] == [])
    found, candidate, gated = _one('''class C {
    var used: Set<String> = []
    func claim(_ base: String) -> String {
        var name = base
        if name.isEmpty { name = "_" }
        while used.contains(name) { name = name + "_" }
        used.insert(name)
        return name
    }
}''')
    check("C57", "a while after an if's closing brace is a while, not a repeat's: RETEST, GATED",
          found["RETEST"] == ["used"] and gated)
    found, candidate, gated = _one('''class C {
    var used: Set<String> = []
    func claim(_ base: String) -> String {
        #if DEBUG
        let seen = used.contains(base)
        #endif
        for i in 1... {
            return "\\(base)\\(i)"
        }
    }
}''')
    check("C58", "`#if` is no if: its directive opens no span", not candidate and found["TIED"] == [])
    found, candidate, gated = _one('''class C {
    var counter = 0
    func next() -> Label {
        counter += 1
        return Label(
            id: "L\\(counter)")
    }
}''')
    check("C59", "a return over two lines is one statement: FRESH", found["FRESH"] == ["counter"])
    one_line = [_one("class C {\n    var n = 0\n    func f() { n += 1; print(\"\\(n)\") }\n}")[0]["FRESH"],
                _one("class C {\n    var n = 0\n    func f() -> String { n += 1; return \"t\\(n)\" }\n}")[0]["FRESH"]]
    check("C60", "on one line, a printed decoration is no FRESH and a returned one is", one_line == [[], ["n"]])
    found, candidate, gated = _one('''class C {
    var names: [String: String] = [:]
    func label(_ k: String) -> String {
        let shown = names[k, default: "x"]
        if names[k] == nil { return "\\(k)\\(shown)" }
        return k
    }
}''')
    check("C61", "a subscript with a string default is no counter", found["SUFFIX"] == [] and not candidate)
    shapes = []
    for body, cue in (('''let id = next
        next += 1
        return "n\\(id)"''', "FRESH"), ('''if let n = used[b] {
            used[b] = n + 1
            return "\\(b)\\(n + 1)"
        }
        used[b] = 1
        return b''', "GATED"), ('''counts[b, default: 0] += 1
        let n = counts[b]!
        return "\\(b)_\\(n)"''', "GATED")):
        found, candidate, gated = _one("class C {\n    var next = 0\n    var used: [String: Int] = [:]\n"
                                       "    var counts: [String: Int] = [:]\n    func f(_ b: String) -> String {\n"
                                       "        " + body + "\n    }\n}")
        shapes.append(bool(found["FRESH"]) if cue == "FRESH" else gated)
    check("C62", "a counter copied into a local first: `let id = next`, `if let n = used[b]`, `let n = counts[b]!`",
          shapes == [True, True, True])
    check("C63", "a file whose comment never closes is unparsable, and is found so quickly; a normal file is not",
          not parsable("func f() {}\n/* never closed\n", seconds=0.2) and parsable(UNIQ_C6C, seconds=0.2))
    found, candidate, gated = _one('''class C {
    var counts: [String: Int] = [:]
    func next(_ b: String) -> String {
        counts[b] = (counts[b] ?? 0) + 1
        return "\\(b)\\(counts[b]!)"
    }
}''')
    check("C47", "`t[k] = (t[k] ?? 0) + 1` makes a counter table; its read in the interpolation is TIED",
          found["TIED"] == ["counts[]"] and gated)
    found, candidate, gated = _one('''class C {
    var used: Set<String> = []
    func claim(_ base: String) -> String {
        var name = base
        while used.contains(name) { name = name + "_" }
        used.insert(name)
        return name
    }
}''')
    check("C48", "a decoration that is no counter, re-tested in a while: RETEST alone carries the gate",
          found["TIED"] == [] and found["RETEST"] == ["used"] and gated)
    kept, dropped = without_fixtures({"/r/Sources/a.swift": "", "/r/fixtures/b.swift": "", "/r/x/Fixtures/c.swift": ""},
                                     "/r")
    check("C46", "a fixtures directory below the root is skipped, ignoring case", list(kept) == ["/r/Sources/a.swift"]
          and dropped == 2)
    return out


def _row(identifier, group="decision", top="/r1", gated=True, path="a.swift", name=None, callees=(), callers=()):
    return {"id": identifier, "group": group, "toplevel": top, "root": top, "path": path, "judged": True,
            "gated": gated, "name": name or identifier, "callees": list(callees), "callers": list(callers),
            "copies": []}


def _owe(verdict="UNIQUIFIER", expressible=True, setup=False, body=False):
    return {"verdict": verdict, "expressible": expressible, "setup": setup, "body_disagrees": body}


KILLS = {"summary": {"controls_passed": True, "complete": True, "decisive": 2}}


def decision_controls():
    out = []

    def check(identifier, description, ok):
        out.append((identifier, description, bool(ok)))

    def build(count, repos, gated=True):
        rows = [_row(f"u{i}", top=f"/r{i % repos}", gated=gated, path=f"f{i}.swift") for i in range(count)]
        return {"candidates": rows}, {row["id"]: _owe() for row in rows}

    report, judged = build(4, 2)
    check("D1", "N = 4 → DECLINE (population)", decide(report, judged, KILLS)[0] == "DECLINE (population)")
    report, judged = build(5, 1)
    check("D2", "N = 5 over 1 repository → DECLINE (population)",
          decide(report, judged, KILLS)[0] == "DECLINE (population)")
    report, judged = build(5, 2)
    report["candidates"][0]["gated"] = False
    check("D3", "N = 5, N_gated = 4 → DECLINE (signal)", decide(report, judged, KILLS)[0] == "DECLINE (signal)")
    report, judged = build(6, 2)
    for index in range(5):
        report["candidates"].append(_row(f"n{index}", top="/r9", path=f"n{index}.swift"))
        judged[f"n{index}"] = {"verdict": "NOT-UNIQUIFIER"}
    outcome, figures, _ = decide(report, judged, KILLS)
    check("D4", "gate precision 6/11 → DECLINE (gate precision), the five listed",
          outcome == "DECLINE (gate precision)" and len(figures["gated_not_owing"]) == 5)
    report, judged = build(6, 2)
    check("D5", "no kill summary → UNMEASURED (kills)", decide(report, judged, {})[0] == "UNMEASURED (kills)")
    check("D6", "a failed runner control, an incomplete run, or no decisive count → UNMEASURED (kills)",
          all(decide(report, judged, {"summary": dict(KILLS["summary"], **change)})[0] == "UNMEASURED (kills)"
              for change in ({"controls_passed": False}, {"complete": False}, {"decisive": None})))
    check("D7", "decisive 0 → DECLINE (kills)",
          decide(report, judged, {"summary": dict(KILLS["summary"], decisive=0)})[0] == "DECLINE (kills)")
    check("D8", "everything met → BUILD", decide(report, judged, KILLS)[0] == "BUILD")
    report, judged = build(6, 2)
    del judged["u0"]
    try:
        decide(report, judged, KILLS)
        check("D9", "a judged row with no judgement is refused", False)
    except SystemExit:
        check("D9", "a judged row with no judgement is refused", True)
    report, judged = build(6, 2)
    judged["u0"] = {"verdict": "UNDETERMINED"}
    judged["u1"] = {"verdict": "UNIQUIFIER"}
    outcome, figures, _ = decide(report, judged, KILLS)
    check("D10", "UNDETERMINED and an unusable owing record count in N_undetermined, not N",
          figures["N"] == 4 and figures["N_undetermined"] == 2
          and figures["sensitivity"]["N + N_undetermined"] == (6, 2))
    rows = [_row("a", name="claim", callees=["helper"]), _row("b", name="helper", callers=["claim"]),
            _row("c", path="other.swift", name="helper")]
    groups_ = owing_groups(rows, {row["id"]: _owe() for row in rows})
    check("D11", "a same-file call merges two owing rows; the same name in another file does not",
          sorted(len(group_) for group_ in groups_) == [1, 2])
    report, judged = build(6, 2)
    judged["u0"] = _owe(expressible=False, setup=True)
    judged["u2"] = _owe(expressible=False, setup=False)
    outcome, figures, lines = decide(report, judged, KILLS)
    check("D12", "not-EXPRESSIBLE rows leave N; only the one with SETUP is in N_setup, and its line is printed",
          figures["N"] == 4 and figures["N_without_expressible"] == 6 and figures["N_setup"] == 1
          and figures["sensitivity"]["N + N_setup"] == (5, 2)
          and "SENSITIVITY N + N_setup: 5 over 2 repositories — clears the population bar" in lines)
    report, judged = build(6, 2)
    for group in ("unmet", "layout"):
        report["candidates"].append(_row(f"x-{group}", group=group, top=f"/{group}"))
        judged[f"x-{group}"] = _owe()
    for index in range(3):
        report["candidates"].append(_row(f"w{index}", group="wide", top=f"/w{index}", path=f"w{index}.swift"))
        judged[f"w{index}"] = _owe() if index == 0 else {"verdict": "NOT-UNIQUIFIER"}
    report["candidates"].append(dict(_row("w-unjudged", group="wide", top="/w9"), judged=False))
    outcome, figures, _ = decide(report, judged, KILLS)
    check("D13", "unmet, layout and wide rows never enter N or the gate's precision; wide is estimated over its "
          "judged share", figures["N"] == 6 and figures["gated"] == 6 and figures["N_unmet"] == 1
          and figures["N_layout"] == 1 and figures["N_wide"] == 1 and figures["wide_candidates"] == 4
          and figures["wide_judged"] == 3 and figures["N_wide_estimate"] == 1.3
          and figures["sensitivity"]["N + N_unmet + N_layout + N_wide"] == (9, 5))
    index = [{"label": "p/1", "id": "a"}, {"label": "p/2", "id": "b"}, {"label": "p/3", "id": "c"}]
    agree = {"verdict": "NOT-UNIQUIFIER"}
    final = join(index, {
        "A": {"p/1": _owe(), "p/2": agree, "p/3": dict(_owe(), witness="")},
        "B": {"p/1": _owe(expressible=False), "p/2": agree, "p/3": dict(_owe(body=True), witness="a1 then a")},
        "C": {"p/1": _owe(verdict="LOOKUP")}})
    check("D14", "join: A and B agreeing decide, flagging body disagrees when either does; a disagreement on "
          "EXPRESSIBLE goes to C", final["b"]["decided_by"] == "A+B" and final["a"]["verdict"] == "LOOKUP"
          and final["c"]["body_disagrees"] is True and final["c"]["witness"] == "a1 then a")
    index = index[:2]
    refusals = 0
    for verdicts in ({"A": {"p/1": agree}, "B": {"p/1": agree}},
                     {"A": {"p/1": agree, "p/2": agree, "p/3": agree}, "B": {"p/1": agree, "p/2": agree}},
                     {"A": {"p/1": agree, "p/2": agree}, "B": {"p/1": _owe(), "p/2": agree}},
                     {"A": {"p/1": _owe(), "p/2": agree}, "B": {"p/1": _owe(setup=True), "p/2": agree}}):
        try:
            join(index, verdicts)
        except SystemExit:
            refusals += 1
    try:
        join(index + [{"label": "p/1", "id": "z"}], {"A": {}, "B": {}})
    except SystemExit:
        refusals += 1
    check("D15", "join refuses a missing, an unknown, an undecided and a SETUP-split label, and a repeated label",
          refusals == 5)
    report, judged = build(6, 2)
    report["candidates"][0]["copies"] = ["other:x.swift:1"]
    outcome, figures, _ = decide(report, judged, KILLS)
    check("D16", "the unmerged count counts every copy", figures["unmerged"] == 7 and figures["N"] == 6)
    right = [dict(expected, label=label) for label, expected in CALIBRATION.items()]
    wrong = [dict(record) for record in right]
    wrong[8]["body_disagrees"] = False
    check("D17", "calibration passes the expected records, and misses one wrong flag and one dropped item",
          calibrate(right) == [] and calibrate(wrong) == ["calibration/9"]
          and calibrate(right[:-1]) == ["calibration/9"])
    report, judged = build(6, 2)
    outcome, figures, lines = decide(report, judged, dict(KILLS, controls={"S0": {"summary": ["UNIQUIFIER-LAW U0 x"]}}))
    check("D18", "S0's summary lines are printed beside the decision", lines[-1] == "S0 UNIQUIFIER-LAW U0 x")
    kills = {"summary": dict(KILLS["summary"], decisive_with_identifiers_kept=1,
                             decisive_resting_on_identifiers=["M039"])}
    outcome, figures, lines = decide(report, judged, kills)
    check("D20", "the decisive count with DiagramIdentifiersTests kept is printed, with the kills resting on it",
          outcome == "BUILD" and "SENSITIVITY decisive count with DiagramIdentifiersTests kept: 1 (resting on its "
          "exclusion: M039)" in lines)
    report, judged = build(6, 2)
    report["candidates"].append(_row("s", top="/r9", gated=False, path="s.swift"))
    judged["s"] = _owe(expressible=False, setup=False)
    report["candidates"].append(_row("x-layout", group="layout", top="/layout"))
    judged["x-layout"] = _owe(expressible=False)
    outcome, figures, _ = decide(report, judged, KILLS)
    check("D19", "R2 lists an ungated owing group even when it is not EXPRESSIBLE, with its flags; an outside "
          "group counts without EXPRESSIBLE beside its count", figures["ungated_owing"] == [
              {"id": "s", "expressible": False, "setup": False}] and figures["N_layout"] == 0
          and figures["outside_without_expressible"]["layout"] == 1)
    return out


def self_test():
    rows = control_rows() + decision_controls()
    failed = [(identifier, description) for identifier, description, ok in rows if not ok]
    for identifier, description in failed:
        print(f"  FAIL {identifier}: {description}")
    print(f"uniquifier census self-test: {len(rows) - len(failed)}/{len(rows)} controls hold")
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
    if len(argv) in (5, 6) and argv[1] == "render":
        path, name, repo = argv[2], argv[3], argv[4]
        text = open(path, encoding="utf-8").read()
        repo_files = subject_files(repo, [repo])[0]
        functions = declarations(text)[1]
        function = next(f for f in functions if f["name"] == name
                        and (len(argv) == 5 or (f["labels"] or [""])[0] == argv[5]))
        defined = {f["name"] for f in functions}
        row = {"repo": os.path.basename(repo), "root": repo, "path": os.path.relpath(os.path.realpath(path), repo),
               "line": function["line"], "owner": function["owner"], "owner_kind": function["owner_kind"],
               "owner_doc": function["owner_doc"], "doc": function["doc"], "text": function["text"],
               "callees": sorted((set(function["calls"]) & defined) - {name}),
               "callers": sorted({f["name"] for f in functions if f is not function and name in f["calls"]}),
               "members": owner_members(repo_files, function["owner"], skip=(os.path.realpath(path), function["line"]))}
        print(render("LABEL", row))
        return 0
    if len(argv) == 3 and argv[1] == "calibrate":
        missed = calibrate(json.load(open(argv[2], encoding="utf-8")))
        print(f"calibration: {'PASS' if not missed else 'MISS ' + ', '.join(missed)}")
        return 0 if not missed else 1
    if len(argv) == 5 and argv[1] == "join":
        index = json.load(open(argv[2], encoding="utf-8"))
        verdicts = collections.defaultdict(dict)
        for name in sorted(os.listdir(argv[3])):
            match = re.match(r"^(packet-\d+)\.([ABC])\.json$", name)
            if match:
                records = json.load(open(os.path.join(argv[3], name), encoding="utf-8"))
                for record in records:
                    label = record.pop("label")
                    if not label.startswith(match.group(1) + "/") or label in verdicts[match.group(2)]:
                        raise SystemExit(f"{name}: label {label} is not this packet's, or repeats")
                    verdicts[match.group(2)][label] = record
        final = join(index, dict(verdicts))
        with open(argv[4], "w", encoding="utf-8") as handle:
            json.dump(final, handle, indent=1, sort_keys=True)
        print(f"{len(final)} judgements → {argv[4]}")
        return 0
    if len(argv) == 5 and argv[1] == "decide":
        report = json.load(open(argv[2], encoding="utf-8"))
        judgements = json.load(open(argv[3], encoding="utf-8"))
        kills = json.load(open(argv[4], encoding="utf-8")) if os.path.exists(argv[4]) else {}
        outcome, figures, lines = decide(report, judgements, kills)
        print("\n".join(lines))
        print(json.dumps(figures, indent=1, sort_keys=True))
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
