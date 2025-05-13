#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2025 KUNBUS GmbH
#
# SPDX-License-Identifier: GPL-2.0-or-later

set -e

# shellcheck disable=SC2005
absdirname () { echo "$(cd "$(dirname "$1")" && pwd)"; }
SRC_ROOT="$(absdirname "${BASH_SOURCE[0]}")"

SSH_HOST_RPI=$1
DEVICE_TYPE=$2
DEVICE_SERIAL=$3
DEVICE_MAC=$4

DEFAULT_USER=pi
DEFAULT_PASS=raspberry

echo "$SSH_HOST_RPI"
echo "$DEVICE_TYPE"
echo "$DEVICE_SERIAL"
echo "$DEVICE_MAC"

# wait for the device to fully reboot
"$SRC_ROOT/lib/utils" wait_for_system_up "$SSH_HOST_RPI"

# let us wait for 20 seconds
sleep 20

# now do the factory reset on the DuT and reboot it afterwards

if [ -f ~/.ssh/known_hosts ]; then
	ssh-keygen -f ~/.ssh/known_hosts -R "$SSH_HOST_RPI"
fi
sshpass -p "$DEFAULT_PASS" ssh-copy-id -o "StrictHostKeyChecking=no" -f -i /sshkey/lava_worker_ed25519.pub "$DEFAULT_USER"@"$SSH_HOST_RPI"
sshpass -p "$DEFAULT_PASS" ssh -o StrictHostKeyChecking=no "$DEFAULT_USER"@"$SSH_HOST_RPI" "sudo cp -r /home/pi/.ssh /root"
sshpass -p "$DEFAULT_PASS" ssh -o StrictHostKeyChecking=no "$DEFAULT_USER"@"$SSH_HOST_RPI" "sudo chown -R root: /root/.ssh"
sshpass -p "$DEFAULT_PASS" ssh -o StrictHostKeyChecking=no "$DEFAULT_USER"@"$SSH_HOST_RPI" "sudo /usr/sbin/revpi-factory-reset \"$DEVICE_TYPE\" \"$DEVICE_SERIAL\" \"$DEVICE_MAC\" && sudo reboot"

# give the DUT time to initiate the reboot as it doesn't necessarily happen *instantly*
sleep 10

exit 0
