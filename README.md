# Dolly

Dolly records a demo of your screen and turns your clicks into smooth zooms, then exports a clip sized for X and Threads.

- Record a window, an area or the whole screen with Control-Option-Command-R.
- Dolly hides the real pointer, draws a smooth one, and zooms in where you click.
- Move, resize, deepen or remove any zoom on the timeline or on the stage.
- Record your camera and microphone beside the screen. Place the camera bubble anywhere and hide it where you like.
- Captions from your voice, transcribed on this Mac, or typed. Edit, split and retime them on the timeline.
- Pick a backdrop: a flat color, one of six gradients, your desktop picture or any image.
- Export every shape at once: Original, 16:9, 1:1, 4:5 and 9:16, with an .srt file if you want one.

Dolly needs Screen Recording, and Camera and Microphone only when you turn those switches on. It never asks for Accessibility or Input Monitoring, and nothing leaves your Mac unless you drag it out.

Build: `scripts/bundle.sh --release`. Gates: `scripts/check.sh`. Design: `docs/superpowers/specs/2026-10-26-dolly-design.md` and the studio pass `docs/superpowers/specs/2026-10-29-dolly-studio.md`.

It needs macOS 27 on Apple Silicon. `scripts/bundle.sh` signs with your own certificate when you set `SIGN_ID` (a name or SHA-1 from `security find-identity -v -p codesigning`). `scripts/check.sh` expects the public [sdusteric/app-updates](https://github.com/sdusteric/app-updates) repo cloned next to this one.

## License

MIT. See `LICENSE`.
