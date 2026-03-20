#!/usr/bin/env bash
set -euo pipefail

# Locate ourselves — works whether installed in project or ~/.claude
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read stdin (hook protocol sends JSON with tool details)
HOOK_INPUT=$(cat)

EVENT="${1:-PostToolUse}"

# Skip if this is a sprite-env command (e.g. invoked by /sprite skill)
if [ "$EVENT" = "PostToolUse" ]; then
  tool_cmd=$(echo "$HOOK_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
  if [[ "$tool_cmd" == *"sprite-env"* ]]; then
    exit 0
  fi
fi

# Cooldown: skip if last check was <30s ago (avoids repeated checks on rapid tool calls)
# Use /tmp with a project-scoped key so we don't write into config dirs
PROJ_HASH=$(echo "${CLAUDE_PROJECT_DIR:-unknown}" | md5sum | cut -c1-8)
COOLDOWN_FILE="/tmp/.sprite-env-check-${PROJ_HASH}"
NOW=$(date +%s)
if [ -f "$COOLDOWN_FILE" ]; then
  LAST_CHECK=$(cat "$COOLDOWN_FILE" 2>/dev/null || echo 0)
  if [ $(( NOW - LAST_CHECK )) -lt 30 ]; then
    exit 0
  fi
fi
echo "$NOW" > "$COOLDOWN_FILE"

WARNINGS=""

# --- Checkpoint staleness check ---
check_checkpoints() {
  local cp_json
  cp_json=$(sprite-env checkpoints list 2>/dev/null) || return 0

  local latest_time
  latest_time=$(echo "$cp_json" | jq -r '
    [ .[] | select(.id != "Current") ] | sort_by(.create_time) | last | .create_time // empty
  ' 2>/dev/null) || return 0

  if [ -z "$latest_time" ]; then
    WARNINGS="${WARNINGS}Checkpoint warning: No versioned checkpoints exist yet. If you have hit any milestones, run a checkpoint using \`sprite-env checkpoints create --comment \"description\"\` so you can safely experiment and restore later.\n"
    return 0
  fi

  local cp_epoch now_epoch age_min
  cp_epoch=$(date -d "$latest_time" +%s 2>/dev/null) || return 0
  now_epoch=$(date -u +%s)
  age_min=$(( (now_epoch - cp_epoch) / 60 ))

  if [ "$age_min" -ge 10 ]; then
    WARNINGS="${WARNINGS}Checkpoint warning: Latest checkpoint is ${age_min} minutes old (created ${latest_time}). If you have hit any milestones, run a checkpoint using \`sprite-env checkpoints create --comment \"description\"\` so you can safely experiment and restore later.\n"
  fi
}

# --- Service health check ---
check_services() {
  local svc_json
  svc_json=$(sprite-env services list 2>/dev/null) || return 0

  local unhealthy
  unhealthy=$(echo "$svc_json" | jq -r '
    [ .[] | select(.state.status != "running") ] |
    if length == 0 then empty
    else .[] | "  - \(.name): status=\(.state.status)" +
      (if .state.error then " error=\(.state.error)" else "" end) +
      (if .state.restart_count and .state.restart_count > 0 then " restarts=\(.state.restart_count)" else "" end)
    end
  ' 2>/dev/null) || return 0

  if [ -n "$unhealthy" ]; then
    WARNINGS="${WARNINGS}Service warning: Some services are not running:\n${unhealthy}\nUse the /sprite skill to investigate and fix service issues.\n"
  fi
}

check_checkpoints
check_services

# Only produce output if there are warnings
if [ -n "$WARNINGS" ]; then
  json_warnings=$(printf '%b' "$WARNINGS" | jq -Rs '.' 2>/dev/null) || exit 0
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "${EVENT}",
    "additionalContext": ${json_warnings}
  }
}
EOF
fi

exit 0
