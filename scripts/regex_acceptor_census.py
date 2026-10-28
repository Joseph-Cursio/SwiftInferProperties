#!/usr/bin/env python3
"""Which producers build a pattern the module then compiles? — `docs/plans/regex-acceptor-census-scope.md`.

#666's law: for a producer `f` whose result the module passes to a regex acceptor, the caller's
argument expression with `f(x)` in place must compile. This pass starts at each acceptor call — a
call the text can see — and resolves its pattern argument to a producer, because nothing in the
tool tracks a return value into an argument (`CalleeNameCollector` returns `nil` for a member call,
and all three of #666's witness calls are member calls).

Each row is one acceptor call site, with one outcome from scope §1.5. The population is the union,
over all rows, of QUALIFYING elements of the row's scan set. Section numbers below are the scope's.

  --self-test                  the scope's pass controls, C1-C30 (no siblings; joins `make measurement-selftest`)
  run <out.json> NAME=PATH…    census the frozen universe (§2), plus each `upstream` clone given as NAME=PATH
  packets <census.json> <dir> NAME=PATH…   write §5's blind judging packets, one per producer, in seeded order
"""
import collections
import hashlib
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from budgeted_truncation_census import brace_pairs, revision, split_top, subjects  # noqa: E402

KEYWORDS = {
    "if", "guard", "switch", "while", "for", "return", "try", "await", "throw", "case", "catch", "do",
    "let", "var", "in", "is", "as", "where", "else", "repeat", "defer", "self", "Self", "super", "init",
    "true", "false", "nil", "some", "any", "func", "static", "inout", "throws", "rethrows", "async",
    "get", "set", "willSet", "didSet", "lazy", "weak", "unowned", "private", "fileprivate", "internal",
    "public", "open", "package", "mutating", "nonmutating", "override", "final", "class", "struct",
    "enum", "actor", "extension", "protocol", "typealias", "import", "operator", "subscript", "deinit",
}

# §2, frozen on 2026-10-27 from `subjects()` on the machine that runs the census.
FROZEN_UNIVERSE = {
    "manifest": ["swift-infer-core", "swift-format", "grdb", "swift-collections", "swift-syntax", "swift-nio",
                 "swift-package-manager", "swift-numerics", "swift-algorithms", "swift-argument-parser",
                 "swift-foundation", "swiftlang-swift", "harmonize", "swift-project-lint", "swift-property-laws",
                 "swift-effect-inference", "maccloud-client-ios", "swiftlint-rule-studio",
                 "swiftformat-rule-studio", "planted-defect-arm", "cycle27-surface", "leaderboard-sort"],
    "funnel": ["LintStudioUI", "MacCloud_client_MacOS", "MacCloud_server", "pbt-book", "pbt-workbook-corpus",
               "pbt-workbook-grader", "pbt-workbook-sampler", "pbt-workbook", "SwiftAssist", "SwiftCloneDetector",
               "SwiftEffectInference", "SwiftFormatRuleStudio", "SwiftIdempotency", "SwiftLintRuleStudio",
               "SwiftLintRuleStudioTeam", "SwiftMarkdownWiki", "SwiftProjectLint", "SwiftPropertyLaws",
               "SwiftUMLStudio"],
    "unmet": ["Euclid", "swift-docc", "OpenAPIKit", "jwt-kit", "swift-system"],
}
DECISION_GROUPS = ("manifest", "funnel", "upstream")
# §2: the one upstream clone, read through `Sources/` (`Snapshots/` holds other projects' code kept as
# formatting fixtures). The user approved the shallow clone on 2026-10-27.
UPSTREAM = {"SwiftFormat": "75e09c0e"}


# ── Lexing (§1) ────────────────────────────────────────────────────────────────────────────────
#
# `mutation_check.mask` blanks a literal's interpolations along with its text, and #666's witnesses
# put producer calls inside interpolations (`"^\(escaped)$"`), so this pass has its own masker. It
# blanks comments, literal text and regex literals, and KEEPS each interpolation's code, recursively.
# Same length as the input with newlines kept, so an offset into the mask is an offset into the source.

REGEX_START_AFTER = set("([,:={!&|?+-*<>;") | {"\n"}


def mask_code(text, literals=True):
    """With `literals=False`, only comments are blanked: §1.5's vendored-copy identity keeps literal
    text, because a hand-rolled escape class lives in a literal (conformance finding A5)."""
    out = list(text)

    def blank(start, end, literal=False):
        if literal and not literals:
            return
        for index in range(start, end):
            if out[index] != "\n":
                out[index] = " "

    def string(index):
        """`index` is at a literal's first `#` or `"`; return the offset just past it."""
        hashes = 0
        while text[index] == "#":
            hashes += 1
            index += 1
        multi = text.startswith('"""', index)
        quote = '"""' if multi else '"'
        closer = quote + "#" * hashes
        interpolation = "\\" + "#" * hashes + "("
        cursor = segment = index + len(quote)
        while cursor < len(text):
            if text.startswith(closer, cursor):
                blank(segment, cursor, literal=True)
                return cursor + len(closer)
            if not multi and text[cursor] == "\n":
                blank(segment, cursor, literal=True)
                return cursor
            if text.startswith(interpolation, cursor):
                blank(segment, cursor + len(interpolation) - 1, literal=True)
                cursor = code(cursor + len(interpolation), inside=True)
                segment = cursor
                continue
            cursor += 2 if (hashes == 0 and text[cursor] == "\\") else 1
        blank(segment, len(text), literal=True)
        return len(text)

    def previous_token(index):
        cursor = index - 1
        while cursor >= 0 and out[cursor] in " \t":
            cursor -= 1
        if cursor < 0:
            return "\n"
        if out[cursor].isalnum() or out[cursor] == "_":
            start = cursor
            while start > 0 and (out[start - 1].isalnum() or out[start - 1] == "_"):
                start -= 1
            return "".join(out[start:cursor + 1])
        return out[cursor]

    def bare_regex_end(index):
        """The offset past a bare `/…/` literal starting at `index`, or -1 if `/` is an operator."""
        if text[index + 1:index + 2] in ("", " ", "\t", "\n", "/", "*", "="):
            return -1
        before = previous_token(index)
        if before not in REGEX_START_AFTER and before not in ("return", "in", "try", "await"):
            return -1
        cursor, in_class = index + 1, False
        while cursor < len(text) and text[cursor] != "\n":
            char = text[cursor]
            if char == "\\":
                cursor += 2
                continue
            if char == "[":
                in_class = True
            elif char == "]":
                in_class = False
            elif char == "/" and not in_class:
                return cursor + 1
            cursor += 1
        return -1

    def code(index, inside=False):
        """Scan code from `index`; inside an interpolation, stop just past its closing `)`."""
        depth = 0
        while index < len(text):
            char = text[index]
            if text.startswith("//", index):
                end = text.find("\n", index)
                end = len(text) if end < 0 else end
                blank(index, end)
                index = end
            elif text.startswith("/*", index):
                end = text.find("*/", index + 2)
                end = len(text) if end < 0 else end + 2
                blank(index, end)
                index = end
            elif char == '"' or (char == "#" and re.match(r'#+"', text[index:index + 8])):
                index = string(index)
            elif char == "#" and re.match(r"#+/", text[index:index + 8]):
                hashes = len(re.match(r"#+", text[index:]).group(0))
                close = text.find("/" + "#" * hashes, index + hashes + 1)
                end = len(text) if close < 0 else close + 1 + hashes
                blank(index + hashes + 1, max(index + hashes + 1, end - 1 - hashes), literal=True)
                index = end
            elif char == "/" and (end := bare_regex_end(index)) > 0:
                blank(index + 1, end - 1, literal=True)
                index = end
            elif inside and char == "(":
                depth += 1
                index += 1
            elif inside and char == ")":
                if depth == 0:
                    return index + 1
                depth -= 1
                index += 1
            else:
                index += 1
        return index

    code(0)
    return "".join(out)


def balanced(masked):
    """§1: after masking, `()`, `[]` and `{}` must balance, nested properly."""
    stack, partner = [], {")": "(", "]": "[", "}": "{"}
    for char in masked:
        if char in "([{":
            stack.append(char)
        elif char in ")]}":
            if not stack or stack.pop() != partner[char]:
                return False
    return not stack


def matching_paren(masked, open_index):
    depth = 0
    for index in range(open_index, len(masked)):
        char = masked[index]
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
            if depth == 0:
                return index
    return len(masked) - 1


def arguments(masked, open_index):
    """`(label, start, end)` for each top-level argument of the call whose `(` is at `open_index`;
    `_` for an unlabeled one."""
    close = matching_paren(masked, open_index)
    found, depth, start = [], 0, open_index + 1
    for index in range(open_index + 1, close + 1):
        char = masked[index]
        if index == close or (char == "," and depth == 0):
            segment = masked[start:index]
            label = re.match(r"\s*([A-Za-z_]\w*)\s*:(?!:)", segment)
            if label:
                found.append((label.group(1), start + label.end(), index))
            elif segment.strip():
                found.append(("_", start + len(segment) - len(segment.lstrip()), index))
            start = index + 1
        elif char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
    return found


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


def previous_char(masked, index):
    cursor = index - 1
    while cursor >= 0 and masked[cursor] in " \t\n":
        cursor -= 1
    return masked[cursor] if cursor >= 0 else ""


def next_char(masked, index):
    cursor = index
    while cursor < len(masked) and masked[cursor] in " \t\n":
        cursor += 1
    return masked[cursor] if cursor < len(masked) else ""


# ── Declarations (§1.3, §1.4) ──────────────────────────────────────────────────────────────────

TYPE_DECL = re.compile(r"\b(struct|class|enum|actor|extension|protocol)\s+([A-Za-z_][\w.]*)")
FUNC_DECL = re.compile(r"\bfunc\s+([A-Za-z_]\w*|`[^`]+`)\s*")
INIT_DECL = re.compile(r"(?<![\w.])init\s*[?!]?\s*")
SUBSCRIPT_DECL = re.compile(r"(?<![\w.])subscript\s*")
COMPUTED_DECL = re.compile(r"\bvar\s+([A-Za-z_]\w*)\s*:\s*([^={}\n]+?)\s*\{")
MEMBER_PROPERTY = re.compile(r"\b(?:let|var)\s+([A-Za-z_]\w*)\b")
VISIBILITY = re.compile(r"\b(public|open|package|internal|fileprivate|private)\b")
REGEX_TYPE = re.compile(r"\b(?:struct|class|enum|actor|typealias)\s+Regex\b")
IF_DIRECTIVE = re.compile(r"^[ \t]*#(if|elseif|else|endif)\b", re.MULTILINE)
RECEIVER_TYPES = {"String", "StringProtocol", "Substring", "Character"}
STRING_RESULTS = {"String", "String?"}
STRING_PARAMS = {"String", "Substring", "Character", "String?", "[String]", "String...", "some StringProtocol"}


def angle_end(masked, index):
    """The offset of the `>` closing the `<` at `index`, or -1."""
    depth = 0
    for cursor in range(index, len(masked)):
        char = masked[cursor]
        if char == "<":
            depth += 1
        elif char == ">" and masked[cursor - 1] != "-":
            depth -= 1
            if depth == 0:
                return cursor
        elif char in "{};":
            return -1
    return -1


def plain_type(text):
    text = " ".join(text.split())
    text = re.sub(r"^(?:@\w+(?:\([^)]*\))?\s*|inout\s+|__owned\s+|__shared\s+|borrowing\s+|consuming\s+"
                  r"|sending\s+)+", "", text)
    return re.sub(r"\bSwift\.", "", text).strip()


def parameter_list(text):
    """`(label, internal, type, defaulted)` for each parameter in a declaration's list."""
    found = []
    for part in split_top(text):
        depth, colon = 0, -1
        for index, char in enumerate(part):
            if char in "([<{":
                depth += 1
            elif char in ")]>}":
                depth -= 1
            elif char == ":" and depth == 0:
                colon = index
                break
        if colon < 0:
            continue
        names = part[:colon].split()
        if not names:
            continue
        label, internal = (names[0], names[-1]) if len(names) > 1 else (names[0], names[0])
        kind, defaulted = part[colon + 1:], False
        depth = 0
        for index, char in enumerate(kind):
            if char in "([<{":
                depth += 1
            elif char in ")]>}":
                depth -= 1
            elif char == "=" and depth == 0 and kind[index + 1:index + 2] != "=":
                kind, defaulted = kind[:index], True
                break
        found.append((label, internal, plain_type(kind), defaulted))
    return found


def doc_comment(text, offset):
    """The `///` lines directly above the declaration line at `offset`."""
    line_start = text.rfind("\n", 0, offset) + 1
    lines, cursor = [], line_start - 1
    while cursor > 0:
        previous = text.rfind("\n", 0, cursor) + 1
        line = text[previous:cursor].strip()
        if line.startswith("///"):
            lines.append(line[3:].strip())
        elif line.startswith("@") or (line == "" and not lines):
            pass
        else:
            break
        cursor = previous - 1
    return " ".join(reversed(lines))


class SourceFile:
    """One file's masked text, brace pairs, type spans, `#if` arms, declarations and scopes."""

    def __init__(self, path, text):
        self.path, self.text = path, text
        self.masked = mask_code(text)
        self.uncommented = mask_code(text, literals=False)
        self.parsed = balanced(self.masked)
        self.pairs = brace_pairs(self.masked)
        self.types, self.decls, self.scopes, self.properties = [], [], [], []
        self.arms = self._if_arms()
        if not self.parsed:
            return
        for match in TYPE_DECL.finditer(self.masked):
            brace = self.masked.find("{", match.end())
            if brace < 0 or self.masked[match.end():brace].count("\n") > 3 or ";" in self.masked[match.end():brace]:
                continue
            visibility = VISIBILITY.findall(self._modifiers(match.start()))
            self.types.append((match.start(), brace, self.pairs.get(brace, len(self.masked) - 1),
                               match.group(1), match.group(2).split(".")[-1], visibility[-1] if visibility else ""))
        self._functions()
        self._computed()
        self._member_properties()

    def _if_arms(self):
        """`[(start, end, group, arm)]` for every `#if` arm, so same-named arms can be told apart."""
        arms, stack, counter = [], [], 0
        for match in IF_DIRECTIVE.finditer(self.masked):
            kind = match.group(1)
            if kind == "if":
                counter += 1
                stack.append([counter, 0, match.end()])
            elif stack and kind in ("elseif", "else"):
                group, arm, start = stack[-1]
                arms.append((start, match.start(), group, arm))
                stack[-1] = [group, arm + 1, match.end()]
            elif stack:
                group, arm, start = stack.pop()
                arms.append((start, match.start(), group, arm))
        return arms

    def arm(self, offset):
        holding = [arm for arm in self.arms if arm[0] <= offset < arm[1]]
        return min(holding, key=lambda arm: arm[1] - arm[0])[2:] if holding else None

    def owner(self, offset):
        holding = self.owners(offset)
        return holding[0] if holding else None

    def owners(self, offset):
        """Every type span holding `offset`, innermost first."""
        return sorted((span for span in self.types if span[1] < offset < span[2]), key=lambda span: span[2] - span[1])

    def visibility(self, start):
        """An explicit modifier, else `private`/`fileprivate` from ANY enclosing type, else the
        innermost type's (§1.3; conformance finding P14)."""
        explicit = VISIBILITY.findall(self._modifiers(start))
        if explicit:
            return explicit[-1]
        owners = self.owners(start)
        restricted = next((span[5] for span in owners if span[5] in ("private", "fileprivate")), None)
        return restricted or (owners[0][5] if owners else "")

    def member_level(self, position):
        """A `let`/`var` directly in a type body or at file scope is a property, never a binding (§1.2)."""
        blocks = self.blocks(position)
        owner = self.owner(position)
        return not blocks or (owner is not None and blocks[0] == (owner[1], owner[2]))

    def _modifiers(self, start):
        line_start = self.masked.rfind("\n", 0, start) + 1
        return self.masked[line_start:start]

    def _record(self, kind, name, params, result, generics, start, brace, end):
        owner = self.owner(start)
        modifiers = self._modifiers(start)
        self.decls.append({
            "kind": kind, "name": name, "params": params, "result": result, "generics": generics,
            "file": self.path, "offset": start, "line": line_of(self.text, start), "open": brace, "close": end,
            "static": bool(re.search(r"\b(static|class)\b", modifiers)),
            "visibility": self.visibility(start),
            "owner_kind": owner[3] if owner else "", "owner_name": owner[4] if owner else "",
            "owner_span": (owner[1], owner[2]) if owner else None,
            "doc": doc_comment(self.text, start), "arm": self.arm(start),
            "body_key": " ".join(self.uncommented[brace + 1:end].split()),
        })

    def _functions(self):
        for regex, kind in ((FUNC_DECL, "func"), (INIT_DECL, "init"), (SUBSCRIPT_DECL, "subscript")):
            for match in regex.finditer(self.masked):
                cursor = match.end()
                generics = ""
                if self.masked[cursor:cursor + 1] == "<":
                    end = angle_end(self.masked, cursor)
                    if end < 0:
                        continue
                    generics, cursor = self.masked[cursor:end + 1], end + 1
                while cursor < len(self.masked) and self.masked[cursor] in " \t":
                    cursor += 1
                if self.masked[cursor:cursor + 1] != "(":
                    continue
                close = matching_paren(self.masked, cursor)
                brace = self.masked.find("{", close)
                if brace < 0:
                    continue
                tail = self.masked[close + 1:brace]
                if tail.count("\n") > 4 or any(token in tail for token in (";", "}", "func ", " var ", " let ")):
                    continue
                result = tail.split("->", 1)[1] if "->" in tail else ""
                where = re.split(r"\bwhere\b", result)
                constraints = generics + (where[1] if len(where) > 1 else "")
                result = plain_type(re.sub(r"\b(async|throws|rethrows)\b", "", where[0]))
                params = parameter_list(self.masked[cursor + 1:close])
                end = self.pairs.get(brace, len(self.masked) - 1)
                self.scopes.append({"start": match.start(), "open": brace, "close": end,
                                    "params": [internal for _, internal, _, _ in params],
                                    "throws": bool(re.search(r"\b(throws|rethrows)\b", tail)),
                                    "name": match.group(1).strip("`") if kind == "func" else kind})
                if kind == "func":
                    self._record("func", match.group(1).strip("`"), params, result, constraints,
                                 match.start(), brace, end)

    def _computed(self):
        for match in COMPUTED_DECL.finditer(self.masked):
            brace = match.end() - 1
            end = self.pairs.get(brace, len(self.masked) - 1)
            body = self.masked[brace + 1:end].strip()
            if not body or re.match(r"(get\s*(set\s*)?\}?$|willSet|didSet|get\s+set)", body):
                continue
            self.scopes.append({"start": match.start(), "open": brace, "close": end, "params": [],
                                "throws": False, "name": match.group(1)})
            self._record("property", match.group(1), [], plain_type(match.group(2)), "", match.start(), brace, end)

    def _member_properties(self):
        """Every property declared outside a function body, of any kind — §1.3's ambiguity count."""
        for match in MEMBER_PROPERTY.finditer(self.masked):
            if self.scope(match.start()) is None and self.member_level(match.start()):
                self.properties.append({"name": match.group(1), "file": self.path, "offset": match.start(),
                                        "visibility": self.visibility(match.start()), "arm": self.arm(match.start())})

    def scope(self, offset):
        holding = [scope for scope in self.scopes if scope["open"] < offset < scope["close"]]
        return min(holding, key=lambda scope: scope["close"] - scope["open"]) if holding else None

    def blocks(self, offset):
        """`(open, close)` of every brace block holding `offset`, innermost first."""
        return sorted(((opener, closer) for opener, closer in self.pairs.items() if opener < offset < closer),
                      key=lambda pair: pair[1] - pair[0])


# ── Acceptor calls (§1.1) ──────────────────────────────────────────────────────────────────────

NS_ACCEPTOR = re.compile(r"(?<![\w.])NSRegularExpression\s*(?:\.\s*init\s*)?\(")
REGEX_NAME = re.compile(r"(?<![\w.])Regex\b")
SILENT_CALL = re.compile(r"(?<![\w$])([A-Za-z_]\w*)\s*\(\s*of\s*:")


def acceptor_calls(masked, regex_is_stdlib=True):
    """`(acceptor, call start, pattern start, pattern end, options)` for every acceptor call."""
    found = []
    for match in NS_ACCEPTOR.finditer(masked):
        args = arguments(masked, match.end() - 1)
        if args and args[0][0] == "pattern":
            options = next((masked[start:end] for label, start, end in args if label == "options"), "")
            found.append(("NSRegularExpression", match.start(), args[0][1], args[0][2], " ".join(options.split())))
    for match in REGEX_NAME.finditer(masked) if regex_is_stdlib else ():
        cursor = match.end()
        generic = ""
        while cursor < len(masked) and masked[cursor] in " \t":
            cursor += 1
        if masked[cursor:cursor + 1] == "<":
            end = angle_end(masked, cursor)
            if end < 0:
                continue
            generic, cursor = masked[cursor:end + 1], end + 1
        opener = re.match(r"\s*(?:\.\s*init\s*)?\(", masked[cursor:])
        if not opener:
            continue
        args = arguments(masked, cursor + opener.end() - 1)
        if not args or args[0][0] != "_":
            continue
        if re.fullmatch(r"#*/\s*/#*", masked[args[0][1]:args[0][2]].strip()):
            continue  # a regex literal: the masker blanks its body and keeps its delimiters
        as_type = next((" ".join(masked[start:end].split()) for label, start, end in args if label == "as"), "")
        found.append(("Regex" + " ".join(generic.split()) + (f"(as: {as_type})" if as_type else ""),
                      match.start(), args[0][1], args[0][2], ""))
    for match in SILENT_CALL.finditer(masked):
        args = arguments(masked, masked.index("(", match.start()))
        options = [masked[start:end] for label, start, end in args if label == "options"]
        if args and args[0][0] == "of" and options and "regularExpression" in options[0]:
            found.append((f"silent:{match.group(1)}", match.start(), args[0][1], args[0][2],
                          " ".join(options[0].split())))
    return sorted(found, key=lambda call: call[1])


def unmatched_spellings(source):
    """R3: acceptor spellings §1.1 does not match."""
    bare_init = len(re.findall(r"(?<![\w])\.\s*init\s*\(\s*pattern\s*:", source.masked))
    predicates = 0
    for match in re.finditer(r"(?<![\w.])NSPredicate\s*\(\s*format\s*:", source.masked):
        close = matching_paren(source.masked, source.masked.index("(", match.start()))
        if "MATCHES" in source.text[match.start():close]:
            predicates += 1
    option_identifiers = 0
    for match in SILENT_CALL.finditer(source.masked):
        args = arguments(source.masked, source.masked.index("(", match.start()))
        options = [source.masked[start:end].strip() for label, start, end in args if label == "options"]
        if args and args[0][0] == "of" and options and re.fullmatch(r"[a-z_][\w.]*", options[0]):
            option_identifiers += 1
    return {"bare_init_pattern": bare_init, "nspredicate_matches": predicates,
            "silent_option_identifier": option_identifiers}


def acceptor_spellings(masked):
    """How many acceptor spellings an UNPARSED file holds — reported, never classified."""
    return (len(NS_ACCEPTOR.findall(masked)) + len(re.findall(r"(?<![\w.])Regex\s*(?:<[^>\n]*>)?\s*\(", masked))
            + len(re.findall(r"\boptions\s*:[^)\n]*regularExpression", masked)))


# ── The value that reaches the call (§1.2) ─────────────────────────────────────────────────────

CALL_TOKEN = re.compile(r"(?<![\w$])([A-Za-z_]\w*)\s*(?=\()")
IDENTIFIER = re.compile(r"(?<![\w$])(\$\d+|[A-Za-z_]\w*)\b")
MEMBER_READ = re.compile(r"\.\s*([a-z_]\w*)\b(?!\s*\()")
UNAPPLIED = re.compile(r"\.\s*(?:map|compactMap|flatMap)\s*\(\s*(?:[A-Z]\w*\s*\.\s*)?([a-z_]\w*)\s*"
                       r"(\((?:[A-Za-z_]\w*:)+\))?\s*\)")
MUTATING = ("append", "insert", "remove", "removeAll", "removeFirst", "removeLast", "removeSubrange",
            "replaceSubrange", "popLast", "trimPrefix", "replace", "sort", "reverse", "shuffle")


def excluded_regions(masked, start, end):
    """§1.2: `escapedPattern(for:)`'s argument list, and subscript brackets."""
    regions = []
    for match in re.finditer(r"escapedPattern\s*\(", masked[start:end]):
        open_index = start + match.end() - 1
        regions.append((open_index, matching_paren(masked, open_index)))
    for index in range(start, end):
        if masked[index] == "[" and index > 0 and re.match(r"[\w)\]?!]", masked[index - 1]):
            regions.append((index, matching_paren(masked, index)))
    return regions


def inside(regions, offset):
    return any(opener < offset < closer for opener, closer in regions)


def calls_in(masked, start, end, regions=()):
    """`{name, labels, member, offset, trailing}` for each call in `masked[start:end]`."""
    found = []
    for match in CALL_TOKEN.finditer(masked, start, end):
        name = match.group(1)
        if name in KEYWORDS or inside(regions, match.start()):
            continue
        member = previous_char(masked, match.start()) == "."
        if not member and name[0].isupper():
            continue  # a type's initializer is a conversion, not a producer
        open_index = masked.index("(", match.end())
        close = matching_paren(masked, open_index)
        labels = [label for label, _, _ in arguments(masked, open_index)]
        found.append({"name": name, "labels": labels, "member": member, "offset": match.start(),
                      "trailing": next_char(masked, close + 1) == "{"})
    for match in UNAPPLIED.finditer(masked, start, end):
        if inside(regions, match.start()):
            continue
        labels = re.findall(r"([A-Za-z_]\w*):", match.group(2)) if match.group(2) else ["_"]
        found.append({"name": match.group(1), "labels": labels, "member": True, "offset": match.start(1),
                      "trailing": False})
    return found


def call_argument_spans(masked, start, end):
    """Argument lists of lowercase (function) calls; a type initializer's are followed through."""
    spans = []
    for match in CALL_TOKEN.finditer(masked, start, end):
        if match.group(1)[0].islower() and match.group(1) not in KEYWORDS:
            open_index = masked.index("(", match.end())
            spans.append((open_index, matching_paren(masked, open_index)))
    return spans


def statement_end(masked, start, stop_at_brace):
    """Where a binding's initializer starting at `start` ends (§1.2)."""
    depth, index = 0, start
    while index < len(masked):
        char = masked[index]
        if char == "{" and depth == 0 and stop_at_brace:
            return index
        if char in "([{":
            depth += 1
        elif char in ")]}":
            if depth == 0:
                return index
            depth -= 1
        elif depth == 0 and char in ";,":
            return index
        elif depth == 0 and char == "\n":
            before = masked[start:index].rstrip()
            after = masked[index + 1:].lstrip()
            continues = re.search(r"(?:[=+\-*/|&?:(]|\b(?:try|await))$", before) is not None \
                or after.startswith((".", "+", "-", "*", "/", "|", "&", "?", ":"))
            if not continues:
                return index
        elif depth == 0 and masked.startswith("else", index) and not re.match(r"\w", masked[index - 1]) \
                and not re.match(r"\w", masked[index + 4:index + 5] or " "):
            return index
        index += 1
    return index


def visible(source, position, offset):
    """A binding at `position` is visible at `offset` when every block holding it also holds `offset`."""
    return all(opener < offset < closer for opener, closer in source.pairs.items() if opener < position < closer)


def binding(source, scope, offset, name):
    """The nearest visible binding of `name` before `offset`: `(keyword, spans, end)`, or `None`.

    `spans` is the initializer, or for a deferred `let v: T`, every later `v = I` before `offset`."""
    masked = source.masked
    region_start = scope["open"] if scope else 0
    pattern = re.compile(rf"\b(?:(if|guard|while)\s+)?(let|var)\s+{re.escape(name)}\b\s*(:[^=\n{{]+?)?(=(?!=)|(?=\s*(?:\n|;)))")
    last = None
    for match in pattern.finditer(masked, region_start, offset):
        if visible(source, match.start(), offset) and not source.member_level(match.start()):
            last = match
    if last is None:
        return None
    keyword = last.group(2)
    if last.group(4):
        start = last.end()
        while start < len(masked) and masked[start] in " \t":
            start += 1
        in_condition = bool(last.group(1)) or bool(
            re.search(r"\b(?:if|guard|while)\b[^{};]*$", masked[region_start:last.start()]))
        end = statement_end(masked, start, stop_at_brace=in_condition)
        return keyword, [(start, end)], end, last.start()
    spans = []
    for match in re.finditer(rf"(?<![\w.]){re.escape(name)}\s*=(?!=)\s*", masked[last.end():offset]):
        start = last.end() + match.end()
        spans.append((start, statement_end(masked, start, stop_at_brace=False)))
    return keyword, spans, last.end(), last.start()


def mutations(source, name, binding_end, offset):
    """Spans of `name`'s mutations that §1.2 counts against a `var` binding ending at `binding_end`."""
    masked = source.masked
    regions = [(binding_end, offset)]
    for opener, closer in source.blocks(offset):
        if opener > binding_end:
            header = masked[masked.rfind("\n", 0, opener) + 1:opener]
            if re.search(r"\b(for|while|repeat)\b", header):
                regions.append((opener, closer))
    found = []
    pattern = re.compile(rf"(?<![\w.]){re.escape(name)}\s*(?:[-+*/%&|^]|<<|>>)?=(?!=)|&{re.escape(name)}\b"
                         rf"|(?<![\w.]){re.escape(name)}\s*\.\s*(?:{'|'.join(MUTATING)})\s*[({{]")
    for start, end in regions:
        for match in pattern.finditer(masked, start, end):
            found.append((match.start(), statement_end(masked, match.end(), stop_at_brace=False)))
    return found


def reaching_value(source, offset, start, end):
    """§1.2: the scan set for the pattern argument at `masked[start:end]`, the marks, what was followed,
    and the spans of any rewritten `var` (its initializer and mutations, for R5).

    A frontier entry is `(start, end, depth, limit, quiet)`. `limit` is the offset bindings must start
    before: the acceptor's own position for `E`, the binding's start inside a followed initializer, so
    `guard let v = v` resolves its inner `v` to the outer one. A `quiet` entry was reached through a
    call's receiver or argument: its calls and member reads join `S`, and nothing in it marks the row
    or becomes a bare property read."""
    masked, scope = source.masked, source.scope(offset)
    elements, marks, chased, rewritten = [], set(), [], []
    frontier, seen = [(start, end, 0, None, False)], set()
    while frontier:
        span_start, span_end, depth, limit, quiet = frontier.pop()
        regions = excluded_regions(masked, span_start, span_end)
        elements.extend(calls_in(masked, span_start, span_end, regions))
        for match in MEMBER_READ.finditer(masked, span_start, span_end):
            if not inside(regions, match.start()):
                elements.append({"name": match.group(1), "labels": None, "member": True, "offset": match.start(1),
                                 "trailing": False})
        argument_spans = call_argument_spans(masked, span_start, span_end)
        for match in IDENTIFIER.finditer(masked, span_start, span_end):
            name = match.group(1)
            if name in KEYWORDS or inside(regions, match.start()) or previous_char(masked, match.start()) == ".":
                continue
            after = masked[match.end():].lstrip(" \t\n")
            if name[0].isupper() and re.match(r"[(.<]", after):
                continue  # a type, or a call of one
            if after.startswith(":") and not after.startswith("::") and previous_char(masked, match.start()) in "(,[":
                continue  # an argument label or a dictionary key
            if re.match(r"\?(?![?.\[])", after):
                continue  # a ternary's condition
            receiver = re.match(r"[?!]?\s*[.(]", after) is not None
            entry_quiet = quiet or receiver or inside(argument_spans, match.start())
            position = match.start() if limit is None else limit
            if (name, position, entry_quiet) in seen:
                continue
            seen.add((name, position, entry_quiet))
            bound = binding(source, scope, position, name) if not name.startswith("$") else None
            if bound:
                keyword, spans, binding_end, binding_start = bound
                if keyword == "var" and spans and (mutated := mutations(source, name, binding_end, offset)):
                    if not entry_quiet:
                        marks.add("REWRITTEN")
                        chased.append(f"{name}: var, mutated")
                        rewritten.extend(spans + mutated)
                    continue
                chased.append(f"{name}: {keyword}" + (" (through a receiver or argument)" if entry_quiet else ""))
                if depth < 3:
                    frontier.extend((span[0], span[1], depth + 1, binding_start, entry_quiet) for span in spans)
            elif entry_quiet:
                continue
            elif scope and name in scope["params"]:
                marks.add("WRAPPER")
                chased.append(f"{name}: parameter of {scope['name']}")
            else:
                elements.append({"name": name, "labels": None, "member": False, "offset": match.start(),
                                 "trailing": False})
    return elements, marks, chased, rewritten


# ── Resolution and producers (§1.3, §1.4) ──────────────────────────────────────────────────────

THREE = ("replacingOccurrences", "replacing", "stringByReplacingMatches", "map", "flatMap", "compactMap",
         "reduce", "forEach", "unicodeScalars", "utf8", "utf16", "indices", "startIndex", "endIndex")
WIDE = ("filter", "components", "split", "trimmingCharacters", "addingPercentEncoding", "applyingTransform",
        "lowercased", "uppercased")
STANDARD_NAMES = set(THREE) | set(WIDE) | {"joined", "escapedPattern"}
KIND_RANK = {"three": 3, "wide": 2, "escape-only": 1}


def labels_match(call, params):
    labels, cursor = call["labels"], 0
    trailing = call.get("trailing", False)
    for label, _, kind, defaulted in params:
        if cursor < len(labels) and labels[cursor] == label:
            cursor += 1
            if kind.endswith("..."):
                while cursor < len(labels) and labels[cursor] == "_":
                    cursor += 1
        elif trailing and "->" in kind:
            trailing = False
        elif not defaulted:
            return False
    return cursor == len(labels)


def one_per_arm(candidates):
    """§1.3: same name and labels in different arms of one `#if` group count as one."""
    if len(candidates) > 1 and len({decl["file"] for decl in candidates}) == 1:
        arms = [decl["arm"] for decl in candidates]
        if all(arms) and len({arm[0] for arm in arms}) == 1 and len({arm[1] for arm in arms}) == len(arms):
            return candidates[:1]
    return candidates


def visible_from(decl, path):
    return decl["visibility"] not in ("private", "fileprivate") or decl["file"] == path


def resolve(element, index, path):
    """`(status, candidates)`: `resolved`, `external` or `ambiguous` (§1.3)."""
    name = element["name"]
    if name in STANDARD_NAMES:
        return "external", []
    if element["labels"] is None:
        properties = [prop for prop in index["properties"].get(name, []) if visible_from(prop, path)]
        computed = one_per_arm([decl for decl in index["decls"].get(name, [])
                                if decl["kind"] == "property" and visible_from(decl, path)])
        if not computed:
            return "external", []
        if len(one_per_arm(properties)) > 1 or len(computed) > 1:
            return "ambiguous", computed
        return "resolved", computed[:1]
    candidates = one_per_arm([decl for decl in index["decls"].get(name, [])
                              if decl["kind"] == "func" and visible_from(decl, path)
                              and labels_match(element, decl["params"])])
    if not candidates:
        return "external", []
    return ("resolved" if len(candidates) == 1 else "ambiguous"), candidates


def string_inputs(decl):
    """§1.4: every String-family parameter name (PARAM), or `["self"]` (RECEIVER), or `[]`."""
    names = []
    for _, internal, kind, _ in decl["params"]:
        generic = re.fullmatch(r"[A-Z]\w*", kind) and re.search(rf"\b{kind}\s*:\s*StringProtocol\b", decl["generics"])
        if kind in STRING_PARAMS or generic:
            names.append(internal)
    if not decl["static"] and decl["owner_kind"] == "extension" and decl["owner_name"] in RECEIVER_TYPES:
        return "RECEIVER", ["self"] + names
    if names:
        return "PARAM", names
    return "OTHER-INPUT", []


IMPLICIT = re.compile(r"(?<![\w.$])(" + "|".join(THREE + WIDE) + r")\b(?!\s*:)")


def direct_evidence(decl, sources):
    """§1.4's loose rule: an input is read and a listed operation appears. `(kind, text)` or `None`."""
    body = sources[decl["file"]].masked[decl["open"] + 1:decl["close"]]
    input_kind, names = string_inputs(decl)
    if input_kind == "OTHER-INPUT":
        return None
    implicit = IMPLICIT.search(body)
    reads = any(re.search(rf"(?<![\w.$]){re.escape(name)}\b", body) for name in names if name != "self")
    if "self" in names:
        reads = reads or bool(re.search(r"\bself\b", body)) or implicit is not None
    if not reads:
        return None
    found = {}
    for name in names:
        hit = re.search(rf"\bin\s+{re.escape(name)}\b|(?<![\w.$]){re.escape(name)}\s*\[", body)
        if hit:
            found.setdefault("three", hit.group(0))
    if implicit:
        found.setdefault("three" if implicit.group(1) in THREE else "wide", implicit.group(1))
    for kind, names_ in (("three", THREE), ("wide", WIDE)):
        hit = re.search(r"\.\s*(" + "|".join(names_) + r")\b", body)
        if hit:
            found.setdefault(kind, hit.group(0))
    hit = re.search(r"escapedPattern\s*\(\s*for\s*:", body)
    if hit:
        found.setdefault("escape-only", hit.group(0))
    if not found:
        return None
    kind = max(found, key=lambda key: KIND_RANK[key])
    return kind, " ".join(found[kind].split())


def classify_producers(index, sources):
    """Every producer's input and evidence. Passing an input to a resolved subject producer, by call
    or property read, is delegation at one level and takes that producer's direct kind (§1.4).
    `delegates` lists every delegate whose direct kind is #666's three, for §8's thin-wrapper merge."""
    facts = {}
    for decls in index["decls"].values():
        for decl in decls:
            if decl["result"] not in STRING_RESULTS:
                continue
            input_kind, names = string_inputs(decl)
            evidence = direct_evidence(decl, sources)
            facts[id(decl)] = {"input": input_kind, "inputs": names, "evidence": evidence,
                               "direct_kind": evidence[0] if evidence else None, "delegates": []}
    for decls in index["decls"].values():
        for decl in decls:
            fact = facts.get(id(decl))
            if not fact or fact["input"] == "OTHER-INPUT":
                continue
            source = sources[decl["file"]]
            reads_ = [{"name": match.group(1), "labels": None, "member": True, "offset": match.start(1),
                       "trailing": False}
                      for match in MEMBER_READ.finditer(source.masked, decl["open"] + 1, decl["close"])]
            for call in calls_in(source.masked, decl["open"] + 1, decl["close"]) + reads_:
                status, targets = resolve(call, index, decl["file"])
                if status != "resolved" or targets[0] is decl:
                    continue
                target = facts.get(id(targets[0]))
                if not target or target["input"] == "OTHER-INPUT" or not target["direct_kind"]:
                    continue
                passed = ""
                if call["labels"] is not None:
                    open_index = source.masked.index("(", call["offset"])
                    passed = source.masked[open_index:matching_paren(source.masked, open_index) + 1]
                receiver = re.search(r"([A-Za-z_]\w*)\s*[?!]?\s*\.\s*$",
                                     source.masked[max(0, call["offset"] - 80):call["offset"]])
                reads = any(re.search(rf"\b{re.escape(name)}\b", passed) for name in fact["inputs"]) \
                    or (receiver is not None and receiver.group(1) in fact["inputs"]) \
                    or ("self" in fact["inputs"] and not call["member"])
                if not reads:
                    continue
                kind = target["direct_kind"]
                if kind == "three":
                    fact["delegates"].append((targets[0]["file"], targets[0]["offset"]))
                own = fact["evidence"]
                if own is None or KIND_RANK[kind] > KIND_RANK[own[0]]:
                    fact["evidence"] = (kind, f"delegates to {targets[0]['name']}")
    return facts


# ── Rows (§1.5) ────────────────────────────────────────────────────────────────────────────────

def statement_start(masked, offset, floor):
    depth, index = 0, offset - 1
    while index > floor:
        char = masked[index]
        if char in ")]":
            depth += 1
        elif char in "([" and depth > 0:
            depth -= 1
        elif char in "{};" and depth == 0:
            return index + 1
        elif char == "\n" and depth == 0:
            before = masked[floor + 1:index].rstrip()
            after = masked[index + 1:offset].lstrip()
            continues = before.endswith(("=", "+", "(", ",", "?", ":", "try", "try?", "try!", "await", "return")) \
                or after.startswith((".", "+", "?", ":"))
            if not continues:
                return index + 1
        index -= 1
    return floor + 1


def handling(source, acceptor, offset):
    if acceptor.startswith("silent:"):
        return "SILENT"
    masked, scope = source.masked, source.scope(offset)
    floor = scope["open"] if scope else -1
    tries = list(re.finditer(r"\btry\b([?!]?)", masked[statement_start(masked, offset, floor):offset]))
    if not tries:
        return "UNKNOWN"
    mark = tries[-1].group(1)
    if mark == "?":
        return "HANDLES-NIL"
    if mark == "!":
        return "ASSERTS"
    for opener, closer in source.blocks(offset):
        if opener <= floor:
            break
        if re.search(r"\bdo\s*$", masked[max(0, opener - 12):opener]) and \
                masked[closer + 1:closer + 40].lstrip().startswith("catch"):
            return "HANDLES-CATCH"
    return "PROPAGATES" if scope and scope["throws"] else "UNKNOWN"


ORDER = ("QUALIFYING", "COMBINATOR", "OTHER-INPUT", "AMBIGUOUS")


def qualifies(fact):
    return bool(fact["evidence"]) and fact["input"] != "OTHER-INPUT"


def classify_element(element, index, facts, path):
    status, candidates = resolve(element, index, path)
    record = {"name": element["name"], "labels": element["labels"], "status": status}
    if status == "ambiguous":
        producing = [decl for decl in candidates if id(decl) in facts]
        if not producing:
            record["class"] = "EXTERNAL"
            return record
        record["class"] = "AMBIGUOUS"
        record["candidates"] = [{"name": decl["name"], "file": decl["file"], "line": decl["line"],
                                 "owner": decl["owner_name"], "qualifies": qualifies(facts[id(decl)])}
                                for decl in producing]
        return record
    if status != "resolved" or id(candidates[0]) not in facts:
        record["class"] = "EXTERNAL" if status == "external" else "NOT-PRODUCER"
        return record
    decl, fact = candidates[0], facts[id(candidates[0])]
    record["class"] = "OTHER-INPUT" if fact["input"] == "OTHER-INPUT" else (
        "QUALIFYING" if fact["evidence"] else "COMBINATOR")
    record["decl"] = decl
    return record


def classify_row(source, acceptor, offset, start, end, options, index, facts):
    elements, marks, chased, rewritten = reaching_value(source, offset, start, end)
    classified = [classify_element(element, index, facts, source.path) for element in elements]
    classes = {record["class"] for record in classified}
    if "ignoreMetacharacters" in options:
        outcome = "LITERAL-MODE"
    elif any(cls in classes for cls in ORDER):
        outcome = next(cls for cls in ORDER if cls in classes)
    elif "REWRITTEN" in marks:
        outcome = "REWRITTEN"
    elif "WRAPPER" in marks:
        outcome = "WRAPPER"
    elif any(element["labels"] is not None for element in elements):
        outcome = "EXTERNAL"
    elif not elements:
        outcome = "LITERAL"
    else:
        outcome = "STORED"
    return {"outcome": outcome, "acceptor": acceptor, "options": options,
            "handling": handling(source, acceptor, offset), "argument": " ".join(source.text[start:end].split()),
            "chased": chased, "elements": classified, "rewritten_spans": rewritten}


def producer_key(decl):
    return (decl["file"], decl["offset"])


def describe(decl, fact):
    return {"name": decl["name"], "kind": decl["kind"], "file": decl["file"], "line": decl["line"],
            "offset": decl["offset"], "owner": decl["owner_name"], "visibility": decl["visibility"],
            "labels": [label for label, _, _, _ in decl["params"]], "input": fact["input"], "inputs": fact["inputs"],
            "evidence_kind": fact["evidence"][0] if fact["evidence"] else None,
            "evidence": fact["evidence"][1] if fact["evidence"] else None,
            "direct_kind": fact["direct_kind"], "delegates": [list(item) for item in fact["delegates"]],
            "doc": decl["doc"],
            "body_key": hashlib.sha1(
                f"{decl['name']}|{[label for label, _, _, _ in decl['params']]}|{decl['body_key']}".encode()
            ).hexdigest()[:16]}


def wrapped_translator(decl, sources, row):
    """R6: does the OTHER-INPUT producer apply a listed operation while reading a stored `String`
    property declared in its own type?"""
    body = sources[decl["file"]].masked[decl["open"] + 1:decl["close"]]
    operation = re.search(r"\.\s*(" + "|".join(THREE + WIDE) + r")\b", body)
    stored = []
    for source in sources.values():
        for span in source.types:
            if span[4] == decl["owner_name"]:
                owner_text = source.masked[span[1]:span[2]]
                stored += re.findall(r"\b(?:let|var)\s+([A-Za-z_]\w*)\s*:\s*String\b(?!\??\s*\{)", owner_text)
    reads = sorted({name for name in stored if re.search(rf"(?<![\w$]){re.escape(name)}\b", body)})
    return {"file": row["file"], "line": row["line"], "producer": decl["name"], "producer_file": decl["file"],
            "producer_line": decl["line"], "applies_operation": bool(operation), "reads_stored_string": reads,
            "wrapped_translator": bool(operation and reads)}


def census(files):
    """Every acceptor row, the producers, and the mechanical recall probes over one subject's files."""
    sources = {path: SourceFile(path, text) for path, text in files.items()}
    unparsed = [{"file": path, "acceptor_spellings": acceptor_spellings(source.masked)}
                for path, source in sources.items() if not source.parsed]
    parsed = {path: source for path, source in sources.items() if source.parsed}
    index = {"decls": collections.defaultdict(list), "properties": collections.defaultdict(list)}
    for source in parsed.values():
        for decl in source.decls:
            index["decls"][decl["name"]].append(decl)
        for prop in source.properties:
            index["properties"][prop["name"]].append(prop)
    facts = classify_producers(index, parsed)
    regex_is_stdlib = not any(REGEX_TYPE.search(source.masked) for source in parsed.values())
    rows, producers, wrappers = [], {}, []
    probes = {"r3": collections.Counter(), "r5": [], "r6": [], "regex_type_calls": 0}
    for path, source in parsed.items():
        if not regex_is_stdlib:
            probes["regex_type_calls"] += len(re.findall(r"(?<![\w.])Regex\s*(?:<[^>\n]*>)?\s*\(", source.masked))
        for acceptor, offset, start, end, options in acceptor_calls(source.masked, regex_is_stdlib):
            row = classify_row(source, acceptor, offset, start, end, options, index, facts)
            scope = source.scope(offset)
            row.update({"file": path, "line": line_of(source.text, offset), "enclosing": scope["name"] if scope else ""})
            for record in row["elements"]:
                decl = record.pop("decl", None)
                if decl is None:
                    continue
                record["producer"] = producer_key(decl)
                producers.setdefault(producer_key(decl), describe(decl, facts[id(decl)]))
                if row["outcome"] == "OTHER-INPUT" and record["class"] == "OTHER-INPUT":
                    probes["r6"].append(wrapped_translator(decl, parsed, row))
            if row["outcome"] == "REWRITTEN":
                for span in row["rewritten_spans"]:
                    for call in calls_in(source.masked, span[0], span[1]):
                        record = classify_element(call, index, facts, path)
                        if record["class"] == "QUALIFYING":
                            probes["r5"].append({"file": path, "line": row["line"], "producer": record["decl"]["name"],
                                                 "producer_file": record["decl"]["file"],
                                                 "producer_line": record["decl"]["line"]})
            row.pop("rewritten_spans")
            rows.append(row)
            if row["outcome"] == "WRAPPER" and scope:
                wrappers.append((row, scope, source))
        probes["r3"].update(unmatched_spellings(source))
    population = sorted({record["producer"] for row in rows if row["outcome"] != "LITERAL-MODE"
                         for record in row["elements"] if record["class"] == "QUALIFYING"})
    judged = set(population) | {record["producer"] for row in rows for record in row["elements"]
                                if record["class"] == "COMBINATOR"}
    for key in judged:
        producers[key]["callers"] = callers(producers[key], key, parsed, index)
    probes["r1"] = one_hop(wrappers, parsed, index, facts, set(population))
    probes["r2"] = [describe(decl, fact) for decls in index["decls"].values() for decl in decls
                    if (fact := facts.get(id(decl))) and qualifies(fact) and producer_key(decl) not in population
                    and re.search(r"regexp?|pattern", decl["name"] + " " + decl["doc"], re.IGNORECASE)]
    probes["r3"] = dict(probes["r3"])
    return {"rows": rows, "producers": producers, "population": population, "unparsed": unparsed,
            "probes": probes, "regex_is_stdlib": regex_is_stdlib}


def callers(producer, key, sources, index):
    """Every call or read the §1.3 resolver resolves to this producer: §5's "every caller"."""
    found = []
    pattern = re.compile(rf"(?<![\w$]){re.escape(producer['name'])}\b")
    for path, source in sources.items():
        for match in pattern.finditer(source.masked):
            after = source.masked[match.end():].lstrip(" \t")
            is_call = after.startswith("(")
            element = {"name": producer["name"], "member": previous_char(source.masked, match.start()) == ".",
                       "offset": match.start(), "trailing": False,
                       "labels": [label for label, _, _ in arguments(source.masked, source.masked.index("(", match.end()))]
                       if is_call else None}
            if not is_call and not element["member"]:
                continue
            before = source.masked[:match.start()].rstrip()
            if re.search(r"\b(func|case)$", before) or re.search(r"\bcase\s*\.$", before):
                continue  # the declaration itself, an enum case, or a case pattern
            receiver = re.search(r"(\w+|[)\]?!])\s*\.$", before)
            if element["member"] and (not receiver or receiver.group(1) in KEYWORDS - {"self", "Self", "super"}):
                continue  # an implicit member expression names a case or static member, not this method
            status, targets = resolve(element, index, path)
            if status == "resolved" and producer_key(targets[0]) == key:
                line_start = source.text.rfind("\n", 0, match.start()) + 1
                line_end = source.text.find("\n", match.start())
                found.append({"file": path, "line": line_of(source.text, match.start()),
                              "text": source.text[line_start:line_end if line_end >= 0 else None].strip()[:200]})
    return found[:50]


def argument_for(call_args, params, wanted):
    """The caller's argument bound to parameter `wanted`, walking the labels as `labels_match` does."""
    cursor = 0
    for label, internal, kind, defaulted in params:
        if cursor < len(call_args) and call_args[cursor][0] == label:
            if internal == wanted:
                return call_args[cursor]
            cursor += 1
            if kind.endswith("..."):
                while cursor < len(call_args) and call_args[cursor][0] == "_":
                    cursor += 1
        elif not defaulted:
            return None
    return None


def one_hop(wrappers, sources, index, facts, population):
    """R1: a `func` WRAPPER's callers, their argument at each wrapped position classified by §1.2-§1.5.
    An `init` or subscript wrapper is not followed."""
    found = []
    for row, scope, source in wrappers:
        decls = [decl for decl in index["decls"].get(scope["name"], [])
                 if decl["file"] == source.path and decl["open"] == scope["open"]]
        wrapped = [chase.split(":")[0] for chase in row["chased"] if "parameter of" in chase]
        if not decls or not wrapped:
            continue
        decl = decls[0]
        for caller_path, caller in sources.items():
            for call in calls_in(caller.masked, 0, len(caller.masked)):
                if call["name"] != decl["name"]:
                    continue
                status, targets = resolve(call, index, caller_path)
                if status != "resolved" or targets[0] is not decl:
                    continue
                call_args = arguments(caller.masked, caller.masked.index("(", call["offset"]))
                for name in wrapped:
                    argument = argument_for(call_args, decl["params"], name)
                    if argument is None:
                        continue
                    inner = classify_row(caller, f"wrapper:{decl['name']}", call["offset"], argument[1], argument[2],
                                         "", index, facts)
                    for record in inner["elements"]:
                        target = record.pop("decl", None)
                        if record["class"] == "QUALIFYING" and target is not None:
                            found.append({"wrapper": decl["name"], "wrapper_file": decl["file"],
                                          "wrapper_line": decl["line"], "caller_file": caller_path,
                                          "caller_line": line_of(caller.text, call["offset"]),
                                          "producer": target["name"], "producer_file": target["file"],
                                          "producer_line": target["line"],
                                          "in_population": producer_key(target) in population})
    return found


# ── Controls (§3) ──────────────────────────────────────────────────────────────────────────────
#
# C1-C3 and C18 are verbatim from the witnesses at the commits the scope names, trimmed to the
# functions involved. The rest are synthetic, one rule each.

UML_STRING = r'''import Foundation

internal extension String {
    func globPatternToRegex() -> String {
        let escaped = replacingOccurrences(
            of: "[.+(){}^$\\\\|]",
            with: "\\\\$0",
            options: .regularExpression
        )
        return "^\(escaped)$"
            .replacingOccurrences(of: "?", with: "[^/]")
            .replacingOccurrences(of: "**/", with: "(.+/)?")
            .replacingOccurrences(of: "**", with: ".+")
            .replacingOccurrences(of: "*", with: "([^/]+)?")
    }

    func isMatching(searchPattern: String) -> Bool {
        let pattern = searchPattern.globPatternToRegex()
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        return regex.firstMatch(in: self, options: [], range: NSRange(location: 0, length: utf16.count)) != nil
    }
}
'''

UML_GLOB = r'''import Foundation

/// Expand one or more comma-delimited file paths using glob syntax
internal func expandGlobs(_ paths: String, in directory: String) -> [Glob] {
    guard pathContainsGlobSyntax(paths) else {
        return parseCommaDelimitedList(paths).map {
            .path(expandPath($0, in: directory).path)
        }
    }
    var paths = paths
    var tokens = [String: String]()
    while let range = paths.range(of: "\\{[^}]+\\}", options: .regularExpression) {
        let options = paths[range].dropFirst().dropLast()
            .replacingOccurrences(of: "[.+(){\\\\|]", with: "\\\\$0", options: .regularExpression)
            .components(separatedBy: ",")
        let token = "<<<\(tokens.count)>>>"
        tokens[token] = "(\(options.joined(separator: "|")))"
        paths.replaceSubrange(range, with: token)
    }
    return parseCommaDelimitedList(paths).map { path -> Glob in
        let path = expandPath(path, in: directory).path
        if FileManager.default.fileExists(atPath: path) {
            return .path(path)
        }
        var regex = path.globPatternToRegex()
        for (token, replacement) in tokens {
            regex = regex.replacingOccurrences(of: token, with: replacement)
        }
        do {
            return try .regex(NSRegularExpression(pattern: regex, options: []))
        } catch {
            BridgeLogger.shared.error("failed to compile glob regex '\(regex)': \(error)")
            return .path(path)
        }
    }
}
'''

ASSIST_GLOB = r'''import Foundation

public struct GlobTool: AgentTool {
    public func execute(call: ToolCall, context: AgentToolContext) -> ToolObservation {
        guard let pattern = call.string("pattern") else {
            return .failure(call.id, "glob: missing required argument 'pattern'")
        }

        // Translate glob → regex; we don't shell out so the matching stays
        // confined to the workspace and follows our own glob rules.
        let regex: NSRegularExpression
        do {
            let translated = Self.translate(glob: pattern)
            regex = try NSRegularExpression(pattern: "^" + translated + "$")
        } catch {
            return .failure(call.id, "glob: invalid pattern: \(String(describing: error))")
        }
        return .success(call.id, "")
    }

    /// Translates a simple glob (`*`, `**`, `?`, `[...]`) into a regex.
    static func translate(glob: String) -> String {
        var result = ""
        var index = glob.startIndex
        while index < glob.endIndex {
            let char = glob[index]
            switch char {
            case "*":
                let next = glob.index(after: index)
                if next < glob.endIndex, glob[next] == "*" {
                    result += ".*"
                    index = glob.index(after: next)
                    continue
                }
                result += "[^/]*"

            case "?":
                result += "[^/]"

            case ".", "(", ")", "+", "|", "^", "$", "{", "}", "\\":
                result += "\\\(char)"

            default:
                result.append(char)
            }
            index = glob.index(after: index)
        }
        return result
    }
}
'''


UML_STRING_111D8BD = r'''import Foundation

internal extension String {
    /// Translate this glob pattern into an anchored regular-expression string
    /// (`^…$`): escape regex metacharacters, then expand `?`, `**/`, `**`, and `*`.
    func globPatternToRegex() -> String {
        "^\(self)$"
            .replacingOccurrences(of: "[.+(){\\\\|]", with: "\\\\$0", options: .regularExpression)
            .replacingOccurrences(of: "?", with: "[^/]")
            .replacingOccurrences(of: "**/", with: "(.+/)?")
            .replacingOccurrences(of: "**", with: ".+")
            .replacingOccurrences(of: "*", with: "([^/]+)?")
    }

    func isMatching(searchPattern: String) -> Bool {
        let pattern = searchPattern.globPatternToRegex()
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return true }
        return regex.firstMatch(in: self, options: [], range: NSRange(location: 0, length: utf16.count)) != nil
    }
}
'''

ESCAPE = 'func escape(_ x: String) -> String { x.replacingOccurrences(of: ".", with: "\\\\.") }\n'

SYNTHETIC = {
    "C4": {"Mark.swift": r'''import Foundation
struct MarkRule {
    private static func nonCapturingGroup(_ pattern: String) -> String { "(?:\(pattern))" }
    func lint(_ text: String) -> Bool {
        let regex = try? NSRegularExpression(pattern: Self.nonCapturingGroup("a+"))
        return regex != nil
    }
}
'''},
    "C5": {"A.swift": "struct A { func escape(_ text: String) -> String { text.replacingOccurrences(of: \".\", with: \"\\\\.\") } }\n",
           "B.swift": "struct B { func escape(_ text: String) -> String { text.replacingOccurrences(of: \"*\", with: \"\\\\*\") } }\n",
           "Use.swift": "import Foundation\nfunc use(_ s: String) throws -> NSRegularExpression {\n    try NSRegularExpression(pattern: escape(s))\n}\n"},
    "C6": {"E.swift": "import Foundation\nfunc literal(_ s: String) throws -> NSRegularExpression {\n"
                      "    try NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: s))\n}\n"
                      + ESCAPE + "func escaped(_ s: String) throws -> NSRegularExpression {\n"
                      "    try NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: escape(s)))\n}\n"},
    "C7": {"L.swift": "import Foundation\nlet compiled = try! NSRegularExpression(pattern: \"a+\")\n"},
    "C8": {"W.swift": "import Foundation\nfunc compile(_ p: String) throws -> NSRegularExpression {\n"
                      "    try NSRegularExpression(pattern: p)\n}\n"},
    "C9": {"S.swift": r'''import Foundation
extension String {
    func toRegex() -> String { replacingOccurrences(of: "*", with: ".*") }
}
func find(_ text: String, _ glob: String) -> Bool {
    text.range(of: glob.toRegex(), options: [.regularExpression, .caseInsensitive]) != nil
}
'''},
    "C10": {"R.swift": r'''func translate(_ glob: String) -> String { glob.map { $0 == "*" ? ".*" : String($0) }.joined() }
func matcher(_ x: String) throws -> Regex<AnyRegexOutput> {
    try Regex(translate(x))
}
'''},
    "C11": {"V.swift": r'''import Foundation
func f(_ x: String) -> String { x.replacingOccurrences(of: "?", with: ".") }
func g(_ x: String) throws -> NSRegularExpression {
    var p = f(x)
    p += "$"
    return try NSRegularExpression(pattern: p)
}
'''},
    "C12": {"P.swift": "private func hidden(_ x: String) -> String { x.replacingOccurrences(of: \".\", with: \"\\\\.\") }\n"
                       "import Foundation\nfunc here(_ x: String) -> Bool { (try? NSRegularExpression(pattern: hidden(x))) != nil }\n",
            "Q.swift": "import Foundation\nfunc there(_ x: String) -> Bool { (try? NSRegularExpression(pattern: hidden(x))) != nil }\n"},
    "C13": {"I.swift": "import Foundation\n" + ESCAPE + r'''func word(_ name: String) throws -> NSRegularExpression {
    try NSRegularExpression(pattern: "^\(escape(name))$")
}
'''},
    "C14": {"T.swift": "import Foundation\n" + ESCAPE + r'''func anchored(_ x: String) throws -> NSRegularExpression {
    let e = escape(x)
    let p = "^\(e)$"
    return try NSRegularExpression(pattern: p)
}
'''},
    "C15": {"N.swift": "import Foundation\n// NSRegularExpression(pattern: escape(x)) is not a call\n"
                       "let note = \"NSRegularExpression(pattern: escape(x))\"\n"},
    "C16": {"K.swift": 'import Foundation\nfunc quoted(_ line: String) -> Bool {\n    let pattern = #""([^"]+)""#\n'
                       '    return (try? NSRegularExpression(pattern: pattern)) != nil\n}\n'},
    "C17": {"F.swift": "import Foundation\nstruct Scan {\n    static let patterns = [\"a+\", \"b+\"]\n"
                       "    func run() { for pattern in Self.patterns { _ = try? NSRegularExpression(pattern: pattern) } }\n}\n"},
    "C19": {"G.swift": r'''import Foundation
enum Flag: String { case i, s }
func flagText(_ flags: [Flag]) -> String { flags.map(\.rawValue).joined() }
func group(_ p: String) -> String { "(?:\(p))" }
func compileGroup(_ p: String) throws -> NSRegularExpression { try NSRegularExpression(pattern: group(p)) }
'''},
    "C20": {"X.swift": "import Foundation\n" + ESCAPE + r'''func one(_ x: String) throws -> NSRegularExpression { try NSRegularExpression.init(pattern: escape(x)) }
func two(_ x: String) throws -> Regex<Substring> { try Regex<Substring>(escape(x)) }
func three(_ s: String, _ x: String) -> String { s.replacingOccurrences(of: escape(x), with: "", options: .regularExpression) }
'''},
    "C21": {"Y.swift": "import Foundation\n" + ESCAPE + r'''func none(_ s: String, _ x: String) throws -> Bool {
    let plain = s.range(of: escape(x)) != nil
    let verbatim = Regex(verbatim: escape(x))
    let literal = /a+/
    let extended = #/a{2}/#
    let bare: NSRegularExpression = try .init(pattern: escape(x))
    let predicate = NSPredicate(format: "SELF MATCHES %@", escape(x))
    _ = (verbatim, literal, extended, bare, predicate)
    return plain
}
'''},
    "C22": {"Z.swift": "import Foundation\n" + ESCAPE + r'''func kept(_ x: String) throws -> NSRegularExpression {
    var p = escape(x)
    return try NSRegularExpression(pattern: p)
}
func appended(_ x: String) throws -> NSRegularExpression {
    var p = escape(x)
    p.append("$")
    return try NSRegularExpression(pattern: p)
}
func inout_(_ x: String) throws -> NSRegularExpression {
    var p = escape(x)
    touch(&p)
    return try NSRegularExpression(pattern: p)
}
'''},
    "C23": {"O.swift": "import Foundation\n" + ESCAPE + r'''func escape(html: String) -> String { html.replacingOccurrences(of: "<", with: "&lt;") }
func translate(_ g: String, anchored: Bool = true) -> String { g.replacingOccurrences(of: "*", with: ".*") }
func a(_ x: String) throws -> NSRegularExpression { try NSRegularExpression(pattern: escape(x)) }
func b(_ x: String) throws -> NSRegularExpression { try NSRegularExpression(pattern: translate(x)) }
'''},
    "C24": {"H.swift": r'''import Foundation
extension String { var asRegex: String { replacingOccurrences(of: "*", with: ".*") } }
func h(_ glob: String) -> Bool { (try? NSRegularExpression(pattern: glob.asRegex)) != nil }
'''},
    "C25": {"M.swift": "import Foundation\n" + ESCAPE + r'''func m(_ x: String) throws -> NSRegularExpression {
    try NSRegularExpression(pattern: escape(x), options: .ignoreMetacharacters)
}
'''},
    "C26": {"J.swift": r'''import Foundation
func compile(_ p: String) throws -> NSRegularExpression {
    let hit = p.firstMatch(of: /a(?:"|\(/)
    let tail = p.firstMatch(of: #/\{"/#)
    _ = (hit, tail)
    return try NSRegularExpression(pattern: p)
}
'''},
    "C27": {"D.swift": r'''import Foundation
func esc(_ s: String) -> String { NSRegularExpression.escapedPattern(for: s) }
func d(_ x: String) throws -> NSRegularExpression { try NSRegularExpression(pattern: "\\b" + esc(x) + "\\b") }
'''},
    "C29": {"U.swift": r'''import Foundation
#if os(macOS)
func platformEscape(_ x: String) -> String { x.replacingOccurrences(of: ".", with: "\\.") }
#else
func platformEscape(_ x: String) -> String { x.replacingOccurrences(of: ".", with: "[.]") }
#endif
func u(_ x: String) throws -> NSRegularExpression { try NSRegularExpression(pattern: platformEscape(x)) }
'''},
    "C31": {"L.swift": r'''import Foundation
extension String { func lowercased() -> String { replacingOccurrences(of: "A", with: "a") } }
func l(_ x: String) throws -> NSRegularExpression { try NSRegularExpression(pattern: x.lowercased()) }
'''},
    "C32": {"Q.swift": "import Foundation\n" + ESCAPE + r'''func anyOf(_ words: [String]) throws -> NSRegularExpression {
    try NSRegularExpression(pattern: words.map(escape).joined(separator: "|"))
}
'''},
    "C33": {"K.swift": "import Foundation\n" + ESCAPE + r'''func lookup(_ table: [String: String], _ key: String) throws -> NSRegularExpression {
    try NSRegularExpression(pattern: table[escape(key)] ?? "")
}
'''},
    "C34": {"Wrap.swift": "import Foundation\n" + ESCAPE + r"""func translate(glob: String) -> String { "^" + escape(glob) + "$" }
func t(_ g: String) throws -> NSRegularExpression { try NSRegularExpression(pattern: translate(glob: g)) }
"""},
    "C35": {"Cond.swift": r"""import Foundation
func helperQ(_ s: String) -> String { s }
func c(_ g: String?) -> NSRegularExpression? {
    if let p = g { print(helperQ("lit")); return try? NSRegularExpression(pattern: p) }
    return nil
}
func c2(_ g: String?) -> NSRegularExpression? {
    if let a = g, let p = String(a) { return try? NSRegularExpression(pattern: p) }
    return nil
}
func c3(_ glob: String?) -> NSRegularExpression? {
    guard let glob = glob else { return nil }
    return try? NSRegularExpression(pattern: glob)
}
"""},
    "C36": {"Amb.swift": r"""import Foundation
extension String { var asRegex: String { replacingOccurrences(of: "*", with: ".*") } }
struct Other { let asRegex: Int = 0 }
func amb(_ glob: String) -> Bool { (try? NSRegularExpression(pattern: glob.asRegex)) != nil }
"""},
    "C37": {"Loop.swift": "import Foundation\n" + ESCAPE + r"""func loop(_ xs: [String]) throws {
    var p = escape("a")
    for x in xs {
        _ = try NSRegularExpression(pattern: p)
        p = x
    }
}
"""},
    "C38": {"Read.swift": "import Foundation\n" + ESCAPE + r"""func read(_ x: String) throws -> NSRegularExpression {
    var p = escape(x)
    let q = p.replacingOccurrences(of: "a", with: "b")
    let t = p.trimmingCharacters(in: .whitespaces)
    _ = (q, t)
    return try NSRegularExpression(pattern: p)
}
"""},
    "C39": {"Ext.swift": "private extension String {\n    func esc() -> String { replacingOccurrences(of: \".\", with: \"\\\\.\") }\n}\n",
            "Far.swift": "import Foundation\nfunc far(_ x: String) -> Bool { (try? NSRegularExpression(pattern: x.esc())) != nil }\n"},
    "C40": {"Var.swift": r"""import Foundation
func alt(_ parts: String...) -> String { parts.map { $0.replacingOccurrences(of: ".", with: "\\.") }.joined(separator: "|") }
func v(_ a: String, _ b: String) throws -> NSRegularExpression { try NSRegularExpression(pattern: alt(a, b)) }
"""},
    "C41": {"Trail.swift": r"""import Foundation
func tr(_ s: String, each: (Character) -> String) -> String { s.map(each).joined() }
func w(_ a: String) throws -> NSRegularExpression { try NSRegularExpression(pattern: tr(a) { String($0) }) }
"""},
    "C42": {"Defer.swift": "import Foundation\n" + ESCAPE + r"""func deferred(_ x: String, _ c: Bool) throws -> NSRegularExpression {
    let p: String
    if c { p = escape(x) } else { p = "a" }
    return try NSRegularExpression(pattern: p)
}
"""},
    "C43": {"Conv.swift": "import Foundation\n" + ESCAPE + r"""func conv(_ x: String) throws -> NSRegularExpression {
    let p = escape(x)
    return try NSRegularExpression(pattern: String(p))
}
"""},
    "C44": {"Own.swift": "import Foundation\n" + ESCAPE + r"""struct Regex { init(_ s: String) {} }
func own(_ x: String) -> Regex { Regex(escape(x)) }
"""},
    "C45": {"Kind.swift": r"""import Foundation
func lowerMap(_ s: String) -> String { s.lowercased().map { $0 == "*" ? ".*" : String($0) }.joined() }
func onlyFilter(_ s: String) -> String { s.filter { $0 != "\\" } }
func k1(_ x: String) throws -> NSRegularExpression { try NSRegularExpression(pattern: lowerMap(x)) }
func k2(_ x: String) throws -> NSRegularExpression { try NSRegularExpression(pattern: onlyFilter(x)) }
"""},
    "C46": {"Short.swift": "import Foundation\n" + ESCAPE + r"""func short(_ x: String) -> NSRegularExpression? {
    let v: String? = escape(x)
    if let v { return try? NSRegularExpression(pattern: v) }
    return nil
}
"""},
    "C47": {"Static.swift": r"""import Foundation
extension String { static func star() -> String { "a".replacingOccurrences(of: "a", with: ".*") } }
func st() throws -> NSRegularExpression { try NSRegularExpression(pattern: String.star()) }
"""},
    "C49": {"Closure.swift": "import Foundation\n" + ESCAPE + r"""func words(_ items: [String]) throws -> NSRegularExpression {
    let p = items.map { escape($0) }.joined(separator: "|")
    return try NSRegularExpression(pattern: p)
}
"""},
    "C50": {"Nest.swift": "private enum Outer {\n    enum Inner {\n        static func esc(_ s: String) -> String { s.replacingOccurrences(of: \".\", with: \"\\\\.\") }\n    }\n}\n",
            "Elsewhere.swift": "import Foundation\nfunc e(_ x: String) -> Bool { (try? NSRegularExpression(pattern: Outer.Inner.esc(x))) != nil }\n"},
    "C51": {"Top.swift": "import Foundation\n" + ESCAPE + "let globalPattern = escape(\"a\")\nlet compiled = try! NSRegularExpression(pattern: globalPattern)\n"},
    "C52": {"Tern.swift": r"""import Foundation
func pick(_ strict: Bool) throws -> NSRegularExpression { try NSRegularExpression(pattern: strict ? "a+" : "b+") }
"""},
    "C30": {"Broken.swift": "import Foundation\nfunc broken(_ p: String) throws -> NSRegularExpression {\n"
                            "    try NSRegularExpression(pattern: p)\n"},
}


def control_rows():
    """`{control: census}` over the controls' sources."""
    found = {
        "C1-C2": census({"String+Extensions.swift": UML_STRING, "Glob.swift": UML_GLOB}),
        "C3": census({"FilesystemTools.swift": ASSIST_GLOB}),
        "C18": census({"String+Extensions.swift": UML_STRING_111D8BD}),
    }
    for name, files in SYNTHETIC.items():
        found[name] = census(files)
    found["C28"] = overlapping_roots()
    found["C48"] = skipped_test_folder()
    return found


def skipped_test_folder():
    """C48: a file under `Sources/CoreTests/` is not indexed (§2's skip rule)."""
    import tempfile
    import shutil
    root = tempfile.mkdtemp(prefix="regex-acceptor-c48-")
    try:
        os.makedirs(os.path.join(root, "Sources", "CoreTests"))
        with open(os.path.join(root, "Sources", "CoreTests", "Escape.swift"), "w", encoding="utf-8") as handle:
            handle.write(ESCAPE)
        with open(os.path.join(root, "Sources", "Use.swift"), "w", encoding="utf-8") as handle:
            handle.write("import Foundation\nfunc use(_ x: String) throws -> NSRegularExpression {\n"
                         "    try NSRegularExpression(pattern: escape(x))\n}\n")
        files, skipped = subject_files(root, [os.path.join(root, "Sources")])
        result = census(files)
        result["skipped"] = skipped
        return result
    finally:
        shutil.rmtree(root, ignore_errors=True)


def overlapping_roots():
    """C28: a subject whose scan roots are `Sources` and `Sources/Core` is indexed once per file."""
    import tempfile
    root = tempfile.mkdtemp(prefix="regex-acceptor-c28-")
    try:
        os.makedirs(os.path.join(root, "Sources", "Core"))
        with open(os.path.join(root, "Sources", "Core", "Escape.swift"), "w", encoding="utf-8") as handle:
            handle.write(ESCAPE)
        with open(os.path.join(root, "Sources", "Use.swift"), "w", encoding="utf-8") as handle:
            handle.write("import Foundation\nfunc use(_ x: String) throws -> NSRegularExpression {\n"
                         "    try NSRegularExpression(pattern: escape(x))\n}\n")
        files, _ = subject_files(root, [os.path.join(root, "Sources"), os.path.join(root, "Sources", "Core")])
        return census(files)
    finally:
        import shutil
        shutil.rmtree(root, ignore_errors=True)


def self_test():
    results = control_rows()
    failures = []

    def expect(label, condition, detail):
        if not condition:
            failures.append(f"{label}: {detail}")

    def rows(name, file_=None):
        return [row for row in results[name]["rows"] if file_ is None or row["file"] == file_]

    def summary(rows_):
        return [(row["file"], row["outcome"], row["handling"], row["acceptor"], row["argument"]) for row in rows_]

    def producer(name, row):
        keys = [record["producer"] for record in row["elements"] if record["class"] == "QUALIFYING"]
        return [results[name]["producers"][key] for key in keys]

    uml = rows("C1-C2")
    matching = [row for row in uml if row["enclosing"] == "isMatching"]
    expect("C1", len(matching) == 1 and matching[0]["outcome"] == "QUALIFYING" and matching[0]["handling"] == "HANDLES-NIL"
           and [(p["name"], p["input"]) for p in producer("C1-C2", matching[0])] == [("globPatternToRegex", "RECEIVER")],
           summary(matching))
    expand = [row for row in uml if row["file"] == "Glob.swift" and row["acceptor"] == "NSRegularExpression"]
    expect("C2", len(expand) == 1 and expand[0]["outcome"] == "REWRITTEN" and expand[0]["handling"] == "HANDLES-CATCH",
           summary(expand))
    literal = [row for row in uml if row["acceptor"].startswith("silent:")]
    expect("C2 (silent literals)", len(literal) == 3 and all(row["outcome"] == "LITERAL" and row["handling"] == "SILENT"
                                                             for row in literal), summary(literal))
    assist = rows("C3")
    expect("C3", len(assist) == 1 and assist[0]["outcome"] == "QUALIFYING" and assist[0]["handling"] == "HANDLES-CATCH"
           and assist[0]["argument"] == '"^" + translated + "$"'
           and [(p["name"], p["input"]) for p in producer("C3", assist[0])] == [("translate", "PARAM")], summary(assist))
    old = [row for row in rows("C18") if row["acceptor"] == "NSRegularExpression"]
    expect("C18", len(old) == 1 and old[0]["outcome"] == "QUALIFYING"
           and [(p["name"], p["input"], p["evidence_kind"]) for p in producer("C18", old[0])]
           == [("globPatternToRegex", "RECEIVER", "three")], summary(old))
    expect("C6", [(row["outcome"], row["handling"]) for row in rows("C6")]
           == [("EXTERNAL", "PROPAGATES"), ("EXTERNAL", "PROPAGATES")], summary(rows("C6")))
    singles = {"C4": ("COMBINATOR", None), "C5": ("AMBIGUOUS", None), "C31": ("EXTERNAL", "PROPAGATES"),
               "C7": ("LITERAL", "ASSERTS"), "C8": ("WRAPPER", "PROPAGATES"), "C9": ("QUALIFYING", "SILENT"),
               "C10": ("QUALIFYING", "PROPAGATES"), "C11": ("REWRITTEN", "PROPAGATES"),
               "C13": ("QUALIFYING", "PROPAGATES"), "C14": ("QUALIFYING", "PROPAGATES"),
               "C16": ("LITERAL", "HANDLES-NIL"), "C17": ("STORED", "HANDLES-NIL"),
               "C19": ("COMBINATOR", "PROPAGATES"), "C24": ("QUALIFYING", "HANDLES-NIL"),
               "C25": ("LITERAL-MODE", "PROPAGATES"), "C26": ("WRAPPER", "PROPAGATES"),
               "C27": ("QUALIFYING", "PROPAGATES"), "C28": ("QUALIFYING", "PROPAGATES"),
               "C29": ("QUALIFYING", "PROPAGATES"), "C32": ("QUALIFYING", "PROPAGATES"),
               "C33": ("WRAPPER", "PROPAGATES")}
    for name, (want, want_handling) in singles.items():
        got = rows(name)
        expect(name, len(got) == 1 and got[0]["outcome"] == want
               and (want_handling is None or got[0]["handling"] == want_handling), summary(got))
    expect("C10 (acceptor)", rows("C10") and rows("C10")[0]["acceptor"] == "Regex", summary(rows("C10")))
    expect("C24 (receiver)", rows("C24") and [p["input"] for p in producer("C24", rows("C24")[0])] == ["RECEIVER"],
           summary(rows("C24")))
    expect("C27 (escape-only)", rows("C27") and [p["evidence_kind"] for p in producer("C27", rows("C27")[0])]
           == ["escape-only"], summary(rows("C27")))
    private = {row["file"]: row["outcome"] for row in rows("C12")}
    expect("C12", private == {"P.swift": "QUALIFYING", "Q.swift": "EXTERNAL"}, private)
    expect("C15", rows("C15") == [], summary(rows("C15")))
    c20 = rows("C20")
    expect("C20", [(row["acceptor"], row["outcome"], row["handling"]) for row in c20]
           == [("NSRegularExpression", "QUALIFYING", "PROPAGATES"), ("Regex<Substring>", "QUALIFYING", "PROPAGATES"),
               ("silent:replacingOccurrences", "QUALIFYING", "SILENT")], summary(c20))
    expect("C21", rows("C21") == [] and results["C21"]["probes"]["r3"].get("bare_init_pattern") == 1
           and results["C21"]["probes"]["r3"].get("nspredicate_matches") == 1,
           (summary(rows("C21")), results["C21"]["probes"]["r3"]))
    expect("C22", [row["outcome"] for row in rows("C22")] == ["QUALIFYING", "REWRITTEN", "REWRITTEN"], summary(rows("C22")))
    expect("C23", [row["outcome"] for row in rows("C23")] == ["QUALIFYING", "QUALIFYING"], summary(rows("C23")))
    expect("C25 (population)", results["C25"]["population"] == [], results["C25"]["population"])
    expect("C34", [(row["outcome"], [p["evidence"] for p in producer("C34", row)]) for row in rows("C34")]
           == [("QUALIFYING", ["delegates to escape"])], summary(rows("C34")))
    expect("C35", [row["outcome"] for row in rows("C35")] == ["WRAPPER", "WRAPPER", "WRAPPER"], summary(rows("C35")))
    expect("C36", [row["outcome"] for row in rows("C36")] == ["AMBIGUOUS"], summary(rows("C36")))
    expect("C37", [row["outcome"] for row in rows("C37")] == ["REWRITTEN"], summary(rows("C37")))
    expect("C38", [row["outcome"] for row in rows("C38")] == ["QUALIFYING"], summary(rows("C38")))
    expect("C39", [row["outcome"] for row in rows("C39")] == ["EXTERNAL"], summary(rows("C39")))
    expect("C40", [row["outcome"] for row in rows("C40")] == ["QUALIFYING"], summary(rows("C40")))
    expect("C41", [row["outcome"] for row in rows("C41")] == ["QUALIFYING"], summary(rows("C41")))
    expect("C42", [row["outcome"] for row in rows("C42")] == ["QUALIFYING"], summary(rows("C42")))
    expect("C43", [row["outcome"] for row in rows("C43")] == ["QUALIFYING"], summary(rows("C43")))
    expect("C44", rows("C44") == [] and results["C44"]["probes"]["regex_type_calls"] == 1,
           (summary(rows("C44")), results["C44"]["probes"]["regex_type_calls"]))
    expect("C45", [[p["evidence_kind"] for p in producer("C45", row)] for row in rows("C45")] == [["three"], ["wide"]],
           summary(rows("C45")))
    expect("C46", [row["outcome"] for row in rows("C46")] == ["QUALIFYING"], summary(rows("C46")))
    expect("C47", [row["outcome"] for row in rows("C47")] == ["OTHER-INPUT"], summary(rows("C47")))
    expect("C48", [row["outcome"] for row in rows("C48")] == ["EXTERNAL"] and results["C48"]["skipped"] == {"*Tests": 1},
           (summary(rows("C48")), results["C48"].get("skipped")))
    expect("C49", [row["outcome"] for row in rows("C49")] == ["QUALIFYING"], summary(rows("C49")))
    expect("C50", {row["file"]: row["outcome"] for row in rows("C50")} == {"Elsewhere.swift": "EXTERNAL"},
           summary(rows("C50")))
    expect("C51", [(row["outcome"], row["handling"]) for row in rows("C51")] == [("STORED", "ASSERTS")],
           summary(rows("C51")))
    expect("C52", [row["outcome"] for row in rows("C52")] == ["LITERAL"], summary(rows("C52")))
    expect("C30", rows("C30") == [] and [item["file"] for item in results["C30"]["unparsed"]] == ["Broken.swift"]
           and results["C30"]["unparsed"][0]["acceptor_spellings"] == 1, results["C30"]["unparsed"])
    for failure in failures:
        print(f"  FAIL  {failure}")
    total = sum(len(value["rows"]) for value in results.values())
    print(f"regex_acceptor_census self-test: {'FAILED' if failures else 'ok'} (52 controls, {total} rows)")
    return not failures


# ── The run (§2) ───────────────────────────────────────────────────────────────────────────────

SKIP_EXACT = {"Tests", ".build", "build", "DerivedData", "checkouts"}


def skip_reason(component):
    if component.startswith("."):
        return "hidden"
    if component in SKIP_EXACT:
        return component
    if component.endswith("UITests"):
        return "*UITests"
    if component.endswith("Tests"):
        return "*Tests"
    return None


def subject_files(subject_root, roots):
    """`({realpath: text}, skipped)`: every `.swift` file under `roots`, with §2's skip rule applied to
    each directory component relative to the subject root."""
    files, skipped, skipped_paths = {}, collections.Counter(), set()
    for root in roots:
        for current, directories, names in os.walk(root):
            relative = os.path.relpath(current, subject_root)
            parts = [] if relative == "." else relative.split(os.sep)
            reasons = [reason for part in parts if (reason := skip_reason(part))]
            if reasons:
                for name in names:
                    path = os.path.realpath(os.path.join(current, name))
                    if name.endswith(".swift") and path not in skipped_paths:
                        skipped_paths.add(path)
                        skipped[reasons[0]] += 1
                continue
            for name in names:
                if not name.endswith(".swift"):
                    continue
                path = os.path.realpath(os.path.join(current, name))
                if path in files:
                    continue
                try:
                    files[path] = open(path, encoding="utf-8", errors="ignore").read()
                except OSError:
                    skipped["unreadable"] += 1
    return files, dict(skipped)


def run(out_path, upstream):
    if not self_test():
        raise SystemExit("a control failed — not reporting a population")
    found, missing = subjects()
    resolved = {group: [name for g, name, _, _ in found if g == group] for group in FROZEN_UNIVERSE}
    if resolved != FROZEN_UNIVERSE:
        raise SystemExit(f"the universe is not §2's frozen list:\n  resolved {resolved}\n  frozen   {FROZEN_UNIVERSE}")
    if sorted(name for name, _ in upstream) != sorted(UPSTREAM) or any(
            not (revision(root) or "").startswith(UPSTREAM[name]) for name, root in upstream):
        raise SystemExit(f"§2 needs exactly the upstream clones {UPSTREAM}, at those revisions")
    found = found + [("upstream", name, root, [os.path.join(root, "Sources")]) for name, root in upstream]
    by_repo = collections.OrderedDict()
    for group, name, root, roots in found:
        key = os.path.realpath(root)
        entry = by_repo.setdefault(key, {"group": group, "name": name, "root": root, "roots": [], "also": []})
        if entry["group"] != group:
            entry["also"].append(f"{group}:{name}")
        entry["roots"].extend(roots)
    report = {"subjects": [], "missing": [{"group": g, "subject": n} for g, n in missing], "rows": [],
              "producers": {}, "population": [], "unparsed": [], "probes": collections.defaultdict(list)}
    for key, entry in by_repo.items():
        files, skipped = subject_files(entry["root"], entry["roots"])
        result = census(files)

        def local(path):
            return os.path.relpath(path, key)

        def ident(producer_key_):
            return f"{entry['name']}:{local(producer_key_[0])}:{producer_key_[1]}"

        for row in result["rows"]:
            row["file"] = local(row["file"])
            for record in row["elements"]:
                if "producer" in record:
                    record["producer"] = ident(record["producer"])
                for candidate in record.get("candidates", []):
                    candidate["file"] = local(candidate["file"])
            row.update({"group": entry["group"], "subject": entry["name"]})
            report["rows"].append(row)
        for producer_key_, producer in result["producers"].items():
            producer.update({"file": local(producer["file"]), "group": entry["group"], "subject": entry["name"]})
            for caller in producer.get("callers", []):
                caller["file"] = local(caller["file"])
            producer["delegates"] = [ident(tuple(item)) for item in producer["delegates"]]
            report["producers"][ident(producer_key_)] = producer
        report["population"].extend(ident(item) for item in result["population"])
        report["unparsed"].extend({"subject": entry["name"], "file": local(item["file"]),
                                   "acceptor_spellings": item["acceptor_spellings"]} for item in result["unparsed"])
        for probe in ("r1", "r2", "r5", "r6"):
            for item in result["probes"][probe]:
                for field in ("file", "wrapper_file", "caller_file", "producer_file"):
                    if field in item and item[field]:
                        item[field] = local(item[field])
                if "delegates" in item:
                    item["delegates"] = [ident(tuple(delegate)) for delegate in item["delegates"]]
                item.update({"group": entry["group"], "subject": entry["name"]})
                report["probes"][probe].append(item)
        report["probes"]["r3"].append({"subject": entry["name"], **result["probes"]["r3"]})
        report["probes"]["regex_type_calls"].append({"subject": entry["name"],
                                                     "regex_is_stdlib": result["regex_is_stdlib"],
                                                     "calls": result["probes"]["regex_type_calls"]})
        outcomes = collections.Counter(row["outcome"] for row in result["rows"])
        report["subjects"].append({"group": entry["group"], "subject": entry["name"], "also": entry["also"],
                                   "root": (f"a shallow clone of github.com/nicklockwood/{entry['name']}"
                                            if entry["group"] == "upstream"
                                            else key.replace(os.path.expanduser("~"), "~", 1)),
                                   "roots": sorted({local(root) for root in entry["roots"]}),
                                   "revision": revision(entry["root"]), "files": len(files), "skipped": skipped,
                                   "unparsed": len(result["unparsed"]), "rows": len(result["rows"]),
                                   "population": len(result["population"]), "outcomes": dict(outcomes)})
        print(f"  {entry['group']:8} {entry['name']:24} files {len(files):5}  unparsed {len(result['unparsed']):3}  "
              f"rows {len(result['rows']):4}  population {len(result['population']):2}")
    report["probes"] = dict(report["probes"])
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=1, sort_keys=True)
        handle.write("\n")
    outcomes = collections.Counter(row["outcome"] for row in report["rows"])
    decision = [ident for ident in report["population"] if report["producers"][ident]["group"] in DECISION_GROUPS]
    merged = {report["producers"][ident]["body_key"] for ident in decision}
    print(f"rows {len(report['rows'])}: {dict(sorted(outcomes.items()))}")
    print(f"population {len(report['population'])} ({len(decision)} in #666's universe, {len(merged)} with vendored "
          f"copies merged); unparsed files {len(report['unparsed'])}; subjects {len(report['subjects'])}")


# ── §5's packets ───────────────────────────────────────────────────────────────────────────────
#
# One packet per producer to judge: population producers, COMBINATOR producers (or §5's seeded 40), and
# AMBIGUOUS-Q rows. A packet shows the declaration, every row it appears on with the call site's context,
# its doc and its callers — and NOT the pass's outcome label, the evidence kind, §7, §8 or any count. The
# order is seeded so QUALIFYING and COMBINATOR producers interleave.

SEED = 20261027


def declaration_text(text, line):
    """The declaration starting at `line` (1-based), with its doc comment, through its closing brace."""
    lines = text.split("\n")
    start = line - 1
    while start > 0 and lines[start - 1].strip().startswith(("///", "@")):
        start -= 1
    offset = sum(len(row) + 1 for row in lines[:line - 1])
    masked = mask_code(text)
    brace = masked.find("{", offset)
    pairs = brace_pairs(masked)
    end = pairs.get(brace, len(masked) - 1)
    head = sum(len(row) + 1 for row in lines[:start])
    return text[head:end + 1]


def context(text, line, radius=6):
    lines = text.split("\n")
    low, high = max(0, line - 1 - radius), min(len(lines), line + radius)
    return "\n".join(f"{number + 1:5}  {lines[number]}" for number in range(low, high))


def packets(census_path, out_dir, upstream):
    import random
    report = json.load(open(census_path, encoding="utf-8"))
    roots = {entry["subject"]: os.path.expanduser(entry["root"]) for entry in report["subjects"]}
    roots.update(dict(upstream))
    decision = {ident for ident in report["population"]
                if report["producers"][ident]["group"] in DECISION_GROUPS}
    combinators = sorted({record["producer"] for row in report["rows"] if row["group"] in DECISION_GROUPS
                          for record in row["elements"] if record["class"] == "COMBINATOR"} - set(report["population"]))
    by_body = {}
    for ident in combinators:
        by_body.setdefault(report["producers"][ident]["body_key"], ident)
    combinators = sorted(by_body.values(), key=lambda ident: (report["producers"][ident]["subject"],
                                                              report["producers"][ident]["file"],
                                                              report["producers"][ident]["line"]))
    if len(combinators) > 40:
        combinators = random.Random(SEED).sample(combinators, 40)
    population = sorted(report["population"])
    chosen = [(ident, "population") for ident in population] + [(ident, "combinator") for ident in combinators]
    random.Random(SEED).shuffle(chosen)
    os.makedirs(out_dir, exist_ok=True)
    index = []
    for number, (ident, kind) in enumerate(chosen, 1):
        producer = report["producers"][ident]
        root = roots[producer["subject"]]
        text = open(os.path.join(root, producer["file"]), encoding="utf-8", errors="ignore").read()
        rows = [row for row in report["rows"] if any(record.get("producer") == ident for record in row["elements"])]
        parts = [f"# Packet P{number:03}", "",
                 f"Subject: {producer['subject']} ({producer['group']}); declaration "
                 f"`{producer['file']}:{producer['line']}`", "",
                 "## The declaration", "", "```swift", declaration_text(text, producer["line"]), "```", "",
                 f"## Call sites that pass its output toward a regex acceptor ({len(rows)})", ""]
        for row in rows:
            row_text = open(os.path.join(roots[row["subject"]], row["file"]), encoding="utf-8", errors="ignore").read()
            parts += [f"### `{row['file']}:{row['line']}` — acceptor `{row['acceptor']}`"
                      + (f", options `{row['options']}`" if row["options"] else ""), "",
                      f"Argument: `{row['argument']}`" + (f"; bindings followed: {row['chased']}" if row["chased"] else ""),
                      "", "```swift", context(row_text, row["line"]), "```", ""]
        parts += [f"## Its callers ({len(producer.get('callers', []))}, as the census resolver finds them)", ""]
        parts += [f"- `{caller['file']}:{caller['line']}` — `{caller['text']}`" for caller in producer.get("callers", [])]
        path = os.path.join(out_dir, f"P{number:03}.md")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("\n".join(parts) + "\n")
        index.append({"packet": f"P{number:03}", "producer": ident, "kind": kind,
                      "in_decision_universe": ident in decision})
    ambiguous = [row for row in report["rows"] if row["outcome"] == "AMBIGUOUS"
                 and any(any(candidate["qualifies"] for candidate in record.get("candidates", []))
                         for record in row["elements"])]
    for number, row in enumerate(sorted(ambiguous, key=lambda row: (row["subject"], row["file"], row["line"])), 1):
        row_text = open(os.path.join(roots[row["subject"]], row["file"]), encoding="utf-8", errors="ignore").read()
        parts = [f"# Packet A{number:03}", "", f"Subject: {row['subject']} ({row['group']})", "",
                 f"## The call site `{row['file']}:{row['line']}` — acceptor `{row['acceptor']}`", "",
                 f"Argument: `{row['argument']}`", "", "```swift", context(row_text, row["line"]), "```", "",
                 "## The declarations the name could mean", ""]
        for record in row["elements"]:
            for candidate in record.get("candidates", []):
                candidate_text = open(os.path.join(roots[row["subject"]], candidate["file"]), encoding="utf-8",
                                      errors="ignore").read()
                parts += [f"### `{candidate['file']}:{candidate['line']}` (in `{candidate['owner'] or 'file scope'}`)",
                          "", "```swift", declaration_text(candidate_text, candidate["line"]), "```", ""]
        path = os.path.join(out_dir, f"A{number:03}.md")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("\n".join(parts) + "\n")
        index.append({"packet": f"A{number:03}", "row": f"{row['subject']}:{row['file']}:{row['line']}",
                      "kind": "ambiguous-q", "in_decision_universe": row["group"] in DECISION_GROUPS})
    with open(os.path.join(out_dir, "index.json"), "w", encoding="utf-8") as handle:
        json.dump(index, handle, indent=1)
        handle.write("\n")
    print(f"{len(index)} packets: {collections.Counter(item['kind'] for item in index)}")


def main(argv):
    if argv[1:] == ["--self-test"]:
        return 0 if self_test() else 1
    if len(argv) >= 4 and argv[1] == "packets":
        packets(argv[2], argv[3], [tuple(item.split("=", 1)) for item in argv[4:] if "=" in item])
        return 0
    if len(argv) >= 3 and argv[1] == "run":
        upstream = [tuple(item.split("=", 1)) for item in argv[3:] if "=" in item]
        run(argv[2], upstream)
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
