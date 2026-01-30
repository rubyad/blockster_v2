defmodule BlocksterV2.UnifiedMultiplier do
  @moduledoc """
  Unified multiplier calculator that combines four separate multiplier components
  into a single overall multiplier using a multiplicative chain.

  ## Formula

      Overall = X Multiplier × Phone Multiplier × ROGUE Multiplier × Wallet Multiplier

  ## Multiplier Ranges

  | Component         | Min   | Max    |
  |-------------------|-------|--------|
  | X Multiplier      | 1.0x  | 10.0x  |
  | Phone Multiplier  | 0.5x  | 2.0x   |
  | ROGUE Multiplier  | 1.0x  | 5.0x   |
  | Wallet Multiplier | 1.0x  | 3.6x   |
  | **Overall**       | **0.5x** | **360.0x** |

  ## Component Sources

  - **X Multiplier**: Based on X account quality score (0-100) → `max(score/10, 1.0)`
  - **Phone Multiplier**: Based on phone verification + geo tier (0.5x unverified, 1.0-2.0x verified)
  - **ROGUE Multiplier**: Based on ROGUE in **Blockster smart wallet** only (see `RogueMultiplier`)
  - **Wallet Multiplier**: Based on ETH + other tokens in **external wallet** (see `WalletMultiplier`)

  ## Storage

  All multiplier data is stored in the `unified_multipliers` Mnesia table for fast access.
  The table is separate from the legacy `user_multipliers` table to avoid migration issues.

  See `docs/unified_multiplier_system_v2.md` for complete documentation.
  """

  require Logger
  alias BlocksterV2.{RogueMultiplier, WalletMultiplier, Accounts}

  # Minimum and maximum values for each component
  @x_min 1.0
  @x_max 10.0
  @phone_min 0.5
  @phone_max 2.0
  @rogue_min 1.0
  @rogue_max 5.0
  @wallet_min 1.0
  @wallet_max 3.6

  # Overall limits
  @overall_min 0.5
  @overall_max 360.0

  # Phone multiplier tiers based on geo_tier
  @phone_tiers %{
    "premium" => 2.0,   # US, CA, UK, AU, DE, FR
    "standard" => 1.5,  # BR, MX, EU, JP, KR
    "basic" => 1.0,     # Other verified countries
    "unverified" => 0.5 # Not verified
  }

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Get the overall multiplier for a user.

  This is the main entry point for getting a user's multiplier.
  Returns a float between 0.5 and 360.0.

  ## Examples

      iex> BlocksterV2.UnifiedMultiplier.get_overall_multiplier(123)
      42.0
  """
  def get_overall_multiplier(user_id) when is_integer(user_id) do
    case :mnesia.dirty_read({:unified_multipliers, user_id}) do
      [] ->
        # No record exists - calculate and save
        multipliers = calculate_all_multipliers(user_id)
        save_unified_multipliers(user_id, multipliers)
        multipliers.overall_multiplier

      [record] ->
        # Return cached overall multiplier
        # Record indices: 0=table, 1=user_id, 2=x_score, 3=x_multiplier, 4=phone_multiplier,
        #                 5=rogue_multiplier, 6=wallet_multiplier, 7=overall_multiplier,
        #                 8=last_updated, 9=created_at
        elem(record, 7) || @overall_min
    end
  end

  def get_overall_multiplier(_), do: @overall_min

  @doc """
  Get the raw X score (0-100) for a user.

  Used for X share rewards where the reward equals the raw X score as BUX.
  This is different from the X multiplier which is calculated as max(score/10, 1.0).

  ## Examples

      iex> BlocksterV2.UnifiedMultiplier.get_x_score(123)
      75
  """
  def get_x_score(user_id) when is_integer(user_id) do
    case :mnesia.dirty_read({:unified_multipliers, user_id}) do
      [] ->
        # No record - check x_connections table
        get_x_score_from_connections(user_id)

      [record] ->
        # Return cached X score (index 2)
        elem(record, 2) || 0
    end
  end

  def get_x_score(_), do: 0

  @doc """
  Get all multiplier components for a user.

  Returns a map with all individual multipliers and the overall multiplier.
  Useful for displaying the multiplier breakdown in UI.

  ## Returns

      %{
        x_score: 75,              # Raw X score (0-100)
        x_multiplier: 7.5,        # Calculated X multiplier (1.0-10.0)
        phone_multiplier: 2.0,    # Phone multiplier (0.5-2.0)
        rogue_multiplier: 3.0,    # ROGUE multiplier (1.0-5.0)
        wallet_multiplier: 2.1,   # Wallet multiplier (1.0-3.6)
        overall_multiplier: 94.5, # Product of all multipliers
        last_updated: 1706000000  # Unix timestamp
      }
  """
  def get_user_multipliers(user_id) when is_integer(user_id) do
    case :mnesia.dirty_read({:unified_multipliers, user_id}) do
      [] ->
        # No record exists - calculate, save, and return
        multipliers = calculate_all_multipliers(user_id)
        save_unified_multipliers(user_id, multipliers)
        multipliers

      [record] ->
        # Return cached values
        # Record indices: 0=table, 1=user_id, 2=x_score, 3=x_multiplier, 4=phone_multiplier,
        #                 5=rogue_multiplier, 6=wallet_multiplier, 7=overall_multiplier,
        #                 8=last_updated, 9=created_at
        %{
          x_score: elem(record, 2) || 0,
          x_multiplier: elem(record, 3) || @x_min,
          phone_multiplier: elem(record, 4) || @phone_min,
          rogue_multiplier: elem(record, 5) || @rogue_min,
          wallet_multiplier: elem(record, 6) || @wallet_min,
          overall_multiplier: elem(record, 7) || @overall_min,
          last_updated: elem(record, 8)
        }
    end
  end

  def get_user_multipliers(_), do: default_multipliers()

  @doc """
  Recalculate and save all multipliers for a user.

  Call this when any component changes:
  - X score updated (after X OAuth or score refresh)
  - Phone verification completed
  - ROGUE balance changes in smart wallet
  - External wallet connected or balances refreshed

  Returns the updated multipliers map.
  """
  def refresh_multipliers(user_id) when is_integer(user_id) do
    multipliers = calculate_all_multipliers(user_id)
    save_unified_multipliers(user_id, multipliers)
    multipliers
  end

  def refresh_multipliers(_), do: default_multipliers()

  @doc """
  Update only the X multiplier component.

  Call this after X score is calculated/updated.
  """
  def update_x_multiplier(user_id, x_score) when is_integer(user_id) and is_number(x_score) do
    x_multiplier = calculate_x_multiplier(x_score)

    case :mnesia.dirty_read({:unified_multipliers, user_id}) do
      [] ->
        # No record - do a full calculation
        refresh_multipliers(user_id)

      [record] ->
        # Update X fields and recalculate overall
        # Record indices: 0=table, 1=user_id, 2=x_score, 3=x_multiplier, 4=phone_multiplier,
        #                 5=rogue_multiplier, 6=wallet_multiplier, 7=overall_multiplier,
        #                 8=last_updated, 9=created_at
        phone_mult = elem(record, 4) || @phone_min
        rogue_mult = elem(record, 5) || @rogue_min
        wallet_mult = elem(record, 6) || @wallet_min
        overall = calculate_overall(x_multiplier, phone_mult, rogue_mult, wallet_mult)
        now = System.system_time(:second)

        updated_record =
          record
          |> put_elem(2, x_score)
          |> put_elem(3, x_multiplier)
          |> put_elem(7, overall)
          |> put_elem(8, now)

        :mnesia.dirty_write(updated_record)

        %{
          x_score: x_score,
          x_multiplier: x_multiplier,
          phone_multiplier: phone_mult,
          rogue_multiplier: rogue_mult,
          wallet_multiplier: wallet_mult,
          overall_multiplier: overall
        }
    end
  end

  def update_x_multiplier(_, _), do: {:error, :invalid_input}

  @doc """
  Update only the phone multiplier component.

  Call this after phone verification completes.
  """
  def update_phone_multiplier(user_id) when is_integer(user_id) do
    phone_multiplier = fetch_phone_multiplier(user_id)

    case :mnesia.dirty_read({:unified_multipliers, user_id}) do
      [] ->
        refresh_multipliers(user_id)

      [record] ->
        # Record indices: 0=table, 1=user_id, 2=x_score, 3=x_multiplier, 4=phone_multiplier,
        #                 5=rogue_multiplier, 6=wallet_multiplier, 7=overall_multiplier,
        #                 8=last_updated, 9=created_at
        x_mult = elem(record, 3) || @x_min
        rogue_mult = elem(record, 5) || @rogue_min
        wallet_mult = elem(record, 6) || @wallet_min
        overall = calculate_overall(x_mult, phone_multiplier, rogue_mult, wallet_mult)
        now = System.system_time(:second)

        updated_record =
          record
          |> put_elem(4, phone_multiplier)
          |> put_elem(7, overall)
          |> put_elem(8, now)

        :mnesia.dirty_write(updated_record)

        %{
          x_score: elem(record, 2) || 0,
          x_multiplier: x_mult,
          phone_multiplier: phone_multiplier,
          rogue_multiplier: rogue_mult,
          wallet_multiplier: wallet_mult,
          overall_multiplier: overall
        }
    end
  end

  def update_phone_multiplier(_), do: {:error, :invalid_input}

  @doc """
  Update only the ROGUE multiplier component.

  Call this when smart wallet ROGUE balance changes.
  """
  def update_rogue_multiplier(user_id) when is_integer(user_id) do
    rogue_data = RogueMultiplier.calculate_rogue_multiplier(user_id)
    rogue_multiplier = rogue_data.total_multiplier

    case :mnesia.dirty_read({:unified_multipliers, user_id}) do
      [] ->
        refresh_multipliers(user_id)

      [record] ->
        # Record indices: 0=table, 1=user_id, 2=x_score, 3=x_multiplier, 4=phone_multiplier,
        #                 5=rogue_multiplier, 6=wallet_multiplier, 7=overall_multiplier,
        #                 8=last_updated, 9=created_at
        x_mult = elem(record, 3) || @x_min
        phone_mult = elem(record, 4) || @phone_min
        wallet_mult = elem(record, 6) || @wallet_min
        overall = calculate_overall(x_mult, phone_mult, rogue_multiplier, wallet_mult)
        now = System.system_time(:second)

        updated_record =
          record
          |> put_elem(5, rogue_multiplier)
          |> put_elem(7, overall)
          |> put_elem(8, now)

        :mnesia.dirty_write(updated_record)

        %{
          x_score: elem(record, 2) || 0,
          x_multiplier: x_mult,
          phone_multiplier: phone_mult,
          rogue_multiplier: rogue_multiplier,
          wallet_multiplier: wallet_mult,
          overall_multiplier: overall
        }
    end
  end

  def update_rogue_multiplier(_), do: {:error, :invalid_input}

  @doc """
  Update only the wallet multiplier component.

  Call this when external wallet is connected or balances refresh.
  """
  def update_wallet_multiplier(user_id) when is_integer(user_id) do
    wallet_data = WalletMultiplier.calculate_hardware_wallet_multiplier(user_id)
    wallet_multiplier = wallet_data.total_multiplier

    case :mnesia.dirty_read({:unified_multipliers, user_id}) do
      [] ->
        refresh_multipliers(user_id)

      [record] ->
        # Record indices: 0=table, 1=user_id, 2=x_score, 3=x_multiplier, 4=phone_multiplier,
        #                 5=rogue_multiplier, 6=wallet_multiplier, 7=overall_multiplier,
        #                 8=last_updated, 9=created_at
        x_mult = elem(record, 3) || @x_min
        phone_mult = elem(record, 4) || @phone_min
        rogue_mult = elem(record, 5) || @rogue_min
        overall = calculate_overall(x_mult, phone_mult, rogue_mult, wallet_multiplier)
        now = System.system_time(:second)

        updated_record =
          record
          |> put_elem(6, wallet_multiplier)
          |> put_elem(7, overall)
          |> put_elem(8, now)

        :mnesia.dirty_write(updated_record)

        %{
          x_score: elem(record, 2) || 0,
          x_multiplier: x_mult,
          phone_multiplier: phone_mult,
          rogue_multiplier: rogue_mult,
          wallet_multiplier: wallet_multiplier,
          overall_multiplier: overall
        }
    end
  end

  def update_wallet_multiplier(_), do: {:error, :invalid_input}

  # ============================================================================
  # Calculation Functions
  # ============================================================================

  @doc """
  Calculate X multiplier from raw X score.

  Formula: max(x_score / 10.0, 1.0)
  Range: 1.0 - 10.0
  """
  def calculate_x_multiplier(x_score) when is_number(x_score) do
    max(x_score / 10.0, @x_min) |> min(@x_max)
  end

  def calculate_x_multiplier(_), do: @x_min

  @doc """
  Calculate phone multiplier from user struct or geo_tier.

  Values:
  - Not verified: 0.5x (penalty)
  - Basic (other countries): 1.0x
  - Standard (BR, MX, EU, JP, KR): 1.5x
  - Premium (US, CA, UK, AU, DE, FR): 2.0x
  """
  def calculate_phone_multiplier(%{phone_verified: true, geo_tier: geo_tier})
      when is_binary(geo_tier) do
    Map.get(@phone_tiers, geo_tier, 1.0)
  end

  def calculate_phone_multiplier(%{phone_verified: false}), do: @phone_min
  def calculate_phone_multiplier(%{geo_tier: nil}), do: @phone_min
  def calculate_phone_multiplier(_), do: @phone_min

  @doc """
  Calculate overall multiplier from all four components.

  Formula: x_mult × phone_mult × rogue_mult × wallet_mult
  """
  def calculate_overall(x_mult, phone_mult, rogue_mult, wallet_mult) do
    result = x_mult * phone_mult * rogue_mult * wallet_mult
    # Round to 1 decimal place for cleaner display
    Float.round(result, 1)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  # Calculate all multipliers from scratch
  defp calculate_all_multipliers(user_id) do
    # X Score - from x_connections Mnesia table
    x_score = get_x_score_from_connections(user_id)
    x_multiplier = calculate_x_multiplier(x_score)

    # Phone - from PostgreSQL users table
    phone_multiplier = fetch_phone_multiplier(user_id)

    # ROGUE - from RogueMultiplier module
    rogue_data = RogueMultiplier.calculate_rogue_multiplier(user_id)
    rogue_multiplier = rogue_data.total_multiplier

    # Wallet - from WalletMultiplier module
    wallet_data = WalletMultiplier.calculate_hardware_wallet_multiplier(user_id)
    wallet_multiplier = wallet_data.total_multiplier

    # Calculate overall
    overall = calculate_overall(x_multiplier, phone_multiplier, rogue_multiplier, wallet_multiplier)

    %{
      x_score: x_score,
      x_multiplier: x_multiplier,
      phone_multiplier: phone_multiplier,
      rogue_multiplier: rogue_multiplier,
      wallet_multiplier: wallet_multiplier,
      overall_multiplier: overall
    }
  end

  # Get X score from the x_connections Mnesia table
  defp get_x_score_from_connections(user_id) do
    case :mnesia.dirty_read({:x_connections, user_id}) do
      [] -> 0
      [record] ->
        # x_score is at index 11 in x_connections table
        # (index 0 is table name, index 1 is user_id, etc.)
        # Attributes order: user_id(1), x_user_id(2), x_username(3), x_name(4), x_profile_image_url(5),
        # access_token_encrypted(6), refresh_token_encrypted(7), token_expires_at(8), scopes(9),
        # connected_at(10), x_score(11), followers_count(12), ...
        elem(record, 11) || 0
    end
  rescue
    _ -> 0
  end

  # Fetch phone multiplier from PostgreSQL user record
  defp fetch_phone_multiplier(user_id) do
    case Accounts.get_user(user_id) do
      nil ->
        @phone_min

      user ->
        calculate_phone_multiplier(user)
    end
  rescue
    _ -> @phone_min
  end

  # Save multipliers to the unified_multipliers Mnesia table
  defp save_unified_multipliers(user_id, multipliers) do
    now = System.system_time(:second)

    record = {
      :unified_multipliers,
      user_id,
      multipliers.x_score,
      multipliers.x_multiplier,
      multipliers.phone_multiplier,
      multipliers.rogue_multiplier,
      multipliers.wallet_multiplier,
      multipliers.overall_multiplier,
      now,  # last_updated
      now   # created_at (will be overwritten if record exists, but that's fine for our use case)
    }

    :mnesia.dirty_write(record)
    :ok
  rescue
    e ->
      Logger.error("[UnifiedMultiplier] Failed to save multipliers for user #{user_id}: #{inspect(e)}")
      :error
  end

  # Default multipliers for invalid/missing users
  defp default_multipliers do
    %{
      x_score: 0,
      x_multiplier: @x_min,
      phone_multiplier: @phone_min,
      rogue_multiplier: @rogue_min,
      wallet_multiplier: @wallet_min,
      overall_multiplier: @overall_min
    }
  end

  # ============================================================================
  # Utility Functions
  # ============================================================================

  @doc """
  Get the maximum possible overall multiplier.
  """
  def max_overall, do: @overall_max

  @doc """
  Get the minimum possible overall multiplier.
  """
  def min_overall, do: @overall_min

  @doc """
  Get the phone multiplier tiers for display in UI.
  """
  def phone_tiers, do: @phone_tiers

  @doc """
  Check if a user has the maximum possible multiplier.
  """
  def is_maxed?(user_id) when is_integer(user_id) do
    multipliers = get_user_multipliers(user_id)
    multipliers.overall_multiplier >= @overall_max
  end

  def is_maxed?(_), do: false
end
