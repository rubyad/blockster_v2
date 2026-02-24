defmodule BlocksterV2.Notifications.FormulaEvaluator do
  @moduledoc """
  Safe expression evaluator for custom rule formulas.

  Supports:
  - Arithmetic: +, -, *, / with standard precedence
  - Variables: metadata field names (e.g., total_bets, bux_net_pnl)
  - Functions: random(min, max), min(a, b), max(a, b)
  - Parentheses for grouping

  Uses a hand-rolled recursive descent parser — no Code.eval_string.
  """

  @allowed_chars ~r/^[a-zA-Z0-9_.\s+\-*\/(),]+$/

  @doc """
  Evaluate a formula string against a metadata map.

  Returns `{:ok, number}` or `:error`.

  ## Examples

      iex> evaluate("total_bets * 10", %{"total_bets" => 5})
      {:ok, 50.0}

      iex> evaluate("random(100, 500)", %{})
      {:ok, 250.0}  # some number in 100..500

      iex> evaluate("100 / 0", %{})
      :error
  """
  @spec evaluate(String.t(), map()) :: {:ok, float()} | :error
  def evaluate(expression, metadata \\ %{})

  def evaluate(nil, _metadata), do: :error
  def evaluate("", _metadata), do: :error

  def evaluate(expression, metadata) when is_binary(expression) do
    expression = String.trim(expression)

    if expression == "" do
      :error
    else
      if Regex.match?(@allowed_chars, expression) do
        tokens = tokenize(expression)

        case parse_expr(tokens, metadata) do
          {:ok, result, []} ->
            if is_number(result) and not (is_float(result) and (result != result or result == :infinity or result == :neg_infinity)) do
              {:ok, result / 1.0}
            else
              :error
            end

          {:ok, result, _rest} ->
            # Leftover tokens — might be valid if trailing whitespace was tokenized
            if is_number(result), do: {:ok, result / 1.0}, else: :error

          :error ->
            :error
        end
      else
        :error
      end
    end
  rescue
    _ -> :error
  end

  def evaluate(number, _metadata) when is_number(number), do: {:ok, number / 1.0}
  def evaluate(_, _), do: :error

  # ============ Tokenizer ============

  defp tokenize(expression) do
    expression
    |> String.trim()
    |> do_tokenize([])
    |> Enum.reverse()
  end

  defp do_tokenize("", acc), do: acc

  defp do_tokenize(<<c, rest::binary>>, acc) when c in [?\s, ?\t, ?\n, ?\r] do
    do_tokenize(rest, acc)
  end

  defp do_tokenize(<<"(", rest::binary>>, acc), do: do_tokenize(rest, [:lparen | acc])
  defp do_tokenize(<<")", rest::binary>>, acc), do: do_tokenize(rest, [:rparen | acc])
  defp do_tokenize(<<",", rest::binary>>, acc), do: do_tokenize(rest, [:comma | acc])
  defp do_tokenize(<<"+", rest::binary>>, acc), do: do_tokenize(rest, [:plus | acc])
  defp do_tokenize(<<"*", rest::binary>>, acc), do: do_tokenize(rest, [:star | acc])
  defp do_tokenize(<<"/", rest::binary>>, acc), do: do_tokenize(rest, [:slash | acc])

  # Minus: could be unary negation or subtraction
  defp do_tokenize(<<"-", rest::binary>>, acc), do: do_tokenize(rest, [:minus | acc])

  # Numbers (integers and floats)
  defp do_tokenize(<<c, _rest::binary>> = s, acc) when c in ?0..?9 do
    {num_str, remaining} = consume_number(s)

    token =
      if String.contains?(num_str, ".") do
        {:number, String.to_float(num_str)}
      else
        {:number, String.to_integer(num_str) * 1.0}
      end

    do_tokenize(remaining, [token | acc])
  end

  # Identifiers (variable names and function names)
  defp do_tokenize(<<c, _rest::binary>> = s, acc) when c in ?a..?z or c in ?A..?Z or c == ?_ do
    {ident, remaining} = consume_identifier(s)
    do_tokenize(remaining, [{:ident, ident} | acc])
  end

  # Dot at start of number (e.g., .5)
  defp do_tokenize(<<".", _rest::binary>> = s, acc) do
    {num_str, remaining} = consume_number(s)
    do_tokenize(remaining, [{:number, String.to_float("0" <> num_str)} | acc])
  end

  defp consume_number(s), do: do_consume_number(s, "", false)

  defp do_consume_number(<<c, rest::binary>>, acc, has_dot) when c in ?0..?9 do
    do_consume_number(rest, acc <> <<c>>, has_dot)
  end

  defp do_consume_number(<<".", rest::binary>>, acc, false) do
    do_consume_number(rest, acc <> ".", true)
  end

  defp do_consume_number(rest, acc, _), do: {acc, rest}

  defp consume_identifier(s), do: do_consume_identifier(s, "")

  defp do_consume_identifier(<<c, rest::binary>>, acc)
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ do
    do_consume_identifier(rest, acc <> <<c>>)
  end

  defp do_consume_identifier(rest, acc), do: {acc, rest}

  # ============ Recursive Descent Parser ============
  # Grammar:
  #   expr   → term (('+' | '-') term)*
  #   term   → factor (('*' | '/') factor)*
  #   factor → unary_minus? atom
  #   atom   → number | variable | function_call | '(' expr ')'

  defp parse_expr(tokens, metadata) do
    case parse_term(tokens, metadata) do
      {:ok, left, rest} ->
        parse_expr_rest(left, rest, metadata)

      :error ->
        :error
    end
  end

  defp parse_expr_rest(left, [:plus | rest], metadata) do
    case parse_term(rest, metadata) do
      {:ok, right, rest2} -> parse_expr_rest(left + right, rest2, metadata)
      :error -> :error
    end
  end

  defp parse_expr_rest(left, [:minus | rest], metadata) do
    case parse_term(rest, metadata) do
      {:ok, right, rest2} -> parse_expr_rest(left - right, rest2, metadata)
      :error -> :error
    end
  end

  defp parse_expr_rest(left, rest, _metadata), do: {:ok, left, rest}

  defp parse_term(tokens, metadata) do
    case parse_factor(tokens, metadata) do
      {:ok, left, rest} ->
        parse_term_rest(left, rest, metadata)

      :error ->
        :error
    end
  end

  defp parse_term_rest(left, [:star | rest], metadata) do
    case parse_factor(rest, metadata) do
      {:ok, right, rest2} -> parse_term_rest(left * right, rest2, metadata)
      :error -> :error
    end
  end

  defp parse_term_rest(left, [:slash | rest], metadata) do
    case parse_factor(rest, metadata) do
      {:ok, right, rest2} ->
        if right == 0 or right == 0.0 do
          :error
        else
          parse_term_rest(left / right, rest2, metadata)
        end

      :error ->
        :error
    end
  end

  defp parse_term_rest(left, rest, _metadata), do: {:ok, left, rest}

  # Unary minus
  defp parse_factor([:minus | rest], metadata) do
    case parse_atom(rest, metadata) do
      {:ok, val, rest2} -> {:ok, -val, rest2}
      :error -> :error
    end
  end

  defp parse_factor(tokens, metadata), do: parse_atom(tokens, metadata)

  # Number literal
  defp parse_atom([{:number, n} | rest], _metadata), do: {:ok, n, rest}

  # Function call: random(a, b), min(a, b), max(a, b)
  defp parse_atom([{:ident, func_name}, :lparen | rest], metadata)
       when func_name in ["random", "min", "max"] do
    case parse_expr(rest, metadata) do
      {:ok, arg1, [:comma | rest2]} ->
        case parse_expr(rest2, metadata) do
          {:ok, arg2, [:rparen | rest3]} ->
            result = call_function(func_name, arg1, arg2)

            case result do
              :error -> :error
              val -> {:ok, val, rest3}
            end

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  # Variable lookup
  defp parse_atom([{:ident, name} | rest], metadata) do
    case lookup_variable(name, metadata) do
      {:ok, val} -> {:ok, val / 1.0, rest}
      :error -> :error
    end
  end

  # Parenthesized expression
  defp parse_atom([:lparen | rest], metadata) do
    case parse_expr(rest, metadata) do
      {:ok, val, [:rparen | rest2]} -> {:ok, val, rest2}
      _ -> :error
    end
  end

  defp parse_atom(_, _metadata), do: :error

  # ============ Functions ============

  defp call_function("random", min_val, max_val) when is_number(min_val) and is_number(max_val) do
    min_int = trunc(Float.ceil(min_val))
    max_int = trunc(Float.floor(max_val))

    if min_int > max_int do
      :error
    else
      if min_int == max_int do
        min_int * 1.0
      else
        (:rand.uniform(max_int - min_int + 1) + min_int - 1) * 1.0
      end
    end
  end

  defp call_function("min", a, b) when is_number(a) and is_number(b), do: Kernel.min(a, b)
  defp call_function("max", a, b) when is_number(a) and is_number(b), do: Kernel.max(a, b)
  defp call_function(_, _, _), do: :error

  # ============ Variable Lookup ============

  defp lookup_variable(name, metadata) do
    # Try string key first, then atom key
    val =
      case Map.get(metadata, name) do
        nil ->
          try do
            Map.get(metadata, String.to_existing_atom(name))
          rescue
            ArgumentError -> nil
          end

        v ->
          v
      end

    case val do
      nil -> :error
      v when is_number(v) -> {:ok, v}
      v when is_binary(v) ->
        case Float.parse(v) do
          {n, _} -> {:ok, n}
          :error -> :error
        end
      _ -> :error
    end
  end
end
