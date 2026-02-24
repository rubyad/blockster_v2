defmodule BlocksterV2.BotSystem.BotSetup do
  @moduledoc """
  One-time creation of bot user accounts.
  Run via: `BlocksterV2.BotSystem.BotSetup.create_all_bots()`

  Creates 1000 bot users with random wallets, usernames, and
  varied multiplier tiers for natural BUX earning diversity.
  Idempotent — only creates remaining bots if some already exist.
  """

  alias BlocksterV2.Repo
  alias BlocksterV2.Accounts.User
  import Ecto.Query
  require Logger

  @total_bots 1000
  @bot_email_domain "blockster.bot"

  # Username word pools
  @prefixes ~w(crypto defi nft web3 chain block token mint rogue pixel voxel hodl stack alpha sigma based degen ape whale shark bear bull moon laser hyper turbo nano mega giga ultra zk stark proof node hash byte fomo wagmi gm wen ser fren chad onchain)
  @suffixes ~w(hunter whale shark ninja wizard sage oracle miner staker farmer builder coder hacker trader flipper runner scout ranger keeper guard pilot rider surfer diver walker thinker reader writer dreamer seeker finder voyager nomad ghost shadow spark flame storm wave pulse echo)

  # Multiplier tiers: {label, percentage, phone_verified, geo_tier, x_score_range, rogue_mult_range, wallet_mult_range}
  @multiplier_tiers [
    {:casual,  0.40, false, "unverified", {0, 5},    {1.0, 1.0}, {1.0, 1.0}},
    {:engaged, 0.35, true,  "basic",      {10, 40},  {1.0, 2.0}, {1.0, 1.5}},
    {:power,   0.20, true,  "standard",   {40, 75},  {2.0, 3.5}, {1.5, 2.5}},
    {:whale,   0.05, true,  "premium",    {75, 100}, {3.5, 5.0}, {2.5, 3.6}}
  ]

  @doc """
  Creates all bot users. Idempotent — skips already-created bots.
  Returns `{:ok, created_count}`.
  """
  def create_all_bots(total \\ @total_bots) do
    existing_count = Repo.one(from u in User, where: u.is_bot == true, select: count(u.id))
    remaining = total - existing_count

    if remaining <= 0 do
      Logger.info("[BotSetup] All #{total} bots already exist")
      {:ok, 0}
    else
      Logger.info("[BotSetup] Creating #{remaining} bot users (#{existing_count} already exist)")

      start_index = existing_count + 1
      created =
        Enum.reduce((start_index)..(start_index + remaining - 1), 0, fn i, acc ->
          case create_bot(i) do
            {:ok, user} ->
              seed_multiplier(user.id, i, total)
              acc + 1

            {:error, changeset} ->
              Logger.warning("[BotSetup] Failed to create bot #{i}: #{inspect(changeset.errors)}")
              acc
          end
        end)

      Logger.info("[BotSetup] Created #{created} bot users")
      {:ok, created}
    end
  end

  @doc """
  Creates a single bot user with index `i` (1-based).
  """
  def create_bot(i) do
    email = bot_email(i)
    wallet = generate_eth_address()
    smart_wallet = generate_eth_address()
    username = generate_username(i)

    attrs = %{
      email: email,
      wallet_address: wallet,
      smart_wallet_address: smart_wallet,
      username: username
    }

    User.email_registration_changeset(attrs)
    |> Ecto.Changeset.put_change(:is_bot, true)
    |> Repo.insert()
  end

  @doc """
  Seeds the unified_multipliers Mnesia table for a bot user.
  Tier is determined by the bot's index position within the total.
  """
  def seed_multiplier(user_id, bot_index, total \\ @total_bots) do
    tier = determine_tier(bot_index, total)
    {_label, _pct, _phone, _geo, x_range, rogue_range, wallet_range} = tier

    {x_min, x_max} = x_range
    x_score = x_min + :rand.uniform() * (x_max - x_min)
    x_multiplier = max(x_score / 10.0, 1.0)

    phone_multiplier = phone_multiplier_for_tier(tier)

    {r_min, r_max} = rogue_range
    rogue_multiplier = r_min + :rand.uniform() * (r_max - r_min)

    {w_min, w_max} = wallet_range
    wallet_multiplier = w_min + :rand.uniform() * (w_max - w_min)

    overall = x_multiplier * phone_multiplier * rogue_multiplier * wallet_multiplier
    now = System.system_time(:second)

    record = {:unified_multipliers, user_id,
      Float.round(x_score, 1),
      Float.round(x_multiplier, 2),
      Float.round(phone_multiplier, 2),
      Float.round(rogue_multiplier, 2),
      Float.round(wallet_multiplier, 2),
      Float.round(overall, 2),
      now, now}

    :mnesia.dirty_write(record)
    :ok
  rescue
    e ->
      Logger.warning("[BotSetup] Failed to seed multiplier for user #{user_id}: #{inspect(e)}")
      :error
  end

  @doc """
  Returns the list of all bot user IDs from the database.
  """
  def get_all_bot_ids do
    Repo.all(from u in User, where: u.is_bot == true, select: u.id, order_by: u.id)
  end

  @doc """
  Returns the count of existing bot users.
  """
  def bot_count do
    Repo.one(from u in User, where: u.is_bot == true, select: count(u.id))
  end

  # --- Private Functions ---

  def bot_email(i) do
    padded = String.pad_leading(Integer.to_string(i), 4, "0")
    "bot_#{padded}@#{@bot_email_domain}"
  end

  @doc false
  def generate_eth_address do
    bytes = :crypto.strong_rand_bytes(20)
    "0x" <> Base.encode16(bytes, case: :lower)
  end

  @doc false
  def generate_username(i) do
    prefix = Enum.random(@prefixes)
    suffix = Enum.random(@suffixes)
    # Add a small number suffix for uniqueness
    num = rem(i, 100) + Enum.random(1..99)
    "#{prefix}_#{suffix}_#{num}"
  end

  defp determine_tier(bot_index, total) do
    # Distribute bots across tiers based on their index position
    position = bot_index / total

    {_cumulative, tier} =
      Enum.reduce_while(@multiplier_tiers, {0.0, List.first(@multiplier_tiers)}, fn tier_def, {cumulative, _current} ->
        {_label, pct, _phone, _geo, _x, _r, _w} = tier_def
        new_cumulative = cumulative + pct

        if position <= new_cumulative do
          {:halt, {new_cumulative, tier_def}}
        else
          {:cont, {new_cumulative, tier_def}}
        end
      end)

    tier
  end

  defp phone_multiplier_for_tier({_label, _pct, phone_verified, geo_tier, _x, _r, _w}) do
    if phone_verified do
      case geo_tier do
        "premium" -> 2.0
        "standard" -> 1.5
        "basic" -> 1.0
        _ -> 0.5
      end
    else
      0.5
    end
  end
end
