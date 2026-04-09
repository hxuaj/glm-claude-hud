#!/usr/bin/env bash
# glm-claude-hub installer
# Copies the wrapper script to ~/.claude/scripts/ and configures settings.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WRAPPER_SRC="$SCRIPT_DIR/scripts/glm-wrapper.ts"
WRAPPER_DEST="$HOME/.claude/scripts/glm-wrapper.ts"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "==> glm-claude-hub installer"

# Check prerequisites
if ! command -v bun &>/dev/null; then
  echo "Error: bun is not installed. Install it from https://bun.sh/"
  exit 1
fi

# Create scripts directory
mkdir -p "$(dirname "$WRAPPER_DEST")"

# Copy wrapper script
cp "$WRAPPER_SRC" "$WRAPPER_DEST"
echo "==> Copied wrapper script to $WRAPPER_DEST"

# Configure settings.json
if [ ! -f "$SETTINGS_FILE" ]; then
  echo '{}' > "$SETTINGS_FILE"
fi

# Use a temp file with node/node-json editing to update settings
node -e "
const fs = require('fs');
const path = '$SETTINGS_FILE'.replace('$HOME', process.env.HOME);
let settings = {};
try { settings = JSON.parse(fs.readFileSync(path, 'utf8')); } catch {}
settings.env = settings.env || {};
settings.statusLine = {
  command: \"bash -c 'exec \\\"\\$HOME/.bun/bin/bun\\\" --env-file /dev/null \\\"\\$HOME/.claude/scripts/glm-wrapper.ts\\\"'\",
  type: 'command'
};
fs.writeFileSync(path, JSON.stringify(settings, null, 2) + '\n');
console.log('==> Updated ' + path);
"

echo ""
echo "==> Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Make sure ANTHROPIC_AUTH_TOKEN is set in ~/.claude/settings.json env section"
echo "  2. Install claude-hud plugin: /install-plugin jarrodwatts/claude-hud"
echo "  3. Configure claude-hud: see README.md for plugin config"
echo "  4. Restart Claude Code"
