#!/usr/bin/env python3
"""fricas_mcp.py: lets claude.ai chats run FriCAS on Bill's STRIX server.

One tool, run_fricas(code, name, timeout, variant, output, spad): saves the code as
~/fricas-work/host-runs/<stamp>-<name>/<stamp>-<name>.input (plus .spad if given) on
this machine, runs it with FRICAS_RUNNER (run_fricas_container.sh on STRIX,
run_fricas_ssh.sh elsewhere), and returns the status and output.

Started by the Claude desktop app as a local stdio MCP server:
    python3 fricas_mcp.py
Uses the same venv as maple_mcp.py and sage_mcp.py (MCP Python SDK 2.x).
"""
import os
import pathlib
import re
import subprocess
import time

from mcp.server.mcpserver import MCPServer

RUNNER = os.path.expanduser(
    os.environ.get("FRICAS_RUNNER", "~/maple-connector/run_fricas_container.sh"))
RUNS = pathlib.Path(os.path.expanduser(
    os.environ.get("FRICAS_RUNS", "~/fricas-work/host-runs")))
MAX_TIMEOUT = 1800        # seconds
MAX_OUTPUT = 100_000      # characters returned to the chat

server = MCPServer(
    "fricas",
    instructions=(
        "Runs FriCAS 1.4.0 (SBCL, Docker container on STRIX) as a script read with "
        ")read, so each input line is echoed before its result. Each call is a fresh "
        "FriCAS process. The run stops at the first error of any kind (interpreter, "
        "library, Lisp, parse, Spad compile) with status 'FriCAS reported an error': "
        "the message just before the end is the error to fix. Results are shown in "
        "one-line Format1D form by default (re-enterable, e.g. 3*5*17, sqrt(%pi)) "
        "followed by their Type; output='2d' gives the classic 2-D display. To test "
        "Spad code, pass it as 'spad': it is compiled with )compile before the script "
        "runs. variant='dev' (or a build name) uses Bill's development build. Use "
        ")lisp for native Lisp (SBCL). Do not end the script with )quit. Check "
        "symbolic results numerically before relying on them."),
)


@server.tool()
def run_fricas(code: str, name: str = "run", timeout: int = 300,
               variant: str = "release", output: str = "1d",
               spad: str = "") -> str:
    """Run a FriCAS script on Bill's server and return its output.

    code: FriCAS interpreter input, one command per line (system commands such as
          )set, )lisp, )show, )compile are allowed). No )quit needed.
    name: short label used in the saved file names.
    timeout: seconds before the run is killed (max 1800).
    variant: 'release' (FriCAS 1.4.0), 'dev' (Bill's current development build),
             or the name of a specific dev build.
    output: '1d' (default, one-line results) or '2d' (classic 2-D layout).
    spad: optional Spad source; saved next to the script and compiled before it.

    Returns a status line (ok / FriCAS reported an error / timed out / ...),
    the saved script path, and the output.
    """
    if not re.fullmatch(r"[A-Za-z0-9._-]+", variant or ""):
        return "status: bad variant (letters, digits, . _ - only)"
    if output not in ("1d", "2d"):
        return "status: output must be '1d' or '2d'"
    label = "".join(c if c.isalnum() or c in "-_" else "_" for c in name)[:40]
    stem = f"{time.strftime('%Y%m%d-%H%M%S')}-{label or 'run'}"
    rundir, n = RUNS / stem, 1
    while rundir.exists():            # two runs in the same second
        n += 1
        rundir = RUNS / f"{stem}-{n}"
    rundir.mkdir(parents=True)
    script = rundir / f"{rundir.name}.input"
    script.write_text(code if code.endswith("\n") else code + "\n")
    if spad.strip():
        script.with_suffix(".spad").write_text(spad)
    timeout = max(1, min(int(timeout), MAX_TIMEOUT))
    env = dict(os.environ, FRICAS_VARIANT=variant, FRICAS_OUTPUT=output)

    try:
        # stdin=DEVNULL: our stdin is the MCP stream; the runner must never read it.
        p = subprocess.run([RUNNER, str(script), str(timeout)], cwd=rundir, env=env,
                           stdin=subprocess.DEVNULL, capture_output=True,
                           text=True, timeout=timeout + 90)
        rc = p.returncode
        out = p.stdout + (f"\n[stderr]\n{p.stderr}" if p.stderr.strip() else "")
    except subprocess.TimeoutExpired:
        rc, out = 124, ""

    status = {0: "ok", 1: "FriCAS reported an error (run stopped there)",
              124: f"timed out after {timeout}s",
              2: "runner usage error",
              3: ("container not reachable, or the requested variant is not built "
                  "(is the 'fricas' container running?)"),
              }.get(rc, f"exit code {rc}")
    if len(out) > MAX_OUTPUT:
        out = (out[:MAX_OUTPUT] +
               f"\n[truncated; full output in {script.with_suffix('.out')}]")
    return (f"status: {status}\nvariant: {variant}, output: {output}\n"
            f"script: {script}\n---\n{out}")


if __name__ == "__main__":
    server.run("stdio")
