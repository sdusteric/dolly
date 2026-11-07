# Dolly studio pass

Date: 2026-10-29. Status: design for review, no code. Adds to `2026-10-26-dolly-design.md`; where the two disagree, this one wins.

The owner asked for a studio editor after a take, with FocuSee's editor as the reference, then for a webcam and captions that stay editable after recording. Dolly already has the editor's frame (spec section 6). This pass makes it a studio by pulling M2 (every shape), the backdrop half of M3 and the microphone forward, adding the camera and captions, and regrouping the inspector. Mockups in `docs/mockup/studio/`, light and dark: `look`, `zoom`, `camera`, `captions` (source `studio.html`; the face in the camera is a stand-in, "Portrait of a Smiling Man" by Theo van Doesburg, 1905, public domain).

## What changes

1. **Shape bar above the stage:** Original, 16:9, 1:1, 4:5, 9:16. Original is the recording's own aspect, long side 1920 px. The note beside it names the export size ("Exports 1080 × 1350 for X and Threads"). The stage shows the output frame at that shape, centered in the stage area on the raised tone. Zooms are unchanged by the shape (spec 5.3, including "In tall shapes").
2. **Inspector tabs:** Look, Zooms, Camera, Captions, as one segmented control at the top of the 288 pt panel. Selecting a zoom, the camera or a caption on the stage or the timeline switches to its tab; Esc or a click on empty stage goes back to the tab that was open before.
   - **Look:** Backdrop, Padding, Corners, Shadow, then Pointer: Size, Ring on each click, Smooth path, Hide when still. "Use for new takes" at the foot.
   - **Zooms:** the zoom inspector of spec 6.4. With no zoom selected it shows the count and "Select a zoom on the timeline or press Z to add one at the playhead."
   - **Camera** and **Captions:** sections 6 and 7 below.
3. **Backdrop library** (Look):
   - Six flat colors: the five of M1 plus near-black `#151413`.
   - Six gradients drawn by Dolly: Harbor, Ember, Slate, Moss, Rose, Sand. Each is a linear gradient with one soft radial light, made with Core Image so preview and export match. Dolly's own colors, not copied from FocuSee or from macOS wallpapers.
   - Pictures: "Desktop" uses the current desktop picture of the display the take was recorded on (`NSWorkspace.desktopImageURL(for:)`, no permission needed). "Choose…" opens a file panel for any image. The picture is copied into the take folder as `backdrop.<ext>`, so a take still opens after the original moves.
   - Blur (0 to 40 pt) appears under the swatches only when a picture is the backdrop.
4. **Sliders with values:** Padding 0 to 160 pt, Corners 0 to 24 pt, Shadow 0 to 100 % (replaces the on and off toggle; an old take's `true` reads as 60 %, `false` as 0 %).
5. **Export sheet:** the plates of spec 7 now include Original. The current shape is checked.

6. **Timeline lanes:** Video, Zoom, Camera, Captions, Clicks. The stage gives up 40 pt of height to the timeline (stage area 868 × 448).

## Camera (webcam)

- **Recording:** the Record bar gets Camera and Microphone switches, both off by default, each with a device menu. With Camera on, a small mirrored preview floats next to the bar until Record. The camera is written to `camera.mov` in the take folder (H.264, 1280 × 720 or the device's closest size, 30 fps), on the same host clock as the screen master, so the two line up without a sync step. It is never drawn into the screen recording.
- **Permission:** Camera access is asked the first time the switch is turned on, with Snap's first-run pattern: why, one button, then a hint if it stays denied. Dolly never opens the camera unless the switch is on.
- **Camera tab:** Show camera; Circle or Rounded; Size 10 to 40 % of the output's short side (22 % default); Corner (four-way picker) or drag on the stage to any spot; Border (3 pt white); Shrink during zooms (to 60 % over the zoom's own move in and move out); Mirror (on by default, because people expect to see themselves mirrored).
- **Camera lane:** one bar for where the camera shows. Drag on the lane to hide a stretch; the gap's ends drag like a zoom's ends. Hiding and showing cut, no fade.
- **Every shape:** the bubble keeps its corner and its size relative to the short side, so 16:9 and 9:16 need no separate placement. A spot placed by dragging is stored relative to the output frame.

## Captions

- **Source:** "From your voice" transcribes the microphone track on this Mac with Apple's SpeechAnalyzer and SpeechTranscriber (macOS 26 and later). macOS may download the language model once; Dolly itself makes no network request. "Typed" starts an empty lane for captions the owner types (`C` adds one at the playhead).
- **Splitting:** the transcriber's phrases become captions of at most two lines and about 42 characters a line, split at sentence ends and pauses over 0.4 s. Return in the caption field splits at the cursor; Delete at the start joins with the one before.
- **Captions tab:** the selected caption's text and times; Bottom, Middle or Top; Size 10 to 24 pt at 1080 px; "Save an .srt file with each export"; "Transcribe again" (asks first when captions were edited).
- **Style:** Avenir Next Demi Bold, white on a near-black pill at 74 %, centered, the same in every shape. A bottom caption moves above a bottom camera instead of covering it.
- **Captions lane:** one chip per caption; drag the middle to move, the ends to retime.
- **Export:** captions are drawn into the video (X and Threads autoplay muted), and an `.srt` with the same name when the switch is on.

## Spikes before the build

- **S3, speech permission:** whether SpeechTranscriber on macOS 27 needs the Speech Recognition permission (`NSSpeechRecognitionUsageDescription`) or only the model download. The owner runs a five-minute check with a debug build, like S1 and S2.
- **S4, camera and screen clocks:** start both, clap once on camera while clicking, check the offset in the take. Under one frame passes.

## What stays

Toolbar, takes sidebar, the spike-tape timeline, Aim mode with its corners, the corner card after a take, the tokens in spec 10.4, and every keyboard command in 6.2 and 6.3.

## Left out on purpose

FocuSee's icon rail, its effects and its AI tools: the four tabs carry everything Dolly does. No 4:3 shape (X and Threads crop it like 1:1 or 4:5). No system audio in this pass (built later, first spec 4.2). No word-by-word highlight in captions.

## Data

- `Look.Background` gains `.gradient(id: String)` and `.picture(file: String, blur: Double)`. `shadow` becomes a `Double` (0 to 1) with the migration above. Take files stay version 1 with the new cases optional on decode.
- `ShapePreset` gains `.original`, sized from `Take.size` with the long side at 1920 px and both sides even.
- The take remembers its last shape (`Take.shape`, default 16:9) so the stage opens where the owner left it.
- `Take.camera`: `{ file, visible: [ranges], shape, size, corner | point, border, shrinkDuringZooms, mirror }`, absent when the take has no camera.
- `Take.captions`: `{ source: voice | typed, locale, position, size, saveSRT, items: [{ id, start, end, text }] }`. The microphone track is `audio.m4a` in the take folder.

## Motion (checked against `app-updates/docs/motion-gate.md`)

| Candidate | Frequency | Verdict |
|---|---|---|
| Switching tabs | Tens per session | Rejected. Instant. |
| Switching shapes | Tens per session | Rejected. The stage re-renders at once (as in 10.6). |
| Picking a backdrop | Tens per session | Rejected. Instant; the stage is the feedback. |
| Blur row appearing for pictures | A few per session | Rejected. It appears with the choice that needs it. |
| Camera shown, hidden or moved to a corner | A few per session | Rejected. Instant in the editor; in the clip it cuts. |
| Shrink during zooms | Content | Not UI motion: it rides the zoom's own move in and out. |
| Caption changes | Content | Cut between captions; no fade or typewriter. |

No new motion.

## Decisions for the owner

1. Gradient backdrops reverse decision 6 of the first spec (flat only). They are clip content, not app chrome, so the app keeps its flat look.
2. The takes sidebar stays. Hiding it (View menu, `⌃⌘S`) is cheap to add if the stage needs more room.
3. Original as a fifth shape.
4. Camera and captions reverse the first spec's non-goals (webcam overlay, captions). The microphone moves from M3 into this pass, because captions need it.
5. Captions are drawn into the video by default; the .srt is opt-in.
