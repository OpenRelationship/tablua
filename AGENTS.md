This is Tablua (see README.md): an embeddable agent and its own computer, Moss (VMOSS), an Elixir library, with
Shroomi folded in (owner, 2026-10-04: Tablua is the core; Arock is its desktop app, designs and server).

## Tablua rules

- Tablua is attached to the Arock repository at `submodules/vmoss`. The core Lua still in Arock (`library/` there)
  is read, never edited from here; a change it needs is made in the Arock repository until it moves here.
- `lua/` (moss-lua), `browser/` (moss-browser) and `shroomi/` (Shroomi) are folders of this repository with rules
  of their own in their AGENTS.md; read it before editing there.
- `site/` is tablua.com, the one place TypeScript, React and Node tooling are allowed (owner, 2026-10-04). Nothing
  an agent runs reaches it: the computer stays Elixir and Lua.
- VMOSS knows no server. What a computer needs from whoever runs it goes through `Moss.Host`; the node's side of
  it (object store, post, names, keys) lives in Arock's `app/server`.
- The core runs in moss-lua from the base state in `Moss.Lua`; every call starts from that state and
  drops it (the VM has no garbage collector).
- A computer is its SQLite file: nothing it does reaches the node's real filesystem, a real shell or another
  computer. Agents talk only by mail.
- Files stay under 400 lines, split by responsibility. No placeholder modules.
- Keys and tokens (model keys, page tokens) are never logged, printed or written to files.

## Project guidelines

- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`

<!-- usage-rules-start -->

<!-- phoenix:elixir-start -->
## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason

## Test guidelines

- **Always use `start_supervised!/1`** to start processes in tests as it guarantees cleanup between tests
- **Avoid** `Process.sleep/1` and `Process.alive?/1` in tests
  - Instead of sleeping to wait for a process to finish, **always** use `Process.monitor/1` and assert on the DOWN message:

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

   - Instead of sleeping to synchronize before the next call, **always** use `_ = :sys.get_state/1` to ensure the process has handled prior messages
<!-- phoenix:elixir-end -->

<!-- usage-rules-end -->