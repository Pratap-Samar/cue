#!/usr/bin/env bash

send_notification() {
    local id="$1"
    local message="$2"

    if ! command -v notify-send >/dev/null 2>&1; then
        echo "Error: notify-send is not installed" >&2
        return 1
    fi

    notify-send -a CUE "Reminder #$id" "$message"
}
