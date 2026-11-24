#!/usr/bin/env bash
# install.sh strix|asus : install the run_fricas tool for the Claude desktop app.
#   strix: runner = run_fricas_container.sh (local docker, container "fricas")
#   asus (any other LAN machine): runner = run_fricas_ssh.sh (ssh to STRIX)
# Copies the files into ~/maple-connector (next to maple_mcp.py and sage_mcp.py, reusing
# its venv), adds mcpServers.fricas to ~/.config/Claude/claude_desktop_config.json
# (backup: .bak-fricas), and runs one test script through the runner.
set -eu
role=${1:-}
here=$(cd "$(dirname "$0")" && pwd)
mc=$HOME/maple-connector
case $role in
    strix) runner=$mc/run_fricas_container.sh ;;
    asus)  runner=$mc/run_fricas_ssh.sh ;;
    *)     echo "usage: $0 strix|asus" >&2; exit 2 ;;
esac
[[ -x $mc/venv/bin/python ]] || { echo "missing $mc/venv (set up for maple/sage first)" >&2; exit 1; }

install -m 755 "$here/run_fricas_container.sh" "$here/run_fricas_ssh.sh" "$mc/"
install -m 644 "$here/fricas_mcp.py" "$mc/"
mkdir -p "$HOME/fricas-work/host-runs"
(cd "$mc" && sha256sum fricas_mcp.py run_fricas_container.sh run_fricas_ssh.sh | cut -c1-16,65-)

cfg=$HOME/.config/Claude/claude_desktop_config.json
[[ -f $cfg ]] && cp "$cfg" "$cfg.bak-fricas"
python3 - "$cfg" "$mc" "$runner" <<'PY'
import json, os, sys
path, mc, runner = sys.argv[1:]
cfg = json.load(open(path)) if os.path.exists(path) else {}
cfg.setdefault("mcpServers", {})["fricas"] = {
    "command": f"{mc}/venv/bin/python",
    "args": [f"{mc}/fricas_mcp.py"],
    "env": {"FRICAS_RUNNER": runner},
}
json.dump(cfg, open(path, "w"), indent=2)
print("desktop config mcpServers:", ", ".join(cfg["mcpServers"]))
PY

t=$HOME/fricas-work/host-runs/install-test-$role
mkdir -p "$t"
printf '%s\n' 'factor(2^64-1)' ')lisp (lisp-implementation-version)' > "$t/install-test-$role.input"
echo "--- test run via $(basename "$runner")"
"$runner" "$t/install-test-$role.input" 120 && echo "--- runner ok" || echo "--- runner exit $?"
echo "Now restart the Claude desktop app on this machine: killall -9 claude-desktop, then reopen it."
