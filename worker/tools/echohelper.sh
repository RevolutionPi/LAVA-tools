#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022 KUNBUS GmbH
#
# SPDX-License-Identifier: GPL-2.0-or-later

echoinfo () {
  printf "\e[32mINFO:\e[0m  %s\n" "$*";
}

echoerr () { 
  printf "\e[31mERROR:\e[0m %s\n" "$*" >&2;
}

