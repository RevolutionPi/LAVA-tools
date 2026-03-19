#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 KUNBUS GmbH
#
# SPDX-License-Identifier: GPL-2.0-or-later

# shellcheck disable=SC2005
absdirname () { echo "$(cd "$(dirname "$1")" && pwd)"; }
SRC_ROOT="$(absdirname "${BASH_SOURCE[0]}")"

SSH_USER="root"
SSH_ARGS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o BatchMode=yes -o ConnectTimeout=10)
SSH_REMOTE=""
STATE_DIR="/var/lib/revpi-eth-rename"
RESULT_FILE="${STATE_DIR}/result"
REVPI_UDEV_RULES="/usr/lib/udev/rules.d/50-revpi.rules"
SHUTDOWN_TIMEOUT=120
BOOT_TIMEOUT=120
IFACE_FAIL=""
# neither pass nor fail: check_ifaces() couldn't read the DUT at all
CHECK_ERROR=2
ITERATIONS=20
EXPECTED_IFACES=()
SSH_HOST=""
OK=0
NOK=0

usage() {
    printf "Usage: %s -H <host> [-n <iterations>] [-i <interfaces>]\n" \
        "$0" >&2
    exit 1
}

while getopts "H:n:i:h" o; do
    case "$o" in
    H) SSH_HOST="${OPTARG}" ;;
    n) ITERATIONS="${OPTARG}" ;;
    i) read -r -a EXPECTED_IFACES <<< "${OPTARG}" ;;
    h|*) usage ;;
    esac
done

if [ -z "$SSH_HOST" ]; then
    printf "Error: SSH host is required (-H <host>)\n" >&2
    usage
fi

if ! [[ "$ITERATIONS" =~ ^[1-9][0-9]*$ ]]; then
    printf "Error: the number of iterations must be a positive integer\n" >&2
    usage
fi
SSH_REMOTE="$SSH_USER@$SSH_HOST"


printf "Remote host: %s\n" "$SSH_HOST"
printf "Iterations: %s\n" "$ITERATIONS"

# List the ethernet interfaces the DUT currently exposes.
list_dut_ifaces() {
    local ifaces=""
    local rc=0

    # tr runs last so the exit code only reports a broken connection and not
    # a grep that found nothing
    # shellcheck disable=SC2029
    ifaces=$(ssh "${SSH_ARGS[@]}" "$SSH_REMOTE" \
        "find /sys/class/net -mindepth 1 -maxdepth 1 -printf '%f\\0' \
            | grep -zE '^(eth|lan)[0-9]+\$' | tr '\\0' '\\n'")
    rc=$?
    if [ "$rc" -ne 0 ]; then
        printf "Error: failed to list the interfaces of the DUT (rc=%d)\n" \
            "$rc" >&2
        return 1
    fi

    printf "%s\n" "$ifaces"

    return 0
}

# The ethernet ports are named lanX on Trixie and ethX before that.
detect_expected_ifaces() {
    local compatible=""
    local prefix="eth"
    local ports=2
    local port=""
    local rc=0

    # A missing rule file must not look like a failed connection.
    # shellcheck disable=SC2029
    ssh "${SSH_ARGS[@]}" "$SSH_REMOTE" \
        "[ -f $REVPI_UDEV_RULES ] \
            && grep -q 'NAME=\"lan0\"' $REVPI_UDEV_RULES"
    rc=$?
    case "$rc" in
    0)
        prefix="lan"
        ;;
    1)
        # no rule file or no match: the DUT still uses the ethX scheme
        ;;
    *)
        printf "Error: failed to read the udev rules of the DUT (rc=%d)\n" \
            "$rc" >&2
        exit 1
        ;;
    esac

    compatible=$(ssh "${SSH_ARGS[@]}" "$SSH_REMOTE" \
        "grep -aoE 'kunbus,revpi-[a-z0-9-]+' \
            /sys/firmware/devicetree/base/compatible | head -1")
    rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$compatible" ]; then
        printf "Error: failed to detect the model of the DUT (rc=%d)\n" \
            "$rc" >&2
        exit 1
    fi

    case "$compatible" in
    kunbus,revpi-core*)
        ports=1
        ;;
    *)
        ;;
    esac

    printf "Device: %s\n" "$compatible"

    EXPECTED_IFACES=()
    for port in $(seq 0 $((ports - 1))); do
        EXPECTED_IFACES+=("${prefix}${port}")
    done
}

# Is the first argument among the remaining ones?
list_contains() {
    local needle="$1"
    local item=""

    shift
    for item in "$@"; do
        [ "$item" = "$needle" ] && return 0
    done

    return 1
}

check_ifaces() {
    local -a present=()
    local -a missing=()
    local -a unexpected=()
    local listed=""
    local iface=""

    IFACE_FAIL=""
    listed=$(list_dut_ifaces) || return "$CHECK_ERROR"
    [ -n "$listed" ] && mapfile -t present <<< "$listed"

    for iface in "${EXPECTED_IFACES[@]}"; do
        list_contains "$iface" "${present[@]}" || missing+=("$iface")
    done

    for iface in "${present[@]}"; do
        list_contains "$iface" "${EXPECTED_IFACES[@]}" || unexpected+=("$iface")
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        IFACE_FAIL="expected interface(s) missing: ${missing[*]}"
    fi
    if [ "${#unexpected[@]}" -gt 0 ]; then
        IFACE_FAIL="${IFACE_FAIL:+$IFACE_FAIL, }"
        IFACE_FAIL="${IFACE_FAIL}unexpected interface(s) found: ${unexpected[*]}"
    fi

    [ -z "$IFACE_FAIL" ]
}

# Put the state of the run on the DUT. A test action can then tell a run that
# finished from one that gave up half way through, whatever the reason was.
store_result() {
    # shellcheck disable=SC2029
    ssh "${SSH_ARGS[@]}" "$SSH_REMOTE" \
        "mkdir -p $STATE_DIR \
            && echo 'total=$ITERATIONS completed=$((OK + NOK)) failures=$NOK' \
                > $RESULT_FILE"
}

reboot_dut() {
    local out=""
    local rc=0

    out=$(ssh "${SSH_ARGS[@]}" "$SSH_REMOTE" "shutdown -r now" 2>&1)
    rc=$?
    # ssh returns 255 if the DUT tears the connection down before ssh does,
    # which happens when the reboot is immediately in progress
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 255 ]; then
        printf "Error while rebooting DUT (rc=%d): %s\n" "$rc" "$out" >&2
        exit 1
    fi
    if ! timeout "$SHUTDOWN_TIMEOUT" \
        "$SRC_ROOT/lib/utils" wait_for_reboot "$SSH_HOST"; then
        printf "Error: DUT didn't reboot within %d seconds\n" \
            "$SHUTDOWN_TIMEOUT" >&2
        exit 1
    fi
    if ! timeout "$BOOT_TIMEOUT" \
        "$SRC_ROOT/lib/utils" wait_for_ssh "$SSH_REMOTE"; then
        printf "Error: DUT didn't come back within %d seconds\n" \
            "$BOOT_TIMEOUT" >&2
        exit 1
    fi
}

if ! store_result; then
    printf "Error: failed to create the result file on the DUT\n" >&2
    exit 1
fi
trap store_result EXIT

if [ "${#EXPECTED_IFACES[@]}" -eq 0 ]; then
    detect_expected_ifaces
fi
printf "Expected interfaces: %s\n" "${EXPECTED_IFACES[*]}"

printf "Running eth rename stability test (%s iterations), please wait...\n" \
    "$ITERATIONS"

for i in $(seq 1 "$ITERATIONS"); do
    check_ifaces
    rc=$?
    if [ "$rc" -eq "$CHECK_ERROR" ]; then
        printf "Error: could not check the interfaces on run %d\n" "$i" >&2
        exit 1
    elif [ "$rc" -eq 0 ]; then
        OK=$((OK + 1))
        printf "Run %d/%d: OK (good=%d bad=%d)\n" \
            "$i" "$ITERATIONS" "$OK" "$NOK"
    else
        NOK=$((NOK + 1))
        printf "Run %d/%d: FAIL - %s (good=%d bad=%d)\n" \
            "$i" "$ITERATIONS" "$IFACE_FAIL" "$OK" "$NOK"
    fi

    if ! store_result; then
        printf "Error: failed to update the result on the DUT\n" >&2
        exit 1
    fi

    if [ "$i" -lt "$ITERATIONS" ]; then
        reboot_dut
    fi
done

printf "=== Result: good=%d bad=%d / %s ===\n" "$OK" "$NOK" "$ITERATIONS"

exit 0
