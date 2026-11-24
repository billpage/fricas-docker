#!/usr/bin/env bash
# run_fricas_container.sh: run a FriCAS script in the local "fricas" Docker container.
#
# Usage: run_fricas_container.sh DIR/STEM.input [timeout_seconds]
#   If DIR/STEM.spad exists it is sent too and compiled ()compile) before the script.
# Writes DIR/STEM.out (cleaned output) and DIR/STEM.log (raw FriCAS output).
# Exit: 0 ok, 1 FriCAS error (run stops at the first error), 124 timeout,
#       2 usage, 3 container not running / variant not built / docker failure.
#
# Environment:
#   FRICAS_VARIANT  release (default) | dev | <build name>   (see fricas-variant)
#   FRICAS_OUTPUT   1d (default: one-line Format1D output) | 2d (classic 2-D output)
#   FRICAS_CONTAINER (fricas), FRICAS_USER (fricas), FRICAS_WORKDIR (/home/fricas/work)
#
# Mechanism: the files go into the container as a tar stream on stdin (so the MCP
# stream is never read) and land in $FRICAS_WORKDIR/runs/STEM/ (= ~/fricas-work/runs
# on the host). FriCAS runs with ")set breakmode quit", which makes every error
# (interpreter, library, Lisp, parse, compile, missing file) exit with status 1.
set -u

script=${1:-}
timeout=${2:-300}
if [[ -z $script || ! -f $script || $script != *.input || ! $timeout =~ ^[0-9]+$ ]]; then
    echo "usage: $0 DIR/STEM.input [timeout_seconds]" >&2
    exit 2
fi

container=${FRICAS_CONTAINER:-fricas}
user=${FRICAS_USER:-fricas}
workdir=${FRICAS_WORKDIR:-/home/fricas/work}
variant=${FRICAS_VARIANT:-release}
output=${FRICAS_OUTPUT:-1d}
dir=$(cd "$(dirname "$script")" && pwd)
stem=$(basename "$script" .input)
out=$dir/$stem.out
log=$dir/$stem.log
files=("$stem.input")
[[ -f $dir/$stem.spad ]] && files+=("$stem.spad")

if [[ ! $variant =~ ^[A-Za-z0-9._-]+$ || ! $output =~ ^(1d|2d)$ ]]; then
    echo "bad FRICAS_VARIANT or FRICAS_OUTPUT" | tee "$out" >&2
    exit 2
fi
if [[ $(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null) != true ]]; then
    echo "container '$container' is not running" | tee "$out" >&2
    exit 3
fi

# $1 stem, $2 timeout, $3 output mode, $4 "spad" if a .spad file was sent
tar -cf - -C "$dir" "${files[@]}" |
docker exec -i -u "$user" -w "$workdir" -e FRICAS_VARIANT="$variant" "$container" bash -c '
    d=runs/$1
    mkdir -p "$d" && tar -xf - -C "$d" || exit 3
    cd "$d" || exit 3
    {
        echo ")set breakmode quit"
        echo ")set message prompt none"
        echo ")set quit unprotected"
        echo ")set output length 120"
        if [ "$3" = 1d ]; then
            echo "setFormat!(Format1D)\$JFriCASSupport"
            echo ")set output formatted on"
            echo ")set output algebra off"
        fi
        echo ")lisp (progn (princ \"@@FRICAS-RUN@@\") (terpri) (values))"
        echo ")read .$1.run.input"
        echo ")quit"
    } > ".$1.prelude"
    # The script as run: the .spad compiled first, and in 1d mode the Format1D setting
    # re-applied after every system command, because )compile, )lib etc. reset it.
    {
        [ "$4" = spad ] && echo ")compile $1.spad"
        cat "$1.input"; echo
    } | if [ "$3" = 1d ]; then
        awk "{ print } /^[ \t]*\\)/ { print \"setFormat!(Format1D)\$JFriCASSupport -- @@1D@@\" }"
    else cat; fi > ".$1.run.input"
    exec timeout "$2" fricas -nosman < ".$1.prelude"
' _ "$stem" "$timeout" "$output" "$([[ ${#files[@]} -gt 1 ]] && echo spad)" > "$log" 2>&1
rc=$?

# Clean the raw log: drop the banner and prelude (everything up to the marker and its
# "Value = NIL"), the Format1D markers, whitespace-only lines and runs of blank lines,
# and the long right-alignment padding of "Type:" lines.
awk '
    !started { if ($0 ~ /@@FRICAS-RUN@@$/) { started = 1; skipval = 1 }; next }
    skipval && /^Value = / { skipval = 0; next }
    { skipval = 0 }
    /-- @@1D@@$/ { skipvoid = 1; next }
    skipvoid && /^[ \t]*$/ { next }
    skipvoid && /^[ \t]+Type: Void$/ { skipvoid = 0; next }
    { skipvoid = 0 }
    /^--FORMAT:(BEG|END):/ { next }
    /^[ \t]+Type: / { sub(/^[ \t]+/, "   ") }
    /^[ \t]*$/ { if (blank++) next; print ""; next }
    { blank = 0; print }
    END { if (!started) exit 1 }
' "$log" > "$out" || cp "$log" "$out"    # no marker: FriCAS never got that far, show all

case $rc in
    0|1|124) ;;
    3|125|126|127) rc=3 ;;
    *) echo "[FriCAS exited with status $rc]" >> "$out"; rc=1 ;;
esac
[[ $rc == 124 ]] && echo "[timed out after ${timeout}s]" >> "$out"
cat "$out"
exit $rc
