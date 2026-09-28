# Runs and their objects start empty on every test run.
for dir <- [:work_dir, :local_objects],
    do: File.rm_rf!(Application.fetch_env!(:volvox_server, dir))

ExUnit.start(exclude: [:r2])
