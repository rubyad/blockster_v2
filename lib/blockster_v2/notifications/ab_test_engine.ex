defmodule BlocksterV2.Notifications.ABTestEngine do
  @moduledoc """
  A/B split testing framework for email optimization.
  Handles variant assignment, significance checking, and winner promotion.
  """

  import Ecto.Query
  alias BlocksterV2.Repo
  alias BlocksterV2.Notifications.{ABTest, ABTestAssignment}

  require Logger

  @doc """
  Assign a user to a variant for an active test.
  Uses deterministic hashing for consistent assignment.
  Returns the variant_id string (e.g., "A", "B").
  """
  def assign_variant(user_id, %ABTest{} = test) do
    case get_existing_assignment(test.id, user_id) do
      %{variant_id: variant} ->
        variant

      nil ->
        variant = select_variant_by_hash(test.variants, user_id, test.id)
        create_assignment(test.id, user_id, variant)
        variant
    end
  end

  @doc """
  Get the active A/B test for an email type and element.
  Returns nil if no running test exists.
  """
  def get_active_test(email_type, element_tested \\ nil) do
    query =
      ABTest
      |> where([t], t.email_type == ^email_type)
      |> where([t], t.status == "running")

    query =
      if element_tested do
        where(query, [t], t.element_tested == ^element_tested)
      else
        query
      end

    query
    |> order_by([t], desc: t.start_date)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Get the variant value for a user in an active test.
  Returns {variant_id, variant_value} or nil if no test.
  """
  def get_variant_for_user(user_id, email_type, element_tested) do
    case get_active_test(email_type, element_tested) do
      nil -> nil
      test ->
        variant_id = assign_variant(user_id, test)
        variant_config = Enum.find(test.variants, fn v -> v["id"] == variant_id end)
        value = if variant_config, do: variant_config["value"], else: nil
        {variant_id, value}
    end
  end

  @doc """
  Record that a user opened an email associated with an A/B test.
  """
  def record_open(test_id, user_id) do
    case get_existing_assignment(test_id, user_id) do
      nil -> :ok
      assignment ->
        assignment
        |> ABTestAssignment.changeset(%{opened: true})
        |> Repo.update()
    end
  end

  @doc """
  Record that a user clicked in an email associated with an A/B test.
  """
  def record_click(test_id, user_id) do
    case get_existing_assignment(test_id, user_id) do
      nil -> :ok
      assignment ->
        assignment
        |> ABTestAssignment.changeset(%{opened: true, clicked: true})
        |> Repo.update()
    end
  end

  @doc """
  Check if a test has reached statistical significance.
  Returns {:significant, winner_id, p_value} | {:not_yet, nil, p_value} | {:insufficient_data, nil, nil}
  """
  def check_significance(%ABTest{} = test) do
    results = get_test_results(test.id)

    if all_variants_have_min_sample?(results, test.min_sample_size) do
      {significant?, p_value, winner} = chi_squared_test(results)

      if significant? and p_value < (1 - test.confidence_threshold) do
        {:significant, winner, p_value}
      else
        {:not_yet, nil, p_value}
      end
    else
      {:insufficient_data, nil, nil}
    end
  end

  @doc """
  Promote winning variant and retire the test.
  """
  def promote_winner(%ABTest{} = test, winning_variant) do
    test
    |> ABTest.changeset(%{
      status: "winner_applied",
      winning_variant: winning_variant,
      end_date: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  @doc """
  Create a new A/B test.
  """
  def create_test(attrs) do
    %ABTest{}
    |> ABTest.changeset(attrs)
    |> Repo.insert()
  end

  @doc "List all tests, optionally filtered by status."
  def list_tests(opts \\ []) do
    status = Keyword.get(opts, :status)

    ABTest
    |> maybe_filter_status(status)
    |> order_by([t], desc: t.start_date)
    |> Repo.all()
  end

  @doc "Get test results grouped by variant."
  def get_test_results(test_id) do
    from(a in ABTestAssignment,
      where: a.ab_test_id == ^test_id,
      group_by: a.variant_id,
      select: %{
        variant_id: a.variant_id,
        total: count(a.id),
        opened: filter(count(a.id), a.opened == true),
        clicked: filter(count(a.id), a.clicked == true)
      }
    )
    |> Repo.all()
  end

  # ============ Private ============

  defp get_existing_assignment(test_id, user_id) do
    Repo.get_by(ABTestAssignment, ab_test_id: test_id, user_id: user_id)
  end

  defp create_assignment(test_id, user_id, variant_id) do
    %ABTestAssignment{}
    |> ABTestAssignment.changeset(%{
      ab_test_id: test_id,
      user_id: user_id,
      variant_id: variant_id
    })
    |> Repo.insert()
  end

  defp select_variant_by_hash(variants, user_id, test_id) do
    hash = :erlang.phash2({user_id, test_id})

    # Calculate total weight
    total_weight = Enum.reduce(variants, 0, fn v, acc -> acc + (v["weight"] || 50) end)

    # Select variant based on hash position
    position = rem(hash, total_weight)

    {variant, _} =
      Enum.reduce_while(variants, {nil, 0}, fn v, {_selected, cumulative} ->
        weight = v["weight"] || 50
        new_cumulative = cumulative + weight

        if position < new_cumulative do
          {:halt, {v["id"], new_cumulative}}
        else
          {:cont, {v["id"], new_cumulative}}
        end
      end)

    variant || (List.first(variants) || %{})["id"] || "A"
  end

  defp all_variants_have_min_sample?(results, min_sample) do
    length(results) >= 2 and Enum.all?(results, fn r -> r.total >= min_sample end)
  end

  defp chi_squared_test(results) do
    # Simplified chi-squared test for open rates between variants
    total_all = Enum.reduce(results, 0, fn r, acc -> acc + r.total end)
    opened_all = Enum.reduce(results, 0, fn r, acc -> acc + r.opened end)

    if total_all == 0 or opened_all == 0 do
      {false, 1.0, nil}
    else
      expected_rate = opened_all / total_all

      chi_sq = Enum.reduce(results, 0.0, fn r, acc ->
        expected = r.total * expected_rate
        not_opened = r.total - r.opened
        expected_not = r.total * (1 - expected_rate)

        if expected > 0 and expected_not > 0 do
          acc +
            :math.pow(r.opened - expected, 2) / expected +
            :math.pow(not_opened - expected_not, 2) / expected_not
        else
          acc
        end
      end)

      # Degrees of freedom = (number of variants - 1)
      df = length(results) - 1

      # Approximate p-value using chi-squared distribution
      p_value = chi_squared_p_value(chi_sq, df)

      # Find winner (highest open rate)
      winner = Enum.max_by(results, fn r ->
        if r.total > 0, do: r.opened / r.total, else: 0
      end)

      {p_value < 0.05, p_value, winner.variant_id}
    end
  end

  # Approximate chi-squared CDF using the regularized incomplete gamma function
  # For small df (1-5), this approximation is sufficient
  defp chi_squared_p_value(chi_sq, df) when chi_sq <= 0, do: 1.0
  defp chi_squared_p_value(chi_sq, df) do
    # Simple approximation for df=1 (most common for 2-variant tests)
    # P(X > chi_sq) ≈ erfc(sqrt(chi_sq/2)) for df=1
    if df == 1 do
      :math.erfc(:math.sqrt(chi_sq / 2))
    else
      # For df>1, use Wilson-Hilferty approximation
      z = :math.pow(chi_sq / df, 1/3) - (1 - 2 / (9 * df))
      z = z / :math.sqrt(2 / (9 * df))
      # Approximate using normal CDF
      0.5 * :math.erfc(z / :math.sqrt(2))
    end
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, [t], t.status == ^status)
end
