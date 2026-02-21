# open890 User Manual

This manual explains how to run and use open890 with a Kenwood TS-890S, including connection setup, audio routing, and common troubleshooting.

## 1. What open890 does

open890 is a browser-based control surface for the TS-890S. It provides:

- Radio control (frequency, mode, filters, AGC, etc.)
- Bandscope and panadapter views
- RX audio streaming
- Optional browser microphone input for VOIP-style TX audio
- Optional browser speaker and microphone device selection

## 2. Prerequisites

Before you start:

1. TS-890S is on the same network as the open890 host.
2. open890 is running (Docker or source build).
3. You know the open890 URL (for example `https://your-host:4000`).
4. For microphone and per-device audio selection, use a modern browser over `https://`.

### Windows install (Docker Desktop, recommended for this fork)

Use this path for Windows users who want the same behavior from this repository branch (including current audio and accessibility updates).

1. Install Docker Desktop for Windows and make sure WSL2 backend is enabled.
2. Install Git for Windows.
3. Open PowerShell.
4. Clone and start from your fork `main` branch:

```powershell
git clone https://github.com/w9fyi/open890.git
cd open890
git switch main
docker compose up --build -d
```

5. Open `http://localhost:4000` in Chrome or Edge.
6. To stop later:

```powershell
docker compose down
```

Notes:

- If a browser blocks microphone access, confirm site permission is allowed and retry on `https://` when running remote access.
- Native Windows `.bat` release packages are valid for upstream releases, but they may not include fork-specific changes unless you build/publish your own Windows artifact.

## 3. Open the UI

1. Open Chrome, Edge, or Safari.
2. Navigate to your open890 URL.
3. If using browser mic/audio device switching, use `https://` (not plain `http://`).

## 4. Connect to the radio

1. Go to the connection section.
2. Select or enter your TS-890 connection.
3. Press **Connect**.
4. Wait for status to show connected/active.

If the UI reports "connection down", see [Troubleshooting](#10-troubleshooting).

## 5. Basic operation

After connecting:

1. Confirm frequency and mode reflect the radio.
2. Tune using the UI controls.
3. Observe bandscope and signal activity.
4. Verify RX audio playback.

## 6. Select speaker/output device (Chrome/Edge)

This is browser-dependent. Chrome/Edge provide the best support.

1. Use `https://`.
2. Find the **audio output** dropdown.
3. Choose **Select output device...** if shown.
4. Approve browser permission prompt.
5. Pick the desired speaker/headphones from the dropdown.

Notes:

- Safari may not support per-site output switching the same way. If so, use system audio routing.
- If labels are missing, grant permission first, then reopen the dropdown.

## 7. Select microphone/input device (Chrome/Edge)

1. Use `https://`.
2. Find the **microphone input** dropdown.
3. If shown, select **Enable microphone list...** to grant permission.
4. Approve mic access in the browser prompt.
5. Re-open/select the microphone dropdown and choose the mic you want.

Behavior details:

- After permission is granted, device labels and choices become available.
- If permission is denied, open890 keeps the previous mic selection and shows status feedback.

## 8. Browser and OS permissions

### Chrome site permission

1. Open site settings for open890.
2. Set **Microphone** to **Allow**.
3. Reload the page.

### macOS permission

1. Open **System Settings**.
2. Go to **Privacy & Security** -> **Microphone**.
3. Ensure Chrome (or your browser) is enabled.
4. Restart browser if needed.

## 9. Secure access recommendations

For reliable media permissions:

- Prefer `https://` for non-localhost access.
- Keep browser updated.
- Avoid mixed-content proxy setups.

## 10. Troubleshooting

### A. "Connection down" after pressing Connect

1. Hard-refresh the page (`Cmd+Shift+R` / `Ctrl+Shift+R`).
2. Confirm open890 backend/container is running.
3. Check browser console for JavaScript parse/runtime errors.
4. Check open890 logs for websocket/session errors.

### B. Speaker dropdown does not switch output

1. Confirm you are on `https://`.
2. In Chrome/Edge, use **Select output device...** and allow the prompt.
3. Re-open dropdown and select device again.
4. If still blocked in Safari, switch output at OS level.

### C. Mic dropdown does not switch input

1. Confirm you are on `https://`.
2. Select **Enable microphone list...** and allow mic permission.
3. Re-select your microphone.
4. Verify browser + OS mic permissions.
5. If mic is busy in another app, close that app and retry.

### D. No device labels (Microphone 1, etc.)

This usually means media permission is not granted yet.

1. Grant mic/speaker permission as prompted.
2. Refresh device list by re-opening the dropdown.

## 11. Daily operation checklist

1. Open open890 URL.
2. Connect to radio.
3. Confirm RX audio.
4. Confirm correct speaker and microphone device.
5. Operate normally.

## 12. Publish notes

If you publish this manual in your project docs, link it from `README.md` under quick start/help sections.
