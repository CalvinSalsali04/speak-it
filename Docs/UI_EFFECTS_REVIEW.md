# UI effects for Speak It

Reviewed 7 September 2026. This is a design assessment, not a dependency audit or device performance benchmark.

## Recommendation and implementation

Make capture feel responsive and recognizable with a custom ink orb. Use motion to distinguish listening from processing; keep Today and Memory quiet enough to read. Implemented in `SpeakIt/Components/ListeningOrb.swift`, already used by the real capture screen and practice flow. No copied vendor code or added dependencies.

- Ready: stationary concentric ink contours and the familiar waveform control.
- Listening: four fluid contours whose deformation and scale respond to the existing microphone amplitude. Silence leaves only gentle contour movement.
- Processing: a narrow traveling monochrome beam around the core, with the existing ellipsis and screen status text. This is indeterminate activity, not completion progress.
- Accessibility: the existing button label and status copy remain authoritative. Reduce Motion uses static geometry, including for changing microphone levels; changing that setting at runtime removes the timeline. Semantic colors support both appearances. The 230-point layout and 72-point core remain unchanged.
- Rendering: native paths and gradients; animation requests at most 30 updates per second and is removed while ready or the scene is inactive. Physical-device energy usage and microphone animation still need hands-on QA.

## All five Libraries.dev effects

| Effect | What it does | Fit and decision |
| --- | --- | --- |
| [Thinking orbs](https://libraries.dev/orbs) | Nine animated activity states; React with local SwiftUI and React Native ports documented | Best match for voice capture. Adapted the stateful-orb concept into native ink contours driven by real audio. |
| [Border beam](https://libraries.dev/beam) | A moving highlight around a border, with monochrome tuning and a SwiftUI port | Used the concept for the processing ring. For the website, a brief edge sweep on a completed demo result could connect speech to the saved result. Avoid endless beams on every card or purchase button. |
| [Gooey](https://libraries.dev/gooey) | Merging and morphing shapes with crisp text | Possible inspiration for a future capture-to-saved transition. Defer changing the dock: stable touch targets and an obvious selected tab matter more than liquid motion there. |
| [Liquid metal](https://libraries.dev/metal) | WebGL chrome halos for icons/buttons; silver, gold and chromatic presets | A subtle silver treatment could work in a standalone marketing experiment. Too visually dominant for ordinary tasks, transcripts or the capture control. Not implemented. |
| [Image generation](https://libraries.dev/image) | A WebGL pixel-mosaic loader that resolves into supplied images; requires Three.js | Not an image generator. Speak It does not generate images, and delaying real screenshots with a simulated generation effect would weaken the product story. Not implemented. |

The catalog documents React as the main target. The public SwiftUI install instructions for Orb and Beam refer to local package paths; these are not drop-in npm components for this app. The marketing site is currently plain HTML/CSS/JS, so introducing React solely for one effect would add unnecessary integration work. Public documentation: [catalog](https://libraries.dev/), [accessibility behavior](https://libraries.dev/accessibility).

## Similar libraries

- [Magic UI Border Beam](https://magicui.design/docs/components/border-beam): adjustable duration, beam size, width and direction. Useful reference for a restrained demo-result edge; its broader [component catalog](https://magicui.design/docs/components) also includes animated lists, blur fades and device frames.
- [React Bits](https://www.reactbits.dev/get-started/index): a broader collection of animated backgrounds and components, including Orb and Liquid Chrome. Suitable for isolated website experiments; full-screen ambient backgrounds would compete with Speak It's existing thought-ring hero.
- [Paper Shaders Liquid Metal](https://shaders.paper.design/liquid-metal): explicit speed, distortion, color dispersion and pixel-count controls, with image-mask support. The most relevant direction if exploring a promotional metal treatment later; benchmark on mobile and provide a still fallback.

## Website direction

The current homepage already has substantial uncommitted design work in its hero, demo, and conversion assets. This pass implements the app improvement and leaves that work intact. Suggested follow-up: one brief result-edge sweep after the website demo resolves, and a shared ink-contour motif around the listening indicator. Keep those effects tied to actual demo state; stop when offscreen, honor reduced motion, and show results immediately. Do not add fake delays or imply that screenshots are being AI-generated.

## Verification

- Full unit suite: 748 passed, 6 skipped, zero failures (`Tools/CI/unit-tests.sh`).
- Unsigned generic-device Release build: passed (`Tools/CI/release-build.sh`).
- Semantic corpus gate: 1,203 cases, zero critical/behavioral failures. The report still lists 22 nonblocking failing cases (metadata/cosmetic); this change does not touch parsing.
- Three focused UI checks passed: full-width welcome-to-capture action, typing/keyboard dismissal, and first-run accessibility/dark-appearance flow.
- Retained capture screenshots in the existing UI tests; inspected light and dark images. Corrected the dark-appearance test to set `SpeakIt.appearance=dark`, because a system appearance argument alone does not override the app's first-install light preference. The corrected test passed separately.
- Local screenshots: `output/ui-effects/capture-light.png` and `output/ui-effects/capture-dark-accessibility.png`.
- Physical microphone behavior, sustained animation smoothness and energy usage are not verified by these simulator checks. Reduce Motion and scene inactivity handling were reviewed in code; the screenshots show the ready state.

## App-only follow-up

Added `SavedCaptureSeal` to the existing saved receipt. Two joined ink lobes settle into its original 104-point circle with a single damped spring. This is a custom native path, not a shader or new package. The receipt's text, controls, persistence and dismissal timing are unchanged. Duplicates, operations and review outcomes do not celebrate. Reduce Motion/inactive scenes render the final shape, and returning to the foreground does not replay the effect. The existing capture UI test now retains a receipt screenshot. Website work remains out of scope; liquid metal and image-loading effects were not recommended for the app.
