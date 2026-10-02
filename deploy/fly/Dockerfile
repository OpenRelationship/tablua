# A Moss node to measure on (Arock PROJECT.md §15 item 5): Moss built from source with the Litestream release it
# runs on the Mac, its benches run over `fly ssh console`. The build context is made by stage.sh, since Moss reads
# Arock Core (library/), alog, Shroomi, rockmail and connectory's port from the Arock checkout (AROCK_ROOT); luex is inside Moss.
# No key or token is in the image or the machine: the benches play the service in memory.
FROM hexpm/elixir:1.20.3-erlang-29.0.5-debian-bookworm-20260824

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential git curl ca-certificates procps sqlite3 \
 && rm -rf /var/lib/apt/lists/*

# the release for the machine's architecture: x86_64 on Fly, arm64 in Docker on a Mac
ARG LITESTREAM=0.5.11
ARG TARGETARCH
RUN arch=$([ "$TARGETARCH" = "arm64" ] && echo arm64 || echo x86_64) \
 && curl -fsSL "https://github.com/benbjohnson/litestream/releases/download/v${LITESTREAM}/litestream-${LITESTREAM}-linux-${arch}.tar.gz" \
    | tar -xz -C /usr/local/bin litestream \
 && litestream version

ENV HOME=/root MIX_HOME=/root/.mix HEX_HOME=/root/.hex AROCK_ROOT=/arock MIX_ENV=dev LANG=C.UTF-8 TMPDIR=/data/tmp
# A dirty I/O scheduler for every awake computer: every SQLite call (exqlite) and every file read runs on one, and a
# call waiting on SQLite's lock or the disk holds its thread. With the default 10, 1,000 computers queued about 900
# calls deep and the packer's reads waited behind them (Arock PROJECT.md §15 item 5).
ENV ERL_FLAGS="+SDio 1024"
WORKDIR /arock
COPY library library
COPY submodules/alog submodules/alog
COPY submodules/shroomi submodules/shroomi
COPY submodules/rockmail submodules/rockmail
COPY submodules/connectory/lua submodules/connectory/lua
COPY submodules/moss submodules/moss

WORKDIR /arock/submodules/moss
RUN mix local.hex --force && mix local.rebar --force && mix deps.get && mix compile

# the work dir and the benches' scratch live on the volume (fly.toml mounts it at /data); benches run through
# deploy/fly/bench.sh, which raises the open-file limit Litestream needs
CMD ["sh", "-c", "ulimit -n 1048576 && mkdir -p /data/tmp && exec sleep infinity"]
