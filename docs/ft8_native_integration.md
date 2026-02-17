# Native FT8 Integration (Option 1)

This document tracks the native FT8 integration path where decoding is performed inside open890 using a local helper process.

## Current implementation

- `Open890.FT8DecoderPort` receives denoised RX audio from `Open890.UDPAudioServer`.
- The decoder runs as an external helper executable over an Elixir Port with packet framing.
- UI integration is available in the Radio view under the `FT8` tab.
- The helper (`c_src/open890_ft8_decoder_wsjtx.c`) runs WSJT-X `jt9` and returns parsed FT8 decodes.

## Dependencies

- WSJT-X `jt9` binary must be installed (Debian/Raspberry Pi: `sudo apt-get install wsjtx`).
- Optional override: set `OPEN890_FT8_JT9_BIN` to a custom `jt9` path.

## Port protocol

Request frame payload (packetized by Elixir `{:packet, 4}`):

- `u32 seq` (big-endian)
- `binary pcm16le_window`

Response frame payload:

- `u32 seq` (big-endian)
- `json` (`{"decodes": [...]}`)

Decode entry fields expected by UI:

- `timestamp` (ISO-8601 string)
- `text` (decode text)
- `snr` (optional)
- `dt` (optional)
- `freq_hz` (optional)

## Next step to use WSJT-X code

Current helper decodes by invoking WSJT-X `jt9`; future work can replace this with direct linked decoder internals while preserving the same JSON schema.

## Licensing note

When WSJT-X GPL code is integrated and distributed with open890 builds, distribution must satisfy GPLv3 obligations for the combined work.
