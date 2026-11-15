# SilverCrest 4435 / Marklife L13 web app

A patched version of
[thermal-pocket-printer-basic](https://github.com/ChiaraCannolee/thermal-pocket-printer-basic)
that supports the SilverCrest 4435 (a Marklife **L13** rebrand) as well as
the original C&Co 3128 / DP-L1S.

The L13 uses the Marklife **L11** protocol: a
96-dot (12 mm) head and GATT service `ff00`, not the 384-dot / DP-L1S
command set of the C&Co.

## Quick start

Web Bluetooth needs Chrome, Edge, or Opera, and a secure context: HTTPS
(GitHub Pages) or `localhost`.

1. Open the GitHub Pages URL in Chrome on Android.
2. Power the printer on. If it is asleep, press its button.
3. Press **Connect** and pick `L13_…_BLE` from the chooser.
4. Set **Printer** to **Auto-detect** (or **Marklife L13 / P12 / P15**).
5. Enter text or drop an image, then press **Print**.

The app auto-detects the model from the device name. Use the **Printer**
dropdown only if auto-detection picks the wrong one.

On a Linux desktop, see [LINUX.md](LINUX.md) if the connection fails with
`Unknown error when connecting`.

To run it locally instead:

```bash
cd l13
python3 -m http.server 8000
```

Then open `http://localhost:8000` in Chromium/Chrome.

## Printing settings

- **Printer** — leave on **Auto-detect**. It picks Marklife from the `L13`
  name. Choose **Marklife L13 / P12 / P15** to force the 96-dot path;
  **C&Co 3128 / DP-L1S** is only for the 384-dot printer.
- **Label mode** — ON for die-cut/sticker labels, OFF for continuous tape.
  It changes the end-of-job feed (`1D 0C` vs `1B 4A 5B`), not the bitmap,
  and is not a centering control.
- **Density** — light / normal / dark. Normal leaves the printer's stored
  value alone.
- **Dither** — better for photos and gradients.
- **Invert** — swaps black and white.

### Centering

The app centers the bitmap within the 96-dot width and within its own
canvas length. It does not know the physical label length, so on a long
die-cut label the content is printed at the label's leading edge rather
than centered on the whole label.

The built-in test pattern is deliberately left-aligned; use your actual
text/image when judging alignment.

If the output looks shifted across the tape, first confirm the log says
`Raster: … × 96 across` and the Printer mode is Marklife. A 384-dot
C&Co job on the L13 will not line up.

## Troubleshooting

- **Chooser is empty.** The printer is asleep. Press its button, wait for
  the LED, and press Connect again.
- **`Unknown error when connecting`.** On Linux this is the BlueZ
  dual-mode issue; see [LINUX.md](LINUX.md). On Android, turn Bluetooth
  off on any other laptop/phone, forget stale `L13…` pairings in Android
  settings, power-cycle the printer, and retry.
- **`No known GATT profile found. Tried A:NotFoundError …`.** The link
  was down before service discovery. Make sure only one device is
  connected to the printer, remove stale bonds, and power-cycle it.
- **Connected but nothing prints.** Check the log says
  `Using Marklife L13 / P12 / P15` and `Raster: … × 96 across`. Check
  that the paper's thermal side faces the head and the cover is closed.
- **Blank or clipped labels.** Turn **Label mode** on for die-cut/gap
  stock and off for continuous tape. The preview shows the exact bitmap.
- **Android system Bluetooth will not connect.** That is expected. Use
  the web app, not the OS pairing UI.

## Technical notes

- **GATT:** service `ff00`, write `ff02`, notify `ff01`.
- **Canvas:** laid out as `length × 96` (readable), then transposed into
  12-byte raster rows for the print head.
- **Job:** init `10 FF 40`, 15 NULs, enable `10 FF F1 02`, `GS v 0`
  raster, then continuous feed `1B 4A 5B` or die-cut advance `1D 0C`,
  and stop `10 FF F1 45`.
- **Acknowledgement:** the app waits for the printer's `0xAA` reply.

### What changed from the original repo

- **BLE filter:** `C&Co` only → `C&Co`, `L13`, `P12`, `P15`, then all LE
  devices.
- **GATT:** hard-coded `ff00/ff02` → probes `ff00`, Microchip UART,
  `fd00`, and `18f0`.
- **Head width:** 384 px → 96 px (12 mm).
- **Wake-up:** 12 NULs → 15 NULs.
- **Enable:** `10 FF F1 03` → `10 FF F1 02`.
- **Init:** none → `10 FF 40`.
- **Feed:** `1B 4A 50` (80) → `1B 4A 5B` (91) or `1D 0C` for gaps.
- **Chunking:** 100 B / 50 ms → 90 B / 30 ms.
- **Acknowledgement:** none → waits for `0xAA`.

The C&Co path is unchanged: canvas width equals head width, so no
repacking is needed.

## Files

- `index.html` — the app (single file, no build step)
- `LINUX.md` — Linux/BlueZ desktop setup and the helper options
- `bluez-l13-bearer.sh` — optional Linux helper for the per-device LE bearer

## Credits

Based on
[thermal-pocket-printer-basic](https://github.com/ChiaraCannolee/thermal-pocket-printer-basic)
by ChiaraCannolee.
