# Brand generator

`generate_brand.swift` draws the whole Speak It brand system from geometry and
writes every file that carries it, so the icon, the in-app wordmark, the brand
masters and the website favicon cannot drift apart.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift Tools/Brand/generate_brand.swift
```

What it writes:

| File | Used by |
| --- | --- |
| `SpeakIt/Assets.xcassets/Wordmark.imageset/SpeakIt-Wordmark.pdf` | `SpeakItWordmark` in the app (template image, tinted at runtime) |
| `Design/Brand/SpeakIt-Wordmark.svg` | the lettering on its own |
| `Design/Brand/SpeakIt-Mark.svg` | the five-bar mark on its own |
| `Design/Brand/SpeakIt-Mark-Topbar24.svg.fragment` | the 24-unit `<path>` the website topbar embeds |
| `Design/Brand/SpeakIt-Logo-v2-Stacked.{svg,png}` | mark above wordmark — splash, listing, social |
| `Design/Brand/SpeakIt-Logo-v2-Horizontal.{svg,png}` | mark beside wordmark — headers, email |
| `Design/Brand/SpeakIt-AppIcon-v2-Master-4K.{svg,png}` | icon master |
| `Design/Brand/SpeakIt-AppIcon-v2-Alt-Wordmark-1024.png` | alternate icon with lettering (not shipped) |
| `Design/Brand/SpeakIt-AppIcon-v2-Alt-Light-1024.png` | alternate light icon (not shipped) |
| `Website/assets/img/favicon.svg` | speakitapp.ca (black bars on a white tile) |
| `output/brand-preview.png` | one sheet to judge the system at several sizes |

The mark is the same five voice bars it has always been (same heights, pitch
and weight). Since 2026-09-04 they are clean capsules everywhere
(`Bars.inkedByHand = false`); the shipped app icon and the site's social card
are the embossed cut written by `generate_emboss.mjs` below. Flip
`inkedByHand` and each bar is instead inked by the generator's `Pen`: a deterministic
felt-tip tool that takes an ideal line and returns the ink outline a hand would
leave, in the spirit of HEYTEA's hand-drawn line work. The line drifts and
trembles, the width breathes with pressure, the edges are slightly rough, the
tip lands heavy and lifts light with a small flick, and the ends are imperfect
caps. Every amplitude is a fraction of the pen width and the grain is sized in
pen widths, so a short bar and a long bar carry the same texture. `Bars.hands`
gives each bar its lean, bow, length nudge, drawing direction and seed; the
noise is seeded, so every run is bit-identical. Tune `Pen`'s defaults (drift,
tremor, pressure, roughness, landing, lift, hook) to make the hand looser or
tighter.

The lettering is a monoline, geometric, all-caps wordmark with open tracking and
rounded terminals. Every glyph is a list of stroke centrelines in a 100-unit
cap-height space; `strokeWidth`, `tracking` and `wordSpace` at the top of the
file are the only knobs most changes need. The website's topbar in
`Website/index.html` embeds both paths by hand; re-copy the lettering from
`SpeakIt-Wordmark.svg` after changing a letter and the glyph from
`SpeakIt-Mark-Topbar24.svg.fragment` after changing the bars.

## Pencil-on-paper study

`generate_pencil_paper_study.mjs` is a separate, review-only generator: it never
touches the production files above. It draws the same five bars (same hands,
heights and pitch as `Bars` in the Swift generator) and several lettering
skeletons as if they were drawn with a pencil on paper, and writes SVG + PNG
candidates plus a review board to `Design/Brand/Explorations/Pencil-Paper-Study/`.

```bash
node Tools/Brand/generate_pencil_paper_study.mjs          # SVGs, board.html, PNGs via Chrome
node Tools/Brand/generate_pencil_paper_study.mjs --no-raster
```

The pencil is a fibre model rather than one outline: three soft filled cores
carry the mass (so a 60 px icon still reads), two dozen thin fibres laid along
the stroke with a Gaussian lateral spread give the frayed edge and the streaks,
short strays appear where the tooth caught the lead, and fibres run into the
round cap so the ends feather instead of stopping. An SVG filter then multiplies
the graphite by a fine `feTurbulence` tooth and a slow pressure cloud; both are
sized in user units, so `icon()` rescales them when it draws the mark larger.
`GRADES` holds the pencil grades (HB, 2B, 6B, carpenter, white chalk) as colour,
tone, fibre count, spread and tooth strength. The rendering is seeded, so a
re-run is bit-identical. The PNG step needs Google Chrome in `/Applications`;
nothing else on a stock Mac rasterises SVG filters.

## Embossed mark masters

`generate_emboss.mjs` writes review masters to `Design/Brand/Emboss/`: the five
bars as clean capsules raised out of light paper (soft shadow bottom-right, light
top-left, a contact shadow, a rim highlight and a faint paper grain), a dark
twin, embossed 1024 icons in both, and flat black-on-white / white-on-black
masters at 4K and 8K plus tight-bounds `SpeakIt-Mark-Black.svg` / `-White.svg`
for embedding. Every offset and blur is a fraction of the bar width, so the
relief looks the same at 1024 and 8192. It also writes the two shipped files:
`SpeakIt/Assets.xcassets/AppIcon.appiconset/SpeakIt-AppIcon-1024.png` (black
bars raised out of light paper) and `Website/assets/img/og.png` (the 1200×630
social card). Re-run it after changing the relief; re-run `generate_brand.swift`
after changing the bars' geometry, then this, so both agree.

```bash
node Tools/Brand/generate_emboss.mjs
```
