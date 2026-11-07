# Dolly design

Date: 2026-10-26. Status: design only, no app code. A new Swift app in the mac-apps family that replaces FocuSee, which stopped working when the owner cancelled Setapp. "Dolly" is a working name (a camera dolly moves the camera in on the subject); renaming it later is cheap.

Product truth is in `../../../PRODUCT.md`. Mockups are in `docs/mockup/` (static HTML rendered to PNG at 2x with headless Chrome, light and dark; `contact-sheet.png` shows all three directions).

Calls marked **(my call)** were made without the owner, who said "just start". Section 15 lists them for review.

## 1. What Dolly is

The owner records demos of their websites and Mac apps and posts them on X and Threads. Dolly records the screen, a window or an area with the real cursor hidden, logs where the pointer went and where it clicked, and turns that into a clip where the view moves in on each click and follows the pointer, set on a background and sized for the feed.

Record, edit, export:

1. **Record.** A hotkey or `dolly://record` opens a small Record bar: pick Window, Area or Display, then Record. A 3-second countdown, then recording; the menu bar timer stops it.
2. **Edit.** The take opens in the editor. Dolly has already turned the clicks into zooms. The owner moves, resizes, deepens or removes them on the timeline or on the stage, trims the ends, picks a background.
3. **Export.** Pick one or more shapes (16:9, 1:1, 4:5, 9:16). Dolly writes one mp4 per shape and offers Copy (the file, for pasting into a browser upload) and Show in Finder.

### Goals

- A 30 to 60 second demo goes from record to a ready mp4 in under five minutes.
- Most zooms land on the right thing with no hand placement.
- One edit exports to every shape without re-editing.
- Smooth, cinematic pointer and camera motion: the clip should look better than the raw screen.

### Non-goals (v1)

- Webcam overlay, AI captions or transcripts, text overlays and titles, templates, music.
- Posting to X or Threads (no accounts, no API keys). The owner uploads by hand.
- Editing several takes into one clip.
- GIF export (later, if asked).

### Anti-goals (it fails even if it works)

- Zooms that lurch, overshoot or hunt for the pointer. A clip that makes viewers seasick is worse than no zoom.
- A permission prompt for Accessibility or Input Monitoring just to record clicks (section 4.3).
- Losing a take. A crash during recording or editing never loses the recorded file.
- An editor that looks like a template video app. It sits in the family with its own look (section 10).

## 2. Who uses it and how often

One person on one Mac, a few times a month, 10 to 30 minutes a session: one to three takes, edit one, export one or two shapes (inferred from FocuSee's use on this Mac: last opened 2026-09-30, 7 launches recorded). Subjects are web pages in a browser and the family's own apps. Clips are watched on phones with the sound off, so the zoom has to make small UI readable.

Snap stays the tool for screenshots and quick plain recordings. Dolly is for demos that get edited and posted.

## 3. Relation to the family

- **Snap.** Dolly copies Snap's recording code into its own repo (repos never share packages): the ScreenCaptureKit filter and configuration builder from `snap/Sources/SnapSystem/LiveRecordingSource.swift`, `RecordingPlan`, `RecordingHeartbeat`, `AudioCheck`, the disk checks and the failure table in Snap's design section 20.6. Dolly does not use `SCRecordingOutput` (Snap does), because it needs per-frame timestamps to line up the pointer log; it writes with `AVAssetWriter` from the `SCStream` sample buffers (section 4.2).
- **Hotkeys.** Dolly registers `⌃⌥⌘R` for Record (Carbon `RegisterEventHotKey`, as Snap does; not among Snap's `⌘⇧3/4/5` or Shelf's `⌃⌥⌘Space`) **(my call)**. Settings can change it.
- **Shelf.** URL scheme `dolly`, `SDShelfActions = [record, open-latest, check-for-updates]`. Status file `status/dolly.json` with the latest take's title, length and export state ("Exported 16:9 and 4:5, 2 h ago"), and an optional poster in `status/dolly/poster.jpg` when "Show in Shelf" is on. Shelf's `AppCatalog` gains a sixth entry (role "Demo videos"). These are changes to `app-updates/CONTRACT.md` and to Shelf, done in their own repos after this design is approved.
- **Updates and signing.** Per `app-updates/CONTRACT.md` and `docs/adding-an-app.md`: Sparkle 2.10.0, feed `https://sdusteric.github.io/app-updates/dolly/appcast.xml`, `DOLLY_NO_UPDATES=1`, Developer ID 8N9KUZLT8N, notarized with the `sdusteric-notary` profile, `scripts/release.sh` with `--dry-run` for agents.
- **Look.** Avenir Next for display, SF for text, a main color none of the siblings use (section 10).

## 4. Recording

### 4.1 Targets

Window (default), Area, Display. Window uses `SCContentFilter(desktopIndependentWindow:)` with `ignoreShadowsSingleWindow = true`; Area and Display exclude Dolly's own panels. The picker is the same click-a-window or drag-an-area overlay Snap uses; Dolly copies Snap's overlay code rather than inventing a new one.

The Record bar is a small floating panel (not a window in the Dock's sense) near the top of the screen: target buttons, "System audio" and "Microphone" toggles (both off by default), Record. Snap's HUD is the reference.

While the bar is open the editor window leaves the screen, so the owner can see and pick what is behind it. The Window target follows the owner: clicking another window (another app, or another window of the same app) while the bar is open picks it, and the window menu still picks any window by hand. Dolly reads the front window from the window list four times a second, only while the bar is open. If they cancel, it comes back where it was; once a recording starts, it stays away and the take card brings it back.

### 4.2 Capture

- `SCStreamConfiguration`: `showsCursor = false` (Dolly draws its own pointer, 4.7), 60 fps (`minimumFrameInterval` 1/60) **(my call: demos have fast pointer moves; 30 fps judders when zoomed)**, native pixel size (Retina 2x), `queueDepth` 6, sRGB, BT.709 tagging on the file.
- Writer: `AVAssetWriter`, HEVC at high quality for the master file (`take.mov`), so edits never re-encode a lossy H.264 twice. Audio as AAC 48 kHz in the same file when on.
- **System audio (2026-11-07, my calls):** a "System audio" switch in the Record bar, off by default and remembered. ScreenCaptureKit records the sound other apps play (`capturesAudio`, `excludesCurrentProcessAudio`, 48 kHz stereo; a window take hears that window's app) into `system.m4a` beside the movie, AAC 160 kbit/s, with its first sample's offset in take.json. It needs no permission beyond Screen Recording. A failure drops the sound, never the take. The editor and export mix it with the microphone at full level on separate tracks; sped-up stretches are silent (6.3.1).
- Every video sample's presentation time is kept; the pointer log (4.3) uses the same host clock (`CMClockGetHostTimeClock`), so pointer and frames line up exactly.
- Disk: refuse to start under 2 GB free; stop cleanly under 500 MB (Snap's rule).
- Max length 30 minutes **(my call)**; a warning at 5 minutes in the menu bar timer tooltip ("Longer than Threads allows").
- Failure modes: Snap's table in its design section 20.6 applies as written, with Dolly's names.

### 4.3 Pointer and click log, without extra permissions

Dolly needs the pointer position at every frame and the time of each click.

- **Position:** sample `NSEvent.mouseLocation` on Dolly's own 120 Hz timer, not on frame callbacks: ScreenCaptureKit sends a frame only when the screen changes, and with the cursor hidden a moving pointer over a still screen produces no frames (no permission needed). Store in global display points.
- **Clicks, plan A:** `NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown])`. Global monitors for mouse events are expected to work without the Accessibility permission (key events need it).
- **Clicks, plan B:** poll `NSEvent.pressedMouseButtons` at 120 Hz on a timer and record press and release edges. Needs no permission at all; misses only clicks shorter than about 8 ms.
- **Spike S1 (first day of building):** confirm plan A works on macOS 27 with no prompt and no Accessibility grant; if it prompts or gets nothing, ship plan B. Either way Dolly never asks for Accessibility or Input Monitoring for clicks.
- **Pointer shape:** sample `NSCursor.currentSystem` (or its replacement on macOS 27) at 10 Hz to learn when the pointer becomes an I-beam or a pointing hand, and store the shape name (arrow, ibeam, pointingHand, other). **Spike S2** checks that this works for other apps' windows; if not, Dolly draws the arrow always and offers "Record the real pointer" (`showsCursor = true`, no smoothing, the real pointer scales with the zoom) as a setting.
- **Keystrokes:** not logged in v1. A later "Show keys" feature would need Input Monitoring and stays off unless the owner turns it on.

Log format: `pointer.bin`, little-endian records of `(t: Float64 host seconds, x: Float32, y: Float32, buttons: UInt8, shape: UInt8)`, one per timer tick plus one per button edge, and `window.bin` for Window targets: `(t, x, y, w, h)` of the window's frame in global points, written whenever it changes **(my call, see 4.4)**. A one-minute take is about 7,200 records, under 200 KB. `dollyctl pointer <take>` dumps it as CSV for tests.

### 4.4 Timing, windows that move, several displays **(my calls, from the builder check)**

- **Variable frame rate master.** `take.mov` keeps frames as ScreenCaptureKit delivers them (variable rate, real timestamps). The compositor holds the last frame for any output time, so preview and export are constant 60 or 30 fps. Probe tests check timestamps, not a fixed frame count.
- **Window targets that move or resize.** The output size is fixed when recording starts. Each frame's `SCStreamFrameInfo.contentRect` and `scaleFactor` attachments say where the window content sits in the frame; `window.bin` logs the window's global frame. Pointer points map into recording coordinates through the window frame at that time. A window that grows is scaled to fit (`scalesToFit`), and the take notes "Window size changed at 0:21.4".
- **Several displays.** All logs use global display points (the space `NSEvent.mouseLocation` uses). Display and Area targets are one display; the pointer on another display is "off recording" and the drawn pointer hides.

### 4.5 Which input makes a zoom **(my calls)**

- Left mouse-down only. A double-click is one click. A drag (held over 0.4 s or moved over 8 pt) is one click at its mouse-down, and its zoom uses Follow pointer until mouse-up. Right clicks and scrolls make no zoom in v1 (logged for later).
- Dolly's own clicks never count: clicks before the countdown ends and the click that stops the recording (menu bar timer, Record bar) are dropped by time, so no take starts or ends with a stray zoom.
- Zoom times are recording time. Trim is a window over them: a zoom that crosses a trim edge is clamped to it, and a move-in before 0:00 is clamped to start at 0:00.

### 4.6 Naming a zoom without Accessibility **(my call)**

Reading the element under a click would need Accessibility, so Dolly reads the pixels instead: after recording, Vision text recognition (`VNRecognizeTextRequest`, on device) runs on the frame at each click, in a 300 × 120 pt box around the click point, and the text line nearest the click becomes the zoom's name ("Run check up"). No text found: "Click at 0:07.9". The take never waits for this: it is saved and opened with the "Click at" names, and the read names fill in when Vision is done (it can take 10 s or more the first time it runs), only on zooms the owner has not renamed meanwhile, and not as an undo step. The owner can rename any zoom in the inspector. Names are labels only; nothing depends on them.

### 4.7 Drawing the pointer

The exported clip shows Dolly's own pointer: the macOS arrow (or I-beam, pointing hand) drawn from bundled vector paths at 1.5x by default, white outline, soft shadow. "Smooth pointer path" (on) runs the logged positions through a critically damped spring (response 0.12 s) so small hand jitter disappears but clicks still land where they happened: within 150 ms of a click, the drawn pointer is pinned to the real click point. "Ring on each click" (on) draws a ring that grows from 0.95x to 1.6x and fades over 360 ms at each mouse-down **(content, not UI motion; see 10.6)**. "Hide when still" hides the pointer after 3 s without movement (off by default).

## 5. Automatic zooms

### 5.1 From clicks to zooms

Rules, applied in order **(my call; all numbers are settings in `ZoomRules` and tunable)**:

1. Every click that counts (4.5) is a candidate.
2. Clicks less than 3.0 s apart join one zoom.
3. A zoom starts 0.6 s before its first click (the move in) and holds until 1.5 s after its last click, then moves out over 0.5 s.
4. Two zooms less than 1.0 s apart (end to start) merge, so the camera never moves out and straight back in.
5. Depth: 2.0x for a single click, 1.8x for a merged zoom whose clicks spread over more than 40% of the recording's width, 1.6x when the window is smaller than 900 pt wide (it is already big on screen). Clamped to 1.25 to 3.0.
6. Aim: a single-click zoom holds on its click ("Hold on the click"). A merged zoom whose clicks are far apart follows the pointer ("Follow pointer").
7. A take with no clicks gets no zooms.

The Shelf demo in the mockups: 9 clicks became 5 zooms (clicks at 15.2, 17.0 and 19.8 s share zoom 3).

### 5.2 Camera

The camera is a rectangle over the recording. At depth `z` in an output of `W x H`, the visible region is `W/z x H/z` of the composed frame (recording plus background padding), centered on the aim point, then clamped so it never shows past the recording's edge into empty background on any side where the recording is larger than the view (`frame.js` in the mockups does exactly this, and `ZoomCamera` must match it).

- **Hold:** the aim point is the click point.
- **Follow pointer:** the aim point follows the smoothed pointer with a dead zone: the camera moves only when the pointer leaves the middle 60% of the view, then eases so the pointer sits back inside.
- **Moving in and out:** depth and position animate together over the move-in and move-out times with an ease-in-out curve (cubic bezier 0.45, 0, 0.25, 1) **(my call)**. A zoom that starts while another is ending blends from the current camera, never from 1x.
- The camera path is computed once from the take and the zoom list (`CameraPath`, pure, in DollyCore) and sampled per output frame. Preview and export sample the same path, so what plays is what exports.

### 5.3 Shapes

Every zoom is stored once, in recording coordinates (aim point, depth, times). Each output shape builds its own camera from the same zooms:

- The recording is fitted into the shape with the padding (64 pt default at 1080 px output height or width, whichever is shorter), then the camera applies.
- In tall shapes (4:5 and 9:16) a wide recording is small at 1x. Dolly fits the recording to the shape's width, so the background fills above and below, and the zoom still aims at the click. "In tall shapes" in the inspector offers "Keep the click centered" (default) or "Fill the height" (crops the recording's sides at 1x and pans to follow the pointer) **(my call)**.
- Changing the shape in the editor switches the stage at once; nothing about the zooms changes.

## 6. The editor

Direction A, Spike marks (section 10), is the target: `docs/mockup/directions/a-light.png` and `a-dark.png`.

### 6.1 Layout (1440 x 900 window, the minimum is 1100 x 720)

- **Toolbar** (52 pt, on the frame color): traffic lights, the take's name (editable, Avenir Next Demi Bold 15) and its facts ("Window, 848 × 858 pt, 60 fps, recorded today 10:42"), then Record and Export on the right. Export is the one near-black primary button.
- **Takes sidebar** (228 pt, frame color): every take with a 56 x 40 poster, name, length and zoom count or "exported". The selected take is a neutral grey pill. Footer: where takes live and the total size. Right-click: Rename, Show in Finder, Move to Trash (to the Trash, never a hard delete; exports stay). Double-click a name to rename it in place: Return or clicking away keeps it, Esc puts it back. File > Move to Trash trashes the open take (no shortcut, so a slip near the zoom Delete key cannot trash a take); the take below it opens next. Duplicate is not built. A new take is named after what was recorded: the window's app and title as the Record bar labels it ("Kalos, apple.com"), or for an area or display the front window under it, cut at a word near 60 characters, with " 2", " 3" when the name is taken. Nothing found: "Untitled take N".
- **Sheet** (white or the dark surface, 16 pt corners, 1 pt edge, inset 8 pt from the window's right and bottom): the stage with the shape switcher above it, the inspector on the right, the timeline below.

### 6.2 The stage

Shows the clip in the chosen shape. Two modes:

- **Play mode** (no zoom selected, or playing): the output as it will export, camera and pointer included.
- **Aim mode** (a zoom is selected and the player is paused): the whole recording at 1x with a scrim outside the zoom's view and four pink spike corners around it, plus its tape label ("2.0×  Run check up") above the top-left corner and a ring at the click that made it. Drag inside the corners to re-aim; drag a corner to change depth (the opposite corner stays put, aspect locked); hold Shift to drag without snapping to the click point. A one-line hint names the two drags until the owner first re-aims a zoom, then never again. Arrow keys nudge the aim 1 pt (Shift 10 pt); `-` and `=` change depth by 0.1x.

### 6.3 The timeline

- Header: play button, time "0:08.6 / 0:48.2", and the length check: "Fits X (2:20 max) and Threads (5:00 max)". Over a limit it says which one in words ("Too long for X by 0:12"); the limits live in one table in DollyCore and are checked against the platforms' current published limits when building (they change).
- Ruler, then three lanes: **Video** (stills from even slices of the take, decoded after it opens with the poster standing in, and trim handles at both ends), **Zoom** (each zoom a pink tape strip spanning its time, depth inside, target name under it; the move-in and move-out show as a darker band at each end), **Clicks** (one dot per click).
- Click a strip to select it; drag its middle to move it in time, its ends to change when it starts or stops. Drag on empty Zoom lane to draw a new zoom (aimed at the pointer position at that time). `Z` adds a zoom at the playhead. Delete removes the selected zoom (undoable). Selecting a strip selects the same zoom on the stage and in the inspector: the strip and the corners are one object.
- Space plays and pauses. J, K, L shuttle. Left and right move the playhead one frame (Shift one second). Tab moves selection to the next zoom.
- Undo and redo cover every edit (`⌘Z`, `⇧⌘Z`).

### 6.3.1 Cuts and speed-ups **(my calls, 2026-11-07)**

- A **Speed** lane sits under Video. Each region on it is a stretch of the take that is cut out of the clip ("Cut", in the control tone) or played faster ("2×", "4×" or "8×", in ink). Cut stretches are shaded on the filmstrip like the trimmed ends.
- Drag on the empty Speed lane to mark a cut. `X` cuts 2 s from the playhead (`⌘X` stays the Edit menu's). Drag a region's ends to resize it and its middle to move it; Delete removes it. Regions never overlap and never leave less than 0.5 s of clip.
- With a region selected, the line under the timeline shows Cut / 2× / 4× / 8×, what it does ("Removes 2.0 s", "Plays 6.0 s in 1.5 s") and Remove. The inspector keeps its tab.
- The timeline stays in take time. The clock, the length check, the sidebar length and Shelf show the clip's length after cuts and speed-ups.
- One time map (DollyCore `TimeMap`) turns take time into clip time for the player, the compositor, the exporter and the .srt, so they agree. Zooms, the pointer, captions and the camera bubble keep their take times; a zoom over a cut simply jumps with the cut. A caption wholly inside a cut is left out of the .srt.
- Sped-up stretches are silent: the microphone and the recording's sound are left out there, since fast speech is noise. The webcam speeds up with the screen.

### 6.4 The inspector (288 pt)

With a zoom selected: its name ("Zoom 2 of 5") and times, "From your click at 0:07.9", Hold on the click or Follow pointer, Depth slider (1x to 3x), Move in and Move out times (0.2 to 1.5 s), Remove this zoom.

Always below: **Look**: Background (five flat colors plus a picture of the owner's choosing; no gradients in v1, see 15), Padding (0 to 160 pt), Corners (0 to 24 pt), Shadow under the recording (on), Pointer size (1x to 3x), Smooth pointer path, Ring on each click, Hide when still. Look settings belong to the take; "Use for new takes" saves them as the default.

### 6.5 Empty, first-run and error states

- Launch and the Dock open the Record bar unless a take is open in this run, so a fresh launch never brings back the last recording. Window > Editor and Shelf's open-latest action still reach the takes.
- No takes yet: the Record bar, since the editor has nothing to show. Opened from Window > Editor, the sheet shows one sentence and the Record button with its shortcut: "Record a window, an area or the whole screen. Dolly zooms in where you click."
- First Record without Screen Recording permission: Snap's first-run pattern (a window that says why, one button that asks macOS, then a hint if it stays denied).
- Take with no clicks: the Zoom lane shows "No clicks in this take. Press Z to add a zoom at the playhead."
- A take whose files are missing or unreadable: the sidebar row says "Can't open this take" with Show in Finder.
- A save that fails (a full disk): a sheet says "Couldn't save this take" with the reason, once until a save works again; the edits stay open. Switching takes while it fails offers Keep editing or Discard edits.
- The open take trashed in Finder: Dolly closes it and never writes its folder back.
- Quit during a stop waits for the take to save; quit during an export cancels it and removes its scratch folder, and launch sweeps any left by a crash.

## 7. Export

- Export opens a sheet attached to the window: the four shapes as **plates** side by side on one baseline (direction B's discipline, kept here), each showing the frame at the playhead in that shape, with a checkbox. The current shape is checked. Below: frame rate (60 fps or 30 fps; H.264), the folder (default `~/Movies/Dolly`), Export.
- Sizes: 16:9 1920 × 1080, 1:1 1080 × 1080, 4:5 1080 × 1350, 9:16 1080 × 1920. H.264 High profile, AAC 48 kHz when there is audio, `+faststart` (moov atom first) so uploads start fast. Bit rate about 12 Mbit/s at 1080p60 **(my call)**; a 48 s clip is about 70 MB.
- Rendering: an `AVVideoCompositing` compositor (Core Image on Metal) that draws background, rounded recording with shadow, the camera transform and the pointer, used by both the preview player and `AVAssetWriter` export. The preview renders at twice the export canvas on a Retina screen (same picture, more pixels), so a zoom shows the recording's own Retina detail instead of a stretched 1080p frame; the pointer, ring and caption bitmaps are drawn at that density too. Export runs in the background with a progress bar per shape in the sheet and in the toolbar; the editor stays usable.
- Done: "Saved 2 files" with Copy (puts the file URLs on the pasteboard so a browser upload field accepts a paste) and Show in Finder. File names: `<take name> 16x9.mp4`.
- Esc closes the sheet. While an export runs, Esc stops it and the sheet stays open.
- Platform limits (length, file size, resolution, fps) are checked before export with plain warnings and never block: the owner may have a paid tier.

## 8. Files and data

```
~/Movies/Dolly/                      # takes and exports (setting)
  Takes/<uuid>/take.mov              # HEVC master, audio if any
  Takes/<uuid>/pointer.bin           # 4.3
  Takes/<uuid>/take.json             # version, name, created, target, size, fps, trim, look, zooms
  Takes/<uuid>/poster.jpg
  <take name> 16x9.mp4               # exports
~/Library/Application Support/Dolly/settings.json
```

`take.json` holds zooms as `{ id, start, end, aim: {x, y} (recording points), depth, mode: hold|follow, moveIn, moveOut, source: auto|manual, clickIDs }`. Auto zooms are saved like manual ones the moment the take opens, so later rule changes never move a zoom the owner already looked at. Writes are atomic (write to a temp file, rename). `DOLLY_HOME` replaces both roots in tests.

## 9. Architecture sketch (not built)

Same shape as Snap and Shelf.

- `DollyCore` (Foundation, CoreMedia types only): `RecordingPlan`, `PointerLog` reader and writer, `ZoomRules` (clicks to zooms), `CameraPath`, `ShapePreset`, `PlatformLimits`, `Take` and `TakeStore`, `UndoStack`, `ExportPlan`, the Shelf status writer, fakes. Pure and fully unit tested: the zoom rules and the camera path are where the product lives, so they get the most tests (golden camera paths from fixture logs).
- `DollySystem`: ScreenCaptureKit stream, `AVAssetWriter`, the pointer sampler and click monitor, Carbon hotkey, `NSWorkspace`, disk checks.
- `DollyRender`: the compositor (Core Image and Metal), shared by preview and export.
- `DollyUI`: SwiftUI in AppKit windows: editor, timeline (a custom view; one `Canvas` for lanes and strips), stage, inspector, Record bar, export sheet. `Shared/Theme.swift` holds every token.
- `Dolly`: the app, Sparkle (exact 2.10.0), shot mode (`--shot` renders each surface from fixtures with no window, like Snap's).
- `dollyctl`: headless CLI: `zooms <pointer.bin>` (prints the zoom list the rules make), `camera <take> --at 8.6`, `render <take> --shape 9:16 --frames 0,8.6,20 --out dir` (stills from the real compositor), `pointer <take>` (CSV).
- Swift 6, macOS 27, Swift Testing. Safety rules as in Snap's CLAUDE.md: tests never capture the screen, open the microphone, register a hotkey, show a window or touch the pasteboard; recording is tested with a fake source that writes real frames and a synthetic pointer log.

## 10. Visual design

Mode: Operate. A working editor used in 10 to 30 minute sessions; the look is in ground, one signal color, type and the one signature move. Physical scene: the owner at a desk, day or night, judging a clip that will be seen on a bright phone, so the stage stays neutral and the chrome follows the system appearance (light and dark both designed).

### 10.1 How the directions were made

`impeccable` (shape, new-work with `concept-seed --scope direction --mode operate`, seed a31aef96) and `design-taste-frontend` (app-screen run, `framed-sheet` style, seed 1557923095, with `--keep` of the family's type: Avenir Next and SF instead of the dealt IBM Plex). The roll assigned candidate 3 of my grounded list (spike tape and the dolly track), which became A. Dealt challengers were fused and judged on audience identification and product clarity:

| Challenger | Verdict | Kept |
|---|---|---|
| Botanical folio (plates at one scale on one baseline) | Competitive: clear for comparing shapes | Became direction B; its discipline is kept in A's export sheet (section 7). |
| Cassette j-card (sides must not overflow the tape) | Declined | The length budget against each platform's limit is always on screen (6.3). |
| Rail split-flap board | Declined | Fixed cells: every time figure is tabular, in fixed-width columns. |
| Metro typographic tiles | Declined | No chrome on the stage: the clip runs edge to edge in its frame. |
| Star atlas | Declined | None needed beyond A's ramp shading. |
| Event catalog (map and grid are one space) | Declined | The strip on the timeline and the corners on the stage are one object: selecting either selects both. |

Impeccable's own pick was C (storyboard). Not built from the roll; shown as the third option.

### 10.2 The three directions

**A. Spike marks (recommended).** On a stage floor, tape marks show where an actor stands and where the camera lands. Zooms are strips of fluorescent pink spike tape on the timeline and L-shaped spike corners on the stage; selecting a zoom shows the whole recording with the four corners around the camera's view, and you drag the corners to re-aim or change depth. Warm concrete frame (light) or stage-floor black (dark), white sheet, near-black ink, pink only on zoom marks. Strength: the most direct way to aim a zoom, a standard editor layout, and a signature that comes from the job. Risk: the pink must read on every background the owner picks for the clip (fixed with a dark outline on the corners, 10.4).

**B. Plates.** The same moment in all four export shapes at once, on one baseline, and zoom depth drawn as a profile over time you drag up and down. Strength: "record once, export every shape" is visible all the time. Weakness: no plate is large enough to aim a zoom precisely, and four live renders cost GPU time while scrubbing.

**C. Storyboard.** The edit as a shot list: wide shots and push-ins as equal panels, each camera move drawn over the wide frame in blue pencil. Strength: the clearest overview of the cut. Weakness: equal panels hide how long each shot is, so timing moves to a thin scrub bar, and fine timing edits get harder.

**Recommendation: A**, with B's plates as the export sheet. A keeps the timeline honest about time, makes aiming a direct drag on the big stage, and its signature (tape marks) is also how the owner reads a take at a glance. B's plates earn their place at the one moment all four shapes matter: choosing what to export.

### 10.3 Critique of A (from the rendered mockups, one round)

1. The stage answers "where does this zoom land?" first and is the biggest thing on screen. Pass.
2. Edges: the stage, inspector and timeline share the sheet's 16 pt margins. The inspector has spare room under the toggles; the build can move Export settings there or let it end at its content. Minor.
3. Color sits only on zoom marks, the spike corners and the Record dot. Pass.
4. Numbers agree: 5 zooms and 9 clicks in the hint, the inspector and the lanes; 2.7 s = 10.1 minus 7.4. Pass.
5. Narrow zooms truncate their label in the strip; the mockup moves the target name under the strip and keeps only the depth inside. The build does the same and shows the full label in a tooltip.
6. The tape label on the stage must sit above the scrim (fixed in the mockup).

Checks run: taste-skill `lint.mjs --app` (0 fail; warnings are the selection rings and the recording's drop shadow, which are box-shadows by construction, and "all-in-one", a Snap feature name in a take title), `impeccable detect` (warns on gray text on the pink strips: false positive, the gray labels sit below the strips, not on them).

### 10.4 Tokens (direction A)

| Token | Light | Dark | Use |
|---|---|---|---|
| frame | #EFEEEB | #0E0E0D | Toolbar and sidebar ground |
| sheet | #FFFFFF | #171716 | Work sheet |
| raised | #F5F4F1 | #222120 | Inspector, lanes, segmented control |
| active | #E4E2DE | #2C2B29 | Selected take |
| border | #E6E4E0 | #2A2928 | Sheet edge, dividers |
| control | #CFCCC6 | #45433F | Control borders, ruler ticks |
| ink / muted | #151413 / #5E5B57 | #F4F2EE / #B0ADA7 | Text |
| tape / on tape | #FF4F9A / #1A0710 | #FF5FA4 / #1A0710 | Zoom strips, spike corners, tape labels |
| primary / on primary | #151413 / #FFFFFF | #F4F2EE / #151413 | Export button, selection outlines, playhead |
| record | #D93A2B | #FF6B5C | Record dot and the recording timer |

Contrast (computed): ink on sheet 18.4:1 and 16.0:1; muted on sheet 6.8:1 and 8.0:1, on frame 5.8:1 and 8.6:1, on raised 6.1:1 and 7.2:1; text on tape 6.3:1 and 6.9:1. Tape as a non-text mark: 3.1:1 on the white sheet, 6.3:1 on the dark sheet. On the stage the background is the owner's choice, so spike corners get a 1 pt outline in ink at 60% and the tape label keeps its own fill; both stay readable on any background.

Type: Avenir Next Demi Bold for the take name, panel titles and tape labels; SF for everything else at 13 pt (12 pt for meta, 11 pt minimum for ruler ticks). Tabular figures on every time, size and depth. Sentence case everywhere.

Shapes: sheet 16 pt corners, inspector 12, controls 6, tape strips square (tape has square ends). No shadows at rest; the sheet is separated by one tone step and a 1 pt edge.

### 10.5 Accessibility

- Every text pair 4.5:1 or better in light and dark (table above). Increase Contrast darkens muted text to ink and adds a 1 pt ink edge to tape strips.
- Nothing by color alone: a zoom is a strip with a depth figure and a name; the selected one has an ink outline and handles.
- Full keyboard use of the timeline and stage (6.2, 6.3). No focus rings anywhere (the owner's call, 2026-11-01): keys still reach the focused stage or timeline, but nothing outlines it.
- VoiceOver: each zoom is an element "Zoom 2 of 5, 0:07.4 to 0:10.1, 2.0 times, holds on Run check up", adjustable with the rotor actions Move earlier, Move later, Deeper, Shallower, Remove. The stage in Aim mode exposes the same element.
- Reduce Motion affects the editor UI only (10.6). The exported clip is the owner's content and keeps its zooms.

### 10.6 Motion (checked against `app-updates/docs/motion-gate.md`)

Editor UI motion only; the clip's camera and pointer motion are content (section 5) and are not UI animation.

| Candidate | Frequency | Purpose | Verdict |
|---|---|---|---|
| Selecting a zoom, switching Play and Aim mode on the stage | Tens per session | none | Rejected. Instant. |
| Dragging corners or strips | Tens per session | Direct manipulation | Follows the pointer 1:1, no easing, no spring. |
| Button press feedback | Tens a day | Feedback | Allowed: 120 ms background change, the family token. |
| Zoom strip or caption chip added or removed (Z, C, Delete, undo) | Occasional | Preventing a jarring change | Allowed: 160 ms opacity, from 0.97 scale. Reduce Motion: opacity only. |
| Aim hint leaving after the first re-aim | Once | Preventing a jarring change | Allowed: 160 ms opacity. |
| Record countdown 3, 2, 1 | A few times a month | State indication | Allowed: each number crossfades in 200 ms. Reduce Motion: instant. |
| Export progress | Occasional | State indication; the number is data | Bar width follows real progress; no easing for style. |
| "Saved 2 files" confirmation | Occasional | State indication | Allowed: 160 ms opacity. |
| Cut or speed-up added or removed on the Speed lane (X, drag, Delete, undo) | Occasional | Preventing a jarring change | Allowed: the strip bridge, 160 ms opacity from 0.97 scale. Reduce Motion: opacity only. |
| The speed row replacing the hint line on selection | Tens per session | none | Rejected. Instant. |
| Shape switch on the stage | Tens per session | none ("looks cool") | Rejected. The stage re-renders at once. |
| Hover lift on strips | Hundreds per session | none | Rejected. A cursor change (resize at ends, move in the middle) is the hover cue. |

Verdict: the one high-leverage motion is the strip add and remove bridge; everything else in the editor is instant.

### 10.7 App icon

A spike-tape L corner in pink over a dark stage square, in the family's icon grid (Snap's and Shelf's icon scripts are the reference). Drawn in code like Shelf's `make-icon.swift`.

## 11. Testing

- `ZoomRules`: fixture pointer logs (the Shelf demo, a no-click take, rapid clicks, a click at the very edge, a two-hour log) to exact zoom lists.
- `CameraPath`: golden values at fixed times for each shape, clamping at every edge, blending between overlapping zooms, follow mode with the dead zone.
- Compositor: `dollyctl render` stills compared to committed PNGs with a small per-pixel tolerance.
- Recording: a fake `RecordingSource` writes real frames and a synthetic pointer log; a probe checks frame count, fps, duration and that pointer and frame times line up within one frame.
- Export: real H.264 files from fixture takes, probed for size, fps, faststart and duration.
- Shots: every surface in light and dark at 2x from fixtures, no window shown.

## 12. Milestones

1. **M1, record and auto zoom (the replacement).** Builds on the safe baselines: clicks by polling (plan B) and the arrow pointer only. S1 and S2 are a five-minute checklist the owner runs at the Mac with a debug build (an agent cannot click or grant permissions on the real Mac); plan A and pointer shapes switch on only if they pass **(my call)**. Record a window, area or display with the pointer log; zoom rules; camera; editor with stage, timeline and inspector; one shape (16:9); export H.264; Copy and Show in Finder. Shelf action and status file.
2. **M2, every shape.** 1:1, 4:5, 9:16 with "In tall shapes"; the plates export sheet; several shapes in one export.
3. **M3, polish.** Picture backgrounds, Hide when still, system audio (built 2026-11-07) and microphone, the app icon, motion gate pass on screenshots, release.

Scope of the first plan **(my call)**: M1 inside the `dolly` repo. The cross-repo pieces (CONTRACT.md, Shelf's sixth tile, the appcast, the private GitHub repo, the first notarized release) are small separate tasks after M1, and the GitHub repo and release wait for the owner.

M1 is done when the gates pass and the owner has watched one real exported demo of a family app and said the zooms feel right. Tests and stills cannot judge "seasick"; the owner's eyes can. Until then the zoom numbers stay settings.

## 13. Spikes and risks

| Item | Risk | Plan |
|---|---|---|
| S1 click monitor without Accessibility | Global mouse monitor may prompt or get nothing on macOS 27 | Polling `pressedMouseButtons` at 120 Hz needs no permission |
| S2 pointer shape of other apps | `NSCursor.currentSystem` may be gone or return only Dolly's cursor | Draw the arrow always, offer "Record the real pointer" |
| Preview at 60 fps with the compositor on 5K takes | Dropped frames while scrubbing | Preview from a half-size proxy made after recording; export at full size |
| Zoom feel | Lurching or seasick moves (anti-goal) | Tune `ZoomRules` and the curve on real demos of the family's apps before M1 ships; keep the numbers as settings |
| Platform limits change | Presets go stale | One `PlatformLimits` table, warnings never block |

## 14. Open questions only the owner can answer

None block M1. Answers would change later milestones:

1. Do your demos need voice-over (microphone), or are they always silent?
2. ~~Do you ever need to cut out the middle of a take?~~ Built on 2026-11-07 as cuts and speed-ups (6.3.1), on the owner's go-ahead to "do all" from the next-steps list.
3. Should Dolly also export a GIF for places that do not autoplay video?

## 15. Decisions to review (my calls)

1. The name "Dolly".
2. Direction A, Spike marks, with B's plates as the export sheet; pink (#FF4F9A) as the main color.
3. 60 fps recording, HEVC master, H.264 exports at about 12 Mbit/s.
4. Zoom rules in 5.1 (3.0 s grouping, 0.6 s in, 1.5 s hold, 0.5 s out, 2.0x default).
5. Hotkey `⌃⌥⌘R`.
6. No gradient backgrounds in v1 (flat colors and a picture), to keep the clip in the family's flat style.
7. Trim the ends only, no cuts in v1. Reversed 2026-11-07: cuts and speed-ups (6.3.1).
8. Takes and exports in `~/Movies/Dolly`.
9. Clicks without any extra permission, even if that means polling.
10. Zoom names read from the pixels with on-device Vision text recognition, never from Accessibility (4.6).
11. Variable frame rate master, pointer sampled on its own 120 Hz timer, fixed output size for moving windows (4.4).
12. Left mouse-down only makes zooms; drags follow the pointer; Dolly's own start and stop clicks are dropped (4.5).
13. M1 ships on the permission-free baselines; the owner runs S1 and S2 and approves one real exported demo before M1 counts as done (12).
