#!/bin/sh
# stage.sh <arock-checkout> <dir>: the build context for this Moss node (Dockerfile beside it), made from an Arock
# checkout with only what Moss reads (Arock Core, alog, Shroomi, rockmail, connectory's port, luos and Moss) and none
# of the host's build output.
# Then: fly deploy <dir> --config <dir>/fly.toml --remote-only
set -eu
src=$1
out=$2
here=$(cd "$(dirname "$0")" && pwd)
rm -rf "$out"
mkdir -p "$out"
for p in library submodules/alog submodules/shroomi submodules/luos submodules/rockmail submodules/connectory/lua \
  submodules/moss; do
  mkdir -p "$out/$p"
  rsync -a --exclude .git --exclude _build --exclude deps --exclude node_modules --exclude tmp \
    --exclude erl_crash.dump --exclude 'priv/work' --exclude 'priv/runs' "$src/$p/" "$out/$p/"
done
cp "$here/Dockerfile" "$here/fly.toml" "$out/"
du -sh "$out"
