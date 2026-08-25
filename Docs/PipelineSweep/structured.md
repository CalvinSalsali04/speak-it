# Lane: structured — do captures with internal structure survive?

**502 utterances probed** across lists/shopping (148), recurrence (103+68 confirm),
location (83), quantities/numbers (100). Frame: Mon 2026-08-03 10:00 America/Toronto.

Corpus files: `scratchpad/structured/u1_lists.txt`, `u2_recur.txt`, `u3_loc.txt`,
`u4_num.txt`, `u5_confirm.txt`. Raw output: `o1.txt`–`o5.txt`.
Compact runner: `scratchpad/structured/c.sh`.

**Headline:** the *numbers* sub-area is clean — zero false clock times in 100
utterances. The other three are not. Everything found collapses into **9 causes**,
and the top three are narrow, mechanical, and independently fixable.

---

## Root-cause clusters, most impactful first

### C1 — Missing `\b` truncates the row title mid-word. CRITICAL. 12/15 probes.

**Mechanism.** `SpeakIt/Repositories/ReminderScheduler.swift:155`

```swift
of: #"(?i)\s*,?\s*(?:but|and)\s+(?:please\s+)?(?:remind\s+me|send\s+me\s+a\s+reminder)\b.*$"#
```

`(?:but|and)` has **no leading word boundary**. Any word ending in `-and` or `-but`
immediately before "remind me" is cut in half, and everything after it is discarded
from the title. Fires on: land, band, brand, stand, husband, island, demand, hand,
errand, grand, debut, Rand, understand.

| utterance | observed title | expected |
|---|---|---|
| `when I land remind me to text mom` | **"When I l"** | "Text mom" |
| `the band remind me to buy tickets` | **"The b"** | "Buy tickets" |
| `call my husband remind me to say sorry` | **"Call my husb"** | "Say sorry" |
| `I need to stand remind me to stretch` | **"St"** | "Stretch" |
| `the island remind me to book the ferry` | **"The isl"** | "Book the ferry" |
| `sales demand remind me to check stock` | **"Sales dem"** | "Check stock" |
| `put it in my hand remind me to hold it` | **"Put it in my h"** | "Hold it" |
| `call Rand remind me about the quote` | **"Call R"** (PER:Rand) | "Call Rand" |

The capture-level `sourceQuote` survives, so nothing is unrecoverable — but the row a
person reads on Today says "St". Adding `\b` before `(?:but|and)` fixes all 12.

---

### C2 — Digit quantities are deleted from shopping rows, title *and* quote. CRITICAL. 6 confirmed.

**Mechanism.** `SpeakIt/Features/Shopping/ShoppingGroups.swift:269`

```swift
.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "-" })
```

`recognizedProducts` tokenizes on *letters only*, so digits become separators and
vanish. Each product is then rebuilt from vocabulary words, and the number the person
said is gone from every field of the row.

| utterance | observed | expected |
|---|---|---|
| `buy 3 apples and 2 bananas` | 2 rows: "Buy apples" q=`apples`, "Buy bananas" q=`bananas` | "Buy 3 apples", "Buy 2 bananas" |
| `buy 2 milk and 3 bread` | "Buy milk", "Buy bread" | "Buy 2 milk", "Buy 3 bread" |
| `get 5 onions and 4 potatoes` | "Get onions", "Get potatoes" | quantities kept |
| `buy 1 chicken and 2 lemons` | "Buy chicken", "Buy lemons" | quantities kept |
| `buy 6 apples and 2 lemons` | "Buy apples", "Buy lemons" | quantities kept |

The same sentence behaves three different ways depending on punctuation and digit form
— this is the sharpest inconsistency in the lane:

- `buy 3 apples, 2 bananas` → **2 rows, quantities preserved** (comma path, correct)
- `buy 3 apples and 2 bananas` → **2 rows, quantities destroyed** (comma-less path)
- `buy three apples and two bananas` → **1 row, nothing split** (spelled-out numbers
  are unrecognized words, so the whole split is refused)

Correct row count for all three is 2, with "3"/"three" preserved.

---

### C3 — A leading time or place phrase splits off as its own contentless row, and the real action loses its schedule. CRITICAL/BEHAVIORAL. 33 utterances.

**Mechanism.** Segmentation treats `<temporal-or-place phrase> <bare imperative>` as
two thoughts. The recurrence/location metadata attaches to the *phrase* row; the action
row frequently gets nothing. The same content spoken as `remind me <phrase> to <action>`
is handled perfectly — the trigger is a bare imperative with no "remind me to" bridge.

| utterance | observed | expected |
|---|---|---|
| `every weekend clean the garage` | 2 rows: "Every weekend" (weekly d[1,7]) + **"Clean the garage" with no recurrence** | 1 row, Clean the garage, weekly Sat/Sun |
| `every 3 days water the fern` | "Every 3 days" (daily x3) + "Water the fern" **no recurrence** | 1 row, daily x3 |
| `every 2 weeks pay the cleaner` | "Every 2 weeks" + "Pay the cleaner" **no recurrence** | 1 row, weekly x2 |
| `every payday pay the visa` | "Every payday" (Memory note) + "Pay the visa" **no recurrence** | 1 row |
| `twice a day take the medication` | "Twice a day" (Memory note) + "Take the medication" **no recurrence** | 1 row |
| `at the office print the contract` | "At the office" (Memory note) + "Print the contract" **no location** | 1 row, LOC arrive work |
| `on my way home pick up milk` | "On my way home" (Memory note) + "Pick up milk" **no location** | 1 row |
| `every single day at 8 remind me to take the meds` | "Every single day at 8" event due **Mon Aug 3 20:00** + "Take the meds" needsReview, no date | 1 row, daily at 08:00 |
| `uh remind me every tuesday to like take the trash out` | row 1 title **"Like"** carries the weekly reminder; row 2 "Take the trash out" has nothing | 1 row, weekly Tue |
| `Monday to Friday at 7 wake up` | "Monday to Friday at 7" event due **Mon Aug 10 19:00** + "Wake up" → **Memory** | 1 row, weekdays 07:00 |

Others in the cluster: `every other day water the seedlings`, `every two months clean
the fridge`, `every hour on the hour check the oven`, `every quarter file the HST`,
`every paycheck put 200 in savings`, `every month on the 1st pay rent`, `on the 15th of
every month pay rent`, `the second Tuesday of every month book club`, `first Monday of
every month pay the mortgage`, `annually on March 2 renew the domain`, `every year on
March 2 renew the domain`, `every day this week check the mail`, `every day until
Friday take the antibiotics`, `every day for the next 10 days take the antibiotics`,
`every morning this week walk before work`, `every Tuesday until December pick up the
kids`, `twice a day for a week take the drops`, `on my drive home call my brother`,
`while I'm out pick up the parcel`, `the door code is 4416 write that down` (this last
one is arguably correct).

Correct row count is **1** in every case: a recurrence or a place is a property of the
action, not a separate thought.

---

### C4 — Bounded recurrence: "until <weekday>" overwrites the frequency; every other bound is silently dropped. CRITICAL.

**Mechanism.** `RecurrenceRule` (`SpeakIt/Models/DomainEnums.swift:101`) has
`frequency / interval / weekdays / anchor / ordinalWeekday / intervalSeconds` and **no
end date** — a bounded series is structurally unrepresentable. Worse, the trailing
weekday in "until Friday" is read as the *recurrence day*.

| utterance | observed | expected |
|---|---|---|
| `remind me every day until Friday to take the pills` | REC **weekly x1 days[6]**, due Fri Aug 7 | daily, ending Fri Aug 7 |
| `take the antibiotics every day until Friday` | REC **weekly x1 days[6]**, due Fri Aug 7 | daily until Fri |
| `every day until Thursday water the seedlings` | row 1 REC weekly days[5] | daily until Thu |
| `take the antibiotics every day for 7 days` | REC daily, **no bound** — recurs forever | daily × 7 |
| `every morning for two weeks do the exercises` | daily, no bound | daily × 14 |
| `every day this week check the mail` | daily, no bound | daily through Sun |
| `remind me every Monday until September to pay the sitter` | weekly Mon, no bound | weekly, ends Sept |

The first three are the dangerous ones: a person who says "take the antibiotics every
day until Friday" is given a reminder that fires **once a week, on Fridays**.

---

### C5 — The place-name reader swallows filler and subject words, destroying the saved-place match. CRITICAL/BEHAVIORAL. 8 utterances.

**Mechanism.** `SpeakIt/Repositories/LocationIntentParser.swift:108` — `placeTerminator`
is a *stop-list* (punctuation, `remind|tell|let|then|to `, an action verb, a time word,
or end of string), not a place grammar. Anything between the place word and the first
stop is absorbed into the name. Once a single extra word attaches, the exact-match
against `homeWords`/`workWords` (line 268) fails and the intent becomes
`.named("home please")` — a searchable place that resolves to nothing, so the reminder
never fires.

| utterance | observed place | expected |
|---|---|---|
| `when I get home please remind me to water the plants` | `named("home please")` | `.home` |
| `when I get home actually remind me to water the plants` | `named("home actually")` | `.home` |
| `uh when I get home can you remind me to like water the plants` | `named("home can you")` | `.home` |
| `when I get home I should really call the landlord about the leak` | `named("home i should really")` | `.home` |
| `next time I'm home look for the passport` | `named("home look for the passport")` + route **Memory** | `.home`, Today task |
| `so next time I'm at Costco I need to grab paper towels` | `named("costco i need")` | `named("costco")` |
| `whenever I'm at the pharmacy I need to pick up the prescription` | `named("pharmacy i need")` | `named("pharmacy")` |
| `next time I'm at Costco maybe grab paper towels` | `named("costco maybe")` | `named("costco")` |

Related: `next time I'm at the store buy batteries` → `named("store")`. The shopping
grouper deliberately refuses "the store" as a name (`genericPlaces`,
ShoppingGroups.swift:227); the location parser accepts it and will monitor a region it
cannot resolve. The two should share that list.

---

### C6 — Whole phrasing families are unrecognized and fall to Memory or to needsReview with no schedule. BEHAVIORAL. ~40 utterances.

Not one mechanism but one shape: a vocabulary that covers the canonical form and
nothing adjacent. Four sub-families:

**(a) "N times a period" recurrence — 0/9 recognized.** All land in Memory as notes.
- `twice a month review the budget` → Memory note, no recurrence
- `twice a week go to the gym` / `three times a week run` / `once a week vacuum` /
  `twice a year change the smoke detector batteries` / `every couple of days check on
  the sourdough` → same
- `once a month pay the credit card` → Memory note, title **"Pay the credit card"**,
  quote **"pay the credit card"** — *"once a month" is gone from both.* **CRITICAL.**
- `every second week take out the bins` → Memory note, title and quote **"take out the
  bins"** — *"every second week" gone from both.* **CRITICAL.**

**(b) Adverb recurrence after "remind me" — needsReview, no rule.**
`remind me daily to stretch`, `remind me monthly to check the smoke alarms`,
`remind me on weekends to water the garden`, `remind me twice a month to…`,
`remind me each payday to transfer to savings`, `daily standup at 9:30` (→ one-off
Tue 09:30, no recurrence). `SpeechRepair.swift:312` rewrites bare `daily`/`monthly`
only when followed by punctuation or `on|at|in|by|from|starting` — "remind me daily
**to** stretch" misses the lookahead.

**(c) Proximity and en-route location — 0/12 recognized.** None produce a
`locationIntent`; about half land in Memory.
`on my way home remind me to stop for gas`, `on the way to the airport remind me to
grab my passport`, `on my way out remind me to take the trash`, `on the way home stop
at the bank` (→Memory), `near the pharmacy remind me to grab my prescription`,
`when I'm near a Shoppers remind me to get advil`, `when I'm close to the pharmacy
remind me`, `when I drive past the bank remind me to deposit the cheque`,
`next time I'm near a mailbox mail the letter` (→Memory), `if I pass a Tim Hortons get
a coffee` (→Memory), `while I'm out pick up the parcel`, `when I'm around the corner
from work call her` (→Memory).

**(d) Arrival/departure verbs outside the grammar.** `arriveVerbs`
(LocationIntentParser.swift:37) omits *land*; the leave lead requires
`next time|when|whenever|once|as soon as` + `i|we`, so progressive forms miss.
`as I'm leaving work remind me to shut the window` → no location, needsReview.
`when I land remind me to text mom` → no location (plus C1).
`next time I'm downtown pick up the dry cleaning` → Memory note.
`if I'm ever at the mall buy new shoes` → Memory note.
`each payday transfer 200 to savings` / `every time I get paid transfer 200 to savings`
→ Memory notes.

---

### C7 — List splitting is gated on a closed grocery vocabulary, so non-grocery lists collapse to one row and trailing conjuncts land in Memory. BEHAVIORAL. ~40 utterances.

**Mechanism.** Two gates, both in `ShoppingGroups.swift`:
`recognizedProducts` (line 266) returns `nil` if **any** word is unrecognized;
`namesOnlyProducts` (line 413) caps at **4 words** and requires every word in
`groceryWords`. `ThoughtOrganizer.swift:506` uses the latter as the *only* route from a
verbless list to `.shopping`, and `ThoughtExtractor.swift:928` uses it as the guard that
keeps a trailing conjunct attached to its list.

**(a) One unknown word refuses the whole split.** Expected 2 rows each, observed 1:
`buy whole wheat bread and peanut butter`, `buy olive oil and balsamic vinegar`,
`buy half and half and coffee`, `buy coffee and filters`, `buy screws nails and a
hammer` (expect 3), `buy pens and sticky notes and printer paper` (expect 3),
`buy dog food and a new leash`, `buy socks and underwear and a belt`,
`buy motor oil and an air filter`, `buy a tent and a sleeping bag`,
`buy tulips and a vase`, `pick up advil and band aids from the pharmacy`,
`buy ibuprofen and vitamin d`, `get lumber and drywall and screws from Home Depot`,
`go to Canadian Tire and buy windshield fluid and wiper blades`,
`get four cans of soup and two boxes of pasta`, `buy a bag of flour and five pounds of
potatoes`, `pick up half a dozen bagels and cream cheese`, `pick up three bananas and a
bag of rice`, `buy 2 gallons of milk and a loaf of bread`, `buy a couple of avocados and
a bunch of bananas`, `buy 2 percent milk and whole wheat bread`.

**(b) The trailing conjunct is split off and filed in Memory as a note.** This one
loses the verb and the destination:

| utterance | observed | expected |
|---|---|---|
| `buy Tropicana orange juice and Kraft peanut butter` | "Buy Tropicana orange juice" (Today) + **"Kraft peanut butter" → Memory note** | 2 Today shopping rows |
| `buy Tide detergent and Bounty paper towels` | row 2 **"Bounty paper towels" → Memory note** | 2 Today shopping rows |
| `get a birthday card and wrapping paper` | "Get a birthday card" (task) + **"Wrapping paper" → Memory note** | 2 Today rows |
| `buy a lamp and a rug and curtains from Ikea` | "Buy a lamp", "A rug", **"Curtains from Ikea" → Memory note** | 3 Today shopping rows, Ikea list |
| `get eggs milk and cheese and don't forget the dry cleaning` | 3 shopping rows + **"Don't forget the dry cleaning" → Memory note** | 4th row = Today task |

**(c) Verbless non-grocery lists become one Memory note.** Expected N Today shopping
rows on an "Other"/named list; observed 1 Memory note:
`screws nails hammer`, `advil band aids cough syrup`, `passport charger socks`,
`pens paper stapler`, `tent sleeping bag flashlight`, `socks underwear belt`,
`hardware store: screws, nails, hammer, wood glue`, `pharmacy: advil, band aids, cough
syrup`, `packing list for Vancouver: passport, charger, socks, toothbrush`,
`camping list: tent, sleeping bag, flashlight, matches`, `office supplies: pens, sticky
notes, printer paper`, `guest list: Sarah, Tom, Priya, and Marcus`,
`invite Sarah Tom Priya and Marcus to the party` (Memory, and PER is mangled to
`"Sarah Tom"`).

Note the asymmetry the recent contract change created: `grocery list: milk and eggs`
correctly yields 2 checkable Today rows, but `hardware store: screws, nails, hammer,
wood glue` yields one un-checkable Memory note. The list-prefix expansion is
grocery-only.

**(d) The 4-word cap and vocabulary holes break lists that *are* groceries.**
- `paper towels toilet paper napkins` → **1 Memory note** (5 words > cap). Expect 3 rows.
- `pasta tomato sauce cheese` → **1 Memory note** ("sauce" not in `groceryWords`). Expect 3.
- `apple juice greek yogurt whole wheat bread peanut butter` → **1 Memory note**. Expect 4.
- `two litres of milk a dozen eggs three onions` → **1 Memory note**. Expect 3.
- `we need a carton of eggs and a jug of milk` → **Memory note**. Expect 2 Today rows.
- `two bags of chips and a case of beer` → **Memory note**. Expect 2.
- `grocery list: 2 milk, 1 dozen eggs, 3 onions` → **1 row**. Expect 3.

**(e) Two junk rows the `namesSomethingToBuy` guard misses.**
- `buy milk, the good kind` → 2 rows: "Buy milk" + **"Buy the good kind"**. Expect 1 row.
- `go to the store and buy milk and eggs` → 3 rows: a redundant **"Go to the store"**
  task + 2 shopping rows. `isBareTripPhrase` only folds when a *named* store was read,
  and "the store"/"the grocery store" are deliberately not names — so the fold never
  runs for the most common phrasing. Expect 2 rows. Same for `go to the grocery store
  and buy milk and eggs`.

---

### C8 — Fabricated one-off due dates on recurring and location items. CRITICAL. ~12 utterances.

The brief asked specifically whether a recurring item also invents a wrong one-off date.
It does, and location items do too.

| utterance | observed | expected |
|---|---|---|
| `annually on March 2 renew the domain` | row 2 "Renew the domain" due **Tue Aug 3** (not March 2) | Tue Mar 2 |
| `every month on the 1st pay rent` | row 2 "Pay rent" due **Thu Sep 3** (not the 1st) | Tue Sep 1 |
| `remind me on the 1st of every month to pay rent` | due **Thu Sep 3** | Tue Sep 1 |
| `on the 15th of every month pay rent` | row 1 due **Thu Sep 3** (not the 15th) | Sat Aug 15 |
| `last day of every month close the books` | due **Thu Sep 3** | Mon Aug 31 |
| `first Monday of every month pay the mortgage` | REC **weekly x1 days[2]** (52/yr, not 12) + row 2 due Mon Aug 10 | monthly, ordinalWeekday first-Mon |
| `remind me every year on my mom's birthday` | due **Tue Aug 3** — today's date, next year, invented | needsReview, no date |
| `every year book the physical` | due **Tue Aug 3 2027** — a year out, never surfaces | today or needsReview |
| `first thing when I'm at work email the client` | LOC arrive work **and** due Tue Aug 4 09:00 | location only |
| `when I get home tonight remind me to water the plants` | LOC arrive home **and** due Mon Aug 3 20:00; quote truncated to `remind me to water the plants` | one trigger |
| `when I get home at 6 remind me to start dinner` | LOC arrive home **and** due Mon Aug 3 18:00 | one trigger |
| `when I get home tomorrow remind me to unpack` | LOC arrive home **and** rem Tue Aug 4 **09:00** (invented hour) | one trigger |

Note `remind me the first Monday of every month to send the report` is **correct**
(monthly x1, due Mon Sep 7) — the `ordinalWeekday` field exists and works; only the
bare-imperative path (C3) degrades it to weekly.

**Sub-daily intervals all fire 24 h late.** `every 4 hours`, `every 15 minutes`,
`every 2 hours`, `every 30 minutes`, `every 6 hours`, `every hour until 5` — every one
produces first due = **Tue Aug 4 10:00**, exactly +24 h from the reference, regardless
of the interval. (`temporal: durationRecurrence` and `intervalSeconds` are set
correctly; it is the *first occurrence* that is wrong.) A 15-minute stand-up reminder
that first fires tomorrow morning is functionally a reminder that does not exist.

---

### C9 — Recurrence-word normalization rewrites the row's `sourceQuote`. METADATA→CRITICAL.

`SpeechRepair.swift:303-317` rewrites `annually→every year`, `quarterly→every 3 months`,
`daily→every day`, `weekdays→every weekday` **before** extraction, and the rewritten
text becomes the row's `sourceQuote`, not just the parse input.

- `my meds are twice daily` → title & quote **"my meds are twice every day"**
- `quarterly taxes are due every quarter` → title & quote **"every 3 months taxes are
  due every quarter"** — "quarterly" is gone from the row entirely
- `remind me weekdays at 8 to check email` → quote **"remind me every weekday at 8…"**
- `annually on March 2…` → row titled **"Every year on March 2"**

The capture-level transcript in `CaptureSession` still holds the original, so this is
not unrecoverable — but the per-row quote is supposed to be the person's words, and it
is not. Repairs should feed the parser without replacing `sourceQuote`.

---

### C10 — Group and store labelling. METADATA. ~8 utterances.

- `buy printer ink and USB cables from Best Buy` → `LIST:"Best"`. `storeCandidate`'s
  `stopWords` (ShoppingGroups.swift:169) contains `"buy"`, so the second half of
  **Best Buy** — a name in `knownStores` — is discarded. Any store whose name contains a
  shopping verb is truncated.
- `buy pens and sticky notes and printer paper` → `LIST:Groceries` ("paper" is a grocery
  word). Same for `buy motor oil and an air filter` ("oil"), `buy dog food and a new
  leash`. `defaultGroup` votes on single words, so one incidental match flips a
  hardware/office list into Groceries.
- `remind me to buy milk and eggs` → 2 rows **with no list at all**.
  `assigningShoppingGroups` (ThoughtExtractor.swift:311) filters out `needsReview` rows,
  so a shopping list that needs a time loses its group. Compare `remind me to buy milk
  and eggs at 5pm`, which keeps `LIST:Groceries`.
- `buy Coke and Doritos` → `LIST:Other`; `get half and half` → `LIST:Other`.
- Fabricated people from place/verb words: `when I get to Costco remind me to buy roast
  beef, bread, and cheese` → **PER:Costco**; `leave work at 5 today` → **PER:Leave**;
  `invite Sarah Tom Priya and Marcus…` → **PER:"Sarah Tom"**. (People lane overlap, but
  they surfaced here.)

---

### C11 — Title cosmetics. COSMETIC.

- Leading numeral triggers sentence-casing of the *next* word: "5 Star review",
  "10 Out of 10 would recommend", "3 Kids", "100 Push ups", "30 Reps", "2% Milk",
  "6 People are coming", "15 Minute break".
- The location clause is stripped from the title for `when I get home…` but not for
  `when I arrive home…`, `when I get to the office…`, `when I leave the house…`,
  `when I get to the cottage…`, `when I get to school…` — those keep the whole sentence
  as the title.
- Verb parity within one split list: `pick up milk and bread and take out the trash`
  → "Pick up milk" / **"Bread"**; `buy a lamp and a rug…` → "Buy a lamp" / **"A rug"**.
- `milk, eggs, bread` → **"Buy Milk"** (title-cased) / "Buy eggs" / "Buy bread".
- `milk` alone → title **"Milk"**, not "Buy milk".
- `so it was 10 out of 10 honestly` → type `unclear`, title **"Review captured thought"**.
- `remind me on my way to work to call the clinic` → title **"Work to call the clinic"**.
- `transfer $250 to savings` → **Memory note**; it is an imperative and belongs on Today.

---

## Already correct — do not break these

These were probed deliberately and behave well.

**Numbers are never misread as clock times.** 100 utterances, zero false times. Money
(`$40`, `40 dollars`, `Uber was 32 bucks`, `lunch was 18.50`, `the quote came in at
8500`), places (`aisle 12`, `gate 22`, `unit 305`, `apartment 7B`, `room 214`, `seat
14C`, `platform 9`, `suite 1100`, `booth 6`, `locker 88`), references (`page 143`,
`chapter 7`, `size 10`, `5 star`, `10 out of 10`, `rated 4.5 stars`), counts (`3 kids`,
`2% milk`, `40 litres`, `15 kilos`, `400 km`, `100 push ups`), codes and routes
(`flight AC 831`, `COVID 19`, `iOS 17`, `Windows 11`, `Highway 7`, `route 66`, `the 6
train`, `the 401`, `the 407`), digit strings (`wifi password is 8 8 4 2`, `gate code is
1 2 3 4`, `locker combo is 24 36 12`, `account number is 4021 8873`, `extension is
4419`, `case number is 20 25 8842`), and near-time traps (`room 4`, `4 tickets`, `12
chairs`, `table for 8`, `party of 6`, `the 5 year plan`, `a 3 month lease`, `15 minute
break`). Meanwhile the genuine times still resolve: `meeting at 4` → Mon 16:00, `lunch
at 12` → 12:00, `dinner at 8 tonight` → 20:00, `the flight is at 6` → 18:00. This guard
is excellent — every C2 fix must keep it.

**"and"-compound products stay one row.** `fish and chips`, `macaroni and cheese`,
`mac and cheese`, `salt and pepper`, `bread and butter`, `peanut butter and jelly`,
`bacon and eggs`, `gin and tonic`, `chicken and waffles`, `surf and turf`,
`salt and pepper shakers`, `bed and breakfast` (→ task, not shopping), `rock and roll
tickets`, `half and half`. And the compound survives *inside* a longer list:
`get salt and pepper and olive oil` → 2 rows, `buy macaroni and cheese and milk` → 2
rows, `buy peanut butter and jelly and bread` → 2 rows. `finalShoppingPair` +
`knownProductPhrases` do this well.

**Multi-word grocery products stay whole.** `apple juice`, `greek yogurt`, `ice cream`,
`chocolate chips`, `toilet paper`, `paper towels`, `almond milk`, `oat milk`, `sour
cream`, `cream cheese`, `frozen pizza`, `tortilla chips`, `chicken breast`, `green
beans`, `sweet potatoes`, `bell peppers`, `laundry detergent`, `dryer sheets`, `baby
formula`, `cat food`, `dog food` — all split correctly at the *product* boundary.

**Verb/prefix parity holds for groceries.** All twelve of `grocery list:`, `grocery
list`, `shopping list:`, `shopping list`, `groceries:`, `groceries`, `buy`, `get`,
`grab`, `pick up`, `we need`, `I need`, `we're out of`, `add … to my shopping list`,
`put … on the shopping list` produce **2 rows** for "milk and eggs". The recent contract
change holds everywhere I could reach it.

**Ordinary uses of location words do not create a geofence.** 20/20 clean:
`I worked from home today`, `working from home tomorrow`, `I am going to work from home
on Friday`, `the store was busy`, `home insurance renewal is due in September`, `call
the home insurance people`, `our new home is amazing`, `the office moved to the third
floor`, `Sarah left work early`, `I left work at 6`, `the airport was a nightmare`,
`the pharmacy called about my prescription`, `home cooked meals are better`, `that store
has the best bread`, `I got home at midnight`, `he works at the office downtown`, `the
gym membership renews next month`, `the home team lost`, `my home screen is a mess`,
`we are near the end of the quarter`, `the near miss on the highway`, `going to the
store later`, `the school called`. None produced a `locationIntent`.

**Ordinary uses of "every" do not create a recurrence.** `every single time I call them
they put me on hold`, `it happens every time`, `every once in a while I forget`, `every
kid in the class got sick`, `every effort was made`, `he calls every so often` — all
Memory notes with no rule. (One leak: `that store is open every day` → Today task with a
daily 09:00 alarm. Expect Memory note.)

**The canonical recurrence and location forms are solid.** `remind me every Tuesday to
take out the trash`, `every Tuesday at 7pm take out the bins`, `gym every Tuesday and
Thursday` (days[3,5]), `every weekday at 8` (days[2–6]), `every other week` (weekly x2),
`every 90 days` (daily x90), `every 6 months` (monthly x6), `remind me the first Monday
of every month to send the report` (monthly + ordinalWeekday), `when I get home remind
me to…` (`.home`), `when I leave work remind me to…` (`.leave`/`.work`), `remind me at
the office to…`, `next time I'm at Costco buy paper towels`, `when I'm at Home Depot buy
furnace filters`. Also: a timed list still splits and shares one fire moment
(`remind me to get eggs, milk, and cheese in one hour` → 3 rows, all 11:00), and a
location-triggered list correctly stays whole (`when I get to Costco remind me to buy
roast beef, bread, and cheese` → 1 row).

**Lists mixed with a task separate cleanly.** `get milk and eggs and call the vet` → 3
rows; `buy milk eggs and bread and book the dentist` → 4 rows; `call the bank and buy
milk and eggs` → 3 rows; `grocery list: milk and eggs, also call mom` → 3 rows with
PER:Mom; `buy coffee and filters and email Sarah about the deck` → 2 rows with
PER:Sarah. The store name propagates: `go to Costco and buy milk and eggs` → 2 rows on
`LIST:Costco` with the trip phrase correctly folded away.
