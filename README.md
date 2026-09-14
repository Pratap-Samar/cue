# CUE

CUE is a minimal, pure-Bash Linux reminder and recurring notification utility.

It operates entirely offline, storing data in simple flat files and relying on standard Linux utilities like `cron` and `notify-send` rather than introducing background daemons, databases, or language runtimes.

## Features

- **One-time Reminders**: Schedule quick alerts using natural timestamps.
- **Recurring Reminders**: Set intervals (e.g., `2h`) or daily schedules (e.g., `day 06:30`).
- **Cron-based Scheduler**: Hooks into your system's native `cron` daemon to trigger notifications.
- **Desktop Notifications**: Alerts are delivered directly to your Linux desktop via `notify-send`.
- **Persistent Storage**: Reminders are saved to `~/.local/share/cue/reminders` with a safe, `flock`-protected file format.
- **Event History**: Tracks completed, cancelled, and removed reminders.

## Quick Start

```bash
# Add a one-time reminder for tonight
cue add "Study DSA" 22:00

# Add a recurring reminder to drink water every 2 hours
cue add "Drink water" --every 2h

# Add a daily reminder for a morning run
cue add "Morning run" --every day 06:30

# View all active reminders
cue list
```

## Requirements

CUE requires a standard Linux desktop environment.

- `bash` (4.0+)
- `cron` daemon (e.g., `cronie`, `vixie-cron`)
- `notify-send` (provided by `libnotify`)
- GNU `date`

## Installation

CUE is designed to run directly from its repository.

### 1. Ensure Dependencies are Installed

**Ubuntu / Debian**
```bash
sudo apt update
sudo apt install cron libnotify-bin
sudo systemctl enable --now cron
```

**Arch Linux**
```bash
sudo pacman -S cronie libnotify
sudo systemctl enable --now cronie
```

**Fedora**
```bash
sudo dnf install cronie libnotify
sudo systemctl enable --now crond
```

### 2. Install CUE

Clone the repository and run the built-in installer:

```bash
git clone https://github.com/Pratap-Samar/cue.git
cd cue
./cue install
```

### Understanding the Installation Steps

There is an important distinction between the moving parts:
- **Enabling the distro's cron service**: Starts the background system daemon (`cronie` or `cron`) that runs scheduled jobs. CUE relies on this to wake up every minute.
- **Installing CUE (`./cue install`)**: This command does two things. First, it creates an executable wrapper for CUE in `~/.local/bin/cue` so you can use the `cue` command from anywhere. Second, it injects a single entry into your user's `crontab` that safely invokes CUE's scheduler (`cue check`) every minute.

## Command Reference

| Command | Description |
|---|---|
| `cue add <message> <time>` | Add a one-time reminder. |
| `cue add <message> --every <interval>` | Add a recurring reminder. |
| `cue list` | List all active reminders. |
| `cue done <id>` | Mark a reminder as completed. |
| `cue cancel <id>` | Cancel a pending reminder. |
| `cue remove <id>` | Permanently delete a reminder. |
| `cue status` | Show current storage statistics. |
| `cue history` | View the history log of resolved reminders. |
| `cue check` | Internal command used by cron to trigger due notifications. |
| `cue install` | Set up the CLI wrapper and cron scheduler job. |
| `cue uninstall` | Remove the CLI wrapper and clean up the cron scheduler job. |
| `cue help` | Display usage information. |

### Time Formats

For one-time reminders, CUE uses GNU `date` under the hood. You can use standard timestamp formats:
- `22:00` (today at 10 PM)
- `"2026-09-15 18:30"` (specific date and time)
- `"tomorrow 09:00"`

### Recurring Reminder Syntax

CUE currently supports two recurring patterns:
- **Interval**: `--every <number><unit>` (e.g., `--every 2h`, `--every 15m`).
- **Daily**: `--every day HH:MM` (e.g., `--every day 06:30`).

### Missed Reminder Behavior

If your computer is asleep or powered off when a recurring reminder was supposed to fire:
- **Interval recurrences** will immediately fire upon the next cron wakeup and advance relative to the time they triggered.
- **Daily recurrences** will fire once, and correctly roll over to the *next valid future day's time*, preventing an annoying backlog of repetitive notifications from triggering all at once.
- Failed `notify-send` executions will **not** advance the reminder's schedule. CUE will simply retry on the next minute's check.

## Architecture

CUE adheres to the UNIX philosophy. The architecture relies on simple chained components:
`CLI (cue add)` -> `Flat File Storage` -> `System Cron` -> `CLI (cue check)` -> `notify-send`

- **Storage**: Data is saved to `~/.local/share/cue/reminders` (pipe-separated format). File reads and writes are strictly protected by `flock` to prevent race conditions during concurrent CLI and cron access.
- **Scheduler**: The system cron wakes up `cue check` every minute. It parses the storage file, compares timestamps, triggers `notify-send` for overdue items, and recalculates their next occurrence.

## Testing

CUE includes a comprehensive test suite to ensure stability and data integrity.

- **Bats**: 27 automated behavioral tests mock system utilities (like `cron` and `notify-send`) securely in a temporary environment. Run with `bats tests/cue.bats`.
- **ShellCheck**: Statically analyzes the Bash codebase. Run with `shellcheck --severity=warning cue lib/*.sh tests/cue.bats`.
- **Bash Syntax**: Basic syntax compilation checks (`bash -n`).
- **GitHub Actions**: Automated CI testing on every push and pull request to `main`.

## Troubleshooting

- **`cue: command not found`**: Ensure `~/.local/bin` is added to your system's `$PATH`.
- **No notifications appearing**: Ensure your desktop environment has a notification daemon running and `libnotify` (which provides `notify-send`) is installed.
- **Cron service not running**: Run `systemctl status cron` (or `cronie`/`crond`) to verify the daemon is active.
- **Checking CUE's cron entry**: Run `crontab -l`. You should see `* * * * * /home/user/.local/bin/cue check >/dev/null 2>&1 # CUE: scheduler`.
- **WSL Limitations**: Windows Subsystem for Linux (WSL) does not automatically start systemd services like `cron` in the background by default in older versions, and lacks a native Linux desktop notification server.

## Uninstallation

To remove the CUE wrapper and cleanly strip its scheduled job from your crontab without affecting your other cron jobs:
```bash
cue uninstall
```
*(Note: Your reminder data will remain in `~/.local/share/cue/` until manually deleted.)*

## License

MIT License
