# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

(Labeled assumption, same convention as Shelf: macOS only, Swift with AppKit and SwiftUI. "adaptive" is not meant literally; there is no iOS or Android target. The owner said "just start", so facts not stated by the owner are marked as inferred.)

## Stack

Delegated: Swift 6, SwiftUI inside AppKit windows, ScreenCaptureKit for capture (ported from Snap's recorder), AVFoundation for composition and export. A separate repo in `mac-apps/dolly`, private GitHub repo under sdusteric like the others. "Dolly" is a working name (a camera dolly moves the camera in on the subject), the agent's call.

## Users

One person: the owner of the mac-apps family, a developer who builds websites and apps and posts short demos of them on X and Threads (stated). They record a demo, shape it into a clip that reads on a phone feed with the sound off, and post it (inferred).

## Product Purpose

Dolly replaces FocuSee, which stopped working when the owner cancelled Setapp on 2026-10-26. It records the screen, a window or an area with the cursor hidden, logs where the pointer went and where it clicked, and turns that into a clip where the view moves in on each click and follows the pointer, set on a background and sized for X or Threads. Success: a 30 to 60 second demo goes from record to a posted-ready mp4 in under five minutes, with zooms that land on the right thing without hand-placing most of them (inferred target).

## Positioning

The only recorder that knows the owner's own apps and family: it shares Snap's capture code and permission handling, Reel's playback know-how, and shows its last export in Shelf. Against FocuSee it drops what the owner does not use (inferred): webcam, AI captions, cloud, templates, team sharing.

## Operating Context

- Used a few times a month (FocuSee's last-used date on this Mac was 2026-09-30, 7 launches recorded; inferred cadence). Each session is 10 to 30 minutes: record one to three takes, edit one, export.
- Subjects: the owner's websites in a browser and their Mac apps (Haul, Tidy, Reel, Snap, Booth, Shelf). Recording sizes from a full 5K display down to a single window.
- Destinations: X and Threads, viewed mostly on phones, muted autoplay. The owner did not name a format; 16:9, 1:1, 4:5 and 9:16 all matter (inferred). Platform limits (length, size, resolution) change; the builder verifies current limits before fixing presets.
- Snap stays the tool for screenshots and quick plain recordings. Dolly is for demos that get edited.

## Capabilities and Constraints

- Permissions: Screen Recording (needed). Clicks and pointer path without Accessibility or Input Monitoring if possible (a spike decides; see the design doc). Keystroke display would need Input Monitoring and is off unless the owner turns it on. Microphone only when voice-over is turned on.
- Offline. Dolly never uploads or posts; the owner posts by hand. Export writes an mp4 and can copy the file to the pasteboard or reveal it in Finder.
- Shared contracts: Sparkle 2.10.0 per `app-updates/CONTRACT.md`, Developer ID signing, `DOLLY_HOME` and `DOLLY_NO_UPDATES=1` for tests, Shelf quick actions (`dolly://record`) and a Shelf status file.
- American spelling, no em or en dashes in any copy.
- Undecided: whether voice-over is in v1, GIF export, keystroke display.

## Brand Commitments

Part of the mac-apps family: Avenir Next for display, SF for text, each app with its own look that does not copy a sibling. Main colors already taken: Booth deep green with marigold and tomato, Tidy ink on paper, Snap cool blue-gray with one frame blue, Shelf teal (#0B6B63). Dolly picks a color none of them use as a main color.

## Evidence on Hand

No user research. Real material: the owner's own apps and sites to record, Snap's recorder code, the family's mockup and contrast-check conventions. Mockups use illustrative demo content (a recording of Shelf's Tile Board and a browser demo of a website) and say so; no claims about views, likes or followers.

## Product Principles

1. The clip is the product: every control exists to make the exported video read better on a phone, nothing else.
2. Automatic first, adjustable second: zooms come from the clicks, and every one of them can be moved, resized or removed on the timeline.
3. Record once, export to every shape: the same edit reframes for 16:9, 1:1, 4:5 and 9:16 without re-editing.
4. Ask for the fewest permissions that do the job, and say why when asking.
5. Nothing leaves the Mac unless the owner drags it out.

## Accessibility & Inclusion

Text at least 4.5:1 in light and dark, full keyboard control of the timeline (move playhead, select and nudge zoom segments), VoiceOver labels on every segment ("Zoom 2, 0:07.4 to 0:10.1, 2x on Save button"), Reduce Motion honored in the editor UI (not in the exported clip, which is the owner's content).
