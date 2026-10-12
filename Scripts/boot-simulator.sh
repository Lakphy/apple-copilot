#!/bin/zsh
# Boot one explicitly selected simulator. No erase, global service, or cache changes.
# Opt-in recovery restarts only this device's dasd after a known migration stall.
set -euo pipefail
# Honor DEVELOPER_DIR or the active xcode-select toolchain.
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"

usage() {
  print -r -- "Usage: $0 UDID [--recover-dasd]"
  print -r -- "Wait up to 180 seconds for real readiness. --recover-dasd permits at most"
  print -r -- "two simulator-local dasd restarts after CoreLocation migration stalls."
}

if (( $# == 0 )) || [[ "$1" == "--help" || "$1" == "-h" ]]; then
  usage
  (( $# > 0 )) && exit 0
  exit 2
fi
if (( $# > 2 )); then
  usage >&2
  exit 2
fi

device_udid="$1"
allow_recovery=false
if (( $# == 2 )); then
  if [[ "$2" != "--recover-dasd" ]]; then
    usage >&2
    exit 2
  fi
  allow_recovery=true
fi
if ! print -r -- "$device_udid" | /usr/bin/grep -Eq '^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$'; then
  print -u2 -r -- "Provide an explicit simulator UDID; aliases such as booted are rejected."
  exit 2
fi
device_udid="${device_udid:u}"

read_device_state() {
  xcrun simctl list devices available --json | python3 -c '
import json, sys
requested = sys.argv[1]
devices = (device for runtime in json.load(sys.stdin)["devices"].values() for device in runtime)
match = next((device for device in devices if device["udid"].upper() == requested), None)
if match is None:
    sys.stderr.write("No available simulator matches the supplied UDID.\n")
    sys.exit(2)
print(match["state"])
' "$device_udid"
}

current_device_state="$(read_device_state)"
case "$current_device_state" in
  Shutdown) xcrun simctl boot "$device_udid" ;;
  Booted|Booting) ;;
  *) print -u2 -r -- "Cannot boot from state: $current_device_state"; exit 1 ;;
esac

task_log_directory="$(mktemp -d "${TMPDIR:-/tmp}/apple-copilot-boot.XXXXXX")"
boot_log="$task_log_directory/bootstatus.log"
monitor_pid=""
recovery_pid=""
cleanup() {
  # These PIDs belong to subprocesses created by this script, never host services.
  if [[ -n "$monitor_pid" ]] && kill -0 "$monitor_pid" 2>/dev/null; then
    kill -TERM "$monitor_pid" 2>/dev/null || true
    wait "$monitor_pid" 2>/dev/null || true
  fi
  if [[ -n "$recovery_pid" ]] && kill -0 "$recovery_pid" 2>/dev/null; then
    kill -TERM "$recovery_pid" 2>/dev/null || true
    wait "$recovery_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

deadline=$(( SECONDS + 180 ))
xcrun simctl bootstatus "$device_udid" >"$boot_log" 2>&1 &
monitor_pid=$!
recovery_count=0
last_recovery_at=-60
migration_stall_at=-1
previous_reason=""
print -r -- "Monitoring $device_udid; boot log: $boot_log"

while kill -0 "$monitor_pid" 2>/dev/null; do
  if (( SECONDS >= deadline )); then
    print -u2 -r -- "Readiness timed out after 180 seconds. Device data is preserved."
    tail -n 30 "$boot_log" >&2
    exit 1
  fi

  latest_reason="$(awk '/Reason:/ { reason = $0 } END { print reason }' "$boot_log")"
  latest_boot_phase="$(awk '/Status=/ { phase = $0 } END { print phase }' "$boot_log")"
  if [[ "$latest_reason" != "$previous_reason" && -n "$latest_reason" ]]; then
    print -r -- "$latest_reason"
    previous_reason="$latest_reason"
  fi
  if [[ "$latest_boot_phase" == *"Status=2,"* \
        && "$latest_reason" == *"com.apple.locationd.migrator"* ]]; then
    (( migration_stall_at < 0 )) && migration_stall_at=$SECONDS
  else
    migration_stall_at=-1
  fi

  if [[ -n "$recovery_pid" ]] && ! kill -0 "$recovery_pid" 2>/dev/null; then
    if ! wait "$recovery_pid"; then
      print -u2 -r -- "The simulator-local dasd restart failed; see $task_log_directory."
    fi
    recovery_pid=""
  fi

  if [[ "$allow_recovery" == true && -z "$recovery_pid" ]] \
      && (( migration_stall_at >= 0 && SECONDS - migration_stall_at >= 15 \
            && SECONDS - last_recovery_at >= 30 && recovery_count < 2 )); then
    recovery_count=$(( recovery_count + 1 ))
    last_recovery_at=$SECONDS
    print -r -- "CoreLocation migration stalled; restarting this simulator's dasd ($recovery_count/2)."
    xcrun simctl spawn "$device_udid" launchctl kickstart -k \
      "user/$(id -u)/com.apple.dasd" >"$task_log_directory/dasd-$recovery_count.log" 2>&1 &
    recovery_pid=$!
  fi
  sleep 2
done

monitor_result=0
wait "$monitor_pid" || monitor_result=$?
monitor_pid=""
current_device_state="$(read_device_state)"
if (( monitor_result != 0 )) || [[ "$current_device_state" != "Booted" ]] \
    || ! /usr/bin/grep -Eq '^[[:space:]]*(Finished|Device already booted, nothing to do\.)[[:space:]]*$' "$boot_log"; then
  print -u2 -r -- "Readiness failed: bootstatus=$monitor_result, state=$current_device_state."
  tail -n 30 "$boot_log" >&2
  exit 1
fi
print -r -- "Ready: $device_udid is Booted and bootstatus confirmed readiness."
