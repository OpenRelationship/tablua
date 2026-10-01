defmodule VolvoxServer.Computer.Files do
  @moduledoc """
  The kernel's files (`Computer.Wasi`): WASI's `fd_*` and `path_*` calls over
  the computer's disk. fd 0 reads the program's stdin, 1 and 2 go to its owner,
  fd 3 is `.`, the working folder, and the folders at the top of the disk
  follow it, preopened by name (see `tops/1`). An open file is read whole into the
  open-file table, and written back to the disk when it is closed or synced.

  The calls that name a path (opening, making, removing, renaming, listing)
  are `Computer.Paths`. The table lives in the dictionary of the process the calls run in (the wasmex
  instance's), made on the first call.
  """
  import VolvoxServer.Computer.Wasi, only: [read: 3, write: 3, u32: 3, u64: 3, iovs: 3]
  alias VolvoxServer.Computer.{Disk, Paths}

  @ok 0
  @ebadf 8
  @espipe 70
  @eexist 20
  @einval 28
  @eisdir 31
  @enoent 44
  @enotdir 54
  @enotempty 55
  @eperm 63

  @folder 3
  @regular 4
  @chardev 2

  @calls ~w(fd_write fd_read fd_pread fd_pwrite fd_seek fd_tell fd_close fd_sync fd_datasync fd_fdstat_get
            fd_fdstat_set_flags fd_filestat_get fd_filestat_set_size fd_filestat_set_times fd_advise fd_allocate
            fd_prestat_get fd_prestat_dir_name fd_readdir path_open path_filestat_get path_filestat_set_times
            path_create_directory path_remove_directory path_unlink_file path_rename path_readlink)

  def answers?(name), do: name in @calls

  def call(name, ctx, args, c) do
    table(c)

    if name in Paths.names(),
      do: Paths.answer(name, ctx, args, c.disk),
      else: answer(name, ctx, args, c.disk)
  end

  defp table(c) do
    Process.get(:computer_fds) ||
      Process.put(
        :computer_fds,
        %{
          0 => %{kind: :stdin, data: c.stdin || "", pos: 0},
          1 => %{kind: :out, owner: c.owner},
          2 => %{kind: :out, owner: c.owner},
          3 => %{kind: :dir, path: Disk.norm(Map.get(c.env, "PWD", "/")), preopen: "."}
        }
        |> Map.merge(tops(c.disk))
      )
  end

  # wasi-libc matches a path against the preopened names, longest first, "." and "/" alike as the empty name:
  # so "." is the working folder, and each folder at the top (/home, /usr, ...) is preopened by its own name,
  # which an absolute path always matches before ".". A relative path that starts with a top folder's name
  # (home/x, from /home) is read as that folder's.
  defp tops(disk) do
    {:ok, entries} = Disk.list(disk, "/")

    for {e, n} <- entries |> Enum.filter(& &1.dir) |> Enum.with_index(4), into: %{} do
      {n, %{kind: :dir, path: "/" <> e.name, preopen: "/" <> e.name}}
    end
  end

  def fds, do: Process.get(:computer_fds)
  def fd(n), do: Map.get(fds(), n)

  def put(n, f) do
    Process.put(:computer_fds, Map.put(fds(), n, f))
    :ok
  end

  def path(ctx, dirfd, ptr, len) do
    case fd(dirfd) do
      %{kind: :dir, path: base} -> {:ok, Disk.norm(read(ctx, ptr, len), base)}
      _ -> {:error, @ebadf}
    end
  end

  def errno(:enoent), do: @enoent
  def errno(:eisdir), do: @eisdir
  def errno(:enotdir), do: @enotdir
  def errno(:eexist), do: @eexist
  def errno(:enotempty), do: @enotempty
  def errno(:eperm), do: @eperm
  def errno(n) when is_integer(n), do: n
  def errno(_), do: @einval

  # -- reading and writing -----------------------------------------------------------------------

  defp answer("fd_write", ctx, [n, list, count, done], _disk) do
    bytes = for {p, l} <- iovs(ctx, list, count), into: <<>>, do: read(ctx, p, l)

    case fd(n) do
      %{kind: :out, owner: owner} ->
        send(owner, {:wasi_out, n, bytes})
        u32(ctx, done, byte_size(bytes)) && @ok

      %{kind: :file} = f ->
        at = if f.append, do: byte_size(f.data), else: f.pos
        put(n, %{f | data: splice(f.data, at, bytes), pos: at + byte_size(bytes), dirty: true})
        u32(ctx, done, byte_size(bytes)) && @ok

      _ ->
        @ebadf
    end
  end

  defp answer("fd_pwrite", ctx, [n, list, count, offset, done], disk) do
    case fd(n) do
      %{kind: :file, pos: pos} = f ->
        put(n, %{f | pos: offset, append: false})
        r = answer("fd_write", ctx, [n, list, count, done], disk)
        put(n, %{fd(n) | pos: pos, append: f.append})
        r

      # a terminal has no positions: a program told so (Zig's positional writer) writes it as a stream
      %{kind: :out} ->
        @espipe

      _ ->
        @ebadf
    end
  end

  defp answer("fd_read", ctx, [n, list, count, done], _disk) do
    case fd(n) do
      %{kind: kind, data: data, pos: pos} = f when kind in [:stdin, :file] ->
        {got, pos} =
          Enum.reduce(iovs(ctx, list, count), {0, pos}, fn {p, l}, {got, at} ->
            chunk =
              binary_part(data, min(at, byte_size(data)), max(0, min(l, byte_size(data) - at)))

            write(ctx, p, chunk)
            {got + byte_size(chunk), at + byte_size(chunk)}
          end)

        put(n, %{f | pos: pos})
        u32(ctx, done, got) && @ok

      %{kind: :dir} ->
        @eisdir

      _ ->
        @ebadf
    end
  end

  defp answer("fd_pread", ctx, [n, list, count, offset, done], disk) do
    case fd(n) do
      %{kind: :file, pos: pos} = f ->
        put(n, %{f | pos: offset})
        r = answer("fd_read", ctx, [n, list, count, done], disk)
        put(n, %{fd(n) | pos: pos})
        r

      _ ->
        @ebadf
    end
  end

  defp answer("fd_seek", ctx, [n, offset, whence, out], _disk) do
    case fd(n) do
      %{kind: kind} = f when kind in [:file, :stdin] ->
        offset = if offset >= 0x8000000000000000, do: offset - 0x10000000000000000, else: offset
        base = Enum.at([0, f.pos, byte_size(f.data)], whence, 0)
        to = base + offset

        if to < 0 do
          @einval
        else
          put(n, %{f | pos: to})
          u64(ctx, out, to) && @ok
        end

      %{kind: :out} ->
        70

      _ ->
        @ebadf
    end
  end

  defp answer("fd_tell", ctx, [n, out], _disk) do
    case fd(n) do
      %{pos: pos} -> u64(ctx, out, pos) && @ok
      _ -> @ebadf
    end
  end

  defp answer(sync, _ctx, [n], disk) when sync in ["fd_sync", "fd_datasync"], do: flush(n, disk)

  defp answer("fd_close", _ctx, [n], disk) do
    r = flush(n, disk)

    if r == @ok and not Map.has_key?(fd(n) || %{}, :preopen),
      do: Process.put(:computer_fds, Map.delete(fds(), n))

    r
  end

  defp answer("fd_filestat_set_size", _ctx, [n, size], _disk) do
    case fd(n) do
      %{kind: :file} = f ->
        data =
          if size <= byte_size(f.data),
            do: binary_part(f.data, 0, size),
            else: f.data <> :binary.copy(<<0>>, size - byte_size(f.data))

        (
          put(n, %{f | data: data, dirty: true})
          @ok
        )

      _ ->
        @ebadf
    end
  end

  defp answer(noop, _ctx, [n | _], _disk)
       when noop in ["fd_advise", "fd_allocate", "fd_fdstat_set_flags", "fd_filestat_set_times"],
       do: if(fd(n), do: @ok, else: @ebadf)

  # -- what a file is ----------------------------------------------------------------------------

  defp answer("fd_fdstat_get", ctx, [n, out], _disk) do
    case fd(n) do
      nil ->
        @ebadf

      f ->
        write(
          ctx,
          out,
          <<type(f)::8, 0::8, flags(f)::little-16, 0::32, -1::little-64, -1::little-64>>
        ) && @ok
    end
  end

  defp answer("fd_filestat_get", ctx, [n, out], disk) do
    case fd(n) do
      nil -> @ebadf
      %{kind: :dir, path: p} -> stat_path(ctx, disk, p, out)
      %{kind: :file} = f -> filestat(ctx, out, @regular, byte_size(f.data), 0)
      f -> filestat(ctx, out, type(f), 0, 0)
    end
  end

  defp answer("fd_prestat_get", ctx, [n, out], _disk) do
    case fd(n) do
      %{preopen: name} -> write(ctx, out, <<0::32, byte_size(name)::little-32>>) && @ok
      _ -> @ebadf
    end
  end

  defp answer("fd_prestat_dir_name", ctx, [n, out, _len], _disk) do
    case fd(n) do
      %{preopen: name} -> write(ctx, out, name) && @ok
      _ -> @ebadf
    end
  end

  @doc """
  Before a path changes under its open files, they are settled: every open file
  at `path` (or inside it) writes what it holds, then follows a rename to `to`,
  or, when the path is removed (`:gone`), keeps its writes to itself, as an
  unlinked file does. Without this a program that writes a file, renames it
  into place and only then closes it (Zig's output, any atomic save) leaves
  the new name empty and the old one written again.
  """
  def settle(disk, path, to \\ :keep) do
    for {n, %{kind: kind, path: at}} <- fds(),
        kind in [:file, :dir],
        is_binary(at),
        at == path or String.starts_with?(at, path <> "/") do
      flush(n, disk)

      case to do
        :keep -> :ok
        :gone -> put(n, %{fd(n) | path: :gone, dirty: false})
        to -> put(n, %{fd(n) | path: to <> String.replace_prefix(at, path, "")})
      end
    end

    :ok
  end

  @doc "Writes every open file's unwritten bytes: a program's files are on its disk when it ends, closed or not."
  def flush_all(disk) do
    for {n, %{kind: :file}} <- fds(), do: flush(n, disk)
    :ok
  end

  def flush(n, disk) do
    case fd(n) do
      %{kind: :file, path: :gone} ->
        @ok

      %{kind: :file, dirty: true} = f ->
        case Disk.write(disk, f.path, f.data) do
          :ok ->
            put(n, %{f | dirty: false})
            @ok

          {:error, e} ->
            errno(e)
        end

      nil ->
        @ebadf

      _ ->
        @ok
    end
  end

  def stat_path(ctx, disk, path, out) do
    case Disk.stat(disk, path) do
      {:ok, s} ->
        filestat(
          ctx,
          out,
          if(s.dir, do: @folder, else: @regular),
          s.size,
          s.mtime * 1_000_000_000
        )

      {:error, e} ->
        errno(e)
    end
  end

  def filestat(ctx, out, type, size, mtime) do
    write(
      ctx,
      out,
      <<0::64, 0::64, type::8, 0::56, 1::little-64, size::little-64, mtime::little-64,
        mtime::little-64, mtime::little-64>>
    ) && @ok
  end

  defp type(%{kind: :dir}), do: @folder
  defp type(%{kind: :file}), do: @regular
  defp type(_), do: @chardev
  defp flags(%{append: true}), do: 1
  defp flags(_), do: 0

  defp splice(data, at, bytes) do
    data =
      if at > byte_size(data), do: data <> :binary.copy(<<0>>, at - byte_size(data)), else: data

    tail = max(0, byte_size(data) - at - byte_size(bytes))
    binary_part(data, 0, at) <> bytes <> binary_part(data, byte_size(data) - tail, tail)
  end
end
