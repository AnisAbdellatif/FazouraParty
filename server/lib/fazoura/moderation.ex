defmodule Fazoura.Moderation do
  @moduledoc """
  Keeping public rooms fit for strangers (PROTOCOL.md §3.5): reports about players,
  and bans from public rooms.

  A player has no account, so everything here hangs off what a room can see — a name,
  an answer — and a keyed hash of the connection's address
  (`Fazoura.Moderation.IpHash`). Nothing here is kept longer than 90 days: decided
  reports go, an open report's address hash is erased, and a ban never outlasts that
  (`sweep/1`). The word filter is `Fazoura.Moderation.Profanity`; the host removing a
  player is the room's own business (`Fazoura.Game`).
  """

  import Ecto.Query

  alias Fazoura.Moderation.{Ban, PlayerReport}
  alias Fazoura.Quizzes.OwnerKey
  alias Fazoura.Repo

  @retention_days 90
  @ban_days [7, 30, 90]

  @typedoc "What a room hands over about the player being reported."
  @type reported :: %{
          room_code: String.t(),
          player_name: String.t(),
          answer: String.t() | nil,
          ip_hash: String.t() | nil
        }

  @doc "How many days a ban may last."
  @spec ban_days() :: [pos_integer()]
  def ban_days, do: @ban_days

  @doc """
  Records a report. One device reporting the same player in the same room again
  rewords its report rather than adding a second voice, as with quiz reports.
  """
  @spec report_player(reported(), String.t() | nil, map()) ::
          {:ok, PlayerReport.t()} | {:error, :owner_key_required | :invalid_report}
  def report_player(reported, reporter_key, params) do
    with {:ok, hash} <- reporter_hash(reporter_key) do
      %PlayerReport{}
      |> PlayerReport.changeset(
        Map.merge(reported, %{
          reason: params["reason"],
          note: params["note"],
          reporter_key_hash: hash
        })
      )
      |> Repo.insert(
        on_conflict: [set: [reason: params["reason"], note: params["note"]]],
        conflict_target: [:room_code, :player_name, :reporter_key_hash],
        returning: true
      )
      |> case do
        {:ok, report} -> {:ok, report}
        {:error, %Ecto.Changeset{}} -> {:error, :invalid_report}
      end
    end
  end

  @doc "Player reports nobody has answered, oldest first."
  @spec open_player_reports(pos_integer()) :: [PlayerReport.t()]
  def open_player_reports(limit \\ 100) do
    PlayerReport
    |> where([r], r.status == "open")
    |> order_by([r], asc: r.reported_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec open_count() :: non_neg_integer()
  def open_count, do: PlayerReport |> where([r], r.status == "open") |> Repo.aggregate(:count)

  @doc """
  Answers a report by keeping that connection out of public rooms for `days`. A report
  whose address hash is gone (or was never known — a LAN guest, a test) can only be
  dismissed.
  """
  @spec ban(String.t(), pos_integer()) ::
          {:ok, Ban.t()} | {:error, :not_found | :no_address | :invalid_days}
  def ban(report_id, days) when days in @ban_days do
    case Repo.get(PlayerReport, report_id) do
      nil ->
        {:error, :not_found}

      %PlayerReport{ip_hash: nil} ->
        {:error, :no_address}

      report ->
        Repo.transaction(fn ->
          ban =
            Repo.insert!(%Ban{
              ip_hash: report.ip_hash,
              player_report_id: report.id,
              expires_at: DateTime.add(DateTime.utc_now(:second), days * 86_400, :second)
            })

          decide(report, "banned")
          ban
        end)
    end
  end

  def ban(_report_id, _days), do: {:error, :invalid_days}

  @spec dismiss(String.t()) :: :ok | {:error, :not_found}
  def dismiss(report_id) do
    case Repo.get(PlayerReport, report_id) do
      nil ->
        {:error, :not_found}

      report ->
        decide(report, "dismissed")
        :ok
    end
  end

  @doc "Whether a connection with this address hash is kept out of public rooms."
  @spec banned?(String.t() | nil, DateTime.t()) :: boolean()
  def banned?(ip_hash, now \\ DateTime.utc_now())
  def banned?(nil, _now), do: false

  def banned?(ip_hash, now) do
    Ban
    |> where([b], b.ip_hash == ^ip_hash and b.expires_at > ^now)
    |> Repo.exists?()
  end

  @doc """
  Forgets what has outlived its use: decided reports and expired bans older than the
  retention, and the address hash on any report that old — open ones included, since
  "up to 90 days" is a promise about the address, not about the queue.

  Options: `:retention_days`, `:now`.
  """
  @spec sweep(keyword()) :: %{
          player_reports: non_neg_integer(),
          addresses: non_neg_integer(),
          bans: non_neg_integer()
        }
  def sweep(opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    cutoff = DateTime.add(now, -Keyword.get(opts, :retention_days, @retention_days) * 86_400)

    {bans, _} = Ban |> where([b], b.expires_at <= ^now) |> Repo.delete_all()

    {reports, _} =
      PlayerReport
      |> where([r], r.status != "open" and r.reviewed_at < ^cutoff)
      |> Repo.delete_all()

    {addresses, _} =
      PlayerReport
      |> where([r], not is_nil(r.ip_hash) and r.reported_at < ^cutoff)
      |> Repo.update_all(set: [ip_hash: nil])

    %{player_reports: reports, addresses: addresses, bans: bans}
  end

  defp decide(report, status) do
    report
    |> Ecto.Changeset.change(status: status, reviewed_at: DateTime.utc_now(:second))
    |> Repo.update!()
  end

  defp reporter_hash(key) do
    case OwnerKey.hash(key) do
      {:ok, hash} -> {:ok, hash}
      _ -> {:error, :owner_key_required}
    end
  end
end
