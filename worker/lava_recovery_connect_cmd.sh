#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2023 KUNBUS GmbH
#
# SPDX-License-Identifier: GPL-2.0-or-later

TIME_SLEEP_RELAY_ON=1
TIME_SLEEP_RELAY_OFF=5
TIME_SLEEP_WAIT_RPIBOOT=5

USB_LOC=$1
CMD=$(echo "$2" | awk '{print tolower ($0)}')

USBPORT=${USB_LOC##*.}
USB_LOC_BASE=${USB_LOC%.*}

RPIBOOT=$(which rpiboot)
UHUBCTL=$(which uhubctl)

# shellcheck disable=SC2005
absdirname () { echo "$(cd "$(dirname "$1")" && pwd)"; }
# shellcheck disable=SC1090
SRC_ROOT="$(absdirname "${BASH_SOURCE[0]}")"
# include echo helper
# shellcheck disable=SC1091
. "$SRC_ROOT/tools/echohelper.sh"

get_revpi_type() {
  grep -zm1 'kunbus,revpi-' /proc/device-tree/compatible | tr -d '\0' | cut -d',' -f2
}

get_relay_var() {
  local revpi_type="$1"
  case "$revpi_type" in
  revpi-connect4)
    echo "RevPiOutput"
    ;;
  revpi-connect*)
    echo "RevPiLED"
    ;;
  *)
    return 1
    ;;
  esac

  return 0
}

get_relay_bit() {
  local revpi_type="$1"
  case "$revpi_type" in
  revpi-connect4)
    echo 0
    ;;
  revpi-connect*)
    echo 6
    ;;
  *)
    return 1
    ;;
  esac

  return 0
}

revpi_unset_relay() {
  local revpi_type="$1"
  local relay_var="$2"
  local relay_bit="$3"
  local relay_val
  # Read value
  relay_val=$(piTest -1 -q -r "$relay_var")
  if [ "$revpi_type" = "revpi-connect4" ]; then
    # For RevPi Connect4, clear the specified bit (set to 0)
    relay_val=$((relay_val & ~(1 << relay_bit)))
  else
    # For standard RevPi Connect, set the specified bit (set to 1)
    relay_val=$((relay_val | (1 << relay_bit)))
  fi
  piTest -w "$relay_var","$relay_val"
}

revpi_set_relay() {
  local revpi_type="$1"
  local relay_var="$2"
  local relay_bit="$3"
  local relay_val
  # Read value
  relay_val=$(piTest -1 -q -r "$relay_var")
  if [ "$revpi_type" = "revpi-connect4" ]; then
    # For RevPi Connect4, set the specified bit (set to 1)
    relay_val=$((relay_val | (1 << relay_bit)))
  else
    # For standard RevPi Connect, clear the specified bit (set to 0)
    relay_val=$((relay_val & ~(1 << relay_bit)))
  fi
  
  piTest -w "$relay_var","$relay_val"
}

uhubctl_cmd() {
  local action="$1"
  local revpi_type
  local relay_var
  local relay_bit
  revpi_type=$(get_revpi_type)
  relay_var=$(get_relay_var "$revpi_type")
  relay_var_rc=$?
  relay_bit=$(get_relay_bit "$revpi_type")
  relay_bit_rc=$?

  if [ "$relay_var_rc" -ne 0 ] || [ "$relay_bit_rc" -ne 0 ]; then
    printf "Don't know how to control power with '%s'\n" "$revpi_type" >&2
    exit 1
  fi

  echoinfo "Executing uhubctl command: $action"
  revpi_unset_relay "$revpi_type" "$relay_var" "$relay_bit"
  sleep "$TIME_SLEEP_RELAY_OFF"
  "$UHUBCTL" -l "$USB_LOC_BASE" -p "$USBPORT" -a "$action"
  if [ "$revpi_type" = "revpi-connect" ]; then
    "$UHUBCTL" -l "$USB_LOC_BASE" -p "$((USBPORT + 1))" -a "$action"
  fi
  sleep "$TIME_SLEEP_RELAY_OFF"
  revpi_set_relay "$revpi_type" "$relay_var" "$relay_bit"
  sleep "$TIME_SLEEP_RELAY_ON"
}

recovery_start() {
  echoinfo "Start Recovery"
  uhubctl_cmd "on"

  # ToDo: check if USB device is available on USB_LOC before using it

  echoinfo "Starting rpiboot on device $USB_LOC"
  "$RPIBOOT" -p "$USB_LOC"

  # wait with sleep for the RPi mass storage device
  sleep "$TIME_SLEEP_WAIT_RPIBOOT"

  usb_disk=$(find /sys/devices -iname "${USB_LOC:?}" -exec find {} -iname block -print0 \; 2>/dev/null | xargs -0 ls)

  if [ ! -b "/dev/$usb_disk" ]; then
    echoerr "no storage device found for USB device $USB_LOC"
    exit 1
  fi

  echoinfo "RPi mass storage added as /dev/$usb_disk"
  echoinfo "Looking for a running container"

  # now get this device into the container, get containers,  one per line and only running ones
  IFS=$'\n' read -r -d '' -a containers < <( lxc-ls -1 --running --filter 'lxc\-[a-zA-Z]*\-[0-9]*')

  # If there is more than one running container, we don't know which container we
  # can or should use (ToDo: check if LAVA can substitute the JOB_ID in a jinja2
  # file). We exit for now, if we have more than one running container.
  if [ ${#containers[@]} != 1 ]; then
  	echoerr "no or too many running LXC containers found, aborting"
	  exit 1
  fi

  echoinfo "Container found (${containers[0]}), adding blockdevice /dev/$usb_disk to container"
  lxc-device -n "${containers[0]}" add "/dev/$usb_disk"
}

recovery_exit() {
    echo "Stop Recovery"

    uhubctl_cmd "off"
}

# Main Script

if [[ $# -ne 2 ]]; then
  echo "help: $0 <USB-Location> <on|off>"
  echo "    example: $0 1-1.2 on"
  exit 1
fi

if [ ! -x "$RPIBOOT" ]; then
    echoerr "rpiboot missing on this system, please install"
    exit 1
fi

if [ ! -x "$UHUBCTL" ]; then
    echoerr "uhubctl missing on this system, please install"
    exit 1
fi

case "$CMD" in
    on) recovery_start ;;
    off) recovery_exit ;;
    *) echo "only on and off are supported as parameter for recovery mode" && exit 1 ;;
esac
