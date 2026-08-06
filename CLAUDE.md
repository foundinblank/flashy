# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Flashy is a Claude Code plugin written in pure Bash that pulses the terminal background color when Claude finishes a turn (Stop event) or sends a notification. It has zero external dependencies.

## Architecture

- **`.claude-plugin/plugin.json`** — Plugin metadata (name, version, author)
- **`hooks/hooks.json`** — Registers two Claude Code hook events (Stop, Notification), each calling `flash.sh` with the event name as `$1`. Notification is narrowed to `matcher: "permission_prompt|idle_prompt|agent_needs_input"`; both entries carry a 2-second `timeout` so a hung hook can't stall Claude Code.
- **`hooks/flash.sh`** — The entire implementation in one script:
  1. Sources user config from `${XDG_CONFIG_HOME:-$HOME/.config}/flashy/config` (if it exists), then applies bash parameter expansion defaults
  2. For `stop`, if stdin isn't a TTY, reads the hook's JSON and suppresses the pulse when Claude Code (v2.1.145+) reports non-empty `background_tasks` or `session_crons` — see "Stop Suppression" below
  3. Detects terminal background color via three-tier cascade: per-TTY color file → OSC 11 terminal query → static `FALLBACK_COLOR`
  4. Computes adaptive flash color by measuring luminance and shifting RGB toward white (dark themes) or black (light themes)
  5. Runs a pulse loop: set bg to flash color via OSC 11, sleep, restore original bg
- **`config.default`** — Reference template for user config; not read at runtime
- **`DESIGN.md`** — Detailed technical design document
- **`tests/test_flash_stop_suppression.sh`** — Pure-bash automated test suite for the stop-suppression logic

## Commands

No build system or linter. There is a pure-bash test suite for the stop-suppression logic, plus manual testing for the rest:

```bash
# Run the automated test suite (no jq/python/node required)
./tests/test_flash_stop_suppression.sh

# Test flash directly (must be run in a supported terminal, not VS Code)
./hooks/flash.sh stop
./hooks/flash.sh notification

# Install as Claude Code plugin
claude plugin add /path/to/flashy
```

## Stop Suppression (v0.2.0)

Claude Code v2.1.145+ can include `background_tasks` and `session_crons` arrays in the Stop hook's stdin JSON when background agents or scheduled crons are still running after the main turn ends. Flashing "done" in that situation is misleading, so `flash.sh` suppresses the stop pulse when either array is confidently non-empty.

This is a narrow, best-effort string scan for a literal top-level `"key": [ ... ]` shape — not a general JSON parser, and no new dependency. Anything it doesn't confidently recognize (missing keys, empty arrays, malformed JSON, a non-array value, empty/closed stdin) fails open to a normal flash. Stdin is only ever read when it's not a TTY, so manual `./hooks/flash.sh stop` from an interactive shell never blocks.

Flashy still only hooks `Stop`, not `SubagentStop` — that fires once per subagent, which would be noisy, and the top-level Stop hook already covers "Claude is done."

A guarded test seam (`FLASHY_TEST_SEAM`, requiring an exact non-trivial token) lets the test suite assert on the real suppress/pulse decision instead of terminal timing. It cannot be triggered by an accidentally-inherited env var.

## Key Design Decisions

- Config uses shell-sourceable `KEY=value` format (not JSON) so `flash.sh` can simply `source` it
- The script must always `exit 0` — a non-zero exit from a hook causes Claude Code to surface an error
- OSC 11 terminal query uses `/dev/tty` directly for reading the response, with a short `read -t` timeout for terminals that don't respond
- `CLAUDE_PLUGIN_ROOT` env var is set by Claude Code at runtime and used in `hooks.json` to locate `flash.sh`
- Stop suppression uses a hand-rolled regex scan rather than a JSON parser, to preserve the zero-dependency, pure-Bash promise
