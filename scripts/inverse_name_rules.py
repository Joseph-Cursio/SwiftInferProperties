#!/usr/bin/env python3
"""Structural inverse-name rules over round-trip pairing rows — `docs/plans/inverse-name-vocabulary-scope.md`.

  match  <rows.json> <out-sample.json>   classify type-only rows by the four rules and draw the hand-check sample
"""
import json
import random
import re
import sys

ANTONYMS = {frozenset(p) for p in [("successor", "predecessor"), ("next", "previous"), ("next", "prior"),
                                    ("after", "before"), ("increment", "decrement"), ("forward", "backward"),
                                    ("wrap", "unwrap"), ("box", "unbox"), ("escape", "unescape"),
                                    ("quote", "unquote"), ("to", "from")]}
DERIVATION = [("_bridgeObject(fromTagged:)", "_bridgeObject(toTagged:)"), ("successor()", "predecessor()"),
              ("_toUTF16Offsets(_:)", "_toUTF16Indices(_:)"), ("slot(of:)", "bucket(at:)")]


def words(text):
    text = text.lstrip("_")
    return [w.lower() for w in re.findall(r"[A-Z]+(?=[A-Z][a-z]|\d|\b)|[A-Z]?[a-z]+|[A-Z]+|\d+", text)]


def parts(display):
    base = display.split("(")[0]
    inside = display[len(base) + 1:-1] if "(" in display else ""
    label = inside.split(":")[0] if inside else ""
    return base, ("" if label == "_" else label)


def returns(signature):
    tail = signature.split("->")[-1].strip()
    return tail.split(".")[-1].strip("?!")


def is_type_only(row):
    kinds = {s["kind"] for s in row["signals"] if s["weight"] > 0}
    return not kinds & {"exactNameMatch", "discoverableAnnotation", "docstringCorroboration"}


def rules(row):
    f, g = row["forward"], row["inverse"]
    (fb, fl), (gb, gl) = parts(f["displayName"]), parts(g["displayName"])
    hit = []
    # R1: same base name, from…/to… labels with the same remainder.
    labels = {fl, gl}
    if fb == gb and len(labels) == 2:
        a, b = sorted(labels, key=lambda l: not l.startswith("from"))
        if a.startswith("from") and b.startswith("to") and a[4:].lower() == b[2:].lower() and a[4:]:
            hit.append("R1")
    # R2: word lists (base + first label) differ in exactly one position, by a listed antonym.
    fw, gw = words(fb) + words(fl), words(gb) + words(gl)
    if len(fw) == len(gw):
        diff = [(x, y) for x, y in zip(fw, gw) if x != y]
        if len(diff) == 1 and frozenset(diff[0]) in ANTONYMS:
            hit.append("R2")
    # R3: both `to…` conversions sharing a word after `to`, differing after it.
    fbw, gbw = words(fb), words(gb)
    if len(fbw) > 2 and len(gbw) > 2 and fbw[0] == gbw[0] == "to" and fbw[1] == gbw[1] and fbw != gbw:
        hit.append("R3")
    # R4: each base name's last word is the last word of its own return type's bare name.
    fr, gr = words(returns(f["signature"])), words(returns(g["signature"]))
    if fbw and gbw and fr and gr and fbw[-1] == fr[-1] and gbw[-1] == gr[-1] and fb != gb:
        hit.append("R4")
    return hit


def derivation(row):
    pair = {row["forward"]["displayName"], row["inverse"]["displayName"]}
    return any(pair == set(d) for d in DERIVATION)


def main(argv):
    rows = json.load(open(argv[2]))
    typed = [r for r in rows if is_type_only(r)]
    matched = []
    for row in typed:
        hit = rules(row)
        if hit:
            matched.append(dict(row, rules=hit, derivation=derivation(row)))
    print(f"{len(rows)} rows, {len(typed)} type-only, {len(matched)} matched by a rule")
    for name in ("R1", "R2", "R3", "R4"):
        print(f"  {name}: {sum(name in m['rules'] for m in matched)}")
    print(f"  derivation pairings among them: {sum(m['derivation'] for m in matched)}")
    key = lambda r: (r["corpus"], r["forward"]["file"], r["forward"]["line"], r["inverse"]["line"])
    sample = sorted(matched, key=key)
    if len(sample) > 60:
        random.Random(20260929).shuffle(sample)
        sample = sample[:60]
    json.dump(sample, open(argv[3], "w"), indent=1, sort_keys=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
