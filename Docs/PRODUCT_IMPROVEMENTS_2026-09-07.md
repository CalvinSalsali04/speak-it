# Speak It product improvements — September 7, 2026

## Implemented

- **Capture integrity:** independent new items survive successful or ambiguous operations. Unresolved operations have their own review row. Accounting reflects creation even when an operation succeeds. Regression cases cover mixed async/sync capture and immediate deduplication.
- **Portable meaning:** version 3 iCloud payloads carry time/place intent, semantic state/gap and shopping groups. Present envelopes support explicit clearing; older writers preserve fields they do not know. Newer legacy timing edits remain authoritative for temporal intent. No SwiftData schema change.
- **Interpretation:** shared guarded obligation peeling prevents the reproduced three-errand collapse. Preparatory and modal-adverb fragments stay attached. Optional model calls are limited to short uncertain supported readings, raced against two-second cancellation. Acceptance checks preserve quote substance, independent actions and resolved behavior; deterministic organization supplies type/person/state.
- **Repeated work:** Today groups actions and shopping summaries once per body evaluation. Memory shares search ranking and computes query scores once per item. Exact names/titles rank above incidental text. Widgets retain only the best eight rows while counting, and avoid identical short-interval publications.
- **App experience:** missing-person/time controls appear before the general editor fields; person correction receives focus. Accessibility-size row titles can wrap fully. Native iOS 26 glass is limited to the floating dock, with solid reduced-transparency/increased-contrast/older-iOS fallbacks.
- **Website:** immediate visible action, readable stacked phone examples, improved type/targets/focus, responsive hero and laptop navigation, reduced-motion/transparency support and offscreen animation pausing. The browser demo remains dependency-free. Unconfigured App Store actions open the demo instead of a misleading website loop.
- **Tooling:** simulator discovery no longer fails from shell/Python quotation; parser probe compilation propagates failures.

## Design research and decisions

Applied the public [Apple design skill](https://github.com/emilkowalski/skills/blob/main/skills/apple-design/SKILL.md) and Apple's [materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials) through readable hierarchy, immediate actions and accessible materials. Reviewed [liquid-gooey](https://github.com/Jakubantalik/Libraries/tree/main/packages/liquid-gooey), a React/SVG morphing library. It does not integrate with native SwiftUI and does not justify introducing React to this static site. No package was installed; native glass and lightweight CSS serve the actual interfaces.

## Verification

- Rules corpus: 1,203 cases, zero critical/behavioral/blocking failures. The existing report retains 18 metadata and 10 cosmetic findings across 22 cases; a passing gate does not mean every corpus expectation is clean.
- Full unit suite: **732 passed, 6 skipped, 0 failures** (738 total). The targeted sync follow-up also passed after the subsequent legacy-timing compatibility correction.
- Unsigned release compile passed, including the final sync compatibility correction.
- Local Chrome: 320×568, 390×844, 844×390, 1280×720 and 1440×900, with no horizontal overflow and visible primary actions. Typed/demo-example flows passed with normal and reduced motion. Expanded demo at 200% text fits all five widths, and all internal anchors resolve. Reading content remains visible with JavaScript disabled. No JavaScript console errors in the viewport run.
- JavaScript syntax and Git whitespace checks passed.

## Practical limits

No Xcode UI suite or physical iPhone install was run, as requested. Live speech, Apple Intelligence quality/cancellation, two-device iCloud, notification delivery, VoiceOver and native material/keyboard layout need hands-on QA. The two-second model race uses cooperative cancellation and is not a proven hard runtime deadline. No iPhone latency or 50,000-item scaling claim is made.

This fixes the reproduced issues and improves the identified hotspots; it does not replace the parser with a universal clause representation or add speculative embeddings/personalization. Full-file iCloud and in-memory lexical retrieval remain candidates for measured future work. Capture operations still use the existing persistence/retry architecture; this is not a transactional operation journal.

A verified App Store listing URL is still needed in `Website/index.html` metadata to enable download links. No website deployment, purchase, external service mutation, commit or push was performed. Existing brand changes were preserved.
