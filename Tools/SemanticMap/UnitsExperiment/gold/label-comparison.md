# Frozen gold compared with the repository's development labels

Written AFTER gold.json was frozen (sha256 `d8d4a436…6d345c`); gold.json was not changed. Labels read from `Tools/CorpusRunner/devsets/rambling.tsv` (expected thought count only) and `coordination.tsv` (expected segments) at `fbb6f90`.

## Result

- **No hard disagreement.** For all 28 labelled captures, the repo's count falls inside the range the gold admits. For the 5 coordination rows, the repo's segment boundaries equal the gold's units.
- **The one systematic difference: on 8 captures the repo commits to a reading the gold leaves open.** RB17C, RB17R, RB19R, RB28C, RB28R, RB30C, RB30R and CM07 hold 11 ambiguous spans in total. On each, the repo counts the ambiguous span as a unit of its own. Six are recall-worthy facts that also motivate an action (the warranty, the lease, the contractor visit, the blood work). One is the deck-boards clause. One is "book the room" after a message.
- **Consequence for scoring:** a candidate that folds such a fact into its action passes the gold but fails the repo count. If the experiment wants the stricter reading, it can score twice, once admitting every listed owner and once forcing `own` on these spans. That choice belongs to the experiment, not to this file.
- The rambling rows carry counts only, so for those 23 captures agreement is on count, not boundaries. CAP14 and CAP25 are unit-test fixtures with no devset label.

## Per capture

| id | gold firm units | gold max units | repo | verdict |
|---|---|---|---|---|
| RB13R | 1 | 1 | 1 | rambling.tsv decision-rambling / Today: agree |
| RB14C | 1 | 1 | 1 | rambling.tsv decision-clean / Today: agree |
| RB16R | 1 | 1 | 1 | rambling.tsv decision-rambling / Today: agree |
| RB17R | 1 | 2 | 2 | rambling.tsv knowledge-action-rambling / Today: agree only under the "own" reading of 1 ambiguous span(s) |
| RB19R | 1 | 2 | 2 | rambling.tsv knowledge-action-rambling / Today: agree only under the "own" reading of 1 ambiguous span(s) |
| RB21R | 2 | 2 | 2 | rambling.tsv chained-rambling / Today: agree |
| RB28C | 2 | 4 | 4 | rambling.tsv long-clean / Today: agree only under the "own" reading of 2 ambiguous span(s) |
| RB28R | 2 | 4 | 4 | rambling.tsv long-rambling / Today: agree only under the "own" reading of 2 ambiguous span(s) |
| RB29C | 3 | 3 | 3 | rambling.tsv long-clean / Today: agree |
| RB29R | 3 | 3 | 3 | rambling.tsv long-rambling / Today: agree |
| RB30C | 3 | 4 | 4 | rambling.tsv long-clean / Today: agree only under the "own" reading of 1 ambiguous span(s) |
| RB30R | 3 | 4 | 4 | rambling.tsv long-rambling / Today: agree only under the "own" reading of 1 ambiguous span(s) |
| RB31C | 1 | 1 | 1 | rambling.tsv coherent-long / Memory: agree |
| RB31R | 1 | 1 | 1 | rambling.tsv coherent-long / Memory: agree |
| RB33R | 2 | 2 | 2 | rambling.tsv decision-rambling / Today: agree |
| RB38C | 1 | 1 | 1 | rambling.tsv coherent-long / Memory: agree |
| RB41R | 1 | 1 | 1 | rambling.tsv decision-rambling / Today: agree |
| RB43R | 2 | 2 | 2 | rambling.tsv decision-rambling / Today: agree |
| RB44R | 2 | 2 | 2 | rambling.tsv decision-rambling / Today: agree |
| RB45R | 1 | 1 | 1 | rambling.tsv deliberation-open-rambling / Memory: agree |
| RB46R | 1 | 1 | 1 | rambling.tsv deliberation-open-rambling / Memory: agree |
| RB17C | 1 | 2 | 2 | rambling.tsv knowledge-action-clean / Today: agree only under the "own" reading of 1 ambiguous span(s) |
| RB21C | 2 | 2 | 2 | rambling.tsv chained-clean / Today: agree |
| CM04 | 1 | 1 | 1 | coordination.tsv communication-complement: agree; boundaries match |
| CM06 | 2 | 2 | 2 | coordination.tsv communication-complement: agree; boundaries match |
| CM07 | 1 | 2 | 2 | coordination.tsv communication-complement: agree only under the "own" reading of 1 ambiguous span(s); boundaries match |
| RS03 | 1 | 1 | 1 | coordination.tsv reported-speech: agree; boundaries match |
| RS04 | 1 | 1 | 1 | coordination.tsv reported-speech: agree; boundaries match |
| CAP14 | 14 | 14 |  | unit-test fixture, no devset label |
| CAP25 | 25 | 25 |  | unit-test fixture, no devset label |
