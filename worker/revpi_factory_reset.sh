#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2025 KUNBUS GmbH
#
# SPDX-License-Identifier: GPL-2.0-or-later

set -e
HOME="$(getent passwd "$(id -un)" | cut -d: -f6)"
export HOME

# shellcheck disable=SC2005
absdirname () { echo "$(cd "$(dirname "$1")" && pwd)"; }
SRC_ROOT="$(absdirname "${BASH_SOURCE[0]}")"

SSH_HOST_RPI=$1
DEVICE_TYPE=$2
DEVICE_SERIAL=$3
DEVICE_MAC=$4

DEFAULT_USER=pi
DEFAULT_PASS=raspberry
DEFAULT_SSH_ARGS="-o StrictHostKeyChecking=no"
SSH_REMOTE="$DEFAULT_USER@$SSH_HOST_RPI"

echo "Remote host: $SSH_HOST_RPI"
echo "Device type: $DEVICE_TYPE"
echo "Device serial: $DEVICE_SERIAL"
echo "Device mac: $DEVICE_MAC"

echo "Waiting for device to be reachable..."
"$SRC_ROOT/lib/utils" wait_for_system_up "$SSH_HOST_RPI"

# Waiting is required because the system does some things on first boot like
# resizing the rootfs or generating the ssh keys, which takes some time. Also
# give some time for the system to settle.
echo "Device online. Waiting 20 seconds to finish first boot before setting up ssh"
sleep 20

# now do the factory reset on the DuT and reboot it afterwards
if [ -f ~/.ssh/known_hosts ]; then
	ssh-keygen -f ~/.ssh/known_hosts -R "$SSH_HOST_RPI"
fi

# shellcheck disable=SC2086
sshpass -p "$DEFAULT_PASS" \
	ssh $DEFAULT_SSH_ARGS "$SSH_REMOTE" \
	"if [ ! -d ~/.ssh ]; then ( umask 077 && mkdir ~/.ssh ); fi"

echo "Copying ssh key to DUT"
# shellcheck disable=SC2086
sshpass -p "$DEFAULT_PASS" \
	ssh-copy-id $DEFAULT_SSH_ARGS \
		-f \
		-i /sshkey/lava_worker_ed25519.pub \
		"$SSH_REMOTE"
# shellcheck disable=SC2086
sshpass -p "$DEFAULT_PASS" \
	ssh $DEFAULT_SSH_ARGS "$SSH_REMOTE" "sudo cp -r /home/pi/.ssh /root"
# shellcheck disable=SC2086
sshpass -p "$DEFAULT_PASS" \
	ssh $DEFAULT_SSH_ARGS "$SSH_REMOTE" "sudo chown -R root: /root/.ssh"

echo "Running factory reset"
# shellcheck disable=SC2086
sshpass -p "$DEFAULT_PASS" \
	ssh $DEFAULT_SSH_ARGS "$SSH_REMOTE" \
		"sudo /usr/sbin/revpi-factory-reset \"$DEVICE_TYPE\" \"$DEVICE_SERIAL\" \"$DEVICE_MAC\""

echo "Rebooting the device"
# manually verify the return code here instead of letting "set -e" fail on any code > 0
# shellcheck disable=SC2086
sshpass -p "$DEFAULT_PASS" \
	ssh $DEFAULT_SSH_ARGS "$SSH_REMOTE" "sudo reboot" || rc=$? && rc=0
if [ "$rc" -eq 255 ]; then
	# if the reboot is immediately in progress instead of waiting for a second,
	# ssh will return 255 as the exit code. this is okay and shouldn't lead to
	# the script failing
	:
elif [ "$rc" -gt 0 ]; then
	printf "Error while calling 'reboot' on DUT\n" >&2
	exit 1
fi

# give the DUT time to initiate the reboot as it doesn't necessarily happen *instantly*
sleep 10

exit 0
