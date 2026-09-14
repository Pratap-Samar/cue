#!/usr/bin/env bash

set -euo pipefail

VERSION="0.1.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/storage.sh"

case "${1:-help}" in
    add)
    if [[ $# -lt 3 ]]; then
        echo "Usage: cue add <message> <time> | --every <interval>" >&2
        exit 1
    fi

    MESSAGE="$2"
    if [[ -z "$MESSAGE" ]]; then
        echo "Error: message cannot be empty" >&2
        exit 1
    fi

    if [[ "$MESSAGE" == *"|"* ]]; then
        echo "Error: message cannot contain '|'" >&2
        exit 1
    fi

    if [[ "$3" == "--every" ]]; then
        if [[ $# -lt 4 ]]; then
            echo "Error: missing recurrence pattern" >&2
            exit 1
        fi

        RECURRENCE_INPUT="$4"
        if [[ "$4" == "day" ]]; then
            if [[ $# -ne 5 ]]; then
                echo "Error: missing time for daily recurrence" >&2
                exit 1
            fi
            RECURRENCE_INPUT="day $5"
        fi

        if ! RECURRENCE="$(parse_recurrence "$RECURRENCE_INPUT")"; then
            exit 1
        fi

        TIME="$(calculate_next_occurrence "$RECURRENCE")"
        TYPE="recurring"
    else
        TIME_INPUT="$3"
        if [[ "$TIME_INPUT" == *"|"* ]]; then
            echo "Error: time cannot contain '|'" >&2
            exit 1
        fi
        if ! TIME="$(normalize_time "$TIME_INPUT")"; then
            exit 1
        fi
        RECURRENCE=""
        TYPE="once"
    fi

    if ! ID="$(add_reminder "$TIME" "$MESSAGE" "$TYPE" "$RECURRENCE")"; then
        echo "$ID" >&2
        exit 1
    fi

    echo "Added reminder #$ID"
    echo "  $TIME — $MESSAGE"
    ;;

    list)
        list_reminders
        ;;

    --version|-v)
        echo "cue $VERSION"
        ;;

    help|--help|-h)
        echo "CUE - a minimal Linux reminder utility"
        echo
        echo "Usage:"
        echo "  cue add <message> <time>"
        echo "  cue add <message> --every 2h"
        echo "  cue add <message> --every day HH:MM"
        echo "  cue list"
        echo "  cue done <id>"
        echo "  cue cancel <id>"
        echo "  cue remove <id>"
        echo "  cue status"
        echo "  cue history"
        echo "  cue check (internal scheduler)"
        echo "  cue install      Install the CUE cron scheduler"
        echo "  cue uninstall    Remove the CUE cron scheduler"
        echo "  cue help"
        ;;

    done)
    if [[ $# -ne 2 ]]; then
        echo "Usage: cue done <id>" >&2
        exit 1
    fi

    if ! validate_id "$2"; then exit 1; fi
    init_storage

    if ! MESSAGE="$(change_status "$2" "completed")"; then
        echo "$MESSAGE" >&2
        exit 1
    fi

    log_history "$2" "completed" "$MESSAGE"
    echo "Completed reminder #$2"
    ;;

    cancel)
    if [[ $# -ne 2 ]]; then
        echo "Usage: cue cancel <id>" >&2
        exit 1
    fi

    if ! validate_id "$2"; then exit 1; fi
    init_storage

    if ! MESSAGE="$(change_status "$2" "cancelled")"; then
        echo "$MESSAGE" >&2
        exit 1
    fi

    log_history "$2" "cancelled" "$MESSAGE"
    echo "Cancelled reminder #$2"
    ;;

    history)
    show_history
    ;;

    remove)
    if [[ $# -ne 2 ]]; then
        echo "Usage: cue remove <id>" >&2
        exit 1
    fi

    if ! validate_id "$2"; then exit 1; fi
    init_storage

    if ! MESSAGE="$(remove_reminder "$2")"; then
        echo "$MESSAGE" >&2
        exit 1
    fi

    log_history "$2" "removed" "$MESSAGE"
    echo "Removed reminder #$2"
    ;;

    check)
        source "$SCRIPT_DIR/lib/scheduler.sh"
        check_reminders
        ;;

    install)
        mkdir -p "$HOME/.local/bin"

        # Create a robust wrapper script pointing to the actual repo
        cat << EOF > "$HOME/.local/bin/cue"
#!/usr/bin/env bash
exec "$SCRIPT_DIR/cue" "\$@"
EOF
        chmod +x "$HOME/.local/bin/cue"

        CRON_LINE="* * * * * $HOME/.local/bin/cue check >/dev/null 2>&1 # CUE: scheduler"

        if crontab -l 2>/dev/null | grep -qF "# CUE: scheduler"; then
            echo "CUE cron job already installed."
        else
            (crontab -l 2>/dev/null || true; echo "$CRON_LINE") | crontab -
            echo "CUE cron job installed."
        fi

        echo
        echo "CUE installed successfully."
        if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
            echo "Warning: $HOME/.local/bin is not in your PATH."
            echo "To use the 'cue' command interactively, you must add it to your shell configuration."
            echo
            echo "For a temporary current-session fix, run:"
            echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
            echo
            echo "For a persistent fix, append the above line to your ~/.bashrc or ~/.zshrc."
        else
            echo "You can now use the 'cue' command from anywhere."
        fi
        ;;

    uninstall)
        if crontab -l 2>/dev/null | grep -qF "# CUE: scheduler"; then
            # Reinstall crontab without the CUE line, protecting against empty result
            new_cron="$(crontab -l 2>/dev/null | grep -vF "# CUE: scheduler" || true)"
            if [[ -z "$new_cron" ]]; then
                crontab -r 2>/dev/null || true
            else
                echo "$new_cron" | crontab -
            fi
            echo "CUE cron job removed."
        else
            echo "CUE cron job is not installed."
        fi

        if [[ -f "$HOME/.local/bin/cue" ]]; then
            rm -f "$HOME/.local/bin/cue"
        fi
        ;;

    status)
    show_status
    ;;

    *)
        echo "cue: unknown command '$1'" >&2
        echo "Run 'cue help' for usage." >&2
        exit 1
        ;;
esac
