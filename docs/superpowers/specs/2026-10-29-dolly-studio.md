# Dolly studio pass

Date: 2026-10-29. Status: design for review, no code. Adds to `2026-10-26-dolly-design.md`; where the two disagree, this one wins.

The owner asked for a studio editor after a take, with FocuSee's editor as the reference. Dolly already has the editor's frame (spec section 6). This pass makes it a studio by pulling M2 (every shape) and the backdrop half of M3 forward, and by regrouping the inspector. Mockups: `docs/mockup/studio/look-light.png`, `look-dark.png`, `zoom-light.png`, `zoom-dark.png` (source `studio.html`).

## What changes

1. **Shape bar above the stage:** Original, 16:9, 1:1, 4:5, 9:16. Original is the recording's own aspect, long side 1920 px. The note beside it names the export size ("Exports 1080 × 1350 for X and Threads"). The stage shows the output frame at that shape, centered in the stage area on the raised tone. Zooms are unchanged by the shape (spec 5.3, including "In tall shapes").
2. **Inspector tabs:** Look, Pointer, Zooms, as one segmented control at the top of the 288 pt panel. Selecting a zoom on the stage or the timeline switches to Zooms; Esc or a click on empty stage goes back to the tab that was open before.
   - **Look:** Backdrop, Padding, Corners, Shadow, and "Use for new takes".
   - **Pointer:** Size, Smooth path, Ring on each click, Hide when still (unchanged controls, moved).
   - **Zooms:** the zoom inspector of spec 6.4. With no zoom selected it shows the count and "Select a zoom on the timeline or press Z to add one at the playhead."
3. **Backdrop library** (Look):
   - Six flat colors: the five of M1 plus near-black `#151413`.
   - Six gradients drawn by Dolly: Harbor, Ember, Slate, Moss, Rose, Sand. Each is a linear gradient with one soft radial light, made with Core Image so preview and export match. Dolly's own colors, not copied from FocuSee or from macOS wallpapers.
   - Pictures: "Desktop" uses the current desktop picture of the display the take was recorded on (`NSWorkspace.desktopImageURL(for:)`, no permission needed). "Choose…" opens a file panel for any image. The picture is copied into the take folder as `backdrop.<ext>`, so a take still opens after the original moves.
   - Blur (0 to 40 pt) appears under the swatches only when a picture is the backdrop.
4. **Sliders with values:** Padding 0 to 160 pt, Corners 0 to 24 pt, Shadow 0 to 100 % (replaces the on and off toggle; an old take's `true` reads as 60 %, `false` as 0 %).
5. **Export sheet:** the plates of spec 7 now include Original. The current shape is checked.

## What stays

Toolbar, takes sidebar, the spike-tape timeline, Aim mode with its corners, the corner card after a take, the tokens in spec 10.4, and every keyboard command in 6.2 and 6.3.

## Left out on purpose

FocuSee's camera, captions, audio and effects tabs, and its icon rail: Dolly has none of those features, and an empty rail would only point at them. No 4:3 shape (X and Threads crop it like 1:1 or 4:5).

## Data

- `Look.Background` gains `.gradient(id: String)` and `.picture(file: String, blur: Double)`. `shadow` becomes a `Double` (0 to 1) with the migration above. Take files stay version 1 with the new cases optional on decode.
- `ShapePreset` gains `.original`, sized from `Take.size` with the long side at 1920 px and both sides even.
- The take remembers its last shape (`Take.shape`, default 16:9) so the stage opens where the owner left it.

## Motion (checked against `app-updates/docs/motion-gate.md`)

| Candidate | Frequency | Verdict |
|---|---|---|
| Switching tabs | Tens per session | Rejected. Instant. |
| Switching shapes | Tens per session | Rejected. The stage re-renders at once (as in 10.6). |
| Picking a backdrop | Tens per session | Rejected. Instant; the stage is the feedback. |
| Blur row appearing for pictures | A few per session | Rejected. It appears with the choice that needs it. |

No new motion.

## Decisions for the owner

1. Gradient backdrops reverse decision 6 of the first spec (flat only). They are clip content, not app chrome, so the app keeps its flat look.
2. The takes sidebar stays. Hiding it (View menu, `⌃⌘S`) is cheap to add if the stage needs more room.
3. Original as a fifth shape.
