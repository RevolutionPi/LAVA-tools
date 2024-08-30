#!/bin/sh

# SPDX-FileCopyrightText: 2024 KUNBUS GmbH
#
# SPDX-License-Identifier: GPL-2.0-or-later

RSDEV="/dev/ttyRS485"
RSBAUD="19200"
SLEEP_TIME="0.3"
LIMIT=50

init() {
    stty -F $RSDEV -echo raw speed $RSBAUD > /dev/null 2>&1
}

get_ack() {
    # shellcheck disable=SC3043
    local expected_ack="$1"
    read -r ack < "$RSDEV"
    ack=$(echo "$ack" | perl -p -e 's/\r//cg')

    if [ "$ack" -ne "$expected_ack" ]; then
        echo "rs485 acknowledgment failed!"
        exit 1
    fi
}

rs485() {
    init
    # shellcheck disable=SC3043
    local mode="$1"
    # shellcheck disable=SC3043
    local cnt=0

    while [ "$cnt" -lt "$LIMIT" ]; do
        if [ "$mode" = "tx" ]; then
            sleep "$SLEEP_TIME"
            echo "$cnt" > "$RSDEV"
            get_ack $((cnt + 1))
            cnt=$((cnt + 1))
        elif [ "$mode" = "rx" ]; then
            get_ack "$cnt"
            cnt=$((cnt + 1))
            sleep "$SLEEP_TIME"
            echo $cnt > "$RSDEV"
        else
            error_msg "Invalid mode: $mode. Use 'tx' or 'rx'."
            exit 1
        fi
    done
}

init
rs485 rx
rs485 tx
