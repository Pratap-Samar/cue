#!/usr/bin/env bash

SCHEDULER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCHEDULER_DIR/notification.sh"

_check_reminders() {
    if [[ ! -s "$REMINDERS_FILE" ]]; then
        return 0
    fi

    local temp_file
    temp_file="$(mktemp)" || { echo "Error: failed to create temporary file" >&2; return 1; }

    local now
    now="$(date '+%Y-%m-%d %H:%M')"

    while IFS='|' read -r id time message type status recurrence last_triggered; do
        if [[ -z "$id" || -z "$time" || -z "$message" || -z "$type" || -z "$status" ]]; then
            echo "Warning: skipping malformed reminder record" >&2
        elif [[ "$status" == "pending" ]]; then
            if [[ "$time" < "$now" || "$time" == "$now" ]]; then
                if [[ "$type" == "recurring" ]]; then
                    if send_notification "$id" "$message"; then
                        last_triggered="$now"
                        time="$(calculate_next_occurrence "$recurrence")"
                    fi
                elif [[ "$type" == "once" ]]; then
                    if [[ -z "$last_triggered" ]]; then
                        if send_notification "$id" "$message"; then
                            last_triggered="$now"
                        fi
                    fi
                fi
            fi
        fi

        printf "%s|%s|%s|%s|%s|%s|%s\n" \
            "$id" "$time" "$message" "$type" "$status" "$recurrence" "$last_triggered"
    done < "$REMINDERS_FILE" > "$temp_file"

    mv "$temp_file" "$REMINDERS_FILE"
}

check_reminders() {
    with_lock _check_reminders
}
