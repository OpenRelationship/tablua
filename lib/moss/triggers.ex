defmodule Moss.Triggers do
  @moduledoc """
  The node's clock for tools with an EVERY (Arock's feature `manifest`): once a minute, each trigger whose time
  has come since it last ran wakes its computer, asleep or not, and runs the tool as its agent would type it.
  The triggers live on the node's names (`Moss.Names`), written there as the manifests are, so a sleeping
  computer is found without being woken.

      hourly            at the top of each hour
      daily 07:00       each day at 07:00
      weekly Mon 07:00  each Monday at 07:00
      every 15m         15 minutes after the last run (m, h or d)

  Times are UTC: a computer has no time zone of its own yet.
  """
  use GenServer
  require Logger

  @minute 60_000
  @days ~w(Mon Tue Wed Thu Fri Sat Sun)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Runs each trigger due at `now` (unix seconds): `[{computer, tool, code}]`, in order."
  def tick(now) do
    for t <- Moss.Names.triggers(), due?(t.every, t.since, now) do
      :ok = Moss.Names.ran(t.computer, t.tool, now)
      r = Moss.Computer.run(t.computer, t.tool)
      if r.code != 0, do: Logger.warning("trigger #{t.tool} on #{t.computer}: #{r.code} #{r.err}")
      {t.computer, t.tool, r.code}
    end
  end

  @doc "Whether a trigger last run (or declared) at `since` is due at `now`."
  def due?(every, since, now), do: next_at(every, since) <= now

  @doc "The first time after `since` (unix seconds) that `every` names."
  def next_at("hourly", since), do: (div(since, 3600) + 1) * 3600

  def next_at("every " <> n, since) do
    {count, unit} = Integer.parse(n)
    since + count * %{"m" => 60, "h" => 3600, "d" => 86_400}[unit]
  end

  def next_at("daily " <> hhmm, since), do: next_day(since, clock(hhmm), fn _ -> true end)

  def next_at("weekly " <> rest, since) do
    [day, hhmm] = String.split(rest, " ", parts: 2)
    want = Enum.find_index(@days, &(&1 == day)) + 1
    next_day(since, clock(hhmm), &(Date.day_of_week(&1) == want))
  end

  # the first day from since's on, at the clock and wanted, that comes after since
  defp next_day(since, seconds, want?) do
    day = DateTime.from_unix!(since) |> DateTime.to_date()

    Stream.iterate(day, &Date.add(&1, 1))
    |> Stream.map(&{&1, Date.diff(&1, ~D[1970-01-01]) * 86_400 + seconds})
    |> Enum.find_value(fn {d, at} -> if at > since and want?.(d), do: at end)
  end

  defp clock(hhmm) do
    [h, m] = String.split(hhmm, ":")
    String.to_integer(h) * 3600 + String.to_integer(m) * 60
  end

  @impl true
  def init(opts) do
    every = opts[:every_ms] || @minute
    Process.send_after(self(), :tick, every)
    {:ok, every}
  end

  @impl true
  def handle_info(:tick, every) do
    try do
      tick(System.os_time(:second))
    rescue
      e -> Logger.warning("triggers: #{Exception.message(e)}")
    end

    Process.send_after(self(), :tick, every)
    {:noreply, every}
  end
end
