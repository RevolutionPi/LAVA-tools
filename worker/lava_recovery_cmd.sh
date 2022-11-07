#!/usr/bin/env bash

if [[ $# -ne 6 ]]; then
  echo "help: $0 <Relaiscard-IP> <Relaiscard-Port> <Power-Relais-No> <USB-Relais-No> <USB-Location> <on|off>"
  echo "    example: $0 192.168.10.1 12345 1 2 2-1.1 on"
  exit
fi

# shellcheck disable=SC2005
absdirname () { echo "$(cd "$(dirname "$1")" && pwd)"; }
SRC_ROOT="$(absdirname "${BASH_SOURCE[0]}")"

# include relaiscard helper functions
# shellcheck disable=SC1090
. "$SRC_ROOT/tools/relaiscard.sh"
# include echo helper
# shellcheck disable=SC1090
. "$SRC_ROOT/tools/echohelper.sh"

IPADDR=$1
PORT=$2
POWER_RELAIS=$3
USB_RELAIS=$4
USB_LOC=$5
CMD=$(echo "$6" | awk '{print tolower ($0)}')

USBPORT=${USB_LOC##*.}
USB_LOC_BASE=${USB_LOC%.*}

RPIBOOT=$(which rpiboot)
UHUBCTL=$(which uhubctl)

if [ ! -x "$RPIBOOT" ]; then
    echoerr "rpiboot missing on this system, please install"
    exit
fi

if [ ! -x "$UHUBCTL" ]; then
    echoerr "uhubctl missing on this system, please install"
    exit
fi

echoinfo "check for availability of relais card"
if ! rc_get_status "$IPADDR" "$PORT"; then
  echoerr "relais card not reachable, stopping script"
  exit
fi

recovery_start() {
  echoinfo "Start Recovery"
        
  rc_set_relais "$IPADDR" "$PORT" "$POWER_RELAIS" 0
  "$UHUBCTL" -l "$USB_LOC_BASE" -p "$USBPORT" -a on
  rc_set_relais "$IPADDR" "$PORT" "$USB_RELAIS" 1
  sleep 0.5

  rc_set_relais "$IPADDR" "$PORT" "$POWER_RELAIS" 1
  sleep 0.5

  # ToDo: check if USB device is available on USB_LOC before using it

  echoinfo "Starting rpiboot on device $USB_LOC"
  $RPIBOOT -p "$USB_LOC"

  # wait with sleep for the RPi mass storage device
  sleep 5

  usb_disk=$(find /sys/devices -iname "${USB_LOC:?}" -exec find {} -iname block -print0 \; 2>/dev/null | xargs -0 ls)

  if [ ! -b "/dev/$usb_disk" ]; then
    echoerr "no storage device found for USB device $USB_LOC"
    exit
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
	  exit
  fi

  echoinfo "Container found (${containers[0]}), adding blockdevice /dev/$usb_disk to container"
  lxc-device -n "${containers[0]}" add /dev/"$usb_disk"
}

recovery_exit() {
    echo "Stop Recovery"

    rc_set_relais "$IPADDR" "$PORT" "$POWER_RELAIS" 0
    "$UHUBCTL" -l "$USB_LOC_BASE" -p "$USBPORT" -a off
    rc_set_relais "$IPADDR" "$PORT" 2 0
    sleep 0.5

    rc_set_relais "$IPADDR" "$PORT" "$POWER_RELAIS" 1
    sleep 0.5
}

case "$CMD" in
    on) recovery_start ;;
    off) recovery_exit ;;
    *) echo "only on and off are supported as parameter for recovery mode" && exit ;;
esac

