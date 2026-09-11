#!/usr/bin/env bash

set -euo pipefail

VERSION="0.1.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/storage.sh"

case "${1:-help}" in
    add)
    if [[ $# -ne 3 ]]; then
        echo "Usage: cue add <message> <time>"
        exit 1
    fi

    MESSAGE="$2"
    TIME="$3"

    init_storage

    ID="$(next_id)"

    echo "$ID|$TIME|$MESSAGE|once|pending" >> "$REMINDERS_FILE"

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
        echo "  cue list"
        echo "  cue done <id>"
        echo "  cue remove <id>"
        echo "  cue status"
        echo "  cue history"
        echo "  cue help"
        ;;

    done)
    if [[ $# -ne 2 ]]; then
        echo "Usage: cue done <id>"
        exit 1
    fi

    init_storage

    MESSAGE="$(mark_done "$2")"

    if [[ -z "$MESSAGE" ]]; then
        echo "cue: reminder #$2 not found"
        exit 1
    fi

    log_history "$2" "completed" "$MESSAGE"

    echo "Completed reminder #$2"
    ;;

    history)
    show_history
    ;;

    remove)
    if [[ $# -ne 2 ]]; then
        echo "Usage: cue remove <id>"
        exit 1
    fi

    init_storage

    if remove_reminder "$2"; then
        echo "Removed reminder #$2"
    else
        echo "cue: reminder #$2 not found"
        exit 1
    fi
    ;;

    status)
    show_status
    ;;

    
    *)
        echo "cue: unknown command '$1'"
        echo "Run 'cue help' for usage."
        exit 1
        ;;
esac