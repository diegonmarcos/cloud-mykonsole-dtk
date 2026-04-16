import { spawnSync } from "child_process";
import { join } from "path";

const HOME = process.env.HOME ?? "/home/diego";
const TOOLS = join(HOME, "git/tools");

export const DTK = join(TOOLS, "dtk.sh");
export const CCO = join(TOOLS, "5-infos/engines/cloud-container-orchestrator/cloud-container-orchestrator.sh");
export const COMMANDS = join(TOOLS, "5-infos/commands/commands.sh");
export const CONNECT = join(TOOLS, "3-dashboards/connect.sh");
export const CONTAINERS = join(TOOLS, "4-setups/containers.sh");
export const FISH_TOOLS = join(TOOLS, "4-setups/fish-tools.sh");
export const FISH_SHELL = join(TOOLS, "4-setups/fish-shell.sh");
export const LLMS = join(TOOLS, "4-setups/llms.sh");
export const VAULT = join(TOOLS, "4-setups/vault.sh");
export const SSH_SH = join(TOOLS, "5-infos/ssh/ssh.sh");
export const INSTALL = join(TOOLS, "5-infos/install/install.sh");
export const ENGINES = join(TOOLS, "5-infos/engines/engines.sh");
export const WEBHOOKS = join(TOOLS, "5-infos/webhooks/webhooks.sh");

function stripAnsi(text: string): string {
  return text.replace(/\x1b\[[0-9;]*[A-Za-z]/g, "").replace(/\x1b\][^\x07]*\x07/g, "");
}

export function run(
  cmd: string,
  args: string[],
  timeout = 120_000,
): { text: string; ok: boolean } {
  const result = spawnSync(cmd, args, {
    timeout,
    encoding: "utf-8",
    env: { ...process.env, TERM: "dumb", _DTK_LOGGING: "1" },
    maxBuffer: 10 * 1024 * 1024,
  });
  const stdout = stripAnsi(result.stdout ?? "");
  const stderr = stripAnsi(result.stderr ?? "");
  const ok = result.status === 0;
  const parts = [stdout];
  if (stderr && !ok) parts.push(`--- stderr ---\n${stderr.slice(-2000)}`);
  return { text: parts.join("\n").slice(-8000), ok };
}

export function dtk(shortcode: string, timeout?: number) {
  return run("sh", [DTK, shortcode], timeout);
}

export function cco(cmd: string, vm?: string, timeout?: number) {
  const args = [CCO, cmd];
  if (vm) args.push(vm);
  return run("bash", args, timeout);
}

export function reply(label: string, r: { text: string; ok: boolean }) {
  return {
    content: [{
      type: "text" as const,
      text: `[${label}] ${r.ok ? "OK" : "FAILED"}\n${r.text}`,
    }],
  };
}
