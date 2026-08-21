# Speak It TikTok UGC Slideshow Delivery

## Source package

- Ten original POV lifestyle photographs in `source_photos/`.
- Deterministic layout and export logic in `render.mjs`.
- Creative strategy, prompts, and posting guidance.

The generated `output/` directory contains 10 complete TikTok photo carousels
(five concepts with two variations each), but is intentionally excluded from
Git because all 70 final slides, contact sheets, captions, previews, and the
delivery index can be rebuilt from this source package.

## Posting

1. Run `node render.mjs` to rebuild `output/`.
2. Choose a folder under `output/` and open Variation `A` or `B`.
3. Upload `slide-01.png` through `slide-07.png` in numeric order as a TikTok
   Photo Mode post.
4. Paste the folder's `caption.txt`.
5. Add a low-volume, lyric-light track from TikTok's Commercial Music Library.
6. Turn on TikTok's Commercial Content Disclosure setting.

The current final slide says **FOLLOW FOR THE LAUNCH** because the App Store
listing has not been verified as live. Replace that CTA only after the live
listing and offer are confirmed.

## Creative integrity

The ten lifestyle backgrounds were generated with OpenAI's built-in image
generation tool. They depict fictional first-person situations and must not be
presented as customer photographs or testimonials. The product screens are real
Speak It screenshots from this workspace, and the marketing copy is grounded in
the current product behavior.

## Folders

- `01-late-night-thought/` — capture friction at 1:43 a.m.
- `02-remember-people/` — remembering a person's small preference.
- `03-capture-before-organizing/` — one capture door instead of four apps.
- `04-chaotic-brain-dump/` — several thoughts organized from one natural capture.
- `05-no-account/` — no-account and user-control positioning.

## Regeneration

`render.mjs` deterministically rebuilds the final slides from `source_photos/`
and the existing Speak It screenshots. It requires the bundled Codex workspace
Node runtime and Sharp dependency used during this delivery. Generated output
and the redundant ZIP delivery archive remain local and are ignored by Git.
