#!/usr/bin/env bash

send_notification() {
    local id="$1"
    local message="$2"

    if ! command -v notify-send >/dev/null 2>&1; then
        echo "Error: notify-send is not installed" >&2
        return 1
    fi

    if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        local uid
        uid="$(id -u)"
        local bus_path="${CUE_TEST_BUS_PATH:-/run/user/$uid/bus}"

        if [[ -S "$bus_path" || ( -e "$bus_path" && -n "${CUE_TEST_BUS_PATH:-}" ) ]]; then
            export DBUS_SESSION_BUS_ADDRESS="unix:path=$bus_path"
        else
            echo "Error: No D-Bus session bus found" >&2
            return 1
        fi
    fi

    notify-send -a CUE "Reminder #$id" "$message"
}
