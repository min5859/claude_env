#!/bin/bash
input=$(cat)

# Parse fields
model=$(echo "$input" | jq -r '.model.display_name // empty')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
rate5h=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
rate7d=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
reset5h=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
reset7d=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // empty')
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')

# Colors
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
DIM='\033[2m'
RESET='\033[0m'

# Progress bar for context usage
bar=""
if [ -n "$used" ]; then
  pct=$(printf '%.0f' "$used")
  filled=$((pct / 10))
  empty=$((10 - filled))

  if [ "$pct" -ge 90 ]; then
    color="$RED"
  elif [ "$pct" -ge 70 ]; then
    color="$YELLOW"
  else
    color="$GREEN"
  fi

  bar_fill=""
  bar_empty=""
  for ((i=0; i<filled; i++)); do bar_fill="${bar_fill}█"; done
  for ((i=0; i<empty; i++)); do bar_empty="${bar_empty}░"; done
  bar="${color}${bar_fill}${DIM}${bar_empty}${RESET} ${pct}%"
fi

# Duration
elapsed=""
if [ -n "$duration_ms" ] && [ "$duration_ms" != "0" ]; then
  total_sec=$((duration_ms / 1000))
  mins=$((total_sec / 60))
  secs=$((total_sec % 60))
  elapsed="${mins}m${secs}s"
fi

# Cost
cost_fmt=""
if [ -n "$cost" ] && [ "$cost" != "0" ]; then
  cost_fmt=$(printf '$%.2f' "$cost")
fi

# Rate limits with reset countdown
format_reset() {
  local ts="$1"
  [ -z "$ts" ] && return
  local now
  now=$(date +%s)
  local diff=$((ts - now))
  [ "$diff" -le 0 ] && echo "soon" && return
  local h=$((diff / 3600))
  local m=$(( (diff % 3600) / 60 ))
  if [ "$h" -gt 0 ]; then
    echo "${h}h${m}m"
  else
    echo "${m}m"
  fi
}

rate=""
if [ -n "$rate5h" ]; then
  pct5h=$(printf '%.0f' "$rate5h")
  reset5h_fmt=$(format_reset "$reset5h")
  rate="5h:${pct5h}%${reset5h_fmt:+ (↺${reset5h_fmt})}"
fi
if [ -n "$rate7d" ]; then
  pct7d=$(printf '%.0f' "$rate7d")
  reset7d_fmt=$(format_reset "$reset7d")
  rate="${rate:+$rate }7d:${pct7d}%${reset7d_fmt:+ (↺${reset7d_fmt})}"
fi

# Current directory name
dir=$(basename "$PWD")

# Build output
line1="${CYAN}${model}${RESET}"
[ -n "$dir" ] && line1="${line1} | 📁 ${dir}"
[ -n "$branch" ] && line1="${line1} | 🌿 ${branch}"
[ -n "$bar" ] && line1="${line1} | ${bar}"

line2=""
parts=()
[ -n "$rate" ] && parts+=("Rate $rate")
[ -n "$cost_fmt" ] && parts+=("$cost_fmt")
[ -n "$elapsed" ] && parts+=("$elapsed")

if [ ${#parts[@]} -gt 0 ]; then
  line2="${parts[0]}"
  for ((i=1; i<${#parts[@]}; i++)); do
    line2="${line2} | ${parts[$i]}"
  done
fi

echo -e "$line1"
[ -n "$line2" ] && echo -e "$line2"
