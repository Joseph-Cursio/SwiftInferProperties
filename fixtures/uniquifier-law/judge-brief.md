# Judging brief: does a function hand out names it promises never to repeat?

You judge Swift functions, one packet at a time. Each row is one function, with:

- its text and its doc comment;
- its owner's name, kind and doc comment;
- the owner's other members in its repository, with their doc comments and without their bodies;
- its file and its repository;
- the same-file functions it calls or that call it.

Decide what each function is, from its contract: what its name, its documentation and the code around it say it
is for. Read the body to answer the questions below. A body that breaks its own contract is still judged by
the contract.

## The law in question

*One receiver, n calls, n distinct results.* Take a fresh receiver (an instance from an initialiser, or a fresh
value of the `inout` state the function updates) and call the function n times with any inputs. The results are
pairwise distinct, with two exceptions:

- a sentinel the function documents or returns from a guard, such as `""` for an item with no name;
- results the contract says are not identifiers, such as an alias a format writes only inside a comment.

A **memoizing** uniquifier owes a different form: equal keys give equal results, and distinct keys give
distinct results.

## Verdicts: give exactly one

- **UNIQUIFIER.** The function issues a name, identifier or alias, and keeps state across calls (its receiver's
  stored properties, or an `inout` parameter) so that no call returns a result an earlier call on the same
  state returned. Typical shapes: test a candidate against the names already issued and decorate it with a
  counter or suffix on a hit; or append a counter that only grows. A counter that only grows still counts.
- **MEMOIZING.** The same, except that a key seen before gets back the result it got the first time. Typical
  shape: an early return of a stored result for the key, then a uniquifier for a new key.
- **BATCH.** It makes a whole collection of names distinct in one call, keeping no state between calls.
- **LOOKUP.** It computes a name that is not yet in the state it is given, but does not record the name it
  returns. Its caller does the registering, so two calls with nothing recorded between them can return the
  same result.
- **NOT-UNIQUIFIER.** Anything else: removing duplicates from a collection (`uniqued()`), a counter used for
  logging or statistics, a round-robin or modular counter that repeats by design, a pool that recycles released
  names, a name built from a UUID or a hash with no counter, formatting, parsing. Give a short reason.
- **UNDETERMINED.** The text does not decide it, even after reading the files allowed below.

## For UNIQUIFIER and MEMOIZING, also answer

- **expressible** (true or false). True when the function's contract promises the law for a fresh receiver
  (or a fresh `inout` value) **with nothing else called first**, and a test could set that up: construct the
  receiver from what the function's own module offers, draw the inputs, and call the function n times. Whether
  the body keeps that promise is `body_disagrees`, not this. It is false in any of these cases:
  - the contract needs another call first, such as a setup or reservation step;
  - the state cannot be made fresh, because it is global, or static and shared;
  - an input cannot be built.

  Internal API that a test reaches with `@testable import` counts as offered by the module.
- **setup** (true or false). True when the contract requires a different call before the first call, such as
  reserving the names a later call must avoid.
- **body_disagrees** (true or false). True when you can name a sequence of calls, allowed by the contract,
  on which the body returns one result twice. For MEMOIZING, it is also true when the body gives two distinct
  keys one result, or one key two results.
  - Give the sequence in `witness`.
  - The usual cause: a decorated candidate equals a name issued earlier or later, because the decoration is
    never checked against every name issued.
  - A sequence that skips a setup call the contract requires is not allowed by the contract.

Answer `null` for these three when the verdict is not UNIQUIFIER or MEMOIZING.

**Before answering expressible or setup, read the row's whole file and the owner's members shown.** A documented
requirement to call another method first settles setup as true and expressible as false. For example, a doc
comment saying a reservation must happen "before the first" call. A test or a caller elsewhere that omits that
call does not change this.

## Rules

- You may read only your packet and, for context, source files under the row's own repository path. Never open,
  list or search a `docs`, `scripts` or `fixtures` directory of the SwiftInferProperties repository (a row from
  that repository is read through its own file only), any `.json` file, any other packet or any other judge's
  output. Never search for a function's name outside the row's own repository.
- Judge each row on its own. Do not try to guess what anyone expects the answers to be, and do not count.
- Write your records as a JSON list to the output path you are given, one record per row, every row of the
  packet once:

```json
[{"label": "packet-01/1", "verdict": "UNIQUIFIER", "expressible": true, "setup": false,
  "body_disagrees": false, "witness": "", "sentinel": "\"\" for an item with no name",
  "reason": "one sentence"}]
```
