# glm-claude-hub

Display GLM (Zhipu AI) model usage quota in [Claude Code](https://docs.anthropic.com/en/docs/claude-code) statusline via [claude-hud](https://github.com/jarrodwatts/claude-hud).

When using GLM models through Zhipu AI's Anthropic-compatible API, Claude Code does not natively report rate limit or usage data. This wrapper bridges that gap by fetching quota information from Zhipu's monitoring API and injecting it into claude-hud's rendering pipeline.

## Preview

```
[GLM-5.1] │ project-name
Context 0% │ Usage 5h 2% (1h 56m) | Weekly 1% (6d 21h)
```

## How It Works

```
┌─────────────┐    stdin JSON     ┌──────────────┐    augmented JSON    ┌────────────┐
│ Claude Code │ ────────────────> │ glm-wrapper  │ ──────────────────> │ claude-hud │
└─────────────┘                   │              │                      └────────────┘
                                  │ ┌──────────┐ │
                                  │ │ Zhipu    │ │
                                  │ │ API Cache │ │
                                  │ └──────────┘ │
                                  └──────────────┘
```

1. **Claude Code** sends session state via stdin every ~300ms
2. **glm-wrapper** reads stdin and injects Zhipu monitoring API quota data
3. Cache is refreshed every 60s in the background via `GET /api/monitor/usage/quota/limit`
4. The augmented data is passed to claude-hud for rendering

### Quota Types

| API Field | Period | claude-hud Field | Reset Time |
|-----------|--------|------------------|------------|
| `TOKENS_LIMIT (unit=3, number=5)` | 5-hour rolling window | `five_hour` | ~hours |
| `TOKENS_LIMIT (unit=6, number=1)` | Weekly | `seven_day` | ~7 days |
| `TIME_LIMIT (unit=5, number=1)` | Monthly | Not displayed | ~30 days |

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- [bun](https://bun.sh/) runtime
- [claude-hud](https://github.com/jarrodwatts/claude-hud) plugin
- Zhipu AI API Key

## Installation

### Quick Install

```bash
git clone https://github.com/YOUR_USERNAME/glm-claude-hub.git
cd glm-claude-hub
bash install.sh
```

### Manual Installation

#### 1. Install claude-hud

In Claude Code:

```
/install-plugin jarrodwatts/claude-hud
```

#### 2. Copy the wrapper script

```bash
mkdir -p ~/.claude/scripts
cp scripts/glm-wrapper.ts ~/.claude/scripts/glm-wrapper.ts
```

#### 3. Configure environment variables

Edit `~/.claude/settings.json`:

```json
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "<your-zhipu-api-key>",
    "ANTHROPIC_BASE_URL": "https://open.bigmodel.cn/api/anthropic",
    "ANTHROPIC_MODEL": "glm-5.1",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "glm-5.1",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "glm-5.1",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "glm-5"
  }
}
```

#### 4. Set statusline command

In `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "command": "bash -c 'exec \"$HOME/.bun/bin/bun\" --env-file /dev/null \"$HOME/.claude/scripts/glm-wrapper.ts\"'",
    "type": "command"
  }
}
```

#### 5. Configure claude-hud plugin

Edit `~/.claude/plugins/claude-hud/config.json`:

```json
{
  "display": {
    "showAgents": true,
    "showTodos": true,
    "usageBarEnabled": true,
    "showContextBar": true,
    "sevenDayThreshold": 0
  }
}
```

| Field | Description |
|-------|-------------|
| `sevenDayThreshold` | Set to `0` to always show weekly usage (default `80` hides it below 80%) |
| `usageBarEnabled` | Show usage progress bar |
| `showContextBar` | Show context progress bar |
| `showAgents` | Show sub-agent info |
| `showTodos` | Show todo list |

#### 6. Restart Claude Code

Exit and restart Claude Code to see the statusline in action.

## Troubleshooting

### Statusline not showing

1. Check bun is installed: `which bun`
2. Test the wrapper manually:
   ```bash
   echo '{"model":{"id":"glm-5.1"},"context_window":{},"cwd":"/tmp"}' | \
     bun --env-file /dev/null ~/.claude/scripts/glm-wrapper.ts
   ```
3. Check `statusLine.command` path in `~/.claude/settings.json`

### Usage/Weekly not displaying

1. Check cache file: `cat ~/.cache/zhipu-usage.json | jq '.code'`
2. Test API manually:
   ```bash
   curl -sf -H "Authorization: $ANTHROPIC_AUTH_TOKEN" \
     "https://open.bigmodel.cn/api/monitor/usage/quota/limit" | jq '.'
   ```
3. Verify `ANTHROPIC_AUTH_TOKEN` is set

### claude-hud update breaks it

The wrapper auto-discovers the latest claude-hud version. If claude-hud's internal API changes, the wrapper may need updating.

## License

[MIT](LICENSE)
