> **Historical conversation — captured before the kit's v2.0 rename.** The recommendation discussed below was adopted:
> - `SwiftProtocolLaws` → **`SwiftPropertyLaws`** (kit repo, pinned at `from: "2.0.0"`)
> - `ProtocolLawKit` → **`PropertyLawKit`** (library product)
> - `ProtoLawCore` → **`PropertyLawCore`** (library product)
>
> The "do it before SwiftInferProperties M3 ships" sequencing in the first reply was followed in spirit. Symbol references in the body below preserve the names current *at the time of the conversation* (`ProtoLawCore` / `ProtocolLawKit` describe the kit as it existed pre-2.0); they shouldn't be retroactively renamed in this historical text.

-----

❯ do not change any code: i'm considering expanding propert-based testing to more than protocols. Perhaps collections, perhaps algorithms, perhaps asynchsequence, and perhaps   

  map/filter. In that case, I think "protocollaws" is too restritive. Thoughts?                                                                                                  

  

⏺ Agree the name gets restrictive the moment you add anything that isn't a protocol-conformance law — algorithm contracts (sort stability, partition correctness), functor laws

  on map/filter, and AsyncSequence cancellation/back-pressure invariants are all "laws" but none are protocol laws. The cleanest umbrella is just **"laws"**: something like

  SwiftLawKit / LawKit (or SwiftPropertyLaws if you want to keep "property" as the genus and "laws" as the differentia) covers protocol laws, algorithm contracts, and           

  higher-order-function laws under one roof without committing to a taxonomy you'll outgrow again. Main tradeoff: SwiftInferProperties is already pinned to ProtoLawCore /

  ProtoLawKit symbols (v1.6 promoted DerivationStrategist, v1.7 promoted MemberwiseEmitter) — every additional consumer makes the rename more expensive, so if you're seriously  

  considering this, doing it before v2.0 / before SwiftInferProperties M3 ships is much cheaper than after.                                                                    

  

  One framing that might help decide: the _mechanism_ you've built (generator derivation, strictness tiers, suppression, replay-with-environment-fingerprint, planted-bug          

  self-test) is generic over "what's the property?" — protocols are just the first instantiation. If the next instantiations are algorithm contracts and functor laws, the rename

   is recognizing what the kit already is, not redirecting it.                                                                                                                   

✻ Churned for 32s                    

  

❯ if we were to expnad beyond protocols for property based testing, which area should we try first?                                                                              

⏺ **Map/filter (functor laws) first.** They're the strongest signal that the kit isn't "just protocol laws" — xs.map(id) == xs, xs.map(g ∘ f) == xs.map(f).map(g),                   

  xs.filter(p).filter(q) == xs.filter { p($0) && q($0) } are operation-level laws, not type-level laws, so they exercise a category of property the current kit literally cannot

  express. They also reuse 100% of what you already have (Array generators are shipped, the backend already takes (Input) -> Bool), and they're the canonical PBT examples in

  every other ecosystem (QuickCheck, Hypothesis, fp-ts) so adopters will recognize them immediately.                                                                             

  The tradeoff is the HKT problem: functor laws "naturally" apply to anything with a map (Array, Optional, Result, custom types), but Swift has no higher-kinded types, so you   

  either ship them as concrete per-type laws (checkArrayMapLaws, checkOptionalMapLaws, …) or invent a macro/protocol-witness shape that lets users register their own map-bearing

   type. I'd start concrete on the four or five stdlib types that ship map/filter/compactMap/flatMap and let the witness shape emerge from real usage rather than designing it up

   front.                                                                                                                                                                      

  

  I'd put **algorithms second** (sort stability, partition correctness, binary search) — high bug-catch payoff but ground-truth oracles are harder to write — and **AsyncSequence last**,

   because async generator shape + cancellation semantics + near-miss tracking under concurrency is a much bigger design lift than the marginal coverage gain.

✻ Churned for 33s                                                                                                                                                              

❯ any other area that I did not mention?                                                                                                                                         

⏺ Three categories worth considering that you didn't list:                                                                                                                       

  **Stateful / model-based testing.** Generate a sequence of method calls against a mutable object (push, pop, peek, …) and check invariants hold after every step against a simple  

  reference model. This is the category that PBT-on-pure-functions literally cannot reach — it catches "method ordering X then Y corrupts state" bugs that no per-call law will  

  surface. Erlang QuickCheck built its reputation on this; it's also a totally different generator shape (commands, not values), so it's a meaningful expansion of the kit's     

  surface rather than a rename.                                                                                                                                                  

  **Round-trip codec / parser laws (beyond Codable).** decode(encode(x)) == x, parse(serialize(x)) == x, compress(decompress(x)) == x, apply(diff(a, b), a) == b. The current kit    

  handles round-trip _only_ for Codable specifically; the general "any encode/decode pair" form is the single most popular PBT example in QuickCheck/Hypothesis/fp-ts and is

  exactly what SwiftInferProperties' M5 cross-function pair-discovery (encode/decode, serialize/deserialize, push/pop) is already aimed at — a kit-side primitive for it would   

  let SwiftInferProperties stop hand-rolling the assertion.                                                                                                                    

  

  **Differential testing.** Run the same generated input through two implementations and assert agreement: reference vs. optimized, swift-collections vs. stdlib, pre-refactor pinned

   snapshot vs. post-refactor code. Almost zero new design — it's "two functions, one input, assert outputs equal" — but it unlocks characterization-test workflows ("I

  refactored a hot path, prove I didn't change behavior") that the current law-based framing doesn't cover.                                                                      

  If I had to rank against your original four for first expansion: I'd actually put **round-trip codec laws above functor laws**, because the SwiftInferProperties tie-in is concrete

   and the bug-catch density is historically higher. Functor laws are the more elegant demo; codec round-trips are the more useful primitive.

✻ Crunched for 43s                                                                                                                                                             

❯ I think I forgot to say swift-collections. Is that in stateful/model-based testing?                                                                                            

⏺ Not exactly — swift-collections is a **target** (a library of types to test), not a category of test. But it's the single most natural target for stateful/model-based testing in  

  the Swift ecosystem: Heap, Deque, OrderedSet, OrderedDictionary, BitSet, TreeSet are all "stateful container with a small command vocabulary and an obvious reference model" — 

  exactly the shape Erlang QuickCheck made its reputation on. Generate a command sequence (insert/remove/popMin/popMax/…), run it against the swift-collections type and a       

  reference model (sorted Array for Heap, Array with dedupe for OrderedSet), and assert observable equivalence after every step.                                                 

  It also lights up **differential testing** strongly — OrderedSet vs. Array for order-preserving ops, TreeSet vs. Set for set ops, Deque vs. Array for sequence ops — and Validation

   Pass 3 already pins swift-collections@8e5e4a8f and runs the kit's protocol laws against TreeSet<Int>, so you have an existing precedent for treating it as a validation     

  target. Extending that precedent into stateful + differential is the highest-leverage thing you could do with swift-collections specifically: protocol laws caught zero bugs   

  there, but stateful command-sequence tests historically catch a lot.                                                                                                         

  

  So the framing I'd use: "swift-collections is the proof-of-value target for stateful/model-based testing," not a separate area.