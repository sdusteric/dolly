# Motion gate, Dolly M1

Final sweep of every M1 surface against `../app-updates/docs/motion-gate.md` and spec section 10.6,
on the shots in `build/shots` and the source in `Sources/DollyUI`. No new motion survived this
sweep. The table lists the motion M1 ships, each one kept in its task's design pass. All of it
uses `Theme.Motion` and drops to opacity only or nothing under Reduce Motion.

| Location | Motion | Purpose | Frequency | Values |
|---|---|---|---|---|
| `Shared/Buttons.swift:19`, `:50`, `Editor/TakesSidebar.swift:111`, `Timeline/TimelineView.swift` play button | Press: fill darkens | Feedback | Tens per session | `Theme.Motion.press` 0.12 s ease-out; none with Reduce Motion |
| `Timeline/TimelineView.swift:102` | Zoom strip added or removed | Preventing a jarring change | A few per take | `Theme.Motion.stripBridge` 0.16 s ease-out, opacity plus scale from 0.97; opacity only with Reduce Motion |
| `Record/RecordBar.swift:94` | Countdown 3, 2, 1 crossfade | State indication | Once per recording | `Theme.Motion.countdown` 0.2 s ease-out, opacity; none with Reduce Motion |
| `Export/ExportSheet.swift:175`, `Inspector/InspectorView.swift:155` | "Saved 1 file" and "Saved for new takes" fade in | Feedback | Once per export, rare | `Theme.Motion.saved` 0.16 s ease-out, opacity; none with Reduce Motion |
| `Editor/TakesSidebar.swift:57` | New take row fades in | Preventing a jarring change | Once per recording | `Theme.Motion.stripBridge` 0.16 s ease-out, opacity |

## Rejected in this sweep

- Settings click readout (`Settings/SettingsView.swift`): the text redraws ten times a second and is
  the measurement the owner is reading. Function: data does not move for style.
- Advanced section appearing (`Settings/SettingsView.swift`): it is decided when the window opens
  with Option held, so nothing appears in place. Purpose: no bridge is needed.
- Stage switching between the player and Aim mode (`Stage/StageView.swift`): happens on every zoom
  selection and Space press, tens of times per session, keyboard included. Frequency.
- Export sheet open and close: AppKit's own sheet animation runs, so adding one would double it.
  Purpose: already bridged by the system.

## Verdict

M1 already has the motion it needs: press feedback, one bridge for things that appear in lists, and
the countdown. The highest-leverage item is the zoom strip bridge, because it is the one place where
an edit (Z, Delete, undo) would otherwise make a strip blink in or out under the pointer.
