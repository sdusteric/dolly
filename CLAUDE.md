# Dolly

A macOS app that replaces FocuSee on this Mac: it records a window, an area or a display with the real pointer hidden, logs the pointer and clicks, turns clicks into zooms, lets the owner edit them in the Spike marks editor and exports mp4 clips for X and Threads. The spec is the source of truth: `docs/superpowers/specs/2026-10-26-dolly-design.md`. Product truth is `PRODUCT.md`. The visual target is `docs/mockup/directions/a-light.png` and `a-dark.png` (direction A). The M1 plan is `docs/superpowers/plans/2026-10-26-dolly-m1.md`. The studio pass (shapes, backdrops, camera, captions, the four-tab inspector) is `docs/superpowers/specs/2026-10-29-dolly-studio.md` with its plan beside the M1 plan and mockups in `docs/mockup/studio/`; where it disagrees with the first spec, it wins.

## Commands

```sh
swift build --scratch-path "$TMPDIR/dolly-<task>"
swift test --scratch-path "$TMPDIR/dolly-<task>" --filter <Suite>
swiftlint lint --strict
DOLLY_SCRATCH="$TMPDIR/dolly-check" scripts/check.sh   # every gate, logs in build/check/
scripts/bundle.sh --release                            # build/bundle/Dolly.app, signed, never launched
scripts/shots.sh [scenario ...]                        # build/shots/<scenario>-<light|dark>.png
scripts/release.sh [--notes <file.md>] [--dry-run <dir>]
swift scripts/make-icon.swift out.png                  # the drawn app icon
```

- Several agents may build at once. Always pass your own `--scratch-path` outside the repo and delete it by its exact path when done. Use `caffeinate -i` for long runs.
- Set `DOLLY_HOME` to a fresh `mktemp -d` dir for every test, shot or `dollyctl` run, and `DOLLY_NO_UPDATES=1`.
- `scripts/release.sh` publishes a real update. Agents run it only with `--dry-run <dir>`, and only when asked.

## Layout

- `DollyCore`: Foundation, CoreGraphics, AVFoundation (writer, probe, fakes). No AppKit, no ScreenCaptureKit. Takes and the take store, pointer and window logs, clicks, zoom rules, camera path, pointer path, editor model with undo, export plan, platform limits, recording controller, Shelf status and URL, fakes. `Studio/`: the webcam track, where the bubble and caption sit (`OverlayLayout`, sizes in points on a 400 pt phone), captions and the splitter. `Model/Backdrop.swift`: the gradient backdrops.
- `DollyRender`: Core Image and AVFoundation. The frame composer and compositor shared by preview and export (backdrops, webcam bubble, captions), the exporter (video and AAC), zoom names (Vision), posters. `Transcriber.swift` is the only file that imports Speech.
- `DollySystem`: the only target that may use ScreenCaptureKit, `AVCaptureDevice`, `AVCaptureSession`, Carbon hotkeys, input polling and the pasteboard. The live camera and microphone recorders and the Record bar's camera preview live here. Nonisolated by default.
- `DollyUI`: SwiftUI in AppKit windows, `@MainActor` by default. Every color, size, radius and motion value comes from `Shared/Theme.swift`.
- `Dolly`: the app, Sparkle (exact 2.10.0), shot mode (`--shot`, renders views with `ImageRenderer`, never touches `NSApp`).
- `dollyctl`: headless CLI on DollyCore and DollyRender. Never links ScreenCaptureKit or Sparkle (check.sh verifies).
- Swift 6 language mode, Swift Testing.

## Safety rules (this is the owner's real Mac)

1. Never show a window, take focus, register a hotkey, capture the screen, open the camera or microphone, run speech recognition on real audio, read or write the real pasteboard, or open a URL from a test, tool or shot. Live system code is exercised only through fakes (`FakeSideSource`, `FakeTranscriber`).
2. Dolly never calls Accessibility or Input Monitoring APIs (swiftlint `no_accessibility_apis`).
3. No network code outside Sparkle (swiftlint `no_network`).
4. Never `rm -rf` with wildcards, relative paths or after `cd`. Delete only exact absolute paths inside `.build`, `build/` or a dir you created with `mktemp`.
5. Track every process you start by PID and stop it by PID.
6. Install nothing, change no system or app settings. Agents never commit, push, publish or install; the main session does.

## Style

- No em dashes or en dashes anywhere. American spelling and plain words in user-visible copy.
- Comments only for the non-obvious, one or two lines.
- No `try!` in `Sources/`; no `try?` in `Sources/DollyCore/**/*Store*.swift`.
- UI work: invoke `impeccable`, `design-taste-frontend`, `unslop` and `find-animation-opportunities`, and check motion against `../app-updates/docs/motion-gate.md` and spec section 10.6.
