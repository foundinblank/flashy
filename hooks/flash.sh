#!/bin/bash
# Flashy — terminal flash notifications for Claude Code
# Pulses the terminal background color on Stop and Notification hook events.

# --- Config ---
# Source user config first (if it exists), then apply defaults for anything unset.
# Order matters: source first so ${VAR:-default} acts as a true fallback.
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/flashy"
[ -f "$CONFIG_DIR/config" ] && . "$CONFIG_DIR/config"

ENABLED="${ENABLED:-true}"
STOP_PULSES="${STOP_PULSES:-1}"
NOTIFICATION_PULSES="${NOTIFICATION_PULSES:-2}"
PULSE_DURATION="${PULSE_DURATION:-0.22}"
PULSE_GAP="${PULSE_GAP:-0.1}"
SHIFT="${SHIFT:-50}"
FALLBACK_COLOR="${FALLBACK_COLOR:-#1a1b26}"
BG_COLOR_FILE="${BG_COLOR_FILE:-}"

# Early exit if disabled
[ "$ENABLED" = "false" ] && exit 0

# --- Resolve pulse count from event name ---
case "$1" in
  stop)         COUNT="$STOP_PULSES" ;;
  notification) COUNT="$NOTIFICATION_PULSES" ;;
  *)            COUNT=1 ;;
esac

# --- Background color detection (three-tier) ---

# Tier 1: Read from per-TTY color file
# For multi-theme setups where the shell writes bg color to a file per TTY.
detect_from_file() {
  [ -z "$BG_COLOR_FILE" ] && return 1
  # Resolve TTY name (e.g., ttys002) for the {tty} placeholder
  local tty_name
  tty_name=$(ps -p $PPID -o tty= 2>/dev/null | tr -d ' ')
  [ -z "$tty_name" ] && return 1
  local path="${BG_COLOR_FILE//\{tty\}/$tty_name}"
  [ -f "$path" ] && cat "$path" 2>/dev/null && return 0
  return 1
}

# Tier 2: Query terminal via OSC 11
# Sends escape sequence asking the terminal for its current bg color.
# Terminal responds with rgb:RRRR/GGGG/BBBB (16-bit hex per channel).
# Not all terminals support this; /dev/tty reads in subprocess context
# are best-effort. Fails silently → falls through to Tier 3.
detect_from_osc11() {
  local response=""
  # Redirect stdin from terminal for reading the response
  exec < /dev/tty 2>/dev/null || return 1
  # Send the query
  printf '\033]11;?\a' > /dev/tty 2>/dev/null
  # Read with short timeout — terminal may not respond
  read -t 0.1 -r response 2>/dev/null || return 1

  # Extract the rgb: portion
  local rgb="${response#*rgb:}"       # strip everything before "rgb:"
  rgb="${rgb%%[^0-9a-fA-F/]*}"        # strip everything after hex/slash chars

  # Expect: RRRR/GGGG/BBBB (4 hex digits per channel)
  if [[ "$rgb" =~ ^([0-9a-fA-F]{4})/([0-9a-fA-F]{4})/([0-9a-fA-F]{4})$ ]]; then
    # Take high byte of each 16-bit channel → 8-bit color
    local r="${BASH_REMATCH[1]:0:2}"
    local g="${BASH_REMATCH[2]:0:2}"
    local b="${BASH_REMATCH[3]:0:2}"
    printf '#%s%s%s' "$r" "$g" "$b"
    return 0
  fi
  return 1
}

# Run detection cascade
BG_COLOR=$(detect_from_file) ||
BG_COLOR=$(detect_from_osc11) ||
BG_COLOR="$FALLBACK_COLOR"

# --- Compute adaptive flash color ---
# Parse #RRGGBB into decimal components
hex_to_dec() { printf '%d' "0x$1"; }

r=$(hex_to_dec "${BG_COLOR:1:2}")
g=$(hex_to_dec "${BG_COLOR:3:2}")
b=$(hex_to_dec "${BG_COLOR:5:2}")

# Perceived luminance (ITU-R BT.601)
lum=$(( (r * 299 + g * 587 + b * 114) / 1000 ))

# Dark theme → lighten; light theme → darken
if [ "$lum" -lt 128 ]; then
  # Lighten: add SHIFT, clamp to 255
  fr=$(( r + SHIFT )); [ "$fr" -gt 255 ] && fr=255
  fg=$(( g + SHIFT )); [ "$fg" -gt 255 ] && fg=255
  fb=$(( b + SHIFT )); [ "$fb" -gt 255 ] && fb=255
else
  # Darken: subtract SHIFT, clamp to 0
  fr=$(( r - SHIFT )); [ "$fr" -lt 0 ] && fr=0
  fg=$(( g - SHIFT )); [ "$fg" -lt 0 ] && fg=0
  fb=$(( b - SHIFT )); [ "$fb" -lt 0 ] && fb=0
fi

# Format as #RRGGBB
FLASH_COLOR=$(printf '#%02x%02x%02x' "$fr" "$fg" "$fb")

# --- Pulse loop ---
for (( i = 0; i < COUNT; i++ )); do
  # Set terminal bg to flash color
  printf '\033]11;%s\a' "$FLASH_COLOR" > /dev/tty 2>/dev/null
  sleep "$PULSE_DURATION"
  # Restore original bg
  printf '\033]11;%s\a' "$BG_COLOR" > /dev/tty 2>/dev/null
  # Gap between pulses (skip after last)
  if (( i < COUNT - 1 )); then
    sleep "$PULSE_GAP"
  fi
done

exit 0
