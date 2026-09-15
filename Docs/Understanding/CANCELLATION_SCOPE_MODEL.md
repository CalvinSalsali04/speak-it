# Cancellation Scope Model

Cancellation is resolved against semantic intent groups, not against the raw
clauses produced by punctuation and conjunction splitting. A group is the
smallest unit the person would recognize as one plan: for example, a visit
(`go to the pharmacy`) plus its purpose (`pick up vitamins`).

The safety preference is asymmetric. When scope or target association is not
structurally clear, preserve visible text for review. Never create an active
item from the cancellation directive, and never remove a plausible sibling by
guessing.

## Rules

1. **Full abandonment.** A terminal bare withdrawal retracts the semantic group
   immediately before it. If that group is the whole capture, the capture
   produces no active item. A visit and its purpose retract together even when
   clause splitting placed them in two pieces.
2. **Partial cancellation.** When a cancellation explicitly names one child of
   a composite intent, remove only that child if the remaining parent is still
   independently actionable. For example, “go to the store, but skip buying
   milk” keeps the visit only when the visit itself remains an expressed plan.
3. **Selective sibling cancellation.** A terminal correction such as “actually
   skip the pharmacy” targets one earlier sibling group by its stated
   destination. Remove the whole matched group—visit and purpose—and preserve
   all unmatched siblings in their original order.
4. **Replacement correction.** Resolve a replacement before cancellation
   scope. The replaced material is unavailable as a live cancellation target;
   a later cancellation applies to the repaired intent that remains.
5. **Shared temporal context.** Date, time, recurrence, and location context are
   attributes of the surviving groups. Removing one sibling must not remove the
   shared context from its siblings or copy the canceled sibling's private
   context onto them.
6. **Correction and restart boundaries.** A restart marker may announce a
   cancellation, but it is not itself evidence for a broader scope. Scope comes
   from the semantic group and an explicit target. An unresolved target stays
   visible for review instead of becoming a positive action or deleting a
   guessed group.

## Structural recognition used by the first fix

The initial production change is deliberately narrow in grammar but general in
meaning. It recognizes coordinated visit groups whose first clause states
travel to a destination and whose following clause states the purpose. It also
recognizes a terminal, restart-marked `skip <destination>` directive and
associates it only when exactly one earlier visit group names that destination.
No store names, objects, dates, or generated phrases are enumerated.

These rules cover the two uniform P0 structures in the saved 10K result set:

- 126 full-abandonment cases: one visit-purpose group followed by “actually
  forget that”.
- 61 selective-cancellation cases: two to five sibling visit-purpose groups
  under shared temporal context followed by “actually skip <destination>”.

## Saved-result distribution

The 187 failures have no over-cancellation cases. Their overlapping structural
counts are:

- cancellation applied only to the latest raw clause: 126
- target not associated with the correct earlier group: 61
- composite visit plus purpose: 187
- multi-item sibling list: 61
- shared-date sibling list: 61
- correction/restart followed by cancellation: 187
- additional discourse/sequencing frame beyond coordination: 0
- object canceled while an independently intended visit remains: 0
- one sibling canceled while other siblings remain: 61
- explicit abandonment of the only whole semantic group: 126

The mutually exclusive generated structures are `corr.10` (126),
`multi.2.8` (10), `multi.3.8` (10), `multi.4.8` (8), `multi.5.8` (13),
`long.3.2` (6), `long.4.2` (7), and `long.5.2` (7).
