# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Flashy is a Claude Code plugin written in pure Bash that pulses the terminal background color when Claude finishes a turn (Stop event) or sends a notification. It has zero external dependencies.

## Architecture

- **`.claude-plugin/plugin.json`** — Plugin metadata (name, version, author)
- **`hooks/hooks.json`** — Registers two Claude Code hook events (Stop, Notification), each calling `flash.sh` with the event name as `$1`
- **`hooks/flash.sh`** — The entire implementation in one script:
  1. Sources user config from `${XDG_CONFIG_HOME:-$HOME/.config}/flashy/config` (if it exists), then applies bash parameter expansion defaults
  2. Detects terminal background color via three-tier cascade: per-TTY color file → OSC 11 terminal query → static `FALLBACK_COLOR`
  3. Computes adaptive flash color by measuring luminance and shifting RGB toward white (dark themes) or black (light themes)
  4. Runs a pulse loop: set bg to flash color via OSC 11, sleep, restore original bg
- **`config.default`** — Reference template for user config; not read at runtime
- **`DESIGN.md`** — Detailed technical design document

## Commands

There is no build system, linter, or test suite. Manual testing:

```bash
# Test flash directly (must be run in a supported terminal, not VS Code)
./hooks/flash.sh stop
./hooks/flash.sh notification

# Install as Claude Code plugin
claude plugin add /path/to/flashy
```

## Key Design Decisions

- Config uses shell-sourceable `KEY=value` format (not JSON) so `flash.sh` can simply `source` it
- The script must always `exit 0` — a non-zero exit from a hook causes Claude Code to surface an error
- OSC 11 terminal query uses `/dev/tty` directly for reading the response, with a short `read -t` timeout for terminals that don't respond
- `CLAUDE_PLUGIN_ROOT` env var is set by Claude Code at runtime and used in `hooks.json` to locate `flash.sh`
