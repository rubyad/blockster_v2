defmodule HighRollers.MnesiaCase do
  @moduledoc """
  ExUnit CaseTemplate for tests that require Mnesia tables.

  Uses RAM-only tables for speed and isolation. Each test starts with
  a fresh Mnesia instance - no data persists between tests.

  Usage:
    use HighRollers.MnesiaCase

  or with async (not recommended for Mnesia tests):
    use HighRollers.MnesiaCase, async: false
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      import HighRollers.MnesiaCase
    end
  end

  setup do
    # Stop Mnesia if running from a previous test
    :mnesia.stop()

    # Delete any existing schema
    :mnesia.delete_schema([node()])

    # Create fresh RAM-only schema
    :ok = :mnesia.create_schema([node()])
    :ok = :mnesia.start()

    # Create all tables with ram_copies (no disc persistence)
    for table_config <- HighRollers.MnesiaInitializer.tables() do
      create_test_table(table_config)
    end

    # Wait for tables to be ready
    table_names = HighRollers.MnesiaInitializer.table_names()
    :ok = :mnesia.wait_for_tables(table_names, 5_000)

    on_exit(fn ->
      :mnesia.stop()
      :mnesia.delete_schema([node()])
    end)

    :ok
  end

  @doc """
  Create a Mnesia table with RAM-only storage for tests.
  """
  def create_test_table(table_config) do
    name = table_config.name
    type = table_config.type
    attributes = table_config.attributes
    indices = table_config[:indices] || []

    table_opts = [
      attributes: attributes,
      type: type,
      ram_copies: [node()]  # RAM-only for fast tests
    ]

    # Add indices if specified
    table_opts =
      if Enum.empty?(indices) do
        table_opts
      else
        Keyword.put(table_opts, :index, indices)
      end

    case :mnesia.create_table(name, table_opts) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, ^name}} -> :ok
      {:aborted, reason} -> raise "Failed to create table #{name}: #{inspect(reason)}"
    end
  end

  @doc """
  Helper to insert a test NFT record into hr_nfts table.
  Returns the token_id for convenience.
  """
  def insert_test_nft(attrs) do
    defaults = %{
      token_id: 1,
      owner: "0x1234567890123456789012345678901234567890",
      original_buyer: "0x1234567890123456789012345678901234567890",
      hostess_index: 0,
      hostess_name: "Penelope Fatale",
      mint_tx_hash: "0xabc123",
      mint_block_number: 1000,
      mint_price: "320000000000000000",
      affiliate: nil,
      affiliate2: nil,
      total_earned: "0",
      pending_amount: "0",
      last_24h_earned: "0",
      apy_basis_points: 0,
      time_start_time: nil,
      time_last_claim: nil,
      time_total_claimed: nil,
      created_at: System.system_time(:second),
      updated_at: System.system_time(:second)
    }

    nft = Map.merge(defaults, attrs)

    record = {:hr_nfts,
      nft.token_id,
      String.downcase(nft.owner),
      String.downcase(nft.original_buyer),
      nft.hostess_index,
      nft.hostess_name,
      nft.mint_tx_hash,
      nft.mint_block_number,
      nft.mint_price,
      nft[:affiliate] && String.downcase(nft.affiliate),
      nft[:affiliate2] && String.downcase(nft.affiliate2),
      nft.total_earned,
      nft.pending_amount,
      nft.last_24h_earned,
      nft.apy_basis_points,
      nft.time_start_time,
      nft.time_last_claim,
      nft.time_total_claimed,
      nft.created_at,
      nft.updated_at
    }

    :ok = :mnesia.dirty_write(record)
    nft.token_id
  end

  @doc """
  Helper to insert a reward event into hr_reward_events table.
  """
  def insert_test_reward_event(attrs) do
    defaults = %{
      commitment_hash: "0x#{:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)}",
      amount: "1000000000000000000",
      timestamp: System.system_time(:second),
      block_number: 1000,
      tx_hash: "0x#{:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)}"
    }

    event = Map.merge(defaults, attrs)

    record = {:hr_reward_events,
      event.commitment_hash,
      event.amount,
      event.timestamp,
      event.block_number,
      event.tx_hash
    }

    :ok = :mnesia.dirty_write(record)
    event.commitment_hash
  end

  @doc """
  Helper to insert a user record into hr_users table.
  """
  def insert_test_user(attrs) do
    defaults = %{
      wallet_address: "0x1234567890123456789012345678901234567890",
      affiliate: nil,
      affiliate2: nil,
      affiliate_balance: "0",
      total_affiliate_earned: "0",
      linked_at: nil,
      linked_on_chain: false,
      created_at: System.system_time(:second),
      updated_at: System.system_time(:second)
    }

    user = Map.merge(defaults, attrs)

    record = {:hr_users,
      String.downcase(user.wallet_address),
      user[:affiliate] && String.downcase(user.affiliate),
      user[:affiliate2] && String.downcase(user.affiliate2),
      user.affiliate_balance,
      user.total_affiliate_earned,
      user.linked_at,
      user.linked_on_chain,
      user.created_at,
      user.updated_at
    }

    :ok = :mnesia.dirty_write(record)
    user.wallet_address
  end

  @doc """
  Helper to insert a stats record into hr_stats table.
  """
  def insert_test_stats(key, data) do
    record = {:hr_stats, key, data, System.system_time(:second)}
    :ok = :mnesia.dirty_write(record)
    key
  end
end
