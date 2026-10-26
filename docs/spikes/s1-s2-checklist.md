# Spikes S1 and S2: owner checklist

Five minutes at the Mac, with Dolly installed. An agent can't click for you or read the permission
panes, so these two checks are yours. Write the results in the table at the end. Until both
pass, Dolly keeps the safe defaults: polling for clicks and the arrow pointer.

## Before you start

1. Open Dolly.
2. Hold Option and choose Dolly > Settings… (⌥⌘,). The Advanced section appears at the bottom.
   Without Option it stays hidden.

## S1: clicks from the event monitor, with no permission

1. In Advanced, set Click source to Event monitor.
2. Click once in Safari, once in a Finder window, and once inside Dolly's editor.
3. After each click, look at the readout under the switches. It should change to something like
   "Last click: 0.4 s ago at (512, 300), from the event monitor", with the point near where you
   clicked (points count from the bottom left of the main display).
4. Watch for a system prompt. None should appear.
5. Open System Settings > Privacy & Security > Accessibility, then Input Monitoring. Dolly should
   not be listed in either.

S1 passes when all three clicks update the readout, no prompt appeared, and Dolly is in neither list.
If it fails, set Click source back to Polling.

## S2: pointer shapes from other apps

1. In Advanced, turn on Record pointer shapes.
2. Open a page in Safari that has a text field and a link.
3. Press ⌃⌥⌘R, record the Safari window for about 10 seconds: hover the text field (I-beam), then
   the link (pointing hand), then plain page (arrow). Press ⌃⌥⌘R again to stop.
4. In the editor, play the take. Export it (⌘E) and play the mp4.

S2 passes when the exported clip shows the I-beam over the field and the hand over the link. If
it shows only the arrow, turn Record pointer shapes off.

## Results

| Check | Date | Pass or fail | Notes |
|---|---|---|---|
| S1 readout updates in Safari, Finder, Dolly | | | |
| S1 no prompt, not in Accessibility or Input Monitoring | | | |
| S2 I-beam and hand in the export | | | |

When both pass, tell the next session: the defaults become Event monitor and pointer shapes on.
