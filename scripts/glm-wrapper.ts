#!/usr/bin/env bun
/**
 * GLM Usage Wrapper for claude-hud
 *
 * Reads Claude Code's stdin JSON, injects Zhipu AI monitoring API quota data,
 * then passes it to claude-hud for rendering.
 *
 * Quota data is cached at ~/.cache/zhipu-usage.json and refreshed every 60s
 * via a background HTTP call to the Zhipu monitoring API.
 */

import { readFileSync, readdirSync, existsSync, mkdirSync, statSync } from "node:fs";
import { spawn, execSync } from "node:child_process";
import { join, dirname } from "node:path";
import { homedir } from "node:os";

const CACHE_PATH = join(homedir(), ".cache", "zhipu-usage.json");
const CACHE_TTL = 60_000; // 60 seconds

function ensureCacheDir() {
  const dir = dirname(CACHE_PATH);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
}

function refreshCacheBackground() {
  const token = process.env.ANTHROPIC_AUTH_TOKEN;
  if (!token) return;
  ensureCacheDir();
  try {
    const child = spawn(
      "curl",
      [
        "-sf", "--max-time", "5",
        "-H", `Authorization: ${token}`,
        "https://open.bigmodel.cn/api/monitor/usage/quota/limit",
        "-o", CACHE_PATH,
      ],
      { detached: true, stdio: "ignore" }
    );
    child.unref();
  } catch {}
}

function readCache(): any[] | null {
  try {
    if (!existsSync(CACHE_PATH)) return null;
    const age = Date.now() - statSync(CACHE_PATH).mtimeMs;
    if (age > CACHE_TTL * 10) return null; // discard cache older than 10 minutes
    const raw = readFileSync(CACHE_PATH, "utf8");
    const resp = JSON.parse(raw);
    if (resp.code === 200 && resp.data?.limits) return resp.data.limits;
  } catch {}
  return null;
}

function readStdin(): Promise<string> {
  return new Promise((resolve) => {
    let data = "";
    let done = false;
    const finish = () => {
      if (!done) { done = true; resolve(data); }
    };
    const timer = setTimeout(finish, 250);
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (c: string) => { data += c; });
    process.stdin.on("end", finish);
    process.stdin.on("error", finish);
  });
}

function findClaudeHudDir(): string {
  const configDir = process.env.CLAUDE_CONFIG_DIR || join(homedir(), ".claude");
  const base = join(configDir, "plugins/cache/claude-hud/claude-hud");
  try {
    if (!existsSync(base)) return "";
    const versions = readdirSync(base)
      .filter((name) => {
        const p = join(base, name);
        return statSync(p).isDirectory() && /^\d+\.\d+\.\d+$/.test(name);
      })
      .sort((a, b) => {
        const pa = a.split(".").map(Number);
        const pb = b.split(".").map(Number);
        for (let i = 0; i < 3; i++) {
          if ((pa[i] ?? 0) !== (pb[i] ?? 0)) return (pa[i] ?? 0) - (pb[i] ?? 0);
        }
        return 0;
      });
    if (versions.length === 0) return "";
    return join(base, versions[versions.length - 1]) + "/";
  } catch { return ""; }
}

(async () => {
  const raw = (await readStdin()).trim();
  if (!raw) return;

  let stdin: any;
  try { stdin = JSON.parse(raw); } catch { return; }

  // Refresh cache in background when expired (non-blocking)
  try {
    if (!existsSync(CACHE_PATH) || Date.now() - statSync(CACHE_PATH).mtimeMs > CACHE_TTL) {
      refreshCacheBackground();
    }
  } catch {}

  // Inject Zhipu API quota data
  // The API returns 3 quota types:
  //   TOKENS_LIMIT (unit=3, number=5) -> 5-hour rolling window, resets in ~hours
  //   TOKENS_LIMIT (unit=6, number=1) -> weekly, resets in ~7 days
  //   TIME_LIMIT   (unit=5, number=1) -> monthly, resets in ~30 days (not displayed)
  const limits = readCache();
  if (limits) {
    const fiveHour = limits.find(
      (l: any) => l.type === "TOKENS_LIMIT" && l.unit === 3 && l.number === 5
    );
    const weekly = limits.find(
      (l: any) => l.type === "TOKENS_LIMIT" && l.unit === 6 && l.number === 1
    );

    stdin.rate_limits = {};
    if (fiveHour) {
      stdin.rate_limits.five_hour = {
        used_percentage: fiveHour.percentage,
        resets_at: Math.floor(fiveHour.nextResetTime / 1000),
      };
    }
    if (weekly) {
      stdin.rate_limits.seven_day = {
        used_percentage: weekly.percentage,
        resets_at: Math.floor(weekly.nextResetTime / 1000),
      };
    }
  }

  // Find and run claude-hud
  const pluginDir = findClaudeHudDir();
  if (!pluginDir) return;

  // Set COLUMNS so claude-hud detects terminal width correctly
  const childEnv = { ...(process.env as Record<string, string>) };
  if (!childEnv.COLUMNS) {
    try {
      childEnv.COLUMNS = execSync("tput cols 2>/dev/null", {
        encoding: "utf8", timeout: 1000,
      }).trim() || "200";
    } catch { childEnv.COLUMNS = "200"; }
  }

  const bunPath = process.env.HOME + "/.bun/bin/bun";
  const child = spawn(
    bunPath,
    ["--env-file", "/dev/null", join(pluginDir, "src/index.ts")],
    { env: childEnv, stdio: ["pipe", "pipe", "pipe"] }
  );

  const timeout = setTimeout(() => { child.kill(); }, 3000);

  child.stdin.write(JSON.stringify(stdin));
  child.stdin.end();

  let output = "";
  child.stdout.on("data", (c: Buffer) => { output += c.toString(); });
  child.stdout.on("end", () => {
    clearTimeout(timeout);
    if (output) process.stdout.write(output);
  });
  child.on("error", () => { clearTimeout(timeout); });
})();
