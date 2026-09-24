defmodule Fazoura.Rooms.RoomServerTest do
  # Suspends a room process and measures time, so it keeps to itself.
  use ExUnit.Case, async: false

  alias Fazoura.QuizFixtures
  alias Fazoura.Rooms

  # A stand-in for a channel process: forwards each snapshot to the test, tagged.
  defp listener(tag) do
    test = self()

    spawn_link(fn -> forward(test, tag) end)
  end

  defp forward(test, tag) do
    receive do
      {:room_state, view} -> send(test, {tag, view, System.monotonic_time(:millisecond)})
      _other -> :ok
    end

    forward(test, tag)
  end

  defp join(code, tag, params) do
    pid = listener(tag)
    {:ok, reply, _room} = Rooms.join(code, pid, params)
    {pid, reply}
  end

  defp room_pid(code) do
    [{pid, _}] = Registry.lookup(Fazoura.Rooms.Registry, code)
    pid
  end

  defp flush_snapshots do
    receive do
      {_tag, _view, _at} -> flush_snapshots()
    after
      50 -> :ok
    end
  end

  test "changes that arrive together go out as one snapshot" do
    {:ok, code, host_token} = Rooms.create(QuizFixtures.pack(), broadcast_interval_ms: 0)
    {host, _} = join(code, :host, %{"host_token" => host_token})
    {sam, _} = join(code, :sam, %{"display_name" => "Sam"})
    {kim, _} = join(code, :kim, %{"display_name" => "Kim"})
    assert :ok = Rooms.intent(code, host, :next)
    flush_snapshots()

    # Both answers are in the room's mailbox before it gets to either.
    room = room_pid(code)
    :sys.suspend(room)

    answers =
      for pid <- [sam, kim] do
        Task.async(fn -> Rooms.intent(code, pid, {:submit, %{"answer" => "nope"}}) end)
      end

    wait_for_queue(room, 2)
    :sys.resume(room)
    assert [:ok, :ok] = Task.await_many(answers)

    assert_receive {:host, %{players: players}, _at}
    assert Enum.count(players, & &1.has_submitted) == 2
    refute_receive {:host, _view, _at}, 100
  end

  test "a snapshot waits out the interval after the last one, and carries the latest state" do
    {:ok, code, host_token} = Rooms.create(QuizFixtures.pack(), broadcast_interval_ms: 300)
    join(code, :host, %{"host_token" => host_token})
    assert_receive {:host, %{players: []}, first_at}

    # Two joins inside the interval: neither is sent on its own.
    join(code, :sam, %{"display_name" => "Sam"})
    join(code, :kim, %{"display_name" => "Kim"})

    assert_receive {:host, %{players: players}, next_at}, 1_000
    assert length(players) == 2
    assert next_at - first_at >= 290
    refute_receive {:host, _view, _at}, 400
  end

  defp wait_for_queue(pid, count) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, n} when n >= count ->
        :ok

      _fewer ->
        Process.sleep(5)
        wait_for_queue(pid, count)
    end
  end
end
