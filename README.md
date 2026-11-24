# fricas-docker

FriCAS for Bill Page's machines: a Docker image on STRIX with FriCAS built from the
[fricas/fricas](https://github.com/fricas/fricas) git repository on an SBCL built from
source, dev builds of [billpage/fricas-dev](https://github.com/billpage/fricas-dev), and
`run_fricas`, a local MCP tool that lets Claude desktop-app chats on STRIX and ASUS run
FriCAS in the container. Claude's instructions for using it are the `fricas` skill in
`billpage/claude-plugins` (`research:fricas`).

```
Dockerfile, Makefile     the image and container (FriCAS 1.4.0, SBCL 2.6.10, GMP)
scripts/                 copied into the image: fricas (variant wrapper), fricas-variant, fricas-dev-build
tool/                    run_fricas: MCP server, runners, installer (installed into ~/maple-connector)
```

| Path on STRIX | In container | What |
|---|---|---|
| (image) | `/usr/local/bin/sbcl` | SBCL `$(SBCL_TAG)`, default heap 8 GiB (`--dynamic-space-size=8Gb` at build) |
| (image) | `/opt/fricas/<ref>`, `/opt/fricas/release` | release FriCAS; `make-check.log` / `.status` from the build |
| (image) | `/usr/local/src/fricas` | its source (tag `<ref>`) |
| `~/fricas-work` | `/home/fricas/work` | runs: `runs/<stem>/` (container side), `host-runs/` (tool side) |
| `~/fricas-dev` | `/home/fricas/dev` | `src/fricas` (git clone, on the host), `build/<name>`, `install/<name>`, `install/current`, `variant` |

The container user `fricas` has wspage's UID/GID, so everything written to the mounts
belongs to wspage.

## Build and start (on STRIX, in this clone)

```bash
make build          # SBCL + FriCAS + FriCAS's test suite; log in build-<ref>-<sbcl>.log
make run            # container "fricas", restart unless-stopped, no ports
make check          # versions, heap, factor(2^64-1), Gaussian integral, test-suite status
make check-log      # tail of the test-suite log
```

Variables (override on the make command line): `SBCL_TAG`, `SBCL_OPTS`, `FRICAS_REF`,
`JOBS` (12), `RUN_CHECK` (1). If the parallel build fails, retry with `JOBS=1`. A new
version (`make build SBCL_TAG=sbcl-2.6.11`) gets a new image tag; a rebuild with the same
tag keeps the replaced image as `<tag>-prev`. Switch with `make restart` (or
`make restart IMAGE=<tag>` to go back). Dev builds live on the host and survive both.

Interactive use: `make fricas` (FriCAS, release or the chosen variant), `make sbcl`,
`make shell`. In the container, `fricas` is a wrapper that picks the build:
`$FRICAS_VARIANT`, else the word in `~/dev/variant` (set by `fricas-variant`), else
`release`.

## Dev builds

Git happens on the host (`~/fricas-dev/src/fricas`, origin
`git@github.com:billpage/fricas-dev.git` over ssh, upstream fricas/fricas); builds happen
in the container:

```bash
docker exec -d fricas fricas-dev-build master --activate   # in the background; log below
tail -f ~/fricas-dev/build/master/build.log                # ends with "=== … build 'master' ok"
docker exec fricas fricas-variant                          # show the default and the builds
```

Options: `--clean` (reconfigure from scratch), `-- <configure args>` (first run or with
`--clean`), `JOBS=n`. A later run of the same name is incremental. New Spad files need no
dev build: `)compile` them in the release FriCAS.

## The run_fricas tool (`tool/`)

The Claude desktop app starts `fricas_mcp.py` as a local stdio MCP server (in the
`~/maple-connector` venv, next to the maple and sage servers). Its tool
`run_fricas(code, name, timeout, variant, output, spad)` saves the script under
`~/fricas-work/host-runs/<stamp>-<name>/` and runs it with `FRICAS_RUNNER`:
`run_fricas_container.sh` on STRIX (local `docker exec`), `run_fricas_ssh.sh` on other
LAN machines (ssh to STRIX, which runs the container runner). Both take
`DIR/STEM.input [timeout]`, send `DIR/STEM.spad` along if present, honour
`FRICAS_VARIANT` and `FRICAS_OUTPUT`, write `STEM.out` and `STEM.log`, and exit 0 (ok),
1 (FriCAS error), 124 (timeout), 2 (usage) or 3 (container/variant/ssh).

How a run behaves:
- `)set breakmode quit`: the first error of any kind (interpreter, library, Lisp, parse,
  Spad compile, missing file, stack exhaustion) ends the run with exit status 1.
- The script is run with `)read`, so input lines are echoed; prompts and banner are
  removed (the banner is cut at a marker printed from Lisp).
- `output=1d` (default): results in `Format1D` one-line form via
  `setFormat!(Format1D)$JFriCASSupport`. `)compile` and `)lib` reset that setting in
  FriCAS 1.4.0, so the runner re-applies it after every system-command line (tagged
  `-- @@1D@@`, removed from the output). `output=2d`: classic 2-D display.

Install or update on both machines, from ASUS (STRIX first, because the ASUS
installer's test run goes through STRIX):

```bash
ssh wspage@192.168.4.73 'cd ~/fricas-docker && git pull && tool/install.sh strix'
cd ~/fricas-docker && git pull && tool/install.sh asus      # a clone on ASUS too
```

`install.sh` copies the files into `~/maple-connector`, adds `mcpServers.fricas` to
`~/.config/Claude/claude_desktop_config.json` (backup `.bak-fricas`) and runs a test.
Then restart the desktop app (`killall -9 claude-desktop`, reopen) so it loads the server.

## History

Set up on 2026-11-24 in Claude's Compute project, where the plan and its test record are
kept (`claude/strix-fricas-container-plan.md`). The first image was built before two
Dockerfile fixes; it was rebuilt from this repository the same afternoon (FriCAS step
145 s with `JOBS=12`), and that build reports SBCL `2.6.10` and `make check: ok` (the
test suite now runs as user `fricas`; as root, `files.input`'s `chmod 400` test fails).
The tool was rechecked against it for the release and the `master` dev build.

## Rules

Claude pushes `claude/<topic>` branches only; Bill reviews and merges.
