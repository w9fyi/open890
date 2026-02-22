# open890

[![Latest Release](https://img.shields.io/github/v/release/w9fyi/open890)](https://github.com/w9fyi/open890/releases/latest)
![Build Status](https://github.com/w9fyi/open890/workflows/Build/badge.svg)

open890 is a web-based UI for the Kenwood TS-890S amateur radio, and features good usability, 
clean design, and high-speed bandscope/audio scope displays, among other features not available
either on the radio itself, or in the ARCP remote control software.

It is currently only designed to interface with the TS-890 via a LAN (or wifi) connection, and not
a USB/serial connection. It may work with the TS-990, as the command set is very similar, but is
currently untested.

![open890 screenshot](docs/screenshot.png)

## 1-Minute Quick Start

1. Install open890 using either:
   - Docker (fastest), or
   - Raspberry Pi install (best for dedicated shack use)
2. Start open890 and open the web UI in your browser.
3. Connect to your radio and verify RX audio.
4. Enable VOIP microphone:
   - Browser should prompt for mic access
   - Select your preferred mic/speaker devices (if browser supports it)
5. Use keyboard shortcuts:
   - `Ctrl+Shift+L` LSB
   - `Ctrl+Shift+U` USB
   - `Ctrl+Shift+C` CW
   - `Ctrl+Shift+A` AM
   - `Ctrl+Shift+F` FM
   - `Cmd+Shift+E` Frequency entry
   - Hold `Option+Shift` for PTT (TX while held)

### Important

Microphone access requires `https://` (or `localhost`).
If you use plain `http://` on LAN, mic permissions may show as unavailable.

### Troubleshooting Tips

- If microphone permissions say unavailable: use `https://` and re-check browser/OS mic permissions.
- iOS Safari may not expose per-site audio output selection; route audio at system level (Control Center/AirPlay).
- If the wrong mic is used, reselect the input device and toggle VOIP mic off/on.

## New Here? Start With This Guide

If this is your first time using open890, follow:

- [First-Time Setup Guide](docs/FIRST_TIME_SETUP.md)

This is written for users with no prior open890 experience and includes Windows, macOS, and Linux quick-start steps.


## Getting Help

I am primarily active on the [TS-890S groups.io discussion board](https://groups.io/g/TS-890)

## Installation from source

See [Installing From Source](https://github.com/w9fyi/open890/wiki/Installing-From-Source)

## Docker

If you are knowledgeable in Docker, you can either pull a published image from the repository,
or build & run your own image locally.

At the moment, open890:latest reflects what is pushed to the `main` branch. Eventually,
releases will be tagged as well.

### Run via docker-compose (preferred)

    docker-compose up

This will map two local directories, open890-db, and open890-config into the image. This will
allow you to back-up your connection database, as well as drop in a config.toml file, and allow
this data to persist across container restarts. You can change the location of these directories
by adjusting the `volumes` setting in `docker-compose.yml`.

### Pull & run a published image (manual)

    docker pull ghcr.io/w9fyi/open890:latest
    docker run -p 4000:4000 -p 60001:60001/udp -it --rm ghcr.io/w9fyi/open890:latest


Port 4000 is for the main web interface, UDP port 60001 is for the UDP audio server for audio streaming.

### Build your own Docker image locally

Build the image, and start a container using the image, exposing the internal server to your host:

    make docker

You should now be able to access http://localhost:4000

If you would like to just build the image, you can run `make build_docker`.

## Binary releases

Platform/architecture-specific binary releases are available from [releases](https://github.com/w9fyi/open890/releases/latest).

### Windows

**REQUIRED**: Install the latest Microsoft Visual C++ Redistributable package from here: https://aka.ms/vs/17/release/vc_redist.x64.exe

This solves the open890 window closing immediately upon startup, or resolves the error message "unable to load emulator DLL".

Then, install open890:

  * Preferred: Download the Windows installer `.exe` and run it.
  * Alternative: Download the Windows release `.zip`, extract it, then run `open890.bat`.

Installer flow:

  * Run `open890-<version>-setup.exe`
  * Accept prompts, choose install location, and allow desktop shortcut creation
  * Optional: enable the troubleshooting checkbox to auto-collect diagnostics and open a pre-filled GitHub issue draft if startup fails
  * Launch the `open890` desktop/start-menu icon
  * The launcher starts open890 and opens your browser to `http://localhost:4000`
  * If startup fails with troubleshooting enabled, a diagnostics zip is created on your Desktop and a pre-filled GitHub issue draft opens automatically

You will probably see several security warnings as described below. After getting through those, access the web interface at http://localhost:4000 with your 
favorite web browser.

#### "Windows Protected your PC"

Since I haven't paid for a certificate to sign binaries, Windows will loudly complain about an unknown developer.

 * Click "More Info" and choose "Run anyway". 

If you are concerned about the safety of the files, **only ever download direct from the Github releases page**, and additionally, compare the MD5 checksum from the release notes with the file you have. An internet search for "Windows MD5 tool" will yield several results if you are concerned.

#### Windows Security Alert

On first run, you will likely receive a warning from Windows stating, "Windows Defender Firewall has blocked some features of this app" - For one or more of the following files:

 * erl.exe

This is due to open890's client-server architecture, and it needs permission to open a port (4000) for the local webserver. Only choose the "private network" option for open890.

### Mac OS

Binary builds for Apple Silicon are available. Intel binaries are unfortunately not available as I do not have access to an Intel Mac anymore to test and support.

[Homebrew](https://brew.sh/) and openSSL 1.1 are required to run binary releases on MacOS. 
Once you have homebrew installed and working properly, run:

```
brew install openssl@1.1
```

Users will need to enable the "Allow applications from any developer" security feature as described below:

#### Mac OS 13 (Ventura) and later:

* Open Terminal.app and run the following command:

```
sudo spctl --master-disable
```

You may be prompted for your account password to authenticate.

* Now navigate to Settings -> Privay & Security -> Allow applications downloaded from: Anywhere

#### MacOS 12 and earlier:

Navigate to Settings -> Privacy & Security -> Allow applications downloaded from: Anywhere


#### All MacOS versions:

After changing the security setting:

* Preferred: Download and run the unsigned macOS installer package `open890-<version>-macos-installer.pkg`
* Alternative: Download and unzip the macOS binary archive to somewhere useful (for example your Desktop)
* If installed via `.pkg`, open890 is installed to `/Applications/open890`
* Start with `/Applications/open890/open890.command`
* The launcher starts open890 in the background, opens your browser to `http://localhost:4000`, and shows a status dialog
* Stop open890 with `/Applications/open890/open890-stop.command`
* If using the archive, use `open890.command` to start and `open890-stop.command` to stop
* If launch fails with `permission denied`, run:
  `sudo chmod +x /Applications/open890/open890.command /Applications/open890/open890-stop.command /Applications/open890/open890-launcher-macos.sh /Applications/open890/bin/open890`


### Linux (Ubuntu)

Linux binaries are supported to run on 64-bit Ubuntu 20.04, although other modern Linux releases may or may not work due to dependencies.

Download the release `.tar.gz`

Then, decide where you want open890 to live, usually somewhere in your home directory.

    cd <where you want it>
    tar zxvf /path/to/open890-release.tar.gz

You will then get a subdirectory called `open890`.

    cd open890
    ./open890.sh

And then open a web browser to http://localhost:4000

If you encounter an error related to shared libraries, etc, they _may_ be solved by installing the correct version,
although the correct packages may not be available in your OS distribution's package manager. 

If all else fails, install from source.

### Raspberry Pi

Binary builds are not available for Raspberry Pi due to CPU architecture differences. You will need to install from source (see above)
in order to get open890 running on a RPi.

## Maintainer Release Process

If you are publishing a new release, use one command:

```bash
./pushrelease v0.1.4
```

This does the following:

1. Pushes your current branch.
2. Creates and pushes the release tag.
3. Triggers GitHub Actions release workflow.
4. Builds and publishes Windows, macOS, and Ubuntu assets in the same release.
5. Publishes the Windows installer (`open890-<tag>-setup.exe`).
6. Publishes the unsigned macOS installer (`open890-<tag>-macos-installer.pkg`).
7. Publishes the first-time setup guide as a release asset.

Requirements:

- Clean git working tree (no uncommitted changes).
- Push access to `w9fyi/open890`.
- Repository secrets configured for build (`SECRET_KEY_BASE`).

Alternative (same behavior):

```bash
make publish_release VERSION=v0.1.4
```

## Network Settings & Security

By default, open890 runs a web server on port `4000` and binds to `0.0.0.0` (all interfaces) on the machine it runs on.

If you would like to change the default host and port that open890 is accessed via, you can set the `OPEN890_HOST` and `OPEN890_PORT` environment variables accordingly. This is most useful if you are accessing open890 from a separate machine than the one it is running on.

You can change default UDP audio server port from 60001 to whatever you'd like by setting `OPEN890_UDP_PORT`. This is useful if your ISP filters port 60001 and would like to forward the port yourself.

You can adjust transmit microphone level scaling with **TX Input Trim (Local)** in the **RX-ANT** tab on the Radio front panel. This slider is saved per connection and is applied in open890 before audio is sent to the radio (not a CAT/radio setting).

You can also set a process-wide default with `OPEN890_TX_MIC_GAIN` (default `1.0`, valid range `0.01` to `8.0`). Per-connection UI values override this default.

You can override where open890 stores its connection database by setting `OPEN890_DB_PATH` to a writable file path (or `OPEN890_DB_DIR` to a writable directory).

Please note that the web interface **is not secured with a password**, and it assumes that you will run it on a trusted network. This is equivalent to running a computer with ARCP-890 left running.

If you wish to require a basic password, edit `config/config.toml` (you may need to copy `example.config.toml` first), and uncomment or add the following section:

```toml
[http.server.basic_auth]
enabled = true
username = "someUserName"
password = "aReallyHardPasswordToGuess"
```

Upon starting open890, you will be prompted for this username and password. Again, **this is only basic authentication and the connection is not encrypted**. If you want to truly secure access, run open890 behind a firewall and use a VPN to access the system.

## Getting Help

If you encounter a bug, please [open a discussion](https://groups.io/g/open890). Please do not directly email me for technical support!

## Contributing

* [Start a discussion](https://groups.io/g/open890) so we can discuss your idea
* Fork this repository
* Make your changes in a branch in your own repo
* Open a pull request!

## Donors

The following people have graciously donated monetarily to open890, and opted-in to be listed here, in alphabetical order. If you would like to donate, please contact Tony at tcollen at gmail.com

* Guy Bujold, VE2CXA
* Willi Föckeler, DK6DT
* Mike Garcia, KJ5CDJ
* Philip Hartwell, VK6GX
* Rick Lapp, KC2FD
* Jeff Sloane, KE6L
* Jack Wren, K4VR

## Legal mumbo-jumbo

This project is licensed under the MIT license. Please see [LICENSE](LICENSE) for more details.

All product names, logos, brands, trademarks and registered trademarks are property of their respective owners. All company, product and service names used in this software are for identification purposes only.


## Optional: RNNoise RX Denoising (Raspberry Pi)

open890 can denoise incoming RX audio on the server side using RNNoise before broadcasting audio to the browser.

### 1) Build RNNoise locally

```bash
cd ~/open890
./scripts/build_rnnoise_local.sh
```

By default this installs RNNoise to `~/.local/open890-rnnoise`.

### 2) Build the open890 RNNoise helper

```bash
cd ~/open890
./scripts/build_open890_rnnoise_filter.sh
```

This creates `priv/bin/open890_rnnoise_filter`.

### 3) Enable RNNoise in open890

Set these environment variables before starting open890:

```bash
export OPEN890_RNNOISE_ENABLED=true
export OPEN890_RNNOISE_BIN="$HOME/open890/priv/bin/open890_rnnoise_filter"
# Optional (default 30)
export OPEN890_RNNOISE_TIMEOUT_MS=30
```

If RNNoise is disabled or unavailable, open890 automatically falls back to passthrough audio.

## Optional: Native FT8 Decoder Scaffold (Experimental)

open890 now includes an **experimental FT8 decoder service scaffold** so we can integrate WSJT-X decoding natively.

Current state:

- Decoder service is wired into the server audio pipeline.
- FT8 tab is available in the UI with enable/disable and decode list.
- Helper binary protocol is in place.
- FT8 helper now decodes using WSJT-X `jt9` (installed separately on the host).

### 0) Install WSJT-X decoder binary

```bash
sudo apt-get install wsjtx
```

`jt9` is provided by this package. If it is installed in a non-standard path, set `OPEN890_FT8_JT9_BIN`.

### 1) Build the FT8 helper

```bash
cd ~/open890
./scripts/build_open890_ft8_decoder.sh
```

This creates `priv/bin/open890_ft8_decoder`.

### 2) Enable FT8 service

```bash
export OPEN890_FT8_ENABLED=true
export OPEN890_FT8_BIN="$HOME/open890/priv/bin/open890_ft8_decoder"
# Optional: path to WSJT-X decoder binary
export OPEN890_FT8_JT9_BIN="/usr/bin/jt9"
# Optional tuning
export OPEN890_FT8_TIMEOUT_MS=1200
export OPEN890_FT8_SAMPLE_RATE_HZ=16000
export OPEN890_FT8_WINDOW_SECONDS=15
```

### 3) Start open890 and open the FT8 tab

- Choose an FT8 band preset from the FT8 tab picker (for example 40m 7.074, 20m 14.074, 17m 18.100).
- Click **Start FT8** to tune to that preset and enable decoding.
- Watch decode output in the list.
- Use **Stop FT8** to stop the FT8 decoder.
- Click a decode entry to retune the active VFO to that FT8 audio offset (relative to 1500 Hz).

### GPL note for real WSJT-X integration

This integration executes the WSJT-X `jt9` decoder binary for each 15-second FT8 window.
When WSJT-X GPL code is integrated into distributed builds, distribution must comply with GPLv3 obligations for the combined work (source availability, notices, and downstream rights).
