#!/usr/bin/env bash

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


revpi_unset_relay() {
  # Read value
  RevPiLED_VAL=$(piTest -1 -q -r RevPiLED)
  # Set bit 6 (bit 6 -> Relay output)
  RevPiLED_VAL=$((RevPiLED_VAL | (1 << 6)))
  piTest -w RevPiLED,$RevPiLED_VAL
}

revpi_set_relay() {
  # Read value
  RevPiLED_VAL=$(piTest -1 -q -r RevPiLED)
  # Clear bit 6 (bit 6 -> Relay output)
  RevPiLED_VAL=$((RevPiLED_VAL & (0 << 6)))
  piTest -w RevPiLED,$RevPiLED_VAL
}

uhubctl_cmd() {
  action="$1"
  echoinfo "Executing uhubctl command: $action"
  revpi_unset_relay
  sleep "$TIME_SLEEP_RELAY_OFF"
  "$UHUBCTL" -l "$USB_LOC_BASE" -p "$USBPORT" -a "$action"
  sleep "$TIME_SLEEP_RELAY_OFF"
  revpi_set_relay
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
