#!/bin/bash
# Automated tests for Flashy's Stop-event background-task/cron suppression.
#
# Pure bash, no external test framework, no jq/python/node — keeps Flashy's
# zero-runtime-dependency promise intact for tests too.
#
# Claude Code (v2.1.145+) can include `background_tasks` and `session_crons`
# arrays in the Stop hook's stdin JSON when background agents or scheduled
# crons are still running. flash.sh suppresses the stop pulse when either
# array is confidently non-empty, and fails open (flashes) on anything else:
# missing keys, empty arrays, empty/closed stdin, or malformed JSON.
#
# These tests drive real flash.sh through a narrowly guarded test seam
# (FLASHY_TEST_SEAM) so assertions are on the actual suppress/pulse decision
# printed to stdout — never on sleep timing.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLASH="$SCRIPT_DIR/../hooks/flash.sh"
HOOKS_JSON="$SCRIPT_DIR/../hooks/hooks.json"

# Same magic token flash.sh requires — deliberately not a plausible value
# (like "1" or "true") that could be set by accident in a real shell/CI env.
SEAM_TOKEN="flashy-test-seam-do-not-set-manually-9f13c2"

# Isolate from the developer's real ~/.config/flashy/config so test results
# don't depend on machine-local settings.
TEST_HOME="$(mktemp -d)"
trap 'rm -rf "$TEST_HOME"' EXIT

pass=0
fail=0

# Runs flash.sh stop with $1 piped to stdin via the test seam, in a clean
# env (isolated HOME, no inherited config), and prints the decision line.
run_seam() {
  local stdin_payload="$1"
  printf '%s' "$stdin_payload" | env -i \
    HOME="$TEST_HOME" \
    PATH="$PATH" \
    FLASHY_TEST_SEAM="$SEAM_TOKEN" \
    "$FLASH" stop
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    pass=$((pass + 1))
    echo "ok - $desc"
  else
    fail=$((fail + 1))
    echo "not ok - $desc (expected [$expected], got [$actual])"
  fi
}

# A background bash "does this hang" timeout with no external `timeout`
# binary — pure bash + sleep + kill, no new dependency.
run_with_timeout() {
  local secs="$1"; shift
  "$@" &
  local pid=$!
  ( sleep "$secs" 2>/dev/null; kill -9 "$pid" 2>/dev/null ) &
  local watcher=$!
  local status
  wait "$pid" 2>/dev/null
  status=$?
  kill "$watcher" 2>/dev/null
  wait "$watcher" 2>/dev/null
  return $status
}

echo "# missing arrays -> fail open (pulse)"
actual=$(run_seam '{"session_id":"abc","hook_event_name":"Stop","stop_hook_active":false}')
rc=$?
assert_eq "missing background_tasks/session_crons pulses" "FLASHY_TEST_RESULT=PULSE count=1" "$actual"
assert_eq "pulse/seam case exits 0" "0" "$rc"

echo "# empty arrays -> fail open (pulse)"
actual=$(run_seam '{"background_tasks": [], "session_crons": []}')
assert_eq "empty arrays pulse" "FLASHY_TEST_RESULT=PULSE count=1" "$actual"

echo "# whitespace-only array body is still empty -> fail open (pulse)"
actual=$(run_seam '{"background_tasks": [

  ], "session_crons": []}')
assert_eq "whitespace-only array body pulses" "FLASHY_TEST_RESULT=PULSE count=1" "$actual"

echo "# nonempty background_tasks with nested object -> suppress"
actual=$(run_seam '{
  "session_id": "abc123",
  "background_tasks": [
    {
      "id": "task-1",
      "description": "syncing files, still running"
    }
  ],
  "session_crons": []
}')
rc=$?
assert_eq "nonempty background_tasks suppresses" "FLASHY_TEST_RESULT=SUPPRESSED" "$actual"
assert_eq "suppressed case exits 0" "0" "$rc"

echo "# nonempty session_crons only -> suppress"
actual=$(run_seam '{"background_tasks": [], "session_crons": [{"name": "nightly-sync", "next_run": "2026-08-07T00:00:00Z"}]}')
assert_eq "nonempty session_crons suppresses" "FLASHY_TEST_RESULT=SUPPRESSED" "$actual"

echo "# both nonempty -> suppress"
actual=$(run_seam '{"background_tasks": [{"id": "t1"}], "session_crons": [{"name": "c1"}]}')
assert_eq "both nonempty suppresses" "FLASHY_TEST_RESULT=SUPPRESSED" "$actual"

echo "# malformed/unrecognized JSON -> fail open (pulse)"
actual=$(run_seam 'not json at all {{{ [ }}}')
assert_eq "malformed JSON pulses" "FLASHY_TEST_RESULT=PULSE count=1" "$actual"

echo "# empty/closed stdin -> fail open (pulse)"
actual=$(run_seam '')
assert_eq "empty stdin pulses" "FLASHY_TEST_RESULT=PULSE count=1" "$actual"

echo "# array value is a string, not an array -> fail open (pulse)"
actual=$(run_seam '{"background_tasks": "oops-not-an-array"}')
assert_eq "non-array value pulses" "FLASHY_TEST_RESULT=PULSE count=1" "$actual"

echo "# seam guard: a plausible-but-wrong token must NOT activate test mode"
# Use a subshell (not env -i) so run_with_timeout (a shell function) stays
# callable while HOME/FLASHY_TEST_SEAM are still overridden for the child.
# Falls through to the real production path (OSC 11 detection + pulse loop),
# which probes /dev/tty — silence that expected "Device not configured"
# noise here since there's no controlling terminal in a test harness.
actual=$(printf '%s' '{"background_tasks": [{"id": "t1"}]}' | (
  export HOME="$TEST_HOME" FLASHY_TEST_SEAM="1"
  unset XDG_CONFIG_HOME
  run_with_timeout 5 "$FLASH" stop 2>/dev/null
))
assert_eq "wrong seam token falls through to production (no marker printed)" "" "$actual"

echo "# manual/closed-stdin invocation does not hang (non-tty, no seam)"
# Also production path (no seam token) -> also probes /dev/tty; silence it.
if run_with_timeout 5 bash -c "env -i HOME='$TEST_HOME' PATH='$PATH' '$FLASH' stop < /dev/null > /dev/null 2>/dev/null"; then
  pass=$((pass + 1))
  echo "ok - closed-stdin stop invocation returns without hanging"
else
  fail=$((fail + 1))
  echo "not ok - closed-stdin stop invocation hung or errored"
fi

echo "# hooks.json's timeout is what bounds a genuinely open (non-EOF) stdin"
# flash.sh's stop-suppression read (`cat`) has no self-imposed limit -- it
# blocks until EOF. In production, only Claude Code's hook "timeout" field
# (hooks/hooks.json) bounds that. We deliberately do NOT add a read timeout
# to flash.sh for this -- that would be new production complexity to solve
# a problem the hook harness already solves.
#
# This test proves the hang is real (flash.sh does not return on its own
# before the configured timeout elapses) and reads the actual timeout value
# out of hooks.json rather than hardcoding it, so a change to that value is
# caught here. It cannot invoke Claude Code's own enforcement (that lives
# outside this repo), so it documents/locks in the reliance instead: still
# blocked at timeout+1s, then torn down manually like the harness would.
STOP_HOOK_BLOCK=$(sed -n '/"Stop"/,/"Notification"/p' "$HOOKS_JSON")
STOP_HOOK_TIMEOUT=$(printf '%s' "$STOP_HOOK_BLOCK" | grep -oE '"timeout"[[:space:]]*:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1)

if [ -z "$STOP_HOOK_TIMEOUT" ]; then
  fail=$((fail + 1))
  echo "not ok - could not read the Stop hook's timeout out of hooks.json"
else
  FIFO="$(mktemp -u)"
  mkfifo "$FIFO"
  # Open the fifo read-write on fd 9 -- this does not block (unlike opening
  # read-only or write-only ends separately) and keeps a writer attached for
  # as long as fd 9 stays open, so the reader never sees EOF.
  exec 9<>"$FIFO"

  env -i HOME="$TEST_HOME" PATH="$PATH" "$FLASH" stop <&9 2>/dev/null &
  FLASH_PID=$!

  SLEEP_SECS=$((STOP_HOOK_TIMEOUT + 1))
  sleep "$SLEEP_SECS"

  if kill -0 "$FLASH_PID" 2>/dev/null; then
    pass=$((pass + 1))
    echo "ok - flash.sh still blocked on open stdin past hooks.json's ${STOP_HOOK_TIMEOUT}s Stop timeout (confirms reliance on that field, not a self-imposed limit)"
  else
    fail=$((fail + 1))
    echo "not ok - flash.sh returned on its own before hooks.json's ${STOP_HOOK_TIMEOUT}s Stop timeout elapsed"
  fi

  # Teardown: nothing in flash.sh enforces this in a test harness, so do
  # what Claude Code's hook timeout would do in production.
  kill -9 "$FLASH_PID" 2>/dev/null
  wait "$FLASH_PID" 2>/dev/null
  exec 9>&-
  rm -f "$FIFO"
fi

echo "# notification event is unaffected by stdin content"
actual=$(printf '%s' '{"background_tasks": [{"id": "t1"}]}' | env -i \
  HOME="$TEST_HOME" PATH="$PATH" FLASHY_TEST_SEAM="$SEAM_TOKEN" "$FLASH" notification)
assert_eq "notification never reads suppression stdin" "FLASHY_TEST_RESULT=PULSE count=2" "$actual"

echo
echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
