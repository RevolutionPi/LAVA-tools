#!/usr/bin/env bash

__number_to_onoff () {
  [ "$1" -eq 0 ] && echo "off" || echo "on"
}

__send_cmd () {
  echo "$3" | nc -w 3 -q 1 "$1" "$2"
  return $?
}

# parameters:
#   $1 ip address of the relaiscard
#   $2 port of the relaiscard
#   $3 which relais to set as number (1 to max relais number)
#   $4 value to set relais to as number (0, 1)
rc_set_relais () {
  if [[ $# != 4 ]]; then
    echo "Error: wrong number of function parameters"
    return 1
  fi

  __send_cmd "$1" "$2" "SR $3 $(__number_to_onoff "$4")" &>/dev/null

  return $?
}

# parameters:
#   $1 ip address of the relaiscard
#   $2 port of the relaiscard
#   $3 which gpio to set; as number (1 to max gpio number)
#   $4 value to set relais to; as number (0, 1)
rc_set_gpio () {
  if [[ $# != 4 ]]; then
    echo "Error: wrong number of function parameters"
    return 1
  fi

  __send_cmd "$1" "$2" "SO $3 $(__number_to_onoff "$4")" &>/dev/null

  return $?
}

# parameters:
#   $1 ip address of the relaiscard
#   $2 port of the relaiscard
rc_get_status () {
  if [[ $# != 2 ]]; then
    echo "Error: wrong number of function parameters"
    return 1
  fi

  __send_cmd "$1" "$2" "ST" &>/dev/null

  return $?
}

