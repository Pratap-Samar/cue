#!/usr/bin/env bash

CUE_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/cue"
REMINDERS_FILE="$CUE_DATA_DIR/reminders"
HISTORY_FILE="$CUE_DATA_DIR/history"

init_storage() {
    mkdir -p "$CUE_DATA_DIR"

    touch "$REMINDERS_FILE"
    touch "$HISTORY_FILE"
}

next_id() {
    if [[ ! -s "$REMINDERS_FILE" ]]; then
        echo "1"
        return
    fi

    awk -F'|' 'BEGIN { max=0 } $1 > max { max=$1 } END { print max+1 }' "$REMINDERS_FILE"
}

list_reminders() {
    init_storage

    echo "CUE"
    echo "────────────────────────────────────────"

    if [[ ! -s "$REMINDERS_FILE" ]]; then
        echo
        echo "No reminders."
        return
    fi

    echo
    echo "TODAY"
    echo

    local pending=0

    while IFS='|' read -r id time message type status recurrence last_triggered; do
        if [[ "$status" == "pending" ]]; then
            local icon="○"
            if [[ "$type" == "recurring" ]]; then
                icon="↻"
            fi
            printf "  #%-2s %-7s %s  %s\n" "$id" "$time" "$icon" "$message"
            pending=$((pending + 1))
        fi
    done < "$REMINDERS_FILE"

    echo
    echo "$pending pending"
}

validate_id() {
    local id="$1"
    if ! [[ "$id" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: invalid ID '$id'" >&2
        return 1
    fi
    return 0
}

parse_recurrence() {
    local input="$1"

    if [[ "$input" =~ ^([1-9][0-9]*)h$ ]]; then
        echo "${BASH_REMATCH[1]}h"
        return 0
    elif [[ "$input" =~ ^day[[:space:]]+([0-9]{1,2}:[0-9]{2})$ ]]; then
        local t="${BASH_REMATCH[1]}"
        local parsed_time
        if ! parsed_time="$(date -d "$t" '+%H:%M' 2>/dev/null)"; then
            echo "Error: invalid time '$t' for daily recurrence" >&2
            return 1
        fi
        echo "day $parsed_time"
        return 0
    fi
    echo "Error: invalid recurrence format '$input'" >&2
    return 1
}

calculate_next_occurrence() {
    local recurrence="$1"
    local now
    now="$(date '+%Y-%m-%d %H:%M')"

    if [[ "$recurrence" =~ ^([1-9][0-9]*)h$ ]]; then
        local hours="${BASH_REMATCH[1]}"
        date -d "$now $hours hours" '+%Y-%m-%d %H:%M'
        return 0
    elif [[ "$recurrence" =~ ^day[[:space:]]+([0-9]{2}:[0-9]{2})$ ]]; then
        local t="${BASH_REMATCH[1]}"
        local candidate
        candidate="$(date -d "$t" '+%Y-%m-%d %H:%M')"
        if [[ "$candidate" < "$now" || "$candidate" == "$now" ]]; then
            date -d "tomorrow $t" '+%Y-%m-%d %H:%M'
        else
            echo "$candidate"
        fi
        return 0
    fi
    return 1
}

normalize_time() {
    local input="$1"
    local parsed_time
    local current_time

    # Try simple HH:MM
    if [[ "$input" =~ ^[0-9]{1,2}:[0-9]{2}$ ]]; then
        if ! parsed_time="$(date -d "$input" '+%Y-%m-%d %H:%M' 2>/dev/null)"; then
            echo "Error: invalid time '$input'" >&2
            return 1
        fi

        current_time="$(date '+%Y-%m-%d %H:%M')"

        if [[ "$parsed_time" < "$current_time" ]]; then
            parsed_time="$(date -d "tomorrow $input" '+%Y-%m-%d %H:%M')"
        fi

        echo "$parsed_time"
        return 0
    fi

    # Try YYYY-MM-DD HH:MM
    if [[ "$input" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{1,2}:[0-9]{2}$ ]]; then
        if ! parsed_time="$(date -d "$input" '+%Y-%m-%d %H:%M' 2>/dev/null)"; then
            echo "Error: invalid date/time '$input'" >&2
            return 1
        fi
        echo "$parsed_time"
        return 0
    fi

    echo "Error: invalid time format '$input'" >&2
    return 1
}

with_lock() {
    init_storage
    if ! command -v flock >/dev/null 2>&1; then
        echo "Error: flock is required for CUE file locking" >&2
        return 1
    fi

    (
        flock -x 200
        "$@"
    ) 200>"$CUE_DATA_DIR/lock"
}

_add_reminder() {
    local time="$1"
    local message="$2"
    local type="${3:-once}"
    local recurrence="$4"
    local id

    id="$(next_id)"
    echo "$id|$time|$message|$type|pending|$recurrence|" >> "$REMINDERS_FILE"
    echo "$id"
}

add_reminder() {
    with_lock _add_reminder "$@"
}

_change_status() {
    local target_id="$1"
    local new_status="$2"
    local temp_file
    local message=""
    local current_status=""

    temp_file="$(mktemp)" || { echo "Error: failed to create temporary file"; return 1; }

    while IFS='|' read -r id time reminder_message type status recurrence last_triggered; do
        if [[ "$id" == "$target_id" ]]; then
            message="$reminder_message"
            current_status="$status"
            if [[ "$status" == "pending" ]]; then
                status="$new_status"
            fi
        fi

        printf "%s|%s|%s|%s|%s|%s|%s\n" \
            "$id" "$time" "$reminder_message" "$type" "$status" "$recurrence" "$last_triggered"
    done < "$REMINDERS_FILE" > "$temp_file"

    if [[ -z "$message" ]]; then
        rm -f "$temp_file"
        echo "Error: reminder #$target_id not found"
        return 1
    elif [[ "$current_status" != "pending" ]]; then
        rm -f "$temp_file"
        echo "Error: reminder #$target_id is already $current_status"
        return 1
    fi

    mv "$temp_file" "$REMINDERS_FILE"
    printf "%s\n" "$message"
    return 0
}

change_status() {
    with_lock _change_status "$@"
}

_log_history() {
    local id="$1"
    local action="$2"
    local message="$3"
    local timestamp

    timestamp="$(date '+%Y-%m-%d %H:%M')"

    printf "%s|%s|%s|%s\n" \
        "$timestamp" "$id" "$action" "$message" >> "$HISTORY_FILE"
}

log_history() {
    with_lock _log_history "$@"
}

show_history() {
    init_storage

    if [[ ! -s "$HISTORY_FILE" ]]; then
        echo "No history."
        return
    fi

    echo "CUE HISTORY"
    echo "────────────────────────────────────────"
    echo

    while IFS='|' read -r timestamp id action message; do
        printf "  %-16s #%s  %-10s %s\n" \
            "$timestamp" "$id" "$action" "$message"
    done < "$HISTORY_FILE"
}

_remove_reminder() {
    local target_id="$1"
    local temp_file
    local message=""

    temp_file="$(mktemp)" || { echo "Error: failed to create temporary file"; return 1; }

    while IFS='|' read -r id time reminder_message type status recurrence last_triggered; do
        if [[ "$id" == "$target_id" ]]; then
            message="$reminder_message"
            continue
        fi

        printf "%s|%s|%s|%s|%s|%s|%s\n" \
            "$id" "$time" "$reminder_message" "$type" "$status" "$recurrence" "$last_triggered"
    done < "$REMINDERS_FILE" > "$temp_file"

    if [[ -z "$message" ]]; then
        rm -f "$temp_file"
        echo "Error: reminder #$target_id not found"
        return 1
    fi

    mv "$temp_file" "$REMINDERS_FILE"
    printf "%s\n" "$message"
    return 0
}

remove_reminder() {
    with_lock _remove_reminder "$@"
}

show_status() {
    init_storage

    local pending=0
    local completed=0
    local recurring=0
    local history_count=0

    while IFS='|' read -r id time message type status recurrence last_triggered; do
        if [[ "$status" == "pending" ]]; then
            pending=$((pending + 1))
        elif [[ "$status" == "completed" ]]; then
            completed=$((completed + 1))
        fi

        if [[ "$type" != "once" ]]; then
            recurring=$((recurring + 1))
        fi
    done < "$REMINDERS_FILE"

    if [[ -s "$HISTORY_FILE" ]]; then
        history_count=$(wc -l < "$HISTORY_FILE")
    fi

    echo "CUE STATUS"
    echo "────────────────────────────────────────"
    echo
    printf "  Pending      %s\n" "$pending"
    printf "  Completed    %s\n" "$completed"
    printf "  Recurring    %s\n" "$recurring"
    printf "  History      %s\n" "$history_count"
}
