defmodule HighRollers.Users do
  @moduledoc """
  Mnesia operations for user data and affiliate links.
  """

  @users_table :hr_users
  @zero_address "0x0000000000000000000000000000000000000000"

  @doc "Get or create a user record"
  def get_or_create(wallet_address) do
    address = String.downcase(wallet_address)

    case :mnesia.dirty_read({@users_table, address}) do
      [record] ->
        user_to_map(record)

      [] ->
        now = System.system_time(:second)
        record = {@users_table,
          address,
          nil,           # affiliate
          nil,           # affiliate2
          "0",           # affiliate_balance
          "0",           # total_affiliate_earned
          nil,           # linked_at
          false,         # linked_on_chain
          now,           # created_at
          now            # updated_at
        }
        :mnesia.dirty_write(record)
        user_to_map(record)
    end
  end

  @doc "Get user by wallet address (returns nil if not found)"
  def get(wallet_address) do
    address = String.downcase(wallet_address)

    case :mnesia.dirty_read({@users_table, address}) do
      [record] -> user_to_map(record)
      [] -> nil
    end
  end

  @doc "Set affiliate for a user (first referrer wins - only sets if nil)"
  def set_affiliate(wallet_address, affiliate_address) do
    address = String.downcase(wallet_address)
    affiliate = String.downcase(affiliate_address)

    # Prevent self-referral
    if address == affiliate do
      {:error, :self_referral}
    else
      link_affiliate_internal(address, affiliate)
    end
  end

  @doc """
  Link affiliate for a buyer. First referrer wins.
  Also derives tier 2 affiliate from tier 1's affiliate.

  Returns:
  - {:ok, %{affiliate: addr, affiliate2: addr2, is_new: true}} if newly linked
  - {:ok, %{affiliate: existing_addr, affiliate2: addr2, is_new: false}} if already linked
  - {:error, :self_referral} if trying to link to self
  """
  def link_affiliate(buyer_address, affiliate_address) do
    buyer = String.downcase(buyer_address)
    affiliate = String.downcase(affiliate_address)

    if buyer == affiliate do
      {:error, :self_referral}
    else
      case :mnesia.dirty_read({@users_table, buyer}) do
        [{@users_table, ^buyer, nil, _, _, _, _, _, _, _} = record] ->
          # No affiliate yet - set it
          affiliate2 = get_affiliate_of(affiliate)
          now = System.system_time(:second)

          updated = record
          |> put_elem(2, affiliate)
          |> put_elem(3, affiliate2)
          |> put_elem(6, now)  # linked_at
          |> put_elem(9, now)  # updated_at

          :mnesia.dirty_write(updated)
          {:ok, %{affiliate: affiliate, affiliate2: affiliate2, is_new: true}}

        [{@users_table, ^buyer, existing, affiliate2, _, _, _, _, _, _}] when not is_nil(existing) ->
          # Already has affiliate
          {:ok, %{affiliate: existing, affiliate2: affiliate2, is_new: false}}

        [] ->
          # Create new user with affiliate
          affiliate2 = get_affiliate_of(affiliate)
          now = System.system_time(:second)

          record = {@users_table,
            buyer,
            affiliate,
            affiliate2,
            "0",           # affiliate_balance
            "0",           # total_affiliate_earned
            now,           # linked_at
            false,         # linked_on_chain
            now,           # created_at
            now            # updated_at
          }
          :mnesia.dirty_write(record)
          {:ok, %{affiliate: affiliate, affiliate2: affiliate2, is_new: true}}
      end
    end
  end

  @doc "Get users referred by an affiliate address"
  def get_by_affiliate(affiliate_address) do
    affiliate = String.downcase(affiliate_address)

    :mnesia.dirty_index_read(@users_table, affiliate, :affiliate)
    |> Enum.map(&user_to_map/1)
  end

  @doc "Mark user as linked on-chain (called by AdminTxQueue after successful linkAffiliate tx)"
  def mark_linked_on_chain(wallet_address) do
    address = String.downcase(wallet_address)

    case :mnesia.dirty_read({@users_table, address}) do
      [record] ->
        updated = record
        |> put_elem(7, true)  # linked_on_chain
        |> put_elem(9, System.system_time(:second))  # updated_at
        :mnesia.dirty_write(updated)
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @doc "Update affiliate balance (add earnings)"
  def add_affiliate_earnings(wallet_address, amount_wei) do
    address = String.downcase(wallet_address)

    case :mnesia.dirty_read({@users_table, address}) do
      [record] ->
        current_balance = elem(record, 4) |> String.to_integer()
        current_total = elem(record, 5) |> String.to_integer()
        amount = String.to_integer(amount_wei)

        updated = record
        |> put_elem(4, Integer.to_string(current_balance + amount))  # affiliate_balance
        |> put_elem(5, Integer.to_string(current_total + amount))    # total_affiliate_earned
        |> put_elem(9, System.system_time(:second))  # updated_at

        :mnesia.dirty_write(updated)
        :ok

      [] ->
        # Create user first, then add earnings
        get_or_create(wallet_address)
        add_affiliate_earnings(wallet_address, amount_wei)
    end
  end

  @doc "Reset affiliate balance after withdrawal"
  def reset_affiliate_balance(wallet_address) do
    address = String.downcase(wallet_address)

    case :mnesia.dirty_read({@users_table, address}) do
      [record] ->
        updated = record
        |> put_elem(4, "0")  # affiliate_balance
        |> put_elem(9, System.system_time(:second))  # updated_at

        :mnesia.dirty_write(updated)
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @doc "Get affiliate address for a buyer (returns nil if no affiliate or zero address)"
  def get_affiliate_of(wallet_address) do
    address = String.downcase(wallet_address)

    case :mnesia.dirty_read({@users_table, address}) do
      [{@users_table, _, affiliate, _, _, _, _, _, _, _}] ->
        if affiliate && affiliate != @zero_address, do: affiliate, else: nil
      [] -> nil
    end
  end

  @doc "Get all users with affiliate set but not yet linked on-chain"
  def get_pending_onchain_links do
    # Match all records where affiliate is set (not nil) and linked_on_chain is false
    :mnesia.dirty_select(@users_table, [
      {
        {@users_table, :"$1", :"$2", :_, :_, :_, :_, :"$3", :_, :_},
        [
          {:andalso,
            {:"/=", :"$2", nil},
            {:==, :"$3", false}
          }
        ],
        [{{:"$1", :"$2"}}]
      }
    ])
    |> Enum.map(fn {buyer, affiliate} -> %{buyer: buyer, affiliate: affiliate} end)
  end

  @doc "Retry all failed on-chain affiliate links"
  def retry_failed_onchain_links do
    pending = get_pending_onchain_links()

    results = Enum.map(pending, fn %{buyer: buyer, affiliate: affiliate} ->
      HighRollers.AdminTxQueue.enqueue_link_affiliate(buyer, affiliate)
      %{buyer: buyer, affiliate: affiliate, queued: true}
    end)

    {:ok, %{count: length(results), links: results}}
  end

  # ===== Private Functions =====

  defp link_affiliate_internal(address, affiliate) do
    case :mnesia.dirty_read({@users_table, address}) do
      [{@users_table, ^address, nil, _, balance, total, _, linked, created, _}] ->
        # No affiliate yet - set it
        # Look up affiliate's affiliate for tier 2
        affiliate2 = get_affiliate_of(affiliate)

        record = {@users_table,
          address,
          affiliate,
          affiliate2,
          balance,
          total,
          System.system_time(:second),  # linked_at
          linked,
          created,
          System.system_time(:second)   # updated_at
        }
        :mnesia.dirty_write(record)
        {:ok, :linked}

      [{@users_table, ^address, existing, _, _, _, _, _, _, _}] when not is_nil(existing) ->
        # Already has affiliate
        {:ok, :already_linked}

      [] ->
        # Create user with affiliate
        affiliate2 = get_affiliate_of(affiliate)
        now = System.system_time(:second)
        record = {@users_table,
          address,
          affiliate,
          affiliate2,
          "0",
          "0",
          now,    # linked_at
          false,  # linked_on_chain
          now,    # created_at
          now     # updated_at
        }
        :mnesia.dirty_write(record)
        {:ok, :created_and_linked}
    end
  end

  defp user_to_map({@users_table, address, affiliate, affiliate2, balance, total, linked_at, linked_on_chain, created, updated}) do
    %{
      wallet_address: address,
      affiliate: affiliate,
      affiliate2: affiliate2,
      affiliate_balance: balance,
      total_affiliate_earned: total,
      linked_at: linked_at,
      linked_on_chain: linked_on_chain,
      created_at: created,
      updated_at: updated
    }
  end
end
