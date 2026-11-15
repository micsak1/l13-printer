#!/usr/bin/env bash
#
# Set BlueZ's per-device preferred bearer to LE for a dual-mode
# Marklife/SilverCrest printer, then try a GATT connect.
#
# Why: BlueZ's Device1.Connect() tries the printer's Classic BR/EDR
# side first. This printer has no usable BR/EDR profile, so BlueZ
# returns org.bluez.Error.BREDR.ProfileUnavailable. Chromium does not
# map that error and shows "Unknown error when connecting to the
# device." PreferredBearer=le makes BlueZ use the LE bearer instead.
#
# The property is experimental, so /etc/bluetooth/main.conf must have
# Experimental = true under [General] and bluetoothd restarted.
# This script never edits that file; it only reports what is missing.

set -euo pipefail

# Usage:
#   ./bluez-l13-bearer.sh                # auto-detect the L13_..._BLE device
#   ./bluez-l13-bearer.sh L13_           # match a different name substring
#   ./bluez-l13-bearer.sh AA:BB:CC:DD:EE:02   # use an explicit address
ADDR_ARG=""
if [[ "${1:-}" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
  ADDR_ARG="$1"
else
  NAME_PATTERN="${1:-L13_}"
fi

find_printer() {
  # Prefer the LE identity: it advertises the Marklife vendor UUID and
  # usually carries the _BLE name suffix.
  local addr
  addr=$(bluetoothctl devices 2>/dev/null | awk -v pat="$NAME_PATTERN" '
    $0 ~ pat && /_BLE/ { print $2; exit }
  ')
  if [ -z "$addr" ]; then
    addr=$(bluetoothctl devices 2>/dev/null | awk -v pat="$NAME_PATTERN" '
      $0 ~ pat { print $2; exit }
    ')
  fi
  printf '%s' "$addr"
}

if ! command -v bluetoothctl >/dev/null 2>&1; then
  echo "bluetoothctl not found. Install bluez." >&2
  exit 1
fi

if [ -n "$ADDR_ARG" ]; then
  addr="$ADDR_ARG"
else
  echo "Scanning for the printer (10s)..."
  timeout 10 bluetoothctl scan on >/dev/null 2>&1 || true
  addr=$(find_printer)
fi
if [ -z "$addr" ]; then
  cat >&2 <<EOF
No printer matching ${NAME_PATTERN} found.

Power the printer on (hold the button until the LED comes on) and run:

  bluetoothctl scan on

in another terminal until L13_..._BLE appears, then run this script again.
The printer sleeps after a few minutes of inactivity.

You can also pass the address explicitly:

  ./bluez-l13-bearer.sh AA:BB:CC:DD:EE:02
EOF
  exit 1
fi

echo "Printer: $addr"
bluetoothctl info "$addr" 2>/dev/null | sed -n '1,14p' || true

echo
echo "Setting PreferredBearer=le ..."
bearer_out=$(bluetoothctl bearer "$addr" le 2>&1) || true
printf '%s\n' "$bearer_out"

if printf '%s' "$bearer_out" | grep -qiE 'failed|not available|unknown|invalid|not found|does not exist'; then
  cat <<EOF

Could not set PreferredBearer.

This property is behind BlueZ's experimental API. Add this to
/etc/bluetooth/main.conf under [General]:

    Experimental = true

then restart BlueZ:

    sudo systemctl restart bluetooth

Run this script again afterwards. You can set Experimental back to
false later; the per-device PreferredBearer value is stored with the
device and still honoured.

If you prefer not to touch the BlueZ config, either use Chrome on
Android (Android connects over LE directly) or set the global
ControllerMode = le (see l13/LINUX.md for the trade-off).
EOF
  exit 2
fi

echo
echo "Trying a GATT connect ..."
connect_out=$(timeout 25 bluetoothctl connect "$addr" 2>&1) || true
printf '%s\n' "$connect_out"

if printf '%s' "$connect_out" | grep -qiE 'failed to connect|not available|not connected'; then
  echo
  echo "Connect failed. Check the printer is awake and not connected to a phone." >&2
  exit 3
fi

echo
echo "Connected. Open the web app and press Connect."
