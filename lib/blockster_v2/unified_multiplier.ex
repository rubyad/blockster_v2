defmodule BlocksterV2.UnifiedMultiplier do
  @moduledoc """
  Unified multiplier calculator that combines four separate multiplier components
  into a single overall multiplier using a multiplicative chain.

  ## Formula

      Overall = X Multiplier x Phone Multiplier x SOL Multiplier x Email Multiplier

  ## Multiplier Ranges

  | Component         | Min   | Max    |
  |-------------------|-------|--------|
  | X Multiplier      | 1.0x  | 10.0x  |
  | Phone Multiplier  | 0.5x  | 2.0x   |
  | SOL Multiplier    | 0.0x  | 5.0x   |
  | Email Multiplier  | 1.0x  | 2.0x   |
  | **Overall**       | **0.0x** | **200.0x** |

  ## Component Sources

  - **X Multiplier**: Based on X account quality score (0-100) -> `max(score/10, 1.0)`
  - **Phone Multiplier**: Based on phone verification + geo tier (0.5x unverified, 1.0-2.0x verified)
  - **SOL Multiplier**: Based on SOL balance in Solana wallet (see `SolMultiplier`)
  - **Email Multiplier**: Based on email verification status (see `EmailMultiplier`)

  ## Storage

  All multiplier data is stored in the `unified_multipliers_v2` Mnesia table.
  This is a NEW table with a clean schema (Phase 5 Solana migration).
  """

  require Logger
  alias BlocksterV2.{SolMultiplier, EmailMultiplier, Accounts}

  # Minimum and maximum values for each component
  @x_min 1.0
  @x_max 10.0
  @phone_min 0.5
  @phone_max 2.0
  @sol_min 0.0
  @sol_max 5.0
  @email_min 1.0
  @email_max 2.0

  # Overall limits
  @overall_min 0.0
  @overall_max 200.0

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
  Returns a float between 0.0 and 200.0.
  """
  def get_overall_multiplier(user_id) when is_integer(user_id) do
    case :mnesia.dirty_read({:unified_multipliers_v2, user_id}) do
      [] ->
        # No record exists - calculate and save
        multipliers = calculate_all_multipliers(user_id)
        save_unified_multipliers(user_id, multipliers)
        multipliers.overall_multiplier

      [record] ->
        # Record: {table, user_id, x_score, x_multiplier, phone_multiplier,
        #          sol_multiplier, email_multiplier, overall_multiplier,
        #          last_updated, created_at}
        elem(record, 7) || @overall_min
    end
  end

  def get_overall_multiplier(_), do: @overall_min

  @doc """
  Get the raw X score (0-100) for a user.

  Used for X share rewards where the reward equals the raw X score as BUX.
  """
  def get_x_score(user_id) when is_integer(user_id) do
    case :mnesia.dirty_read({:unified_multipliers_v2, user_id}) do
      [] ->
        get_x_score_from_connections(user_id)

      [record] ->
        elem(record, 2) || 0
    end
  end

  def get_x_score(_), do: 0

  @doc """
  Get all multiplier components for a user.

  Returns a map with all individual multipliers and the overall multiplier.
  """
  def get_user_multipliers(user_id) when is_integer(user_id) do
    case :mnesia.dirty_read({:unified_multipliers_v2, user_id}) do
      [] ->
        # No record exists - calculate, save, and return
        multipliers = calculate_all_multipliers(user_id)
        save_unified_multipliers(user_id, multipliers)
        multipliers

      [record] ->
        # Record: {table, user_id, x_score, x_multiplier, phone_multiplier,
        #          sol_multiplier, email_multiplier, overall_multiplier,
        #          last_updated, created_at}
        %{
          x_score: elem(record, 2) || 0,
          x_multiplier: elem(record, 3) || @x_min,
          phone_multiplier: elem(record, 4) || @phone_min,
          sol_multiplier: elem(record, 5) || @sol_min,
          email_multiplier: elem(record, 6) || @email_min,
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
  - SOL balance changes
  - Email verification completed
  """
  def refresh_multipliers(user_id) when is_integer(user_id) do
    multipliers = calculate_all_multipliers(user_id)
    save_unified_multipliers(user_id, multipliers)
    multipliers
  end

  def refresh_multipliers(_), do: default_multipliers()

  @doc """
  Update only the X multiplier component.
  """
  def update_x_multiplier(user_id, x_score) when is_integer(user_id) and is_number(x_score) do
    x_multiplier = calculate_x_multiplier(x_score)

    case :mnesia.dirty_read({:unified_multipliers_v2, user_id}) do
      [] ->
        refresh_multipliers(user_id)

      [record] ->
        phone_mult = elem(record, 4) || @phone_min
        sol_mult = elem(record, 5) || @sol_min
        email_mult = elem(record, 6) || @email_min
        overall = calculate_overall(x_multiplier, phone_mult, sol_mult, email_mult)
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
          sol_multiplier: sol_mult,
          email_multiplier: email_mult,
          overall_multiplier: overall
        }
    end
  end

  def update_x_multiplier(_, _), do: {:error, :invalid_input}

  @doc """
  Update only the phone multiplier component.
  """
  def update_phone_multiplier(user_id) when is_integer(user_id) do
    phone_multiplier = fetch_phone_multiplier(user_id)

    case :mnesia.dirty_read({:unified_multipliers_v2, user_id}) do
      [] ->
        refresh_multipliers(user_id)

      [record] ->
        x_mult = elem(record, 3) || @x_min
        sol_mult = elem(record, 5) || @sol_min
        email_mult = elem(record, 6) || @email_min
        overall = calculate_overall(x_mult, phone_multiplier, sol_mult, email_mult)
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
          sol_multiplier: sol_mult,
          email_multiplier: email_mult,
          overall_multiplier: overall
        }
    end
  end

  def update_phone_multiplier(_), do: {:error, :invalid_input}

  @doc """
  Update only the SOL multiplier component.

  Call this when SOL balance changes (profile visit, periodic sync).
  """
  def update_sol_multiplier(user_id) when is_integer(user_id) do
    sol_multiplier = SolMultiplier.get_multiplier(user_id)

    case :mnesia.dirty_read({:unified_multipliers_v2, user_id}) do
      [] ->
        refresh_multipliers(user_id)

      [record] ->
        x_mult = elem(record, 3) || @x_min
        phone_mult = elem(record, 4) || @phone_min
        email_mult = elem(record, 6) || @email_min
        overall = calculate_overall(x_mult, phone_mult, sol_multiplier, email_mult)
        now = System.system_time(:second)

        updated_record =
          record
          |> put_elem(5, sol_multiplier)
          |> put_elem(7, overall)
          |> put_elem(8, now)

        :mnesia.dirty_write(updated_record)

        %{
          x_score: elem(record, 2) || 0,
          x_multiplier: x_mult,
          phone_multiplier: phone_mult,
          sol_multiplier: sol_multiplier,
          email_multiplier: email_mult,
          overall_multiplier: overall
        }
    end
  end

  def update_sol_multiplier(_), do: {:error, :invalid_input}

  @doc """
  Update only the email multiplier component.

  Call this when email verification status changes.
  """
  def update_email_multiplier(user_id) when is_integer(user_id) do
    email_multiplier = EmailMultiplier.calculate_for_user(user_id)

    case :mnesia.dirty_read({:unified_multipliers_v2, user_id}) do
      [] ->
        refresh_multipliers(user_id)

      [record] ->
        x_mult = elem(record, 3) || @x_min
        phone_mult = elem(record, 4) || @phone_min
        sol_mult = elem(record, 5) || @sol_min
        overall = calculate_overall(x_mult, phone_mult, sol_mult, email_multiplier)
        now = System.system_time(:second)

        updated_record =
          record
          |> put_elem(6, email_multiplier)
          |> put_elem(7, overall)
          |> put_elem(8, now)

        :mnesia.dirty_write(updated_record)

        %{
          x_score: elem(record, 2) || 0,
          x_multiplier: x_mult,
          phone_multiplier: phone_mult,
          sol_multiplier: sol_mult,
          email_multiplier: email_multiplier,
          overall_multiplier: overall
        }
    end
  end

  def update_email_multiplier(_), do: {:error, :invalid_input}

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

  Formula: x_mult x phone_mult x sol_mult x email_mult
  """
  def calculate_overall(x_mult, phone_mult, sol_mult, email_mult) do
    result = x_mult * phone_mult * sol_mult * email_mult
    Float.round(result, 1)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp calculate_all_multipliers(user_id) do
    # X Score - from x_connections Mnesia table
    x_score = get_x_score_from_connections(user_id)
    x_multiplier = calculate_x_multiplier(x_score)

    # Phone - from PostgreSQL users table
    phone_multiplier = fetch_phone_multiplier(user_id)

    # SOL - from SolMultiplier (reads user_solana_balances Mnesia table)
    sol_multiplier = SolMultiplier.get_multiplier(user_id)

    # Email - from EmailMultiplier (reads user from DB)
    email_multiplier = EmailMultiplier.calculate_for_user(user_id)

    overall = calculate_overall(x_multiplier, phone_multiplier, sol_multiplier, email_multiplier)

    %{
      x_score: x_score,
      x_multiplier: x_multiplier,
      phone_multiplier: phone_multiplier,
      sol_multiplier: sol_multiplier,
      email_multiplier: email_multiplier,
      overall_multiplier: overall
    }
  end

  defp get_x_score_from_connections(user_id) do
    case :mnesia.dirty_read({:x_connections, user_id}) do
      [] -> 0
      [record] ->
        elem(record, 11) || 0
    end
  rescue
    _ -> 0
  end

  defp fetch_phone_multiplier(user_id) do
    case Accounts.get_user(user_id) do
      nil -> @phone_min
      user -> calculate_phone_multiplier(user)
    end
  rescue
    _ -> @phone_min
  end

  defp save_unified_multipliers(user_id, multipliers) do
    now = System.system_time(:second)

    record = {
      :unified_multipliers_v2,
      user_id,
      multipliers.x_score,
      multipliers.x_multiplier,
      multipliers.phone_multiplier,
      multipliers.sol_multiplier,
      multipliers.email_multiplier,
      multipliers.overall_multiplier,
      now,  # last_updated
      now   # created_at
    }

    :mnesia.dirty_write(record)
    :ok
  rescue
    e ->
      Logger.error("[UnifiedMultiplier] Failed to save multipliers for user #{user_id}: #{inspect(e)}")
      :error
  end

  defp default_multipliers do
    %{
      x_score: 0,
      x_multiplier: @x_min,
      phone_multiplier: @phone_min,
      sol_multiplier: @sol_min,
      email_multiplier: @email_min,
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
