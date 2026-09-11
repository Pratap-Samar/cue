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

    while IFS='|' read -r id time message type status; do
        if [[ "$status" == "pending" ]]; then
            printf "  %-7s ○  %s\n" "$time" "$message"
            pending=$((pending + 1))
        fi
    done < "$REMINDERS_FILE"

    echo
    echo "$pending pending"
}

mark_done() {
    local target_id="$1"
    local temp_file
    local message=""

    temp_file="$(mktemp)"

    while IFS='|' read -r id time reminder_message type status; do
        if [[ "$id" == "$target_id" ]]; then
            message="$reminder_message"
            status="completed"
        fi

        printf "%s|%s|%s|%s|%s\n" \
            "$id" "$time" "$reminder_message" "$type" "$status"
    done < "$REMINDERS_FILE" > "$temp_file"

    mv "$temp_file" "$REMINDERS_FILE"

    printf "%s\n" "$message"
}

log_history() {
    local id="$1"
    local action="$2"
    local message="$3"
    local timestamp

    timestamp="$(date '+%Y-%m-%d %H:%M')"

    printf "%s|%s|%s|%s\n" \
        "$timestamp" "$id" "$action" "$message" >> "$HISTORY_FILE"
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

remove_reminder() {
    local target_id="$1"
    local temp_file
    local found=0

    temp_file="$(mktemp)"

    while IFS='|' read -r id time message type status; do
        if [[ "$id" == "$target_id" ]]; then
            found=1
            continue
        fi

        printf "%s|%s|%s|%s|%s\n" \
            "$id" "$time" "$message" "$type" "$status"
    done < "$REMINDERS_FILE" > "$temp_file"

    mv "$temp_file" "$REMINDERS_FILE"

    return $((!found))
}

show_status() {
    init_storage

    local pending=0
    local completed=0
    local recurring=0
    local history_count=0

    while IFS='|' read -r id time message type status; do
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