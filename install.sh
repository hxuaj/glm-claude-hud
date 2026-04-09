#!/usr/bin/env bash
# glm-claude-hub installer
# Copies the wrapper script, configures settings.json and claude-hud plugin

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WRAPPER_SRC="$SCRIPT_DIR/scripts/glm-wrapper.ts"
WRAPPER_DEST="$HOME/.claude/scripts/glm-wrapper.ts"
SETTINGS_FILE="$HOME/.claude/settings.json"
HUD_CONFIG_FILE="$HOME/.claude/plugins/claude-hud/config.json"

echo "==> glm-claude-hub installer"
echo ""

# ── Check prerequisites ──────────────────────────────────────────────
if ! command -v bun &>/dev/null; then
  echo "Error: bun is not installed. Install it from https://bun.sh/"
  exit 1
fi

HUD_PLUGIN_DIR="$HOME/.claude/plugins/cache/claude-hud/claude-hud"
if [ ! -d "$HUD_PLUGIN_DIR" ]; then
  echo "Error: claude-hud plugin not found."
  echo "Please install it first in Claude Code:"
  echo "  /install-plugin jarrodwatts/claude-hud"
  echo ""
  echo "Then re-run this installer."
  exit 1
fi

# ── 1. Copy wrapper script ───────────────────────────────────────────
mkdir -p "$(dirname "$WRAPPER_DEST")"
cp "$WRAPPER_SRC" "$WRAPPER_DEST"
echo "[1/4] Copied wrapper script to $WRAPPER_DEST"

# ── 2. Configure settings.json (env + statusLine) ────────────────────
mkdir -p "$(dirname "$SETTINGS_FILE")"
if [ ! -f "$SETTINGS_FILE" ]; then
  echo '{}' > "$SETTINGS_FILE"
fi

# Use bun to edit JSON (since bun is a prerequisite)
bun -e "
const fs = require('fs');
const path = '$SETTINGS_FILE'.replace('\$HOME', process.env.HOME);
let settings = {};
try { settings = JSON.parse(fs.readFileSync(path, 'utf8')); } catch {}

// Set env vars
settings.env = settings.env || {};
if (!settings.env.ANTHROPIC_BASE_URL) {
  settings.env.ANTHROPIC_BASE_URL = 'https://open.bigmodel.cn/api/anthropic';
}
if (!settings.env.ANTHROPIC_MODEL) {
  settings.env.ANTHROPIC_MODEL = 'glm-5.1';
}
if (!settings.env.ANTHROPIC_DEFAULT_SONNET_MODEL) {
  settings.env.ANTHROPIC_DEFAULT_SONNET_MODEL = 'glm-5.1';
}
if (!settings.env.ANTHROPIC_DEFAULT_OPUS_MODEL) {
  settings.env.ANTHROPIC_DEFAULT_OPUS_MODEL = 'glm-5.1';
}
if (!settings.env.ANTHROPIC_DEFAULT_HAIKU_MODEL) {
  settings.env.ANTHROPIC_DEFAULT_HAIKU_MODEL = 'glm-5';
}

// Set statusLine
settings.statusLine = {
  command: \"bash -c 'exec \\\"\\$HOME/.bun/bin/bun\\\" --env-file /dev/null \\\"\\$HOME/.claude/scripts/glm-wrapper.ts\\\"'\",
  type: 'command'
};

fs.writeFileSync(path, JSON.stringify(settings, null, 2) + '\n');
console.log('Updated ' + path);
"
echo "[2/4] Configured settings.json (statusLine + env)"

# ── 3. Configure claude-hud plugin ───────────────────────────────────
mkdir -p "$(dirname "$HUD_CONFIG_FILE")"
if [ ! -f "$HUD_CONFIG_FILE" ]; then
  echo '{}' > "$HUD_CONFIG_FILE"
fi

bun -e "
const fs = require('fs');
const path = '$HUD_CONFIG_FILE'.replace('\$HOME', process.env.HOME);
let config = {};
try { config = JSON.parse(fs.readFileSync(path, 'utf8')); } catch {}

config.display = config.display || {};
config.display.showAgents = true;
config.display.showTodos = true;
config.display.usageBarEnabled = true;
config.display.showContextBar = true;
config.display.sevenDayThreshold = 0;

fs.writeFileSync(path, JSON.stringify(config, null, 2) + '\n');
console.log('Updated ' + path);
"
echo "[3/4] Configured claude-hud plugin"

# ── 4. Prompt for API key ────────────────────────────────────────────
if [ -z "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
  echo ""
  echo "ANTHROPIC_AUTH_TOKEN is not set."
  read -rp "Enter your Zhipu AI API key: " api_key
  if [ -n "$api_key" ]; then
    bun -e "
const fs = require('fs');
const path = '$SETTINGS_FILE'.replace('\$HOME', process.env.HOME);
const settings = JSON.parse(fs.readFileSync(path, 'utf8'));
settings.env = settings.env || {};
settings.env.ANTHROPIC_AUTH_TOKEN = '$api_key';
fs.writeFileSync(path, JSON.stringify(settings, null, 2) + '\n');
"
    echo "[4/4] API key saved to settings.json"
  else
    echo "[4/4] Skipped — please set ANTHROPIC_AUTH_TOKEN in $SETTINGS_FILE"
  fi
else
  echo "[4/4] ANTHROPIC_AUTH_TOKEN already set in environment"
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "==> Installation complete! Restart Claude Code to apply."
