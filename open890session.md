# open890 Session Notes

Date: 2026-02-19

## What was done

### 1) Audio diagnostics on Pi (`raspbnodered.local`)
- Confirmed `open890` was running in Docker on port `4000` and TLS proxy (`open890-tls`) was running via nginx.
- Confirmed radio UDP audio packets were arriving at port `60001`.
- Confirmed the likely playback-side issue was browser audio context/device handling rather than radio transport.

### 2) Accessibility fix (VoiceOver)
- Updated connection names to be actual links (instead of plain text headings) so they are exposed as actionable elements.
- File changed on Pi repo:
  - `/home/ai5os/open890/lib/open890_web/live/connections.html.heex`

### 3) Browser audio behavior improvements
- Added audio context resume/unlock handling on user interaction.
- Added broader output-device switching support:
  - Use `AudioContext.setSinkId` when available.
  - Fallback to `HTMLMediaElement.setSinkId` when `AudioContext.setSinkId` is unavailable.
- Added explicit secure-context checks for device selection:
  - Mic/output selectors now indicate HTTPS is required for browser device selection.
- File changed on Pi repo:
  - `/home/ai5os/open890/assets/js/hooks.js`

### 4) Rebuild/redeploy
- Rebuilt `open890:local` image from `/home/ai5os/open890`.
- Restarted container `open890` with same ports/volumes/env.
- Verified updated JS bundle is served and includes new strings/logic.

## Current expected behavior
- Connections list names are links and should be better for VoiceOver navigation.
- For non-default browser audio input/output selection, use:
  - `https://raspbnodered.local` (not plain `http://`)
- If a browser lacks per-site output selection support, output may still be limited to system default.

## Next planned task
- Add MIDI controller support for CTR MIDI 2.
- Recommended first implementation:
  - Define a MIDI mapping profile (knobs/buttons -> open890 actions).
  - Start with a minimal, testable map: tuning, volume, filter width, mode toggle, PTT-safe action.
  - Add a small config file for user-remappable bindings.

## Quick return prompt
When resuming, say:
- "Continue from open890session.md and start CTR MIDI 2 mapping."
