# Judging brief: does a unit build an XML document as text?

You judge Swift functions and computed properties, one packet at a time. Each row is one unit, with:

- its text and its doc comment;
- its owner's name, kind and doc comment;
- the owner's other members in its repository, with their doc comments and without their bodies;
- the same-type members it references, in full, and the names of the same-type members that reference it;
- its file and its repository.

Decide what each unit is, from its contract: what its name, its documentation and the code around it say it is
for. Read the body, and the members it references, to answer the questions below. A body that breaks its own
contract is still judged by the contract.

## The laws in question

- **Law 1: the document parses.** The unit's result, unless it is a sentinel the contract allows (such as the `""`
  a guard returns for an empty input), is a well-formed XML document: `XMLParser(data: Data(result.utf8)).parse()`
  returns true. A well-formed document has an optional prolog (`<?xml …?>`, comments, a doctype) and exactly one
  root element; every element is closed; `<` and `&` appear in text and attribute values only as part of an entity
  or character reference; a comment never holds `--`; text never holds `]]>`; and no character XML 1.0 forbids
  appears (a C0 control other than tab, line feed and carriage return, U+FFFE or U+FFFF), even as a character
  reference.
- **Law 2 (SVG only): every same-document reference resolves.** Each `url(#X)`, `href="#X"` and `xlink:href="#X"`
  in the result names an element with `id="X"` in the same result.

## Verdicts: give exactly one

- **DOCUMENT.** On every input its contract admits, apart from a sentinel (below), the unit returns a complete XML
  document built as text: an optional prolog and exactly one root element. SVG, plist, Atom, RSS, Checkstyle and
  JUnit reports are all XML documents. **A result that is one complete root element is a DOCUMENT even when callers
  embed it in a larger page**, such as an inline `<svg>` icon, unless that element is HTML's (below).
- **FRAGMENT.** It returns markup meant to sit inside a larger document and that is not one complete root element: a
  start tag, a header, a `<defs>` block, several sibling elements, an element's attributes. The result alone is not a
  document.
- **HTML.** It returns an HTML page, or markup in HTML's vocabulary meant for an HTML page (`<!DOCTYPE html>`,
  `<html>`, `<div>`, `<p>`, `<span>`, void elements such as `<br>`), even if an SVG sits inside it, and even when the
  markup would also parse as XML.
- **NOT-EMITTER.** Anything else: the XML text is a search key or a format sniffer, a constant the unit does not
  return, a parser's or decoder's input, or something written to disk rather than returned. **A unit that takes no
  input and reads no state that varies, and so returns one constant text, is NOT-EMITTER (constant)**: a law over it
  is one example, not a property. Give a short reason.
- **UNDETERMINED.** The text does not decide it, even after reading the files allowed below.

## For DOCUMENT, also answer

- **expressible** (true or false). True when a test can draw every input the unit takes from what its own module
  offers (internal API that a test reaches with `@testable import` counts), call it, and state the law over those
  inputs, **whether or not the body satisfies it** (that is `body_disagrees`). It is false in any of these cases:
  - an input cannot be built;
  - the state the unit reads cannot be made fresh, because it is global or shared;
  - **an input's own contract requires well-formed markup**: a parameter documented, or plainly used, as a markup
    fragment the unit wraps (`inner: String` holding `<path>` elements). Such a parameter is correct by contract
    only when the caller passes well-formed markup, which a test cannot draw without its own law.

  Reading the working directory, the clock or the environment does not by itself make it false; that is `ambient`.
- **ambient** (true or false). True when the result depends on state outside the unit's inputs and its owner's stored
  properties: the working directory, the clock, the environment, files, a random source, or other process-wide state,
  read directly or through a call into another type. Name the source in `reason`.
- **sentinel.** What a guard returns instead of a document, whether or not it is documented, such as `""` for an
  empty input; or `none` when there is no such return. A sentinel is never a body_disagrees witness.
- **law2.** One of:
  - **OWES**: the root is `svg`, and the result's same-document references name ids the unit's own result defines
    (in its own literals, or in a member it references);
  - **VACUOUS**: the root is `svg`, and the unit never writes a same-document reference;
  - **EXTERNAL**: the root is `svg`, and its references name ids defined outside the document by design, such as a
    sprite sheet the host page embeds;
  - **NOT-SVG**: the root is not `svg`.
- **body_disagrees** (true or false). True when you can name an input, allowed by the contract, on which the
  result is not a well-formed document. Give it in `witness`, with the malformed text it produces. The usual
  causes: caller text interpolated without escaping, a label written inside a comment (`--`), a forbidden character
  passed through, or an element left unclosed on one branch. **A crash or a trap is not body_disagrees** (an
  out-of-range `Int(…)` conversion, an index out of bounds): this flag asks for malformed text.
- **refs_dangle** (true or false). For OWES only (false otherwise): true when you can name an input, allowed by the
  contract, on which a reference names an id the result does not define. Give it in `witness`.

Answer `null` for expressible, ambient, law2, body_disagrees and refs_dangle when the verdict is not DOCUMENT.

**Before answering expressible, ambient, law2, body_disagrees or refs_dangle, read the row's whole file (when the
repository is readable) and every same-type member it references.** A referenced member's text in the packet is cut
at 120 lines; read the file for the rest. An input "allowed by the contract" is one the unit's types
admit and its documentation does not exclude. A value only the unit's callers would never pass is still allowed,
unless the documentation excludes it.

## Rules

- You may read only your packet and, for context, source files under the row's own repository path. Never open,
  list or search a `docs`, `scripts` or `fixtures` directory of the SwiftInferProperties repository (a row from
  that repository is read through its own file only), any `.json` file, any other packet or any other judge's
  output. Never search for a unit's name outside the row's own repository.
- Judge each row on its own. Do not try to guess what anyone expects the answers to be, and do not count.
- Return one record per row, every row of the packet once, each with these fields (the angle brackets name what goes
  there; they are not values):

```
{"label": "<the row's label>", "verdict": "<one of the five verdicts>",
 "expressible": <true, false, or null>, "ambient": <true, false, or null>, "sentinel": "<what the guard returns, or none>",
 "law2": <"OWES", "VACUOUS", "EXTERNAL", "NOT-SVG", or null>, "body_disagrees": <true, false, or null>,
 "refs_dangle": <true, false, or null>, "witness": "<the input and the malformed or dangling text, or empty>",
 "reason": "<one sentence>"}
```
