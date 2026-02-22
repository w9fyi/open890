# open890 First-Time Setup Guide

This guide is for operators who have never used open890 before.

If you want the fastest path on Windows, follow the Windows section first.

## Before You Start

You will need:

1. A Kenwood TS-890S on your local network.
2. A computer on the same network as the radio.
3. A modern web browser (Chrome, Edge, Firefox, or Safari).

open890 serves a local web UI from your computer. You open that UI in your browser.

## Windows (Recommended for Most Users)

### Step 1: Install Visual C++ Runtime (required)

Download and install:

- https://aka.ms/vs/17/release/vc_redist.x64.exe

If you skip this, open890 may close immediately on startup.

### Step 2: Download open890

1. Open releases:
   - https://github.com/w9fyi/open890/releases/latest
2. Download:
   - `open890-<version>-setup.exe` (recommended)
3. Run the installer and follow prompts.
4. Keep desktop shortcut enabled when prompted.

### Step 3: Start open890

1. Double-click the `open890` desktop icon (or Start Menu entry).
2. The launcher starts the service, opens your browser, and shows a status message.

Zip fallback (advanced users):

1. Download `open890-<version>-windows-x64.zip`.
2. Extract it.
3. Run `open890.bat` from the extracted folder.

### Step 4: Open the Web UI

Open your browser and go to:

- http://localhost:4000

### Step 5: First Connection to Radio

1. Open the **Connections** page in the UI.
2. Add your TS-890 using its IP address.
3. Connect and verify you see frequency/mode updates and hear RX audio.

## Common Windows Prompts (Expected)

### "Windows protected your PC"

Because open890 binaries are not code-signed, Windows may show this warning.

1. Click **More info**
2. Click **Run anyway**

### "Windows Defender Firewall has blocked some features of this app"

Allow access on **Private networks** so local browser access works.

## macOS Quick Start

1. Download the macOS release archive from:
   - https://github.com/w9fyi/open890/releases/latest
2. Preferred: run `open890-<version>-macos-installer.pkg` (unsigned installer).
3. If prompted by macOS security, allow it from Privacy & Security and continue.
4. Start with `/Applications/open890/open890.command`.
5. Open:
   - http://localhost:4000

Archive fallback:

1. Download `open890-<version>-macos.tar.gz`.
2. Extract it.
3. Start with `open890.command`.

If macOS blocks execution, adjust your Privacy/Security settings to allow the app/script and retry.

## Linux (Ubuntu) Quick Start

1. Download the Ubuntu x64 release archive from:
   - https://github.com/w9fyi/open890/releases/latest
2. Extract it.
3. Start open890:

```bash
./open890.sh
```

4. Open:
   - http://localhost:4000

## Basic Troubleshooting

1. Page does not open:
   - Confirm open890 is running and use `http://localhost:4000`.
2. No microphone option:
   - Use `https://` or `localhost` and check browser mic permissions.
3. No radio control:
   - Confirm radio IP, same LAN/subnet, and no firewall blocks between PC and radio.
4. App closes right away on Windows:
   - Install the Visual C++ runtime listed above.

## Need Help?

- TS-890 group: https://groups.io/g/TS-890
- open890 discussion: https://groups.io/g/open890
