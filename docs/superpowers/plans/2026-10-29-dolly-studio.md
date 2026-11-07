# Dolly Studio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Dolly's editor into the studio: every shape, the backdrop library, a recorded webcam and microphone, captions from the owner's voice, the four-tab inspector, two new timeline lanes and the plates export sheet.

**Architecture:** Same four-layer split as M1. New rules live in `DollyCore` as pure, tested values (backdrops, shapes, camera track and bubble layout, captions and their splitter, SRT). `DollyRender` draws them in the one `FrameComposer` used by preview and export, and transcribes audio. `DollySystem` alone opens the camera and microphone. `DollyUI` draws the studio from `docs/mockup/studio/`.

**Tech Stack:** Swift 6.4 tools, Swift 6 mode, macOS 27, SwiftUI in AppKit, ScreenCaptureKit, AVFoundation (`AVCaptureSession`, `AVAssetWriter`, `AVAssetReader`, `AVVideoCompositing`), Core Image, Core Text, Speech (`SpeechAnalyzer`, `SpeechTranscriber`, `AssetInventory`), Swift Testing, swiftlint.

**Spec:** `docs/superpowers/specs/2026-10-29-dolly-studio.md` (approved 2026-10-29), on top of `docs/superpowers/specs/2026-10-26-dolly-design.md`. Visual target: `docs/mockup/studio/{look,zoom,camera,captions}-{light,dark}.png` and `studio.html`.

## Global Constraints

- Everything in the M1 plan's Global Constraints still holds (`docs/superpowers/plans/2026-10-26-dolly-m1.md`): `DOLLY_HOME` and `DOLLY_NO_UPDATES=1` for every test, shot and `dollyctl` run; own `--scratch-path`; no Accessibility or Input Monitoring APIs; no network code; no em or en dashes; American spelling; tabular figures on every time, size and depth.
- Tests, tools and shots never open the camera or microphone, never call `SpeechAnalyzer` on real audio, never show a window or take focus. Live camera, microphone and speech code is exercised only through fakes.
- `AVCaptureDevice`, `AVCaptureSession` and camera or microphone permission calls live only in `Sources/DollySystem` (extend swiftlint `screen_capture_only_in_system` with `\bAVCaptureSession\b`). `import Speech` lives only in `Sources/DollyRender/Transcriber.swift`.
- Info.plist gains `NSCameraUsageDescription` "Dolly records your camera only when the Camera switch is on." and `NSMicrophoneUsageDescription` "Dolly records your microphone only when the Microphone switch is on." Add `NSSpeechRecognitionUsageDescription` "Dolly turns your voice into captions on this Mac." only if spike S3 shows it is needed. Entitlements gain `com.apple.security.device.camera` and `com.apple.security.device.audio-input`.
- Take files stay `version` 1. Every new field decodes when missing (old takes open unchanged).
- File names in a take folder: `camera.mov`, `audio.m4a`, `backdrop.<ext>`.
- Every color, size and motion value in UI code comes from `Theme`. Backdrop gradient colors live in `DollyCore/Model/Backdrop.swift`, because they are clip content.
- UI tasks (7 to 10): invoke `impeccable`, `design-taste-frontend`, `unslop` and `find-animation-opportunities` on that task's shots, and keep only motion that passes `../app-updates/docs/motion-gate.md` and the studio spec's motion table. The studio adds no UI motion. The reviewer checks the transcript for the four Skill calls.
- The implementer leaves changes in the working tree; the main session commits each task with the message in its last step, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Old takes.** A take saved by M1 (`"shadow": true`, no `shape`, `camera` or `captions` keys) opens, shows a 60 % shadow, the 16:9 stage and empty Camera and Captions lanes. Test in Task 1 (`m1TakeDecodes`).
2. **A missing or moved picture backdrop.** `backdrop.jpg` deleted from the take folder: the take opens and renders with the default flat color, and the Look tab shows no picture selected. Test in Task 1 (`missingPictureFallsBackToDefault`) and Task 4 (`missingPictureRendersDefaultColor`).
3. **Camera or microphone that fails mid-take.** The device is unplugged or denied while recording: the screen take still saves; the camera or audio file is kept up to its last good sample or dropped, and the take records a note ("The camera stopped at 0:21.4"). Test in Task 5 (`sideSourceFailureKeepsScreenTake`).
4. **Captions that do not fit.** A 140-character phrase, a phrase with no pause, and a single 50-character word all split into captions of at most two lines of at most 42 characters, never an empty caption and never overlapping times. Test in Task 3 (`longPhrasesSplitWithinLimits`).
5. **Camera, caption and zoom together in tall shapes.** In 9:16 with the camera at the bottom left and a bottom caption, the caption sits above the bubble and both stay inside the canvas at every zoom depth. Test in Task 2 (`bottomCaptionClearsBottomCamera`).

---

## File structure

```
Sources/DollyCore/
  Model/      Look.swift (changed)  Backdrop.swift  Take.swift (changed)  TakeStore.swift (changed)
  Export/     ShapePreset.swift (changed)  ExportPlan.swift (changed)  SRT.swift
  Zoom/       ShapeLayout.swift (changed)
  Studio/     CameraTrack.swift  OverlayLayout.swift  Captions.swift  CaptionSplitter.swift
  Edit/       EditorModel.swift (changed)
  Recording/  SideSource.swift  RecordingPlan.swift (changed)  RecordingController.swift (changed)
  Fakes/      FakeSideSource.swift  FakeTranscriber.swift  SyntheticTake.swift (changed)
Sources/DollyRender/  FrameComposer.swift (changed)  CaptionArt.swift  DollyCompositor.swift (changed)
                      PlayerItemFactory.swift (changed)  Exporter.swift (changed)  Transcriber.swift
Sources/DollySystem/  LiveCameraSource.swift  LiveMicrophoneSource.swift  CaptureDevices.swift  PermissionProbe.swift (changed)
Sources/DollyUI/
  Inspector/  StudioInspector.swift  LookTab.swift  CameraTab.swift  CaptionsTab.swift  InspectorView.swift (becomes ZoomsTab)
  Stage/      StageView.swift (changed)  ShapeBar.swift  CameraDragOverlay.swift
  Timeline/   TimelineLayout.swift (changed)  TimelineView.swift (changed)  TimelineInput.swift (changed)
  Record/     RecordBar.swift (changed)  RecordBarModel.swift (changed)  CameraPreviewPanel.swift
  Export/     ExportSheet.swift (changed)
Sources/Dolly/        AppWiring.swift  RecordingWiring.swift  ShotMode.swift  ShotScenarios.swift (changed)
docs/spikes/s3-s5-checklist.md
```

---

### Task 1: Look, backdrops, shapes and the take's new fields

**Files:**
- Create: `Sources/DollyCore/Model/Backdrop.swift`
- Modify: `Sources/DollyCore/Model/Look.swift`, `Sources/DollyCore/Model/Take.swift`, `Sources/DollyCore/Model/TakeStore.swift`, `Sources/DollyCore/Export/ShapePreset.swift`, `Sources/DollyCore/Zoom/ShapeLayout.swift`, every caller of `ShapePreset.pixelSize`
- Test: `Tests/DollyCoreTests/LookTests.swift`, `Tests/DollyCoreTests/ShapeLayoutTests.swift`, `Tests/DollyCoreTests/TakeStoreTests.swift`

**Interfaces:**
- Produces:
  - `Look.Background`: `.color(hex: String)`, `.gradient(id: String)`, `.picture(file: String, blur: Double)`. `Look.shadow: Double` (0...1). `Look.flatColors: [String]` = the five M1 colors plus `"#151413"`.
  - `Backdrop.Gradient { id, top: String, bottom: String, light: String, lightAt: CGPoint, angle: Double }`; `Backdrop.gradients: [Backdrop.Gradient]` in order harbor, ember, slate, moss, rose, sand, with the hex values from `docs/mockup/studio/studio.html` (`--bd-*`).
  - `ShapePreset` gains `case original` (first in `allCases`); `func pixelSize(recording: CGSize) -> PixelSize`; `label` "Original"; `fileSuffix` "original".
  - `Take.shape: ShapePreset?` (nil reads as `.wide16x9` through `Take.currentShape`). `Take.camera` and `Take.captions` are added by Tasks 2 and 3.
  - `TakeStore.importBackdrop(_ source: URL, into folder: URL) throws -> String` returns the file name it wrote (`backdrop.<ext>`), replacing an older one.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func m1TakeDecodes() throws {
    let json = #"{"version":1,"id":"6B1F2C1E-8C2B-4D0B-9A40-1D2C3B4A5F60","name":"Old","created":0,"target":"window","size":[[0,0],[848,858]],"pixelScale":2,"fps":60,"duration":10,"trim":[0,10],"look":{"background":{"color":{"hex":"#3E4A4F"}},"padding":64,"corners":12,"shadow":true,"pointerScale":1.5,"smoothPointer":true,"clickRing":true,"hideWhenStill":false},"zooms":[],"exports":[],"recordingStartHost":0,"notes":[]}"#
    let take = try JSONDecoder().decode(Take.self, from: Data(json.utf8))
    #expect(take.look.shadow == 0.6)
    #expect(take.currentShape == .wide16x9)
}
@Test func shadowFalseReadsAsZero()  // same JSON with "shadow":false -> 0
@Test func originalIsLongSide1920AndEven() {
    #expect(ShapePreset.original.pixelSize(recording: CGSize(width: 848, height: 858)) == PixelSize(width: 1898, height: 1920))
    #expect(ShapePreset.original.pixelSize(recording: CGSize(width: 1512, height: 982)) == PixelSize(width: 1920, height: 1248))
    #expect(ShapePreset.tall9x16.pixelSize(recording: .zero) == PixelSize(width: 1080, height: 1920))
}
@Test func sixGradientsInMockupOrder() { #expect(Backdrop.gradients.map(\.id) == ["harbor", "ember", "slate", "moss", "rose", "sand"]) }
@Test func importBackdropReplacesOld()  // import a.png then b.jpg: folder holds backdrop.jpg only, returns "backdrop.jpg"
@Test func missingPictureFallsBackToDefault() {
    // Look.resolved(in: folder) returns .color(Look.flatColors[0]) when the picture file is gone.
}
```

- [ ] **Step 2: Run** `swift test --scratch-path "$TMPDIR/dolly-t1" --filter "LookTests|ShapeLayoutTests|TakeStoreTests"`. Expected: FAIL (no `original`, no `currentShape`).

- [ ] **Step 3: Implement.** `Look` gets a hand-written `init(from:)` that reads `shadow` as `Bool` or `Double` (`true` 0.6, `false` 0) and `decodeIfPresent` for every key. `Look.resolved(in folder: URL) -> Look` swaps a missing picture for `.color(Look.flatColors[0])`. `ShapeLayout.init` takes the canvas from `shape.pixelSize(recording: recordingSize)`. Original: scale so the long side is 1920 px, round each side down to even.

- [ ] **Step 4: Run** the same filter, then the whole `swift test`. Expected: PASS, M1 tests unchanged.

- [ ] **Step 5: Commit** `Studio: backdrops, shadow amount, Original shape, take fields`

---

### Task 2: Camera track and the overlay layout

**Files:**
- Create: `Sources/DollyCore/Studio/CameraTrack.swift`, `Sources/DollyCore/Studio/OverlayLayout.swift`
- Test: `Tests/DollyCoreTests/OverlayLayoutTests.swift`

**Interfaces:**
- Produces:
  - `CameraTrack: Codable, Hashable, Sendable { file: String = "camera.mov"; startOffset: Double /* camera time 0 is this many seconds into the take */; hidden: [ClosedRange<Double>]; shape: Shape (.circle, .rounded); size: Double = 0.22 /* of the short side, 0.10...0.40 */; corner: Corner (.topLeft, .topRight, .bottomLeft, .bottomRight) = .bottomLeft; point: CGPoint? /* unit coordinates of the bubble center in the canvas, set by dragging; wins over corner */; border = true; shrinkDuringZooms = true; mirror = true }`
  - `CameraTrack.isVisible(at t: Double) -> Bool`; `Take.camera: CameraTrack?` (decodes as nil when missing).
  - `enum CaptionPosition: String, Codable, Sendable { case bottom, middle, top }` lives in `OverlayLayout.swift`; Task 3's `CaptionTrack` uses it.
  - `OverlayLayout(canvas: CGSize, recordingRect: CGRect, camera: CameraTrack?, captionPosition: CaptionPosition, captionHeight: Double)` with `func bubble(at depthProgress: Double) -> CGRect?` and `func captionRect(width: Double) -> CGRect`. `depthProgress` is 0 at 1x and 1 at the zoom's full depth.
  - Constants: margin `0.6 * padding` (spec mockup), border 3 pt at 1080, shrink to 60 %, caption gap 10 pt at 1080.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func bubbleSitsInItsCornerAtTheShortSideFraction() {
    let o = OverlayLayout(canvas: CGSize(width: 1920, height: 1080), recordingRect: CGRect(x: 420, y: 64, width: 1080, height: 952),
                          camera: CameraTrack(startOffset: 0), captionPosition: .bottom, captionHeight: 60)
    let b = try #require(o.bubble(at: 0))
    #expect(b.width == 1080 * 0.22 && b.height == b.width)
    #expect(b.minX == 38.4 && b.maxY == 1080 - 38.4)   // margin 0.6 * 64 at 1080
}
@Test func shrinkDuringZoomsReaches60Percent()       // bubble(at: 1).width == 0.6 * bubble(at: 0).width, same corner anchor
@Test func draggedPointWinsOverCorner()              // point (0.5, 0.5) centers the bubble
@Test func hiddenRangesHide() { /* hidden [3...5]: isVisible(4) false, isVisible(5.01) true */ }
@Test func m1TakeHasNoCamera()                     // the M1 JSON from Task 1 decodes with take.camera == nil
@Test func bottomCaptionClearsBottomCamera() {
    // 9:16 canvas 1080x1920, camera bottomLeft, caption bottom: captionRect.maxY <= bubble.minY - 10 * k, and inside the canvas.
    // Camera topLeft: caption sits at the bottom margin instead.
}
```

- [ ] **Step 2: Run** `--filter OverlayLayoutTests`. Expected: FAIL.
- [ ] **Step 3: Implement** in the two files; the caption's center x is the canvas center; when the camera is at the top or hidden, the bottom caption's `maxY` is `canvas.height - margin`.
- [ ] **Step 4: Run** the filter. Expected: PASS.
- [ ] **Step 5: Commit** `Studio: camera track and overlay layout`

---

### Task 3: Captions, the splitter, SRT and the transcriber

**Files:**
- Create: `Sources/DollyCore/Studio/Captions.swift`, `Sources/DollyCore/Studio/CaptionSplitter.swift`, `Sources/DollyCore/Export/SRT.swift`, `Sources/DollyCore/Fakes/FakeTranscriber.swift`, `Sources/DollyRender/Transcriber.swift`
- Test: `Tests/DollyCoreTests/CaptionTests.swift`

**Interfaces:**
- Produces:
  - `CaptionTrack: Codable, Hashable, Sendable { enum Source { voice, typed }; source; locale: String; position: CaptionPosition = .bottom; size: Double = 15 /* pt at 1080, 10...24 */; saveSRT = false; items: [Caption] }`, `Caption: Codable, Hashable, Identifiable, Sendable { id: UUID; start: Double; end: Double; text: String }`, `CaptionTrack.caption(at t: Double) -> Caption?`; `Take.captions: CaptionTrack?` (nil when missing).
  - `Phrase { text: String; start: Double; end: Double; words: [(text: String, start: Double, end: Double)] }`.
  - `CaptionSplitter.captions(from phrases: [Phrase], maxLine: Int = 42, maxLines: Int = 2, pause: Double = 0.4) -> [Caption]`.
  - `SRT.text(_ items: [Caption], trimStart: Double) -> String` (times relative to the trim start, `00:00:11,400 --> 00:00:14,600`, numbered from 1, blank line between).
  - `protocol Transcribing: Sendable { func transcribe(audio: URL, locale: Locale) async throws -> [Phrase] }`; `Transcriber` (SpeechAnalyzer and SpeechTranscriber with the `.transcription` preset, installs assets through `AssetInventory` when missing, maps result time ranges to `Phrase`); `FakeTranscriber(phrases:)`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func splitsAtSentenceEndsAndPauses()     // "This is Shelf. Haul shows downloads." with a 0.6 s pause -> 2 captions with the word times
@Test func longPhrasesSplitWithinLimits()      // 140 chars, no pause, and one 50-char word: every caption <= 2 lines of <= 42 chars (a long word gets a line of its own), none empty, starts strictly increase, no overlap
@Test func srtFormatsRelativeToTrim()          // trimStart 2.0, caption 13.4...16.6 -> "1\n00:00:11,400 --> 00:00:14,600\nEach tile has its own quick actions.\n"
@Test func captionAtTime()                     // caption(at: 12.4) returns caption 4 of the shelf demo set from the mockup
@Test func m1TakeHasNoCaptions()               // the M1 JSON from Task 1 decodes with take.captions == nil
```

- [ ] **Step 2: Run** `--filter CaptionTests`. Expected: FAIL.
- [ ] **Step 3: Implement** the three DollyCore files and the fake; `Transcriber` compiles against Speech and is exercised only by the owner's S3 check.
- [ ] **Step 4: Run** the filter. Expected: PASS.
- [ ] **Step 5: Commit** `Studio: captions, splitter, SRT, transcriber`

---

### Task 4: Composer draws backdrops, shadow amount, the camera and captions

**Files:**
- Create: `Sources/DollyRender/CaptionArt.swift`
- Modify: `Sources/DollyRender/FrameComposer.swift`, `Sources/DollyRender/DollyCompositor.swift`, `Sources/DollyRender/PlayerItemFactory.swift`, `Sources/DollyRender/Exporter.swift`, `Sources/DollyCore/Fakes/SyntheticTake.swift`
- Test: `Tests/DollyRenderTests/FrameComposerTests.swift`, `Tests/DollyRenderTests/ExporterTests.swift`

**Interfaces:**
- Consumes: Task 1 `Look`, `Backdrop`, `ShapePreset.pixelSize(recording:)`; Task 2 `CameraTrack`, `OverlayLayout`; Task 3 `CaptionTrack`.
- Produces:
  - `FrameComposer.init(layout:look:recordingPixelScale:backdropImage: CIImage?)`; `compose(recording:camera:pointer:ring:cameraFrame: CIImage?, cameraState: (track: CameraTrack, depthProgress: Double)?, caption: String?) -> CIImage`.
  - `CaptionArt.image(text: String, sizePoints: Double, k: Double, maxWidth: Double) -> CIImage?`: Avenir Next Demi Bold, white, on `#0C0C0C` at 74 %, corner 8 pt, padding 6 by 14 pt, at most two centered lines; cached by `(text, size, maxWidth)`.
  - `PlayerItemFactory.composition(take:folder:shape:fps:pointer:)` adds the camera track (inserted at `camera.startOffset - trim.lowerBound`) and the `audio.m4a` track when present.
  - `Exporter` writes AAC 48 kHz stereo 160 kbit/s when the composition has audio.
  - `SyntheticTake.writeCamera(to: URL, seconds: Double, color: (UInt8, UInt8, UInt8))` and `writeTone(to: URL, seconds: Double)` for fixtures.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func gradientBackdropIsLighterAtItsLight()   // rose: pixel near the light point brighter than the opposite corner
@Test func pictureBackdropFillsAndBlurs()          // a 2-color test picture: blur 40 makes the seam pixel a mix, blur 0 keeps it sharp
@Test func shadowZeroDrawsNoShadow()               // pixel just below the recording equals the backdrop color
@Test func missingPictureRendersDefaultColor()
@Test func cameraBubbleShowsCameraPixels()         // red camera frame: bubble center is red, mirror flips a left-half marker to the right
@Test func captionDrawsInsideItsRect()             // non-backdrop pixels only inside OverlayLayout.captionRect
@Test func exportWithCameraAndAudioHasBothTracks() // fixture take with camera.mov and audio.m4a: probe shows 1 video, 1 audio track, duration within one frame
```

- [ ] **Step 2: Run** `--filter "FrameComposerTests|ExporterTests"`. Expected: FAIL.
- [ ] **Step 3: Implement.** Draw order: backdrop, shadow (alpha `0.28 * look.shadow / 0.6`, so 60 % matches M1), rounded recording, camera transform, then the click ring and pointer (as today), then the camera bubble and the caption in canvas space after the camera transform, so neither zooms. The picture backdrop is aspect-filled, then `applyingGaussianBlur(sigma: blur * k / 2)` and clamped to extent before cropping. The compositor fetches the camera track's frame only while `isVisible(at:)` is true.
- [ ] **Step 4: Run** the filter, then `swift test`. Expected: PASS.
- [ ] **Step 5: Commit** `Studio: composer draws backdrops, camera and captions; export carries audio`

---

### Task 5: Camera and microphone recording

**Files:**
- Create: `Sources/DollyCore/Recording/SideSource.swift`, `Sources/DollyCore/Fakes/FakeSideSource.swift`, `Sources/DollySystem/LiveCameraSource.swift`, `Sources/DollySystem/LiveMicrophoneSource.swift`, `Sources/DollySystem/CaptureDevices.swift`
- Modify: `Sources/DollyCore/Recording/RecordingPlan.swift`, `Sources/DollyCore/Recording/RecordingController.swift`, `Sources/DollySystem/PermissionProbe.swift`, `resources/Info.plist.in`, `resources/Dolly.entitlements`, `.swiftlint.yml`
- Test: `Tests/DollyCoreTests/RecordingControllerTests.swift`

**Interfaces:**
- Produces:
  - `protocol SideSource: AnyObject, Sendable { func start(url: URL, failed: @escaping @Sendable (String) -> Void) async throws -> Double /* host time of the first sample */; func stop() async throws }`
  - `RecordingPlan.cameraID: String?`, `RecordingPlan.microphoneID: String?`.
  - `RecordingController.init(..., camera: (any SideSource)? = nil, microphone: (any SideSource)? = nil)`; on stop, `Take.camera = CameraTrack(startOffset: firstCameraHost - recordingStartHost)` when a camera ran, and `audio.m4a` stays in the folder.
  - `CaptureDevices.cameras() -> [(id: String, name: String)]`, `.microphones()`; `PermissionProbe.camera() -> Status`, `.microphone() -> Status`, `requestCamera() async -> Bool`, `requestMicrophone() async -> Bool` (`Status`: `.allowed`, `.denied`, `.notAsked`).
  - Live camera: `AVCaptureSession` with `AVCaptureVideoDataOutput` into an `AVAssetWriter` (H.264, 1280 by 720 or the closest format, 30 fps), session started at the first sample's host time. Live microphone: `AVCaptureAudioDataOutput` into AAC 48 kHz mono `audio.m4a`, same clock.

- [ ] **Step 1: Write the failing tests** (fakes only)

```swift
@Test func cameraOffsetComesFromFirstSample()       // fake camera reports first host 100.25, screen starts 100.0 -> take.camera.startOffset == 0.25
@Test func noSwitchesNoSideFiles()                  // plan without IDs: no camera.mov, no audio.m4a, take.camera == nil
@Test func sideSourceFailureKeepsScreenTake()       // fake camera calls failed("unplugged") at 21.4 s: take saves, notes contain "The camera stopped at 0:21.4"
@Test func sideSourceThatCannotStartIsDropped()     // start throws: recording continues, note "The camera did not start", take.camera == nil
```

- [ ] **Step 2: Run** `--filter RecordingControllerTests`. Expected: FAIL.
- [ ] **Step 3: Implement** the protocol, fakes and controller changes; then the live sources (compiled, never run in tests).
- [ ] **Step 4: Run** the filter and `swiftlint lint --strict`. Expected: PASS, no `AVCaptureSession` outside DollySystem.
- [ ] **Step 5: Commit** `Studio: record the camera and microphone beside the screen`

---

### Task 6: Editor model for shapes, the camera and captions

**Files:**
- Modify: `Sources/DollyCore/Edit/EditorModel.swift`
- Test: `Tests/DollyCoreTests/EditorModelTests.swift`

**Interfaces:**
- Consumes: Tasks 1, 2, 3.
- Produces (each is one undo step; drags use `beginGesture()` like zooms):
  - `setShape(_ s: ShapePreset)`; `setBackdrop(_ b: Look.Background)`.
  - `setCamera(_ change: (inout CameraTrack) -> Void)`; `hideCamera(from: Double, to: Double)` (merges overlapping ranges); `showCamera(range index: Int)`; `resizeCameraGap(index: Int, edge: Edge, to t: Double)`.
  - `enum Selection { case zoom(Zoom.ID), caption(Caption.ID), camera }` replaces `selection: Zoom.ID?` (keep `selectedZoom: Zoom.ID?` as a computed property for existing callers).
  - `setCaptions(_ track: CaptionTrack)` (after transcribing), `addCaption(at t: Double)` (typed, 2 s, empty text, selected), `editCaption(_ id: Caption.ID, text: String)`, `splitCaption(_ id: Caption.ID, at characterIndex: Int)` (time split in proportion to characters), `joinCaption(_ id: Caption.ID)` (with the one before), `moveCaption(_ id: Caption.ID, by dt: Double)`, `resizeCaption(_ id: Caption.ID, edge: Edge, to t: Double)` (minimum 0.4 s, never past a neighbor).

- [ ] **Step 1: Write the failing tests**

```swift
@Test func splitCaptionByCharacters()     // "Each tile has its own quick actions." 11.4...14.6 split at 14 -> "Each tile has" and "its own quick actions." with the cut at 11.4 + 3.2 * 14/36, undo restores one caption
@Test func joinKeepsTimes()
@Test func captionsNeverOverlap()          // moving or resizing into a neighbor stops at its edge
@Test func hiddenCameraRangesMerge()       // hide 3...5 then 4...8 -> [3...8]
@Test func shapeChangeKeepsZooms()         // zooms identical before and after setShape(.tall9x16)
```

- [ ] **Step 2: Run** `--filter EditorModelTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter and the whole suite. Expected: PASS.
- [ ] **Step 5: Commit** `Studio: editor edits for shapes, camera and captions`

---

### Task 7: Shape bar, stage and the four-tab inspector

**Files:**
- Create: `Sources/DollyUI/Stage/ShapeBar.swift`, `Sources/DollyUI/Stage/CameraDragOverlay.swift`, `Sources/DollyUI/Inspector/StudioInspector.swift`, `LookTab.swift`, `CameraTab.swift`, `CaptionsTab.swift`
- Modify: `Sources/DollyUI/Stage/StageView.swift`, `Sources/DollyUI/Inspector/InspectorView.swift` (becomes the Zooms tab), `Sources/DollyUI/Shared/Theme.swift`, `Sources/Dolly/ShotMode.swift`, `Sources/Dolly/ShotScenarios.swift`, `scripts/shots.sh`
- Test: `Tests/DollyUITests/StudioInspectorTests.swift`

**Interfaces:**
- Consumes: Task 6 `EditorModel` API.
- Produces:
  - `StudioTab: CaseIterable { look, zooms, camera, captions }` with labels "Look", "Zooms", "Camera", "Captions"; `StudioInspectorModel.tab(for selection: EditorModel.Selection?, previous: StudioTab) -> StudioTab`.
  - Shape bar note: `"Exports \(w) × \(h) for X and Threads"`.
  - Stage area 868 × 448 at the 1440 × 900 window (spec item 6); the output frame centered on `Theme.raised`.
  - Shot scenarios `studio-look`, `studio-zoom`, `studio-camera`, `studio-captions`, matching the mockup states (4:5 Rose at 0:24.6; 16:9 Harbor aiming zoom 2; 16:9 Slate at 0:12.4; 9:16 Moss at 0:12.4 with caption 4 selected). The camera bubble in shots uses a solid frame from `SyntheticTake.writeCamera`, not the mockup's stand-in face.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func selectingSwitchesTabAndEscReturns()  // .zoom -> .zooms; .caption -> .captions; .camera -> .camera; nil -> previous
@Test func shapeNoteNamesTheSize()              // .portrait4x5 -> "Exports 1080 × 1350 for X and Threads"; .original for 848x858 -> "Exports 1898 × 1920 for X and Threads"
@Test func blurRowOnlyForPictures()             // LookTab.showsBlur(.picture) true, .gradient false, .color false
```

- [ ] **Step 2: Run** `--filter StudioInspectorTests`. Expected: FAIL.
- [ ] **Step 3: Implement** the views from `docs/mockup/studio/studio.html`: tabs segmented control; Look (backdrop grid 6 + 6, Desktop and Choose…, Blur for pictures, Padding 0 to 160 pt, Corners 0 to 24 pt, Shadow 0 to 100 %, Pointer: Size, Ring on each click, Smooth path, Hide when still, "Use for new takes"); Camera (Show camera, Circle or Rounded, Size 10 to 40 %, Corner picker, Border, Shrink during zooms, Mirror, "Drag the camera on the stage to move it"); Captions (From your voice or Typed, "English, transcribed on this Mac.", the selected caption's field and times, Bottom, Middle, Top, Size 10 to 24 pt, "Save an .srt file with each export", "Transcribe again", "Return splits a caption"). In the caption field Return calls `splitCaption` at the cursor and Delete at position 0 calls `joinCaption`. Dragging the bubble on the stage sets `CameraTrack.point`.
- [ ] **Step 4: Run** the filter, `scripts/bundle.sh --release`, then `scripts/shots.sh studio-look studio-zoom studio-camera studio-captions` and compare with the mockup PNGs. Run the four UI skills on the shots.
- [ ] **Step 5: Commit** `Studio: shape bar, stage and the four-tab inspector`

---

### Task 8: Camera and Captions lanes on the timeline

**Files:**
- Modify: `Sources/DollyUI/Timeline/TimelineLayout.swift`, `TimelineView.swift`, `TimelineInput.swift`
- Test: `Tests/DollyUITests/TimelineLayoutTests.swift`

**Interfaces:**
- Produces: `TimelineHit` gains `.cameraBar(Double)`, `.cameraGap(Int, StripPart)`, `.caption(Caption.ID, StripPart)`, `.emptyCaptionLane(Double)`; `TimelineAction.addCaption` on `c` (no modifiers). Lane heights: Video 44, Zoom 46, Camera 26, Captions 30, Clicks 18.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func hitsCaptionChipEdgesAndBody()  // 6 pt edge zones like zoom strips
@Test func dragOnCameraBarHidesARange()   // hit .cameraBar(t) at 33.0, drag to 36.5 -> editor.hideCamera(from: 33, to: 36.5)
@Test func cKeyAddsCaption()              // TimelineInput.action(key: "c", shift: false, command: false) == .addCaption
@Test func captionChipLabel()             // VoiceOver: "Caption 4 of 10, 0:11.4 to 0:14.6, Each tile has its own quick actions."
```

- [ ] **Step 2: Run** `--filter TimelineLayoutTests`. Expected: FAIL.
- [ ] **Step 3: Implement**; the playhead spans all five lanes; the hint line stays.
- [ ] **Step 4: Run** the filter; re-render the four studio shots; run the four UI skills.
- [ ] **Step 5: Commit** `Studio: camera and captions lanes`

---

### Task 9: Record bar switches, camera preview and permissions

**Files:**
- Create: `Sources/DollyUI/Record/CameraPreviewPanel.swift`
- Modify: `Sources/DollyUI/Record/RecordBar.swift`, `RecordBarModel.swift`, `Sources/Dolly/RecordingWiring.swift`, `Sources/DollyCore/Model/Settings.swift`
- Test: `Tests/DollyUITests/RecordBarModelTests.swift`

**Interfaces:**
- Produces:
  - `RecordBarModel.camera: Bool = false`, `.microphone: Bool = false`, `.cameraID: String?`, `.microphoneID: String?`; `Settings.recordCamera`, `.recordMicrophone`, `.cameraID`, `.microphoneID` remembered across launches.
  - `RecordBarModel.permissionStep(camera: PermissionProbe.Status, microphone: PermissionProbe.Status) -> PermissionStep?` (`.askCamera`, `.askMicrophone`, `.cameraDenied`, `.microphoneDenied`), using Snap's first-run pattern copy: "Dolly needs Camera to record your camera. It never opens the camera unless the Camera switch is on." and the Microphone equivalent.
  - `CameraPreviewPanel`: a mirrored 200 pt wide preview below the bar while the switch is on and the bar is open; closed before the countdown.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func switchesStartOff()
@Test func turningCameraOnAsksOnce()        // notAsked -> .askCamera; allowed -> nil; denied -> .cameraDenied
@Test func planCarriesDeviceIDs()           // camera on with ID "cam-1" -> RecordingPlan.cameraID == "cam-1"; switch off -> nil
```

- [ ] **Step 2: Run** `--filter RecordBarModelTests`. Expected: FAIL.
- [ ] **Step 3: Implement**; add a `record-bar-camera` shot (switch on, preview drawn from a solid frame); run the four UI skills.
- [ ] **Step 4: Run** the filter and shots.
- [ ] **Step 5: Commit** `Studio: camera and microphone switches in the Record bar`

---

### Task 10: Plates export sheet, several shapes and SRT

**Files:**
- Modify: `Sources/DollyUI/Export/ExportSheet.swift`, `Sources/DollyCore/Export/ExportPlan.swift`, `Sources/Dolly/AppWiring.swift`
- Test: `Tests/DollyUITests/ExportSheetModelTests.swift`

**Interfaces:**
- Produces: `ExportSheetModel.shapes: Set<ShapePreset>` (starts with the take's current shape), `progress: [ShapePreset: Double]`; `export()` runs the shapes one after another and reports `done([URL])`; with `captions.saveSRT` it writes `<take name> <suffix>.srt` beside each mp4 through `SRT.text`. Plates: five, on one baseline, each the frame at the playhead in that shape, with a checkbox.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func exportsEveryCheckedShapeInOrder()   // fake exporter: 16:9 and 9:16 checked -> two URLs, allCases order
@Test func writesSRTBesideEachClip()           // saveSRT true: "Demo 16x9.srt" next to "Demo 16x9.mp4"
@Test func doneTextCountsFiles()               // "Saved 2 files"; SRT files not counted
@Test func failedShapeStopsAndSays()           // second shape throws -> failed("Couldn't export 9:16: <reason>"), first file kept
```

- [ ] **Step 2: Run** `--filter ExportSheetModelTests`. Expected: FAIL.
- [ ] **Step 3: Implement**; shots `export`, `export-progress`, `export-done` updated; run the four UI skills.
- [ ] **Step 4: Run** the filter and shots.
- [ ] **Step 5: Commit** `Studio: plates export sheet with every shape and SRT`

---

### Task 11: Wiring, transcription flow, spikes and the gate

**Files:**
- Modify: `Sources/Dolly/AppWiring.swift`, `Sources/Dolly/RecordingWiring.swift`, `Sources/dollyctl/main.swift`, `Sources/DollyCore/Tools/DollyctlCommands.swift`, `CLAUDE.md`, `README.md`
- Create: `docs/spikes/s3-s5-checklist.md`
- Test: `Tests/DollyCoreTests/DollyctlTests.swift`

**Interfaces:**
- Produces:
  - After a take with `audio.m4a` and `Settings.captionsFromVoice` (default true when the microphone was on), the editor transcribes in the background with `Transcriber` and calls `editor.setCaptions`; the Captions tab shows "Transcribing…" until then and "Couldn't transcribe: <reason>" on failure, with Transcribe again. Transcribe again on captions the owner edited first asks "Replace your edited captions?" with Replace and Cancel (`CaptionTrack.edited` set by every Task 6 caption edit, cleared by `setCaptions`).
  - Choose… for a picture backdrop: `NSOpenPanel` for images, then `TakeStore.importBackdrop`. Desktop: `NSWorkspace.shared.desktopImageURL(for:)` of the screen the take was recorded on, imported the same way.
  - `dollyctl render <take> --shape original|16x9|1x1|4x5|9x16 --at <s> --out <png>` and `dollyctl captions <take> --srt` (prints SRT from `take.json`).
  - `docs/spikes/s3-s5-checklist.md`: S3 (record 20 s with Microphone on, speak; see whether macOS asks for Speech Recognition; note whether a model download prompt appears; check the caption times against the voice) and S4 (Camera on, clap on camera while clicking; in the editor the clap frame and the click are within one frame at 60 fps).

- [ ] **Step 1: Write the failing tests**

```swift
@Test func renderAcceptsEveryShape()   // DollyctlCommands.parseShape("4x5") == .portrait4x5, "original" == .original, "3x2" throws
@Test func captionsCommandPrintsSRT()  // fixture take with two captions -> exact SRT text
```

- [ ] **Step 2: Run** `--filter DollyctlTests`. Expected: FAIL.
- [ ] **Step 3: Implement** the wiring and commands; write the checklist; add the studio to CLAUDE.md's layout notes.
- [ ] **Step 4: Run** the full gate once: `DOLLY_SCRATCH="$TMPDIR/dolly-check" scripts/check.sh`, then `scripts/shots.sh` for every scenario. Expected: all gates pass; shots match the mockups in layout.
- [ ] **Step 5: Commit** `Studio: wiring, dollyctl shapes and captions, S3 and S4 checklist`

---

## After the plan

Whole-branch review by one fresh reviewer on the most capable model; fix Critical and Important findings red to green. Install with `scripts/bundle.sh --release --install` only when Dolly is not running. The owner runs S3 and S4; if S3 shows the Speech Recognition permission is needed, add `NSSpeechRecognitionUsageDescription` and a first-run step like Camera's.
