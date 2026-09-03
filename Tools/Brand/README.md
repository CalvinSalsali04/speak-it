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
| `SpeakIt/Assets.xcassets/AppIcon.appiconset/SpeakIt-AppIcon-1024.png` | the shipped app icon (opaque, no alpha) |
| `SpeakIt/Assets.xcassets/Wordmark.imageset/SpeakIt-Wordmark.pdf` | `SpeakItWordmark` in the app (template image, tinted at runtime) |
| `Design/Brand/SpeakIt-Wordmark.svg` | the lettering on its own |
| `Design/Brand/SpeakIt-Mark.svg` | the five-bar mark on its own |
| `Design/Brand/SpeakIt-Mark-Topbar24.svg.fragment` | the 24-unit `<path>` the website topbar embeds |
| `Design/Brand/SpeakIt-Logo-v2-Stacked.{svg,png}` | mark above wordmark — splash, listing, social |
| `Design/Brand/SpeakIt-Logo-v2-Horizontal.{svg,png}` | mark beside wordmark — headers, email |
| `Design/Brand/SpeakIt-AppIcon-v2-Master-4K.{svg,png}` | icon master |
| `Design/Brand/SpeakIt-AppIcon-v2-Alt-Wordmark-1024.png` | alternate icon with lettering (not shipped) |
| `Design/Brand/SpeakIt-AppIcon-v2-Alt-Light-1024.png` | alternate light icon (not shipped) |
| `Website/assets/img/favicon.svg` | speakitapp.ca |
| `output/brand-preview.png` | one sheet to judge the system at several sizes |

The mark is the same five voice bars it has always been (same heights, pitch
and weight), but each bar is inked by the generator's `Pen`: a deterministic
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
