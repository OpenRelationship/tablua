defmodule VolvoxServer.Computer.Paths do
  @moduledoc """
  The kernel's calls that name a path (`Computer.Files` holds the open files):
  opening one, making and removing folders and files, renaming, listing a
  folder, and a path's facts. A path is read against the folder its fd names;
  `Disk.norm` keeps it inside `/`.
  """
  import Bitwise
  import VolvoxServer.Computer.Wasi, only: [write: 3, u32: 3]

  import VolvoxServer.Computer.Files,
    only: [fd: 1, fds: 0, put: 2, path: 4, errno: 1, stat_path: 4]

  alias VolvoxServer.Computer.Disk

  @ok 0
  @einval 28
  @enotdir 54
  @folder 3
  @regular 4

  @names ~w(path_filestat_get path_filestat_set_times fd_readdir path_readlink path_open path_create_directory
            path_unlink_file path_remove_directory path_rename)
  def names, do: @names

  def answer("path_filestat_get", ctx, [dirfd, _flags, p, l, out], disk) do
    with {:ok, path} <- path(ctx, dirfd, p, l),
         do: stat_path(ctx, disk, path, out),
         else: ({:error, e} -> e)
  end

  def answer("path_filestat_set_times", _ctx, _args, _disk), do: @ok

  def answer("fd_readdir", ctx, [n, buf, len, cookie, used], disk) do
    case fd(n) do
      %{kind: :dir, path: p} ->
        {:ok, kids} = Disk.list(disk, p)
        entries = [{".", true}, {"..", true} | Enum.map(kids, &{&1.name, &1.dir})]

        bytes =
          entries
          |> Enum.with_index(1)
          |> Enum.drop(cookie)
          |> Enum.map_join(fn {{name, dir}, next} ->
            <<next::little-64, next::little-64, byte_size(name)::little-32,
              if(dir, do: @folder, else: @regular)::8, 0::24>> <> name
          end)

        bytes = binary_part(bytes, 0, min(len, byte_size(bytes)))
        write(ctx, buf, bytes)
        u32(ctx, used, byte_size(bytes)) && @ok

      _ ->
        @enotdir
    end
  end

  def answer("path_readlink", _ctx, _args, _disk), do: @einval

  # -- opening, making and removing --------------------------------------------------------------

  def answer(
        "path_open",
        ctx,
        [dirfd, _dirflags, p, l, oflags, _rights, _inheriting, fdflags, out],
        disk
      ) do
    with {:ok, path} <- path(ctx, dirfd, p, l),
         {:ok, f} <- open(disk, path, oflags, fdflags) do
      n = (fds() |> Map.keys() |> Enum.max()) + 1
      put(n, f)
      u32(ctx, out, n) && @ok
    else
      {:error, e} -> errno(e)
    end
  end

  def answer("path_create_directory", ctx, [dirfd, p, l], disk),
    do: on_path(ctx, dirfd, p, l, &Disk.mkdir(disk, &1))

  def answer("path_unlink_file", ctx, [dirfd, p, l], disk),
    do: on_path(ctx, dirfd, p, l, &unlink(disk, &1))

  def answer("path_remove_directory", ctx, [dirfd, p, l], disk),
    do: on_path(ctx, dirfd, p, l, &rmdir(disk, &1))

  def answer("path_rename", ctx, [fd1, p1, l1, fd2, p2, l2], disk) do
    with {:ok, from} <- path(ctx, fd1, p1, l1),
         {:ok, to} <- path(ctx, fd2, p2, l2),
         :ok <- Disk.rename(disk, from, to) do
      @ok
    else
      {:error, e} -> errno(e)
    end
  end

  defp open(disk, path, oflags, fdflags) do
    {create, directory, excl, trunc} = {oflags &&& 1, oflags &&& 2, oflags &&& 4, oflags &&& 8}

    case Disk.stat(disk, path) do
      {:ok, _} when excl != 0 and create != 0 ->
        {:error, :eexist}

      {:ok, %{dir: true}} ->
        {:ok, %{kind: :dir, path: path}}

      {:ok, _} when directory != 0 ->
        {:error, :enotdir}

      {:ok, _} when trunc != 0 ->
        {:ok, file(path, "", fdflags, true)}

      {:ok, _} ->
        with {:ok, data} <- Disk.read(disk, path), do: {:ok, file(path, data, fdflags, false)}

      {:error, :enoent} when create != 0 ->
        new_file(disk, path, fdflags)

      error ->
        error
    end
  end

  defp new_file(disk, path, fdflags) do
    with :ok <- Disk.write(disk, path, ""), do: {:ok, file(path, "", fdflags, false)}
  end

  defp file(path, data, fdflags, dirty),
    do: %{kind: :file, path: path, data: data, pos: 0, append: (fdflags &&& 1) != 0, dirty: dirty}

  defp unlink(disk, path) do
    case Disk.stat(disk, path) do
      {:ok, %{dir: true}} -> {:error, :eisdir}
      {:ok, _} -> Disk.remove(disk, path)
      error -> error
    end
  end

  defp rmdir(disk, path) do
    case Disk.stat(disk, path) do
      {:ok, %{dir: true}} -> Disk.remove(disk, path)
      {:ok, _} -> {:error, :enotdir}
      error -> error
    end
  end

  defp on_path(ctx, dirfd, p, l, fun) do
    with {:ok, path} <- path(ctx, dirfd, p, l),
         :ok <- fun.(path),
         do: @ok,
         else: ({:error, e} -> errno(e))
  end
end
