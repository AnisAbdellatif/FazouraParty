defmodule Fazoura.ModerationTest do
  use Fazoura.DataCase, async: false

  alias Fazoura.Moderation
  alias Fazoura.Moderation.{Ban, PlayerReport}

  @reporter "reporter-key-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  @other "reporter-key-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

  defp reported(overrides \\ %{}) do
    Map.merge(
      %{room_code: "ROOM42", player_name: "Troll", answer: "rude", ip_hash: "hash-1"},
      overrides
    )
  end

  test "a report keeps what was on screen and the address hash, once per device" do
    {:ok, first} = Moderation.report_player(reported(), @reporter, %{"reason" => "hate"})
    assert %PlayerReport{player_name: "Troll", answer: "rude", ip_hash: "hash-1"} = first

    {:ok, again} =
      Moderation.report_player(reported(), @reporter, %{"reason" => "spam", "note" => "x"})

    assert again.id == first.id
    assert again.reason == "spam"

    {:ok, _} = Moderation.report_player(reported(), @other, %{"reason" => "hate"})
    assert Moderation.open_count() == 2
  end

  test "a report needs a reporter and a known reason" do
    assert Moderation.report_player(reported(), nil, %{"reason" => "hate"}) ==
             {:error, :owner_key_required}

    assert Moderation.report_player(reported(), @reporter, %{"reason" => "boring"}) ==
             {:error, :invalid_report}
  end

  test "a ban keeps that address out of public rooms until it expires" do
    {:ok, report} = Moderation.report_player(reported(), @reporter, %{"reason" => "hate"})
    refute Moderation.banned?("hash-1")

    {:ok, %Ban{}} = Moderation.ban(report.id, 7)

    assert Moderation.banned?("hash-1")
    refute Moderation.banned?("hash-2")
    refute Moderation.banned?(nil)
    refute Moderation.banned?("hash-1", DateTime.add(DateTime.utc_now(), 8 * 86_400))
    assert Repo.get(PlayerReport, report.id).status == "banned"
    assert Moderation.open_count() == 0
  end

  test "only for as long as a ban may last, and only with an address to ban" do
    {:ok, report} = Moderation.report_player(reported(), @reporter, %{"reason" => "hate"})
    assert Moderation.ban(report.id, 365) == {:error, :invalid_days}

    {:ok, lan} =
      Moderation.report_player(reported(%{ip_hash: nil}), @other, %{"reason" => "hate"})

    assert Moderation.ban(lan.id, 7) == {:error, :no_address}
  end

  test "nothing about a player is kept past 90 days" do
    {:ok, open} = Moderation.report_player(reported(), @reporter, %{"reason" => "hate"})

    {:ok, decided} =
      Moderation.report_player(reported(%{player_name: "Other"}), @reporter, %{
        "reason" => "hate"
      })

    {:ok, _ban} = Moderation.ban(decided.id, 7)

    later = DateTime.add(DateTime.utc_now(), 91 * 86_400)
    assert %{player_reports: 1, addresses: 1, bans: 1} = Moderation.sweep(now: later)

    # The open report stays — it is the queue — but not its address.
    assert %PlayerReport{ip_hash: nil, status: "open"} = Repo.get(PlayerReport, open.id)
    refute Repo.get(PlayerReport, decided.id)
  end
end
