#!/usr/bin/env bash
# run_fricas_ssh.sh: run a FriCAS script in the "fricas" container on STRIX from another
# LAN machine, by ssh to the STRIX host and its run_fricas_container.sh.
#
# Usage: run_fricas_ssh.sh DIR/STEM.input [timeout_seconds]
#   DIR/STEM.spad, if present, is sent too (compiled before the script).
# Writes DIR/STEM.out (the cleaned output returned by STRIX).
# Exit: 0 ok, 1 FriCAS error, 124 timeout, 2 usage, 3 ssh/container/variant failure.
#
# The files go over ssh as a tar stream to STRIX ~/fricas-work/host-runs/<host>-STEM/
# (renamed <host>-STEM.*), then STRIX's container runner takes over. FRICAS_VARIANT
# and FRICAS_OUTPUT are passed along (ssh does not forward the environment).
#
# Overrides: FRICAS_SSH_HOST (wspage@192.168.4.73), FRICAS_SSH_PORT (22),
#            FRICAS_REMOTE_RUNNER (~/maple-connector/run_fricas_container.sh).
set -u

script=${1:-}
timeout=${2:-300}
if [[ -z $script || ! -f $script || $script != *.input || ! $timeout =~ ^[0-9]+$ ]]; then
    echo "usage: $0 DIR/STEM.input [timeout_seconds]" >&2
    exit 2
fi
variant=${FRICAS_VARIANT:-release}
output=${FRICAS_OUTPUT:-1d}
if [[ ! $variant =~ ^[A-Za-z0-9._-]+$ || ! $output =~ ^(1d|2d)$ ]]; then
    echo "bad FRICAS_VARIANT or FRICAS_OUTPUT" >&2
    exit 2
fi

host=${FRICAS_SSH_HOST:-wspage@192.168.4.73}
port=${FRICAS_SSH_PORT:-22}
runner=${FRICAS_REMOTE_RUNNER:-'~/maple-connector/run_fricas_container.sh'}
dir=$(cd "$(dirname "$script")" && pwd)
stem=$(basename "$script" .input)
rstem="$(hostname -s)-$stem"
out=$dir/$stem.out
files=("$stem.input")
[[ -f $dir/$stem.spad ]] && files+=("$stem.spad")

# Remote side: unpack into its own run directory, then hand over to the container runner.
remote='d=~/fricas-work/host-runs/$1; mkdir -p "$d" && tar -xf - -C "$d" || exit 3
FRICAS_VARIANT=$3 FRICAS_OUTPUT=$4 exec '"$runner"' "$d/$1.input" "$2"'
tar -cf - -C "$dir" --transform "s|^$stem\\.|$rstem.|" "${files[@]}" |
ssh -4 -T -p "$port" -o BatchMode=yes -o ConnectTimeout=10 "$host" \
    "bash -c $(printf %q "$remote") _ $(printf %q "$rstem") $timeout $variant $output" \
    > "$out" 2>&1
rc=$?

cat "$out"
case $rc in
    0|1|2|3|124) exit $rc ;;
    *)           exit 3 ;;      # 255 = ssh itself failed
esac
