#!/usr/bin/env bats

setup() {
    export XDG_DATA_HOME="$BATS_TEST_TMPDIR/data"
    export CUE_BIN="$BATS_TEST_DIRNAME/../cue"

    mkdir -p "$XDG_DATA_HOME"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

    # Mock notify-send
    cat > "$BATS_TEST_TMPDIR/bin/notify-send" << "INNER"
#!/usr/bin/env bash
if [ -f "$XDG_DATA_HOME/notify_fail" ]; then
    exit 1
fi
echo "$@" >> "$XDG_DATA_HOME/notify_calls"
exit 0
INNER
    chmod +x "$BATS_TEST_TMPDIR/bin/notify-send"

    # Mock crontab
    cat > "$BATS_TEST_TMPDIR/bin/crontab" << "INNER"
#!/usr/bin/env bash
if [[ "$1" == "-l" ]]; then
    if [ ! -f "$XDG_DATA_HOME/mock_crontab" ]; then
        exit 1
    fi
    cat "$XDG_DATA_HOME/mock_crontab"
elif [[ "$1" == "-r" ]]; then
    rm -f "$XDG_DATA_HOME/mock_crontab"
elif [[ "$1" == "-" ]]; then
    cat > "$XDG_DATA_HOME/mock_crontab.tmp" && mv "$XDG_DATA_HOME/mock_crontab.tmp" "$XDG_DATA_HOME/mock_crontab"
else
    cat "$1" > "$XDG_DATA_HOME/mock_crontab.tmp" && mv "$XDG_DATA_HOME/mock_crontab.tmp" "$XDG_DATA_HOME/mock_crontab"
fi
INNER
    chmod +x "$BATS_TEST_TMPDIR/bin/crontab"

    run_cue() {
        "$CUE_BIN" "$@"
    }
}

@test "A. Basic add" {
    run run_cue add "Study DSA" 22:00
    [ "$status" -eq 0 ]

    reminders_file="$XDG_DATA_HOME/cue/reminders"
    [ -f "$reminders_file" ]

    line=$(cat "$reminders_file")
    id=$(echo "$line" | cut -d"|" -f1)
    msg=$(echo "$line" | cut -d"|" -f3)
    type=$(echo "$line" | cut -d"|" -f4)
    status_field=$(echo "$line" | cut -d"|" -f5)

    [ "$id" = "1" ]
    [ "$msg" = "Study DSA" ]
    [ "$type" = "once" ]
    [ "$status_field" = "pending" ]
}

@test "B. Full timestamp add" {
    run run_cue add "Submit assignment" "2026-09-15 18:30"
    [ "$status" -eq 0 ]

    line=$(cat "$XDG_DATA_HOME/cue/reminders")
    time=$(echo "$line" | cut -d"|" -f2)
    [ "$time" = "2026-09-15 18:30" ]
}

@test "C. Invalid time" {
    run run_cue add "Task" "25:00"
    [ "$status" -ne 0 ]

    run run_cue add "Task" "12:60"
    [ "$status" -ne 0 ]

    run run_cue add "Task" "abc"
    [ "$status" -ne 0 ]

    [ ! -f "$XDG_DATA_HOME/cue/reminders" ] || [ ! -s "$XDG_DATA_HOME/cue/reminders" ]
}

@test "D. Message validation" {
    run run_cue add "" "12:00"
    [ "$status" -ne 0 ]

    run run_cue add "hello|world" "12:00"
    [ "$status" -ne 0 ]
}

@test "E. List" {
    run_cue add "Task 1" "12:00"
    run_cue add "Task 2" "13:00"

    run run_cue list
    [ "$status" -eq 0 ]
    [[ "$output" == *"Task 1"* ]]
    [[ "$output" == *"Task 2"* ]]
}

@test "F. Done" {
    run_cue add "Task" "12:00"
    run run_cue "done" 1
    [ "$status" -eq 0 ]

    line=$(cat "$XDG_DATA_HOME/cue/reminders")
    status_field=$(echo "$line" | cut -d"|" -f5)
    [ "$status_field" = "completed" ]

    history_line=$(cat "$XDG_DATA_HOME/cue/history")
    [[ "$history_line" == *"|1|completed|"* ]]
}

@test "G. Cancel" {
    run_cue add "Task" "12:00"
    run run_cue cancel 1
    [ "$status" -eq 0 ]

    line=$(cat "$XDG_DATA_HOME/cue/reminders")
    status_field=$(echo "$line" | cut -d"|" -f5)
    [ "$status_field" = "cancelled" ]

    history_line=$(cat "$XDG_DATA_HOME/cue/history")
    [[ "$history_line" == *"|1|cancelled|"* ]]
}

@test "H. Remove" {
    run_cue add "Task" "12:00"
    run run_cue remove 1
    [ "$status" -eq 0 ]

    line=$(cat "$XDG_DATA_HOME/cue/reminders")
    [ -z "$line" ]

    history_line=$(cat "$XDG_DATA_HOME/cue/history")
    [[ "$history_line" == *"|1|removed|"* ]]
}

@test "I. Invalid ID" {
    run_cue add "Task" "12:00"

    run run_cue "done" 0
    [ "$status" -ne 0 ]

    run run_cue "done" -1
    [ "$status" -ne 0 ]

    run run_cue "done" abc
    [ "$status" -ne 0 ]

    run run_cue "done" ""
    [ "$status" -ne 0 ]
}

@test "J. Duplicate completion/cancellation" {
    run_cue add "Task" "12:00"
    run_cue "done" 1
    run run_cue "done" 1
    [ "$status" -ne 0 ]

    run_cue add "Task 2" "13:00"
    run_cue cancel 2
    run run_cue cancel 2
    [ "$status" -ne 0 ]
}

@test "4.1 Recurring interval add" {
    run run_cue add "Drink water" --every 2h
    [ "$status" -eq 0 ]

    line=$(cat "$XDG_DATA_HOME/cue/reminders")
    type=$(echo "$line" | cut -d"|" -f4)
    status_field=$(echo "$line" | cut -d"|" -f5)
    recurrence=$(echo "$line" | cut -d"|" -f6)
    last_triggered=$(echo "$line" | cut -d"|" -f7)

    [ "$type" = "recurring" ]
    [ "$recurrence" = "2h" ]
    [ "$status_field" = "pending" ]
    [ -z "$last_triggered" ]
}

@test "4.2 Recurring daily add" {
    run run_cue add "Morning run" --every day 06:30
    [ "$status" -eq 0 ]

    line=$(cat "$XDG_DATA_HOME/cue/reminders")
    type=$(echo "$line" | cut -d"|" -f4)
    recurrence=$(echo "$line" | cut -d"|" -f6)

    [ "$type" = "recurring" ]
    [ "$recurrence" = "day 06:30" ]
}

@test "4.3 Invalid recurrence formats" {
    run run_cue add "Fail" --every 0h
    [ "$status" -ne 0 ]

    run run_cue add "Fail" --every -2h
    [ "$status" -ne 0 ]

    run run_cue add "Fail" --every abc
    [ "$status" -ne 0 ]

    run run_cue add "Fail" --every 2hours
    [ "$status" -ne 0 ]

    run run_cue add "Fail" --every day abc
    [ "$status" -ne 0 ]

    run run_cue add "Fail" --every day 25:00
    [ "$status" -ne 0 ]
}

@test "5.1 Scheduler once" {
    mkdir -p "$XDG_DATA_HOME/cue"
    echo "1|2000-01-01 12:00|Task|once|pending||" > "$XDG_DATA_HOME/cue/reminders"

    run run_cue check
    [ "$status" -eq 0 ]

    [ -f "$XDG_DATA_HOME/notify_calls" ]

    line=$(cat "$XDG_DATA_HOME/cue/reminders")
    status_field=$(echo "$line" | cut -d"|" -f5)
    last_triggered=$(echo "$line" | cut -d"|" -f7)

    [ "$status_field" = "pending" ]
    [ -n "$last_triggered" ]

    rm -f "$XDG_DATA_HOME/notify_calls"
    run run_cue check
    [ ! -f "$XDG_DATA_HOME/notify_calls" ]
}

@test "5.2 Scheduler once notification failure" {
    mkdir -p "$XDG_DATA_HOME/cue"
    echo "1|2000-01-01 12:00|Task|once|pending||" > "$XDG_DATA_HOME/cue/reminders"
    touch "$XDG_DATA_HOME/notify_fail"

    run run_cue check

    line=$(cat "$XDG_DATA_HOME/cue/reminders")
    last_triggered=$(echo "$line" | cut -d"|" -f7)

    [ -z "$last_triggered" ]
}

@test "6.1 Overdue interval reminder" {
    mkdir -p "$XDG_DATA_HOME/cue"
    echo "1|2000-01-01 12:00|Drink water|recurring|pending|2h|" > "$XDG_DATA_HOME/cue/reminders"

    run run_cue check
    [ -f "$XDG_DATA_HOME/notify_calls" ]

    line=$(cat "$XDG_DATA_HOME/cue/reminders")
    time=$(echo "$line" | cut -d"|" -f2)
    last_triggered=$(echo "$line" | cut -d"|" -f7)

    [ "$time" != "2000-01-01 12:00" ]
    [ -n "$last_triggered" ]

    rm -f "$XDG_DATA_HOME/notify_calls"
    run run_cue check
    [ ! -f "$XDG_DATA_HOME/notify_calls" ]
}

@test "6.2 Overdue daily reminder" {
    mkdir -p "$XDG_DATA_HOME/cue"
    echo "1|2000-01-01 06:30|Morning run|recurring|pending|day 06:30|" > "$XDG_DATA_HOME/cue/reminders"

    run run_cue check
    [ -f "$XDG_DATA_HOME/notify_calls" ]

    line=$(cat "$XDG_DATA_HOME/cue/reminders")
    time=$(echo "$line" | cut -d"|" -f2)
    last_triggered=$(echo "$line" | cut -d"|" -f7)

    [ "$time" != "2000-01-01 06:30" ]
    [ -n "$last_triggered" ]
}

@test "6.3 Future recurring reminder" {
    mkdir -p "$XDG_DATA_HOME/cue"
    future_time=$(date -d "1 hour" "+%H:%M")
    today=$(date "+%Y-%m-%d")
    echo "1|$today $future_time|Future|recurring|pending|day $future_time|" > "$XDG_DATA_HOME/cue/reminders"

    run run_cue check
    [ ! -f "$XDG_DATA_HOME/notify_calls" ]

    line=$(cat "$XDG_DATA_HOME/cue/reminders")
    time=$(echo "$line" | cut -d"|" -f2)
    last_triggered=$(echo "$line" | cut -d"|" -f7)

    [ "$time" = "$today $future_time" ]
    [ -z "$last_triggered" ]
}

@test "6.4 Recurring notification failure" {
    mkdir -p "$XDG_DATA_HOME/cue"
    echo "1|2000-01-01 12:00|Task|recurring|pending|2h|" > "$XDG_DATA_HOME/cue/reminders"
    touch "$XDG_DATA_HOME/notify_fail"

    run run_cue check

    line=$(cat "$XDG_DATA_HOME/cue/reminders")
    time=$(echo "$line" | cut -d"|" -f2)
    last_triggered=$(echo "$line" | cut -d"|" -f7)

    [ "$time" = "2000-01-01 12:00" ]
    [ -z "$last_triggered" ]
}

@test "7. Malformed data test" {
    mkdir -p "$XDG_DATA_HOME/cue"
    echo "broken|record" > "$XDG_DATA_HOME/cue/reminders"
    echo "2|2000-01-01 12:00|Task|once|pending||" >> "$XDG_DATA_HOME/cue/reminders"

    run run_cue check
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning: skipping malformed"* ]]

    [ -f "$XDG_DATA_HOME/notify_calls" ]

    run bash -c "head -n 1 \"$XDG_DATA_HOME/cue/reminders\" | grep 'broken|record'"
    [ "$status" -eq 0 ]
}

@test "8. Concurrency test" {
    for i in {1..5}; do
        run_cue add "Concurrent Task $i" "12:00" &
    done
    wait

    count=$(wc -l < "$XDG_DATA_HOME/cue/reminders")
    [ "$count" -eq 5 ]

    ids=$(cut -d"|" -f1 "$XDG_DATA_HOME/cue/reminders" | sort -n | tr "\n" " ")
    [ "$ids" = "1 2 3 4 5 " ]
}

@test "9. Help test" {
    run run_cue help
    [ "$status" -eq 0 ]
    [[ "$output" == *"cue install"* ]]
    [[ "$output" == *"cue uninstall"* ]]
    [[ "$output" == *"--every"* ]]
}

@test "10.1 Cron install empty" {
    export HOME="$BATS_TEST_TMPDIR"
    run run_cue install
    [ "$status" -eq 0 ]

    crontab_contents=$(cat "$XDG_DATA_HOME/mock_crontab")
    [[ "$crontab_contents" == *"# CUE: scheduler"* ]]

    count=$(grep -c "# CUE: scheduler" "$XDG_DATA_HOME/mock_crontab")
    [ "$count" -eq 1 ]
}

@test "10.2 Cron install existing jobs" {
    export HOME="$BATS_TEST_TMPDIR"
    echo "0 8 * * * /job" > "$XDG_DATA_HOME/mock_crontab"

    run run_cue install
    crontab_contents=$(cat "$XDG_DATA_HOME/mock_crontab")

    [[ "$crontab_contents" == *"0 8 * * * /job"* ]]
    [[ "$crontab_contents" == *"# CUE: scheduler"* ]]
}

@test "10.3 Cron install unrelated CUE marker" {
    export HOME="$BATS_TEST_TMPDIR"
    echo "* * * * * /other # CUE" > "$XDG_DATA_HOME/mock_crontab"

    run run_cue install
    crontab_contents=$(cat "$XDG_DATA_HOME/mock_crontab")

    [[ "$crontab_contents" == *"/other # CUE"* ]]
    [[ "$crontab_contents" == *"# CUE: scheduler"* ]]
}

@test "10.4 Cron install duplicate prevention" {
    export HOME="$BATS_TEST_TMPDIR"
    run_cue install
    run_cue install

    count=$(grep -c "# CUE: scheduler" "$XDG_DATA_HOME/mock_crontab")
    [ "$count" -eq 1 ]
}

@test "10.5 Cron uninstall" {
    export HOME="$BATS_TEST_TMPDIR"
    echo "0 8 * * * /job" > "$XDG_DATA_HOME/mock_crontab"
    run_cue install

    run run_cue uninstall

    crontab_contents=$(cat "$XDG_DATA_HOME/mock_crontab")
    [[ "$crontab_contents" == *"0 8 * * * /job"* ]]
    [[ "$crontab_contents" != *"# CUE: scheduler"* ]]
}
