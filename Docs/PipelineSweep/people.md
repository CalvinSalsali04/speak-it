# Lane: people — are people correctly identified, attached, and never dropped?

Frame: Monday 2026-08-03 10:00 America/Toronto. Probe = `scratchpad/frozen/probe`.
Corpus: **940 distinct utterances** across 13 files in `scratchpad/people/`, every
one run **cased and `.lowercased()`** and diffed.

> Line numbers below were re-verified against the working tree at the end of this
> run. The main session is editing these files concurrently — `ThoughtExtractor.swift`
> has moved ~100 lines since the probe was frozen — so anchor on the quoted code, not
> the number.

Headline: on a 372-utterance cased/lowercased diff, **79 (21%) change behaviour**
purely because of capitalization. **41 lose a row outright.** The clause-splitting
gap is worse than the brief's single probe suggests: it is not "multi-person
conjunctions" — it is *every* verb-elided conjunct, and it costs **313 of 341**
common first names.

---

## Headline answer to the lexicon question

**Do not ship a first-name lexicon. It fixes 26% of the problem and makes an
existing, already-shipping bug measurably worse.**

Three measured reasons.

**1. The object slot does not need a lexicon — it already works, cased and
lowercased.** I ran `call <name> tomorrow` for **341** distinct first names
(US top-100 M/F, ordinary-word names, non-Anglo names), lowercased.
**338/341 resolved a person.** The only three failures — `will`, `may`, `june` —
fail *cased too*, because they sit in the `neverName` stoplist (`modals`,
`temporalWords`). A lexicon adds nothing here; to "fix" those three it would have
to *override* a deliberate stoplist.

**2. The lexicon would only cover a quarter of the real gap.** The gap is the
clause split, and the thing on the right of "and" is very often not a first name.
Over 50 realistic conjuncts (`people/m-lexcoverage.txt`), 47 lose the second row today:

| recovered by | count | % |
|---|---|---|
| a bundled first-name lexicon | 12 | **26%** |
| a lexicon-free positional rule (below) | 47 | **100%** |

The 35 the lexicon misses are: kinship (`and dad friday`, `and grandma friday`,
`and nana thursday`), described people (`and my sister friday`, `and the dentist
monday`, `and the vet friday`), titled people (`and dr patel friday`, `and
professor okonkwo monday`, `and coach williams thursday`, `and aunt ruth friday`),
**surnames** (`and patel friday`, `and okonkwo tomorrow`, `and nakamura monday`,
`and kowalski thursday`, `and o'sullivan friday`, `and van dijk tomorrow`),
nicknames and initials (`and mikey friday`, `and bex monday`, `and sanj thursday`,
`and cj friday`, `and jt tomorrow`, `and pops friday`), and possessive people
(`and sam's mom friday`, `and marcus's manager monday`).
And 26% is *generous*: I counted my own 341-name list as the lexicon, and it
happens to contain Oluwaseun, Ngozi, Kwame, Hyunwoo, Takeshi, Elif, Siobhan and
Aleksandr. A real bundled US-census top-1000 list contains none of them; realistic
coverage is closer to **8%**.

**3. "Ordinary words become people" is not a hypothetical risk of the lexicon —
it is a bug that ships today, and a lexicon feeds it.** The `allowLowercase` path
already accepts any non-stoplisted token in the object slot *and* greedily joins
the next word. Observed today, no lexicon involved (`people/k-lexrisk.txt`):

| utterance | person filed |
|---|---|
| `email frank feedback to the team friday` | **Frank Feedback** |
| `text art supplies to the studio` | **Art Supplies** |
| `call rose gold about the ring` | **Rose Gold** |
| `send drew conclusions to the board` | **Drew Conclusions** |
| `email miles driven for the expense report` | **Miles Driven** |
| `email ray tracing notes to the team` | **Ray Tracing** |
| `text sky conditions to the pilot` | **Sky Conditions** |
| `send penny stocks research friday` | **Penny Stocks** |
| `email joy division tickets friday` | **Joy Division** |
| `call summer camp about registration` | **Summer Camp** |
| `email autumn schedule to parents` | **Autumn Schedule** |
| `call faith based groups monday` | **Faith Based** |
| `send bill to the client friday` / `ask bill for a refund` | **Bill** |
| `ask hope for the best` | **Hope** |
| `tell mark the spot on the map` | **Mark** |
| `call chip in for the gift` | **Chip** |

17/20 of that probe file files a false person. Every one of those heads
(frank, art, rose, drew, miles, ray, sky, penny, joy, summer, autumn, faith,
bill, hope, mark, chip) is a name a lexicon would have to contain. **The lexicon
supplies positive evidence for exactly the tokens that are already over-claiming.**

### Is positional evidence enough on its own? Yes — but not the naive version.

I built and scored a candidate lexicon-free rule (`people/rule.py`) and ran it over
**432 labelled cases**: **precision 1.000, recall 0.994** (2 misses: `may`, `june`).

The naive positional rule — "and `<head>` `<weekday>`" — is **not** enough, and I
have the counter-evidence. Simulating that rule by capitalizing the right-hand head
splits 34/44 shapes that must stay together: `pay rent and Insurance Monday`,
`do laundry and Dishes tomorrow`, `clean the kitchen and Bathroom Saturday`,
`wash the car and Windows Saturday`, `defrost chicken and Salmon tonight`.
Capitalization is currently doing *all* the discriminating work; remove it and the
rule has no precision.

What restores precision is a **semantic gate that already exists in the codebase**:

> **Gate 1** — the LEFT conjunct must itself resolve a `PersonMention`
> (`PersonMentionResolver`, unchanged).
> **Gate 2** — the LEFT conjunct must end with a temporal, or with the person itself
> (so `call mom tomorrow` / `text alex tonight` / `call mom` qualify; `ask mom about
> dinner` does not).
> **Gate 3** — the RIGHT conjunct is ≤4 tokens, carries no verb of its own, its head
> is not a temporal / verb / `commonObjects` member, and a determiner head is allowed
> only when a `relationNouns` word follows it (`the dentist`, `my sister`).

Measured on my negative corpus: **0 of 40** genuine list-continuations have a left
conjunct that names a person (`pick up milk`, `pay rent`, `email hr`,
`call insurance`, `call the plumber`, `book the vet`, `email the landlord` — all
person=nil). The gate is free precision.

**Honest caveat.** Gates 1–3 also fire on `call mom tomorrow and laundry saturday`,
`text alex tonight and groceries tomorrow`, `call sarah friday and yoga saturday`
(11/14 of an adversarial set). But splitting those is *correct* — they genuinely
are two thoughts — and the split fragment is filed with **person = nil**
(`laundry saturday`, `groceries tomorrow`, `yoga saturday`, `dinner tomorrow` all
probe to `person=-`). Splitting and naming are separable decisions; only the split
needs to change.

**One extra change is required or the fix is only half a fix.** A bare lowercase
fragment names nobody on its own: `alex friday` in isolation → `person=-`,
`type=event`. Cased `Alex Friday` → `person=Alex`, `type=personFollowUp`. So the
split must **carry the left conjunct's verb onto the right fragment** (analysis text
only — the quote must stay verbatim), or the recovered row arrives on Today as a
nameless event.

**Recommendation:** implement the three-gate parallel-object-ellipsis rule in
`ThoughtExtractor.isIndependentConjunct`, carry the verb, and ship **no lexicon**.
Then separately tighten the `allowLowercase` label-join (cluster P4/P5), which is
the change a lexicon would have made harder rather than easier.

---

## Root-cause clusters

### P1 — CRITICAL — Clause boundary between two people is decided by capitalization alone
**Mechanism.** `isIndependentConjunct`,
`SpeakIt/Repositories/ThoughtExtractor.swift:1010-1101`. For a verb-elided conjunct
the only two paths that can return `true` are the `NLTagger .nameType == .personalName`
check (line 1088) and the capitalized-opening-token fallback (line 1094).
I compiled a standalone `NLTagger` probe (`people/tag.swift`): **`.nameType` never
fires on these fragments at all** — `Alex Friday` is tagged `PlaceName`,
`Priya Friday` / `priya friday` / `alex friday` are `(none)`. So **line 1094's
capital letter is the entire rule**. `PersonMentionResolver` is never consulted.

**Volume.** `call mom tomorrow and <name> friday` over 341 first names:
**cased 340/341 split; lowercased 28/341 split. 313 names lose the second row.**
The 28 survivors are luck, not rule: NLTagger mislabels `sarah`, `xiaoming` as
*Verb*, which trips a different branch.

**Worse than a missing row — the surviving row's time is hijacked.**
| utterance | cased | lowercased |
|---|---|---|
| `Text Mom tonight and Dad tomorrow` | 2 rows, Mom due **Mon Aug 3 20:00** | 1 row, due **Tue Aug 4 20:00** |
| `Text Sam Thursday and Alexandra Sunday` | 2 rows, Sam due **Thu Aug 6** | 1 row, due **Sun Aug 9** |
| `Meet Priya and Marcus at noon` | 2 rows, Priya due **nil** | 1 row, due **Mon Aug 3 12:00** |
| `Call Mom tomorrow and Alex Friday and Priya Saturday` | **3 rows** | **1 row** |
| `Call Dr. Patel Monday and Dr. Chen Thursday` | 2 rows | 1 row |
| `Call Alex at nine and Priya at ten` | 2 rows | 1 row, 21:00 |
| `Text Priya this morning and Marcus this afternoon` | 2 rows | 1 row, **15:00** |

### P2 — CRITICAL — A described, kinship or titled second person never splits, **cased or lowercased**
Same line 1094: the head must be a capitalized *token*, so a determiner head is
excluded outright and the branch is never reached.
| utterance (as typed, cased) | observed | expected |
|---|---|---|
| `Call Mom tomorrow and my sister Friday` | **1 row**, person=Mom, due Tue Aug 4 | 2 rows |
| `Call Mom tomorrow and the dentist Friday` | **1 row** | 2 rows |
| `Call Priya Friday and the dentist Monday` | **1 row**, due **Mon Aug 10** — Priya's Friday destroyed | 2 rows |
| `Text Alex tonight and my brother tomorrow` | **1 row**, due **Tue Aug 4 20:00** — "tonight" became tomorrow | 2 rows |
| `Call Mom tomorrow and my boss Friday` | **1 row** | 2 rows |

This is a pre-existing CRITICAL independent of the casing bug, and the three-gate
rule above fixes it in the same change.

### P3 — CRITICAL — Names beginning "Ok"/"Um"/"Uh" are mangled in the row title
**Mechanism.** `ThoughtTitleFormatter.polished`,
`SpeakIt/Repositories/ThoughtOrganizer.swift:115`:

```swift
of: #"^(?:(?:um+|uh+|okay|ok|hey\s+siri)\s*[,.:;-]?\s*)+"#
```

There is **no `\b`**, and `\s*` makes the separator optional, so the pattern eats a
word-internal prefix. (`Actionability.swift:397` has the same defect:
`^(?:okay|ok|so|well|oh|also|and|um+|uh+)?[\s,]*`, no `\b`.)
Casing-independent, and the failure is concentrated in non-Anglo names.

| utterance | row title shown | person field |
|---|---|---|
| `Okonkwo is presenting Thursday` | **Onkwo** is presenting Thursday | Okonkwo |
| `Okafor moved to Calgary` | **Afor** moved to Calgary | Okafor |
| `Okoye is joining the team` | **Oye** is joining the team | Okoye |
| `Oksana called me at five` | **Sana** called me at five | Oksana |
| `Okada is visiting Friday` | **Ada** is visiting Friday | Okada |
| `Okalani is visiting Friday` | **Alani** is visiting Friday | Okalani |
| `Umar is presenting Thursday` | **Ar** is presenting Thursday | Umar |
| `Uma Thurman is presenting` | **A** Thurman is presenting | Uma Thurman |
| `Umberto called me at five` | **Berto** called me at five | Umberto |
| `Umut is joining the team` | **Ut** is joining the team | Umut |
| `Uhura is presenting Thursday` | **Ura** is presenting Thursday | Uhura |

The immutable quote survives, so this is recoverable — but the row the user reads
shows a destroyed name, and it disagrees with the person label on the same row.
Fix: add `\b` after the alternation in both patterns.

### P4 — BEHAVIORAL — Under lowercase the person label swallows the next word
**Mechanism.** `PersonMention.swift:471-481` — the two-word join fires when
`first.isCapitalized || allowLowercase`, and `properName` then accepts any token not
in `neverName`. Adverbs, adjectives and `happy` are not in `neverName`.
**24 of 372** aggregate diffs; 21/49 in the dedicated probe (`people/b-labelgreed.txt`).

| lowercased utterance | person filed | expected |
|---|---|---|
| `wish grandma happy birthday tomorrow` | **Grandma Happy** | Grandma |
| `ask sam nicely` | **Sam Nicely** | Sam |
| `call priya twice` | **Priya Twice** | Priya |
| `meet marcus downtown` | **Marcus Downtown** | Marcus |
| `call mom quickly before noon` | **Mom Quickly** | Mom |
| `call alex right away` | **Alex Right** | Alex |
| `tell alex honestly what happened` | **Alex Honestly** | Alex |
| `owe priya twenty bucks` | **Priya Twenty** | Priya |
| `i keep forgetting to call grandma, gotta do it sunday` | **Grandma Gotta** | Grandma |

User-visible consequence: the same human gets two entries in Memory → People.
`call sarah tomorrow` files under *Sarah*; `text sarah happy birthday tomorrow`
files under *Sarah Happy*.

### P5 — BEHAVIORAL — Ordinary noun phrases become people in the object slot
Same `allowLowercase` path, one step further: nothing in the object slot is checked
for name-likeness beyond the `neverName` stoplist. 17 examples in the lexicon table
at the top of this file. This is the cluster a first-name lexicon would amplify.

### P6 — BEHAVIORAL — Lists of three or more people fuse two names into one invented person
**Mechanism.** Same two-word join (`PersonMention.swift:475`), this time with both
tokens capitalized. Casing-independent — it happens on *well-cased* input.

| utterance | observed | expected |
|---|---|---|
| `Call Mom Dad and Grandma this weekend` | row 1 person=**Mom Dad**; row 2 `Grandma this weekend` → **Memory/note**, person=nil | 3 Today rows: Mom, Dad, Grandma |
| `Call Sarah, Daniel, and Priya tomorrow` | row 1 person=**Sarah Daniel**; row 2 Priya | 3 rows |
| `Text Alex Priya and Marcus about the offsite` | row 1 person=**Alex Priya**; row 2 `Marcus about the offsite` → Memory, person=nil | 3 rows |
| `Email Alex Priya Marcus and Sarah the deck` | row 1 person=**Alex Priya**; row 2 `Sarah the deck` → Memory, person=nil | 4 rows |

A person named "Mom Dad" is content *invented*, which is the CRITICAL bar; I rate
it BEHAVIORAL only because no words are lost from title or quote.

### P7 — BEHAVIORAL — Pronoun antecedent resolution is switched off by lowercase
**Mechanism.** `ThoughtExtractor.resolvingPronouns`
(`SpeakIt/Repositories/ThoughtExtractor.swift:699-701`) filters
`confidence > .low`; `personPhrase` assigns `.low` to every non-kinship lowercase
name (`PersonMention.swift:486-489`). So the antecedent list is empty for any
lowercased transcript. 8/20 in `people/f-pronoun.txt`.

| lowercased utterance | second row's person, cased → lowercased |
|---|---|
| `call yusuf tomorrow and thank him for the ride` | Yusuf → **nil** (and category people → general) |
| `ping oluwaseun monday and ask him about the schedule` | Oluwaseun → **nil** |
| `text priya tonight and confirm her flight` | Priya → **nil** |
| `meet marcus thursday and give him the keys` | Marcus → **nil** |
| `call sam tomorrow and get his address` | Sam → **nil** |
| `don't call catherine tomorrow, call her friday` | Catherine → **nil** |

### P8 — CRITICAL (narrow) — `make sure X` / `get X to` hardcode a literal capital
`PersonMention.swift:243-252` in `objectIndex`, the only two rules in the file that
ignore `allowLowercase`:
```swift
list[candidate].isCapitalized || kinship.contains(list[candidate].lower)
```
`Make sure Sam returns the books` → person=Sam; `make sure sam returns the books` →
**person=nil**. Same for `Get Alex to sign the form` → `get alex to sign the form`.
These were the only 2 person-drops in a 95-utterance single-person sweep, so the fix
is a one-line `|| allowLowercase` in each.

### P9 — CRITICAL — Surname particles drop the whole name, and only when *correctly* cased
`isNameToken` requires `word.isCapitalized` when `allowLowercase` is false, and
`isCasuallyCased` returns false as soon as the sentence carries a real capital.
Rendering invariance is violated **in the opposite direction** here.

| utterance | person |
|---|---|
| `Call de Souza Monday` | **nil** |
| `Text van Dijk tonight` | **nil** |
| `call de souza monday` | De Souza |
| `text van dijk tonight` | Van Dijk |

Affects `de`, `van`, `von`, `da`, `di`, `bin`, `al`, `ter`, `del`.
(`Al-Rashid`, `Ben-David`, `O'Sullivan`, `MacDonald`, `Jean-Luc` are all fine —
the hyphen/apostrophe path works.)

### P10 — BEHAVIORAL — The appositive "my sister Amy" throws the name away
Casing-independent. `followUpTarget` returns `.described("my sister Amy")`, and
`ThoughtOrganizer.swift:346-348` maps `.described` → `personName = nil`, so a name
the user *did* say is discarded.

| utterance | observed | expected |
|---|---|---|
| `Call my sister Amy tomorrow` | Today/personFollowUp, person=**nil** | person=Amy |
| `Text my brother Dan tonight` | person=**nil** | Dan |
| `Email my friend Priya the link` | person=**nil** | Priya |
| `Ask my neighbour Frank about the fence` | person=**nil** | Frank |
| `My sister Amy is coming Friday` | Today/event, person=**nil** | Amy |
| `My brother Dan just moved` | Memory/note, person=**nil**, cat=general | Dan, cat=people |

### P11 — BEHAVIORAL — Two-word-name Memory facts drop the subject under lowercase
`factSubject` (`PersonMention.swift:304`) hardcodes `list[1].isCapitalized` for
the surname join instead of honouring `allowLowercase`, and the un-joined surname
then fails the predicate test, so the *whole* subject is lost — not just the surname.
`Alex Kim is joining the team` → person=**Alex Kim**;
`alex kim is joining the team` → person=**nil**, category general.

### P12 — METADATA — Memory facts file nobody when the predicate is outside the closed vocabulary
Casing-independent. `strongPeoplePredicates` / `humanActivityParticiples` /
`humanActionVerbs` are deliberately narrow, and the near misses are common:
`Sarah Jane got the promotion` (nil), `Priya Sharma is the new lead` (nil),
`O'Brien is handling the roof` (nil), `Aunt Ruth is turning eighty` (nil),
`Coach Williams changed practice to Thursday` (nil),
`Marcus got engaged last weekend` (nil), `Grandma's recipe uses buttermilk` (nil).
Each lands in Memory but under no name, so it never appears on the person's profile.

### P13 — BEHAVIORAL — The second person in "X and Y" gets a row but no name, sometimes in Memory
Casing-independent (this shape does split).
`Text Sarah and Marcus about the move` → row 2 `Marcus about the move`,
**Memory/note, person=nil**. `Email Marcus and Priya the deck` → row 2
`Priya the deck`, **Memory/note, person=nil**. `Meet Priya and Marcus at noon` →
row 2 `Marcus at noon`, Today/event, person=nil.
Same root cause as the missing verb-carry in P1: the fragment has no verb, so
`addressMentions` has no object slot to read.

### P14 — BEHAVIORAL — People verbs routed wrongly (adjacent lane, noted for completeness)
`Get back to Daniel by Thursday` → **type shopping, category shopping**.
`Get Alex to sign the form` → **shopping**. `Gotta get back to Priya about the
lease before Friday` → **shopping**.
`Circle back with Priya next week`, `Reach out to Marcus about the lease`,
`Ping Sarah about standup`, `DM Daniel the link`, `Congratulate Priya on the
promotion`, `Thank Marcus for the ride` → all **Memory/note** when they are actions
for Today.
Phantom rows: `Reminder, text Priya tomorrow` → extra row titled *"Your reminder"*;
`Call wait no text Sarah tomorrow` → extra row *"Call wait no"* (Today, people);
`Um so I need to like call Priya tomorrow about the thing` → extra row *"Like"*;
`Sarah / Marcus - schedule the offsite` → extra row *"Sarah / Marcus -"*.

---

## Already correct — guards I probed that work, do not break these

**The deliberate non-people guards all hold, cased *and* lowercased**
(`people/k-lexrisk.txt`). Every one → `person=nil`:
`Finish the Alex report` · `finish the alex report` · `Read about Ada Lovelace` ·
`read about ada lovelace` · `Book the Anderson conference room` ·
`Update the Johnson invoice` · `Review the Miller contract Friday` ·
`Call the Alex Hotel about the booking` · `Ship the Chen prototype tomorrow` ·
`Read the Malcolm Gladwell book` · `Watch the Sarah Silverman special` ·
`Listen to the Taylor Swift album` · `Order the Julia Child cookbook` ·
`Return the Stephen King novel` · `Buy the Neil Gaiman collection`.
The mechanism is positional, not lexical: a determiner in the object slot sends the
phrase to `describedTarget` instead of `personPhrase`. **A lexicon must not be
allowed to override that determiner gate.**

**Names that collide with places are read as people, correctly** — NLTagger's
`PlaceName` label does not win over position:
`Call Austin tomorrow`, `Text Jordan Friday`, `Email Georgia about the deposit`,
`Call Paris Monday`, `Text Sydney tonight`, `Call Brooklyn tomorrow`,
`Email Madison Friday`, `Call Dakota Monday`, `Text Phoenix tomorrow` — all file the
person. Lowercased too.

**Non-Anglo names survive both casings** in the object slot: Yusuf, Siobhan,
Oluwaseun, Xiaoming, Nguyen, Aleksandr, Fatima, Rahul, Ngozi, Bogdan, Mahmoud,
Anjali, Kwame, Sinead, Ivan, Elif, Hyunwoo, Takeshi, Wei Chen, Priya Sharma —
plus `Jean-Luc`, `O'Sullivan`, `MacDonald`, `Al-Rashid`, `Ben-David`, `O'Brien`.
(`de Souza` / `van Dijk` are the exception — see P9.)

**Ordinary-word first names work in the object slot, both casings**: Mark, Bill,
Rose, Grace, Sunny, Art, Hope, Frank, Dawn, Penny, Rusty, Faith, Miles, Rich, Drew,
Sky, Ray, Bob, Chase, Summer, Autumn, Joy, Angel, Melody, Cliff, Chip, Buddy, Sonny,
Woody, Bud, Norm, Precious — **338/341 names tested.**

**`neverName` is doing real work and should not be relaxed**: `will`, `may`, `june`
are refused as names in the object slot (`Ask Will about the lease`, `Call May
tomorrow`, `Email June about the invoice` → person=nil). That is the correct
trade — `tell will he can start monday` and `ask may be we can move it` must not
file people.

**Titles work**: `Dr. Patel`, `Doctor Chen`, `Professor Okonkwo`, `Coach Williams`,
`Officer Reyes`, `Aunt Ruth`, `Uncle Tom`, `Grandma Nora` — all correct, and
`dr patel` lowercased still yields `Dr. Patel`. A bare title names nobody
(`Professor said…`).

**Possessive people work**: `Sam's mom`, `Priya's assistant`, `Marcus's manager`,
`Sarah's boss` → the specific human; `I need to return Priya's book` → Priya;
`Alex's mom is in the hospital` → Alex; all casing-invariant.

**Quoted speech does not confuse the resolver**: `She said "call Priya Friday"` →
Priya; `Alex said "the deadline moved to Friday"` → Alex.

**List continuations do not split** (the guard the new rule must preserve):
`clean the garage and the basement Saturday`, `book the flight and the hotel
tomorrow`, `water the plants and the herbs tomorrow`, `return the books and the
DVDs Friday`, `pay rent and insurance monday`, `email hr and it friday`,
`call the plumber and electrician monday`, `book the vet and groomer thursday`,
`cancel netflix and spotify monday` — 40/40 stay one row, and **0/40 have a left
conjunct that names a person**, so Gate 1 protects all of them for free.

**Compound subjects, recurrence and idioms hold, both casings**:
`Alex and his brother are coming Friday` (1 row), `Priya and her mom are visiting
Sunday`, `Mom and Dad are coming Friday`, `Remember Alex likes golf and hates
mornings`, `Yoga every Tuesday and Thursday`, `I've been going back and forth on
this but I need to call the insurance company`.

**Single-person address is essentially casing-invariant already**: a 95-utterance
sweep of address verbs, prepositional verbs, social nouns, kinship, titles,
possessives, disfluency and non-Anglo names produced **only 3 diffs** — the two P8
hardcoded capitals and one label-greed case. The `isCasuallyCased` / `allowLowercase`
design is sound; it is `isIndependentConjunct` that never got the memo.

---

## Files
`scratchpad/people/` — `a-conjunctions.txt` `b-labelgreed.txt` `c-memoryfacts.txt`
`d-wordnames.txt` `e-broad.txt` `f-pronoun.txt` `g-splitmatrix.txt` `h-names.txt`
(341 names) `i-negatives.txt` `j-riskset.txt` `k-lexrisk.txt` `l-shapes.txt`
`m-lexcoverage.txt` `all.txt`; tooling `pp.py` (probe parser + cased/lowered differ),
`rule.py` (candidate rule + scorer), `tag.swift`/`tagger` (standalone NLTagger probe).
