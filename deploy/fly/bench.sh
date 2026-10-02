#!/bin/sh
# bench.sh <bench> [args...]: runs one of Moss's benches on this node, e.g. `bench.sh packs.exs load 1000 300` or
# `bench.sh computers.exs 20000 400`. Litestream holds about five files open per awake computer, so the default
# limit of 10,240 stopped it at 2,000 computers ("too many open files"); the limit is raised first.
set -eu
ulimit -n 1048576
export HOME=/root
cd /arock/submodules/moss
bench=$1
shift
case "$bench" in
  packs.exs) exec mix run --no-start "bench/$bench" "$@" ;;
  *) exec mix run "bench/$bench" "$@" ;;
esac
