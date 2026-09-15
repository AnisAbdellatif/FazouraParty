defmodule FazouraWeb.ProtocolScenariosTest do
  @moduledoc """
  Replays every `protocol/fixtures/scenarios/*.json` script against the Phoenix
  implementation (PROTOCOL.md §11). The LAN host must pass the same scripts.

  Each actor is its own process acting as a socket transport, so pushes and replies
  are attributed to the right client.
  """

  use FazouraWeb.ChannelCase, async: true

  alias Fazoura.Game.Pack
  alias Fazoura.ProtocolFixtures
  alias Fazoura.Rooms

  @clock_start 1_789_502_400_000
  @wait_ms 1_000

  scenarios = Path.wildcard(Path.join(ProtocolFixtures.dir(), "scenarios/*.json"))
  if scenarios == [], do: raise("no protocol scenarios found in #{ProtocolFixtures.dir()}")

  for path <- scenarios do
    @external_resource path
    scenario = path |> File.read!() |> Jason.decode!()

    test "scenario #{Path.basename(path)}: #{scenario["name"]}" do
      run_scenario(unquote(Macro.escape(scenario)))
    end
  end

  ## Runner

  defp run_scenario(scenario) do
    {:ok, clock} = Agent.start_link(fn -> @clock_start end)
    pack = Pack.from_map(scenario["pack"])
    {:ok, code, host_token} = Rooms.create(pack, now: fn -> Agent.get(clock, & &1) end)

    ctx = %{code: code, clock: clock, actors: %{}, vars: %{"$host_token" => host_token}}

    ctx =
      scenario["steps"]
      |> Enum.with_index(1)
      |> Enum.reduce(ctx, fn {step, index}, ctx ->
        run_step(step, ctx, "step #{index}: #{Jason.encode!(step)}")
      end)

    # Stop the room while the fake clock it reads is still alive.
    with [{pid, _}] <- Registry.lookup(Fazoura.Rooms.Registry, ctx.code) do
      DynamicSupervisor.terminate_child(Fazoura.Rooms.Supervisor, pid)
    end
  end

  defp run_step(%{"advance_clock_ms" => ms}, ctx, _label) do
    Agent.update(ctx.clock, &(&1 + ms))
    :ok = Rooms.tick(ctx.code)
    ctx
  end

  defp run_step(%{"actor" => name, "join" => payload} = step, ctx, label) do
    actor = start_actor(socket(FazouraWeb.UserSocket, nil, %{}))
    reply = actor_call(actor, {:join, "room:" <> ctx.code, subst(payload, ctx)})
    assert_matches(subst(step["expect"], ctx), reply, label)

    vars =
      case reply do
        %{"status" => "ok", "response" => %{"player_id" => id, "player_token" => token}}
        when is_binary(id) ->
          Map.merge(ctx.vars, %{"$player_id:#{name}" => id, "$player_token:#{name}" => token})

        _ ->
          ctx.vars
      end

    if reply["status"] == "ok",
      do: %{ctx | actors: Map.put(ctx.actors, name, actor), vars: vars},
      else: ctx
  end

  defp run_step(%{"actor" => name, "push" => event} = step, ctx, label) do
    reply = actor_call(actor!(ctx, name), {:push, event, subst(step["payload"], ctx)})
    assert_matches(subst(step["expect"], ctx), reply, label)
    ctx
  end

  defp run_step(%{"actor" => name, "expect_state" => expected}, ctx, label) do
    wait_for_state(
      actor!(ctx, name),
      subst(expected, ctx),
      label,
      System.monotonic_time(:millisecond)
    )

    ctx
  end

  defp run_step(%{"actor" => name, "disconnect" => true}, ctx, _label) do
    actor = actor!(ctx, name)
    ref = Process.monitor(actor)
    Process.exit(actor, :kill)
    assert_receive {:DOWN, ^ref, _, _, _}
    %{ctx | actors: Map.delete(ctx.actors, name)}
  end

  defp actor!(ctx, name), do: Map.get(ctx.actors, name) || flunk("unknown actor #{name}")

  defp wait_for_state(actor, expected, label, started) do
    state = actor_call(actor, :latest_state)

    cond do
      matches?(expected, state) ->
        :ok

      System.monotonic_time(:millisecond) - started > @wait_ms ->
        flunk(
          "#{label}\nexpected state to match:\n#{inspect(expected)}\nlatest state:\n#{inspect(state)}"
        )

      true ->
        Process.sleep(10)
        wait_for_state(actor, expected, label, started)
    end
  end

  ## Placeholders and partial matching (PROTOCOL.md §11)

  defp subst(value, ctx) when is_binary(value), do: Map.get(ctx.vars, value, value)

  defp subst(value, ctx) when is_map(value),
    do: Map.new(value, fn {k, v} -> {k, subst(v, ctx)} end)

  defp subst(value, ctx) when is_list(value), do: Enum.map(value, &subst(&1, ctx))
  defp subst(value, _ctx), do: value

  defp assert_matches(expected, actual, label) do
    assert matches?(expected, actual),
           "#{label}\nexpected:\n#{inspect(expected)}\ngot:\n#{inspect(actual)}"
  end

  defp matches?(expected, actual) when is_map(expected) and is_map(actual),
    do: Enum.all?(expected, fn {k, v} -> Map.has_key?(actual, k) and matches?(v, actual[k]) end)

  defp matches?(expected, actual) when is_list(expected) and is_list(actual),
    do:
      length(expected) == length(actual) and
        Enum.all?(Enum.zip(expected, actual), fn {e, a} -> matches?(e, a) end)

  defp matches?(expected, actual), do: expected == actual

  ## Actor process: one per client, acting as that client's transport

  defp start_actor(socket) do
    actor = spawn(fn -> actor_loop(nil, nil) end)
    send(actor, {:socket, %{socket | transport_pid: actor}})
    actor
  end

  defp actor_call(actor, request) do
    ref = make_ref()
    send(actor, {:call, self(), ref, request})

    receive do
      {^ref, result} -> result
    after
      5_000 -> flunk("actor did not answer #{inspect(request)}")
    end
  end

  defp actor_loop(socket, latest_state) do
    receive do
      {:socket, socket} ->
        actor_loop(socket, latest_state)

      %Phoenix.Socket.Message{event: "state", payload: payload} ->
        actor_loop(socket, wire(payload))

      %Phoenix.Socket.Message{} ->
        actor_loop(socket, latest_state)

      {:call, from, ref, {:join, topic, payload}} ->
        case join(socket, FazouraWeb.RoomChannel, topic, payload) do
          {:ok, reply, joined} ->
            send(from, {ref, wire(%{status: "ok", response: reply})})
            actor_loop(joined, latest_state)

          {:error, reply} ->
            send(from, {ref, wire(%{status: "error", response: reply})})
            actor_loop(socket, latest_state)
        end

      {:call, from, ref, {:push, event, payload}} ->
        push_ref = push(socket, event, payload)

        receive do
          %Phoenix.Socket.Reply{ref: ^push_ref, status: status, payload: reply} ->
            send(from, {ref, wire(%{status: status, response: reply})})
        after
          5_000 -> send(from, {ref, :no_reply})
        end

        actor_loop(socket, latest_state)

      {:call, from, ref, :latest_state} ->
        send(from, {ref, latest_state})
        actor_loop(socket, latest_state)
    end
  end

  # Round-trip through JSON so assertions see exactly what goes over the wire.
  defp wire(term), do: term |> Jason.encode!() |> Jason.decode!()
end
