# Speak It — pencil-on-paper logo study

Date: 4 September 2026
Companion to `report-source.md` (the strategy research) and to the review board
in `Design/Brand/Explorations/Pencil-Paper-Study/`. Nothing here is adopted;
`Tools/Brand/generate_brand.swift` still produces the shipped brand.

## The brief

Keep the five-bar audio mark, but make the whole logo look like someone actually
drew it with a pencil on paper: graphite grain, pressure, frayed edges, one
lettering hand that belongs to Speak It. Simple and unique. Two reference images
from Calvin: white dots on black (a stippled bar) and the bars pressed into ruled
paper (a blind deboss).

## What was built

`Tools/Brand/generate_pencil_paper_study.mjs` (Node, no dependencies, seeded)
renders 16 lockups and 10 icons, plus a board, as SVG and PNG. The earlier
`generate_pencil_logo_study.mjs` drew smooth monoline paths and only *called*
them pencil; this one models the material:

| Layer | What it does | Why |
| --- | --- | --- |
| Three soft cores | Filled outlines at 90 %, 68 % and 40 % of the lead width with round, feathered caps | The mass that survives 60 px; graphite is darkest in the middle |
| Fibres | 18–32 thin strokes per line, Gaussian lateral spread (σ ≈ 0.28 w, clipped at 0.48 w), each with its own slow wander, random start/end, lower opacity toward the edge | The frayed edge and the streaks a real lead leaves |
| Strays | Fibres beyond 72 % of the half-width become short segments | Where the tooth caught the lead |
| Caps | Fibres run into the round cap by a chord length, some drag 12 % past | Ends feather instead of stopping |
| Pressure | Landing +4 %, lift −22 %, slow noise ±14 % | Same profile as the Swift `Pen` |
| Tooth | `feTurbulence` at 1.0 cycles per unit, thresholded and keyed into the graphite (`feComposite in`) | Paper peaks stay white |
| Pressure cloud | A second turbulence 20× slower, gentle alpha | Tone varies along the stroke like a hand does |
| Grades | HB, 2B, 6B, carpenter (flat lead, uniform spread, butt caps), chalk (white on dark) | Colour, tone, fibre count, spread and tooth strength per grade |

Every noise source is xorshift64* seeded with the same constants as the Swift
generator, so a re-run is bit-identical. Both filters are sized in user units and
rescaled when the icon draws the mark 2.6× larger than the lockup does; without
that the icon looked like fog.

Three lettering skeletons: the production geometric caps, the earlier study's
relaxed lowercase, and a new **note hand** (single-stroke `e` and `a`, entry hooks,
exit flicks, `t` crossed after, capitals with a bowed spine). Per-letter baseline
and rotation jitter is fixed data, not random, so it can be tuned.

Two non-pencil paper directions from the references: **stipple** (bars built from
dots on a hand lattice, denser in the middle, dropout toward the edge) and
**deboss** (clean capsule, inner shadow top-left, inner light bottom-right, rim
highlight, optional ruled lines).

## What the board says

- **The pencil reads.** At 1024 the 2B and 6B bars look like graphite on toothy
  paper, not like a filter over a vector. At 160 and 90 px the fibres merge into a
  soft-edged grey bar that still reads as hand-made. At 29 px it is a grey mark;
  the current inked icon is stronger there.
- **Grade matters more than lettering.** HB is too light for an app icon; 2B is
  the sketchbook look; 6B is the only grade that holds its weight at 60 px.
- **Note hand `Speak It` (L14) is the strongest lockup.** It is the first lettering
  that looks written rather than typed, and it still spaces like a wordmark. L15
  (6B, slimmer bars, cream) is the most complete "one drawing" version.
- **Slim bars (62 %) read as pencil lines; full bars read as a marker held on its
  side.** Both are defensible; full bars keep continuity with today's mark.
- **Scribble fill (L07/I03) is a legitimate hand gesture** but reads as texture
  before it reads as bars; keep it for campaign use, not the icon.
- **One gesture (L08/I06) needs the connectors fainter still** or they read as
  scaffolding; the idea (the pencil barely lifts between beats) is right.
- **Stipple (I07/I08)** is the most distinctive icon on the board and the easiest
  to defend as a texture-free vector: it is just circles. It also scales down
  cleanly, because dots average to tone.
- **Deboss (I09/I10)** is elegant but drops the black-on-white contrast; it would
  need a dark or tinted variant to satisfy iOS's dark and tinted icon appearances.

## Technique research (verified by fetching sources)

The programmatic state of the art for "hand-drawn" vectors is rough.js (seeded
multi-stroke with length-aware jitter gain: full jitter under 200 units, 40 %
over 500; hachure fills; `preserveVertices`) and perfect-freehand (pressure from
velocity, taper easings, one closed polygon). Both were installed and run here;
both are deterministic. Neither draws graphite: they draw pen. The pencil look in
every tool that has one (Inkscape's Sketch path effect, POSTECH's real-time
pencil renderer, Praun's Tonal Art Maps) comes from **multiple overlapping
strokes and stroke density**, and the realism at large sizes comes from **one
paper-space tooth field shared by every stroke** (Procreate's "texturized" grain
mode). That is exactly the split the study generator uses: fibres carry the hand,
a single turbulence field carries the paper.

Numbers worth keeping from the literature: overlapping contour copies look best at
3–5 (Lee et al., NPAR 2006); paper peaks should keep 30–50 % of their whiteness
even under repeated strokes; Excalidraw halves roughness under 50 px and thirds
it under 10 px, which is the trade-off any icon forces.

Fonts: of every "handwriting" family on Google Fonts, only Cabin Sketch,
Fredericka the Great and FFF Tusj read as pencil, and they all do it with hatched
double strokes. Monoline handwriting faces (Caveat, Kalam, Patrick Hand, Shadows
Into Light) read as pen. Architects Daughter is the closest pencil *skeleton*.
None should be used for the wordmark; the note hand is ours.

AI and online tools: Recraft's vector styles have no pencil substyle (pencil and
crosshatch exist only as raster illustration styles), Logo Diffusion and Kittl
vectorise a generated raster, Ideogram, Krea and Midjourney are raster only.
The only AI route that accepts our geometry is Illustrator's Generative Shape
Fill / Concept to Vector, and it is not deterministic. Vectorizer.ai and Image
Trace can turn a real pencil scan into paths if a hand-drawn master is ever
wanted. Full tables with prices and URLs are in the research transcript
summarised in `report-source.md`'s tool audit and in this session's notes.

Production constraint that decides a lot: Xcode asset catalogs and the in-app
template PDF ignore SVG filters. If a pencil direction ships, the icon is a PNG
(filters are fine, it is rasterised once), the website SVG can keep the filter,
and the in-app wordmark must be fibres-only or a simplified outline. The fibre
layers alone already look like pencil at UI sizes; the filter mostly matters
above 300 px.

## Not done

- The brand-reference survey (hand-drawn identities, sketch treatments of audio
  marks, Brand New critiques) did not complete: the agent hit a rate limit.
  `report-source.md` already covers HEYTEA, Mailchimp, Teabox, Instagram and
  Voicenotes; a wider audio-category audit is still open.
- No trademark search. No user recognition test against the current icon.
- The deboss uses the hand-drawn bar shapes; a clean capsule would look more like
  the reference image.
- Nothing in the app, the website or the production generator changed.

## Suggested next step

Pick a grade (6B), a lettering hand (note hand `Speak It`), and a bar weight
(full or 62 %), then port the fibre model into `generate_brand.swift` as a
`Pencil` profile beside `Pen`, with a fibre-only export for the PDF template and
a filtered PNG for the icon. Keep the current inked mark for sizes under 24 px
(the website topbar, favicon), where the pencil identity is carried by silhouette
alone.
