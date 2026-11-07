# Spikes S3, S4 and S5: owner checklist

Ten minutes at the Mac, with this build of Dolly installed. An agent can't speak, clap or read the
permission prompts, so these checks are yours. Write the results in the table at the end.

## Before you start

1. Open Dolly and press ⌃⌥⌘R to open the Record bar.
2. Turn on Microphone. The first time, Dolly explains why and macOS asks; allow it.

## S3: captions from your voice

1. With Microphone on (Camera off), record any window for about 20 seconds. Speak a few plain
   sentences with short pauses, for example "This is Shelf. Haul shows downloads. Tidy cleans up."
2. Stop with ⌃⌥⌘R. Open the take from the corner card.
3. Watch for system prompts while the Captions tab says "Transcribing…". Note whether macOS asks
   for Speech Recognition, and whether it asks to download a language model.
4. When captions appear, play the take. Each caption should show while you say its words.

S3 passes when captions appear without a Speech Recognition prompt and line up with your voice
within about a quarter second. If macOS asked for Speech Recognition, write that down: Dolly then
needs the `NSSpeechRecognitionUsageDescription` string and a first-run step like Camera's. If
captions never appear, the Captions tab says why after "Couldn't transcribe".

## S4: camera and screen in step

1. In the Record bar, turn on Camera too. The first time, Dolly explains why and macOS asks; allow
   it. A small mirrored preview shows under the bar.
2. Record a window for about 15 seconds. Partway through, clap once on camera while you click in
   the window at the same moment.
3. Open the take. In the editor, step frame by frame (← and →) around the click on the Clicks lane.

S4 passes when the frame where your hands meet and the click's frame are no more than one frame
apart (at 60 fps). Write the gap in frames either way.

## S5: system audio

1. In the Record bar, turn on System audio (no prompt: Screen Recording covers it).
2. Record a window that plays sound, for example a video in Kalos or Reel, for about 15 seconds.
   Click play in the window at a moment you can see.
3. Open the take and play it in the editor. Export 16:9 and play the mp4.

S5 passes when the sound plays in the editor and in the export, starts with the picture (no
visible lag at the click), and Dolly's own sounds are not in it.

## Results

| Check | Date | Pass or fail | Notes |
|---|---|---|---|
| S3 captions from your voice | | | |
| S4 camera and screen in step | | | |
| S5 system audio | | | |
