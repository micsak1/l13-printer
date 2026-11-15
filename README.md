# SilverCrest 4435 / Marklife L13 — working web app

This folder contains a patched version of
[thermal-pocket-printer-basic](https://github.com/ChiaraCannolee/thermal-pocket-printer-basic)
that talks to the SilverCrest 4435 (a Marklife **L13** rebrand) instead of
the C&Co 3128 / DP-L1S it was written for.

It also keeps the original C&Co / DP-L1S path, so both printers work from
the same page.

## TL;DR

Your printer is **not** a DP-L1S. It advertises as `L13_XXXX_BLE` and uses
the Marklife **L11** protocol: a 96-dot (12 mm) head, not the 384-dot
57 mm head of the C&Co.

Two separate things were failing:

1. **The browser could not connect.** On Linux, BlueZ tries the printer's
   Classic Bluetooth (BR/EDR) side first. The printer has no usable
   BR/EDR profile, so BlueZ returns
   `org.bluez.Error.BREDR.ProfileUnavailable`. Chromium has no mapping
   for that error and turns it into
   `NetworkError: Unknown error when connecting to the device.` — the
   "Unknown Error" you saw.
2. **Even after connecting, nothing would print.** The original page
   filters for `C&Co`, then sends DP-L1S commands (`10 FF F1 03`,
   384-pixel bitmaps). The L13 wants `10 FF F1 02`, 96-pixel bitmaps,
   and a different job order.

## Evidence from Linux / BlueZ

BlueZ sees both identities of the same printer:

```
Device AA:BB:CC:DD:EE:01  L13_XXXX       Class: 0x00800604 (Imaging)
Device AA:BB:CC:DD:EE:02  L13_XXXX_BLE   UUID: e7810a71-73ae-499d-8c15-faa9aef0c3f2
```

Connecting to the LE identity reproduces the browser failure exactly:

```console
$ bluetoothctl connect AA:BB:CC:DD:EE:02
Attempting to connect to AA:BB:CC:DD:EE:02
[CHG] Device AA:BB:CC:DD:EE:02 Connected: yes
[CHG] Device AA:BB:CC:DD:EE:02 ServicesResolved: yes
Failed to connect: org.bluez.Error.BREDR.ProfileUnavailable No more profiles to connect to
```

`BREDR.ProfileUnavailable` is not in Chromium's
`DBusErrorToConnectError()` mapping, so it becomes `ERROR_UNKNOWN` →
`CONNECT_UNKNOWN_ERROR` →
`"Unknown error when connecting to the device."`.

The advertised vendor UUID `e7810a71-…` is the same one documented for
the Marklife P12/P15/S2 family, and the L13 is supported by
[LaBLEr](https://github.com/toolicious/labler) with the same
96-dot/L11 protocol.

The MAC addresses and the `XXXX` suffix above are placeholders. Use the
values from `bluetoothctl devices` on your machine.

## Run the patched app

Web Bluetooth needs a secure context. `http://localhost` counts;
`file://` does not.

```bash
cd l13
python3 -m http.server 8000
```

Then open **http://localhost:8000** in Chromium/Chrome and press
**Connect**. Pick `L13_XXXX_BLE` (or `L13_XXXX`) from the chooser.

The page auto-detects the model from the BLE name. If it guesses wrong,
use the **Printer** dropdown.

## Make Linux connect (the "Unknown Error" fix)

Pick one option. Option A is the most reliable.

### Option A — per-device preferred bearer (recommended)

BlueZ can be told to use the LE bearer for this one device. The property
is experimental, so it has to be exposed first.

1. Enable the experimental API (one-time, reversible). Back up the file
   first, and note that restarting BlueZ briefly disconnects any Bluetooth
   headphones/mouse you are using:

   ```bash
   sudo cp /etc/bluetooth/main.conf /etc/bluetooth/main.conf.bak
   sudo sed -i 's/^#\?Experimental\s*=.*/Experimental = true/' /etc/bluetooth/main.conf
   sudo systemctl restart bluetooth
   ```

   Or edit `/etc/bluetooth/main.conf` and set, under `[General]`:

   ```ini
   Experimental = true
   ```

2. Clear any stale pairing/bond left by earlier OS-level attempts. A
   BR/EDR bond makes BlueZ prefer the Classic bearer even when
   `PreferredBearer=le` is set, so this matters:

   ```bash
   bluetoothctl remove AA:BB:CC:DD:EE:02
   bluetoothctl remove AA:BB:CC:DD:EE:01
   ```

   `remove` only forgets the device; it pairs again on demand. If a line
   says `not available`, that identity was not bonded, so just continue.
   Power-cycle the printer afterwards.

3. Power the printer on, then run the helper:

   ```bash
   ./bluez-l13-bearer.sh
   ```

   It finds the `L13_…_BLE` device, runs
   `bluetoothctl bearer <address> le`, and tries a GATT connect.

   Or do it by hand:

   ```bash
   bluetoothctl devices | grep -i l13
   bluetoothctl bearer AA:BB:CC:DD:EE:02 le
   bluetoothctl connect AA:BB:CC:DD:EE:02
   ```

   A successful connect now looks like:

   ```
   [CHG] Device ... ServicesResolved: yes
   Connection successful
   ```

4. Open the web app and press Connect.

You can set `Experimental = false` and restart BlueZ afterwards. The
per-device `PreferredBearer` value is stored in
`/var/lib/bluetooth/<adapter>/<device>/info` and is still honoured on
load; only the D-Bus property used to set it is experimental.

To restore the config exactly:

```bash
sudo cp /etc/bluetooth/main.conf.bak /etc/bluetooth/main.conf
sudo systemctl restart bluetooth
```

To undo the per-device setting:

```bash
bluetoothctl bearer AA:BB:CC:DD:EE:02 last-used
```

### Option B — pair over LE first (no config change)

BlueZ prefers the **bonded** bearer. Bonding over LE should make
`Connect()` pick LE without touching `main.conf`:

```bash
bluetoothctl pair AA:BB:CC:DD:EE:02
bluetoothctl info AA:BB:CC:DD:EE:02 | grep -E 'Paired|Bonded'
bluetoothctl connect AA:BB:CC:DD:EE:02
```

The `pair` command may still report `BREDR.ProfileUnavailable` even when
the LE bond succeeded (that is
[bluez#318](https://github.com/bluez/bluez/issues/318)). Check the
`Paired`/`Bonded` lines. If they are `yes`, try connecting again.

To undo:

```bash
bluetoothctl remove AA:BB:CC:DD:EE:02
```

### Option C — global LE-only controller (last resort)

This is the workaround from the original README:

```ini
# /etc/bluetooth/main.conf
[General]
ControllerMode = le
```

then `sudo systemctl restart bluetooth`.

Trade-off: while this is active, the adapter will not use Classic
Bluetooth at all. Bluetooth headphones/speakers, a Classic mouse or
keyboard, and car audio stop working. LE devices (most modern earbuds,
BLE keyboards/mice) are unaffected. Revert and restart to get Classic
back.

### Option D — Chrome on Android

Android's Web Bluetooth connects with `connectGatt(..., TRANSPORT_LE)`,
so it does not hit the BlueZ bug. Chrome on Android should connect to the
patched page directly **if the page is served over HTTPS** (or from
`localhost` on the phone itself). A plain `http://<LAN-IP>:8000` is not a
secure context, so Web Bluetooth will be unavailable there. The easiest
routes are to put `index.html` on GitHub Pages (or any HTTPS host) or to
use LaBLEr.

(The Android system Bluetooth settings will never "connect" to this
printer; that is expected. It has no Classic audio or input profile.)

## Why the OS "standard Bluetooth connection" fails

There is nothing to fix there. The SilverCrest 4435 has:

- a Classic BR/EDR identity (`L13_XXXX`, Class "Imaging") that exists for
  the SPP serial profile, not for the settings menu;
- an LE/GATT identity (`L13_XXXX_BLE`) that the app actually uses.

Desktop Bluetooth settings and Android's pairing UI try to establish a
generic connection or a known profile. On this printer there is no
generic profile to establish, so they fail. That is normal for this
class of device. Use the app, not the OS settings.

## What the patched page changes

| Thing | Original repo | L13 / Marklife |
|---|---|---|
| BLE filter | `C&Co` only | `C&Co`, `L13`, `P12`, `P15`, then all devices |
| `optionalServices` | `ff00` only | all four Marklife GATT layouts + vendor UUID |
| GATT profile | hard-coded `ff00/ff02` | probes `ff00`, Microchip UART, `fd00`, `18f0` |
| Head width | 384 px | 96 px (12 mm) |
| Canvas layout | 384 × length | length × 96 (readable), transposed on print |
| Wake-up | 12 NULs | 15 NULs |
| Enable | `10 FF F1 03` | `10 FF F1 02` |
| Init | none | `10 FF 40` |
| Density | `10 FF 10 00 d` | `1F 70 02 d` (1/2/3), omitted for normal |
| Feed | `1B 4A 50` (80) | `1B 4A 5B` (91) continuous / `1D 0C` gap |
| End | `10 FF F1 45` | `10 FF F1 45` (+ two `10 FF 40` for die-cut) |
| Chunking | 100 B / 50 ms | 90 B / 30 ms |
| Ack | none | waits for `0xAA` |

The bitmap itself is still standard `GS v 0` (`1D 76 30 00`), MSB-first,
`1 = dark`. On the Marklife path the editor canvas is laid out the
readable way round (`length × 96`), then packed into 12-byte raster rows
with the exact column transform LaBLEr calls `packColumns` (vertical
mirror per column, LSB-first within each 8-dot group). That produces the
90° rotation that puts the readable label lengthwise under the head. The
C&amp;Co path is unchanged: canvas width = head width, so no repacking.

## Troubleshooting

- **Chooser is empty after pressing Connect.** The printer is asleep.
  Press its button; the LED should come on, and the name should appear in
  `bluetoothctl scan on`. Then press Connect again and cancel the first
  chooser if it is still empty; the page falls back to "show all LE
  devices".
- **Still `Unknown error when connecting`.** The bearer fix did not take.
  Run `bluetoothctl connect <addr>` directly: it should say
  `Connection successful`, not `BREDR.ProfileUnavailable`. If it fails,
  Option A step 1 was not applied or BlueZ was not restarted.
- **Connected, but printing does nothing.** The page logs the GATT
  profile and every notification. Make sure the Printer dropdown says
  "Marklife L13 / P12 / P15". If the printer never sends `0xAA`, the
  command set or the head width is still wrong; the log will show what
  was sent.
- **Paper feeds but nothing is printed.** Check the roll is inserted with
  the thermal side facing the head, and that the cover is closed. The
  printer reports paper/cover problems only through the LED, not over
  BLE.
- **Labels come out blank or clipped.** Turn **Label mode** on for
  die-cut/gap stock; turn it off for continuous tape. The preview shows
  the exact bitmap, including the 96-px width.
- **Chrome on Android also fails.** Make sure the page is served over
  HTTPS (or `localhost` on the phone). Then "Forget" the printer in
  Android's Bluetooth settings: a stale BR/EDR bond from an earlier
  settings-menu attempt can make Android keep retrying the Classic side
  while Chrome tries GATT.

## Files

- `index.html` — the patched app (single file, no build step)
- `bluez-l13-bearer.sh` — finds the L13 and sets `PreferredBearer=le`

## If you would rather not use a browser

[LaBLEr](https://github.com/toolicious/labler) is an Android app that
explicitly supports the Marklife L13/P12/P15, has no internet permission,
and is on F-Droid. It is the least-friction way to print from Android.

For Linux without BlueZ changes, some Marklife units also expose Classic
SPP (Serial Port, UUID `0x1101`). If yours does, pair it with PIN `1234`
and write the same L11 byte stream to `/dev/rfcomm0`; that path does not
go through the BLE/BR/EDR bearer negotiation that Chrome trips over.
