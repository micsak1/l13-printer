# Linux / BlueZ desktop setup

The web app works from Chrome on Android over HTTPS. On a Linux desktop,
BlueZ can refuse the connection before the app gets a chance to talk to
the printer. This file covers that case.

## The problem

The SilverCrest 4435 is dual-mode:

```text
Device AA:BB:CC:DD:EE:01  L13_XXXX       Class: 0x00800604 (Imaging)
Device AA:BB:CC:DD:EE:02  L13_XXXX_BLE   UUID: e7810a71-73ae-499d-8c15-faa9aef0c3f2
```

BlueZ tries the Classic (BR/EDR) bearer first. The printer has no usable
BR/EDR profile, so `Connect()` returns:

```text
Failed to connect: org.bluez.Error.BREDR.ProfileUnavailable No more profiles to connect to
```

Chromium has no mapping for that error, so the page shows:

```text
NetworkError: Unknown error when connecting to the device.
```

The LE/GATT side is fine: service `ff00`, write `ff02`, notify `ff01`.
The OS Bluetooth settings and pairing UI will not connect to this printer;
use the web app instead.

Addresses above are placeholders. Use the two addresses from
`bluetoothctl devices | grep L13`.

## Option A — per-device LE bearer

BlueZ can be told to use LE for this one device. The property is
experimental, so enable it first.

1. Back up the config and enable the experimental API:

   ```bash
   sudo cp /etc/bluetooth/main.conf /etc/bluetooth/main.conf.bak
   sudo sed -i 's/^#\?Experimental\s*=.*/Experimental = true/' /etc/bluetooth/main.conf
   sudo systemctl restart bluetooth
   ```

   If your build has no `Experimental` line, add it under `[General]`:

   ```ini
   [General]
   Experimental = true
   ```

2. Remove stale bonds (a BR/EDR bond makes BlueZ prefer Classic even
   when the LE bearer is set):

   ```bash
   bluetoothctl remove AA:BB:CC:DD:EE:02
   bluetoothctl remove AA:BB:CC:DD:EE:01
   ```

   `remove` only forgets the device. `not available` means it was not
   bonded; continue. Power-cycle the printer afterwards.

3. Set the bearer and connect. Either use the helper:

   ```bash
   ./bluez-l13-bearer.sh
   ```

   or do it by hand:

   ```bash
   bluetoothctl devices | grep -i l13
   bluetoothctl bearer AA:BB:CC:DD:EE:02 le
   bluetoothctl connect AA:BB:CC:DD:EE:02
   ```

   A successful connect ends with:

   ```text
   [CHG] Device ... ServicesResolved: yes
   Connection successful
   ```

4. Open the web app and press **Connect**.

Restore `Experimental = false` afterwards if you like; the per-device
`PreferredBearer` value is stored in
`/var/lib/bluetooth/<adapter>/<device>/info` and is still honoured.

```bash
sudo cp /etc/bluetooth/main.conf.bak /etc/bluetooth/main.conf
sudo systemctl restart bluetooth
```

To clear the per-device setting:

```bash
bluetoothctl bearer AA:BB:CC:DD:EE:02 last-used
```

## Option B — pair over LE first

BlueZ prefers the bonded bearer. Bonding over LE should make `Connect()`
pick LE without touching `main.conf`:

```bash
bluetoothctl pair AA:BB:CC:DD:EE:02
bluetoothctl info AA:BB:CC:DD:EE:02 | grep -E 'Paired|Bonded'
bluetoothctl connect AA:BB:CC:DD:EE:02
```

`pair` may still print `BREDR.ProfileUnavailable` even when the LE bond
succeeded ([bluez#318](https://github.com/bluez/bluez/issues/318)).
Check the `Paired`/`Bonded` lines; if they are `yes`, connect again.

To undo:

```bash
bluetoothctl remove AA:BB:CC:DD:EE:02
```

## Option C — global LE-only controller

This is the deterministic fallback when A and B keep returning
`BREDR.ProfileUnavailable`, or when the connection resolves but no GATT
services appear.

1. Back up the config and set LE-only mode:

   ```bash
   sudo cp /etc/bluetooth/main.conf /etc/bluetooth/main.conf.bak
   sudo sed -i 's/^#\?ControllerMode\s*=.*/ControllerMode = le/' /etc/bluetooth/main.conf
   grep -n '^ControllerMode' /etc/bluetooth/main.conf
   ```

   If `grep` prints nothing, add the line under `[General]`:

   ```bash
   sudo sed -i '/^\[General\]/a ControllerMode = le' /etc/bluetooth/main.conf
   ```

2. Restart BlueZ and reconnect:

   ```bash
   sudo systemctl restart bluetooth
   bluetoothctl power on
   bluetoothctl remove AA:BB:CC:DD:EE:02
   bluetoothctl remove AA:BB:CC:DD:EE:01
   # power-cycle the printer, then:
   bluetoothctl connect AA:BB:CC:DD:EE:02
   ```

   Look for `Connection successful` and `ServicesResolved: yes`. Then
   reload the web app and press **Connect**.

3. To undo:

   ```bash
   sudo cp /etc/bluetooth/main.conf.bak /etc/bluetooth/main.conf
   sudo systemctl restart bluetooth
   ```

Trade-off: while this is active the adapter does not use Classic
Bluetooth at all. Bluetooth headphones/speakers, a Classic mouse or
keyboard, and car audio stop working. LE devices keep working. Revert and
restart to get Classic back.

## If the browser still fails

- **`No known GATT profile found`** — the link was already down when the
  page asked for services. Make sure no other laptop or phone is
  connected to the printer, remove both addresses, power-cycle the
  printer, and retry.
- **Still `Unknown error when connecting`** — the bearer setting did not
  take. Check `bluetoothctl connect <LE-address>` directly; it must say
  `Connection successful`, not `BREDR.ProfileUnavailable`.
- **Classic SPP fallback** — some Marklife units also expose Classic SPP
  (UUID `0x1101`). If `bluetoothctl info <classic-address>` shows it,
  pair with PIN `1234`, bind it with
  `rfcomm connect /dev/rfcomm0 <classic-address> 1`, and write the same
  L11 byte stream to `/dev/rfcomm0`. This bypasses the BLE bearer
  negotiation entirely.
