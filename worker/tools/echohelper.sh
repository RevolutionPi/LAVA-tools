#!/usr/bin/env bash

echoinfo () {
  printf "\e[32mINFO:\e[0m  %s\n" "$*" >&2;
}

echoerr () { 
  printf "\e[31mERROR:\e[0m %s\n" "$*" >&2;
}

